import AppKit
import ServiceManagement

func slog(_ s: String) {
    let line = "\(Date()) \(s)\n"
    let path = "/tmp/deskpin.log"
    if let h = FileHandle(forWritingAtPath: path) {
        h.seekToEndOfFile()
        h.write(line.data(using: .utf8)!)
        try? h.close()
    } else {
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var panels: [String: WidgetPanel] = [:]
    private var views: [String: WidgetView] = [:]
    private var timer: Timer?
    private var reasserting = false   // reassertTraits의 setFrame이 windowDidMove로 영속값을 덮는 것 차단

    func applicationDidFinishLaunching(_ n: Notification) {
        // 전부 숨긴 채 종료했더라도, 앱을 다시 켰다는 건 위젯을 보겠다는 뜻 — 잠금 상태 방지
        if ConfigStore.shared.config.widgets.allSatisfy({ !$0.visible }) {
            for wc in ConfigStore.shared.config.widgets {
                ConfigStore.shared.update(wc.id) { $0.visible = true }
            }
        }
        for wc in ConfigStore.shared.config.widgets { makePanel(wc) }
        setupStatusItem()
        watchScreenAndWake()
        startTimer()
        if ConfigStore.shared.config.launchAtLogin == nil {
            enableLaunchAtLogin()   // Boss 결정(2026-06-13): 기본 ON — 메뉴에서 끌 수 있음
        }
        NotificationCenter.default.addObserver(
            forName: .deskPinConfigChanged, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildStatusMenu()
        }
        slog("deskpin up widgets=\(panels.count) level=\(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)")
    }

    func applicationWillTerminate(_ n: Notification) {
        ConfigStore.shared.saveNow()
    }

    // MARK: - 위젯 창 (W1~W5)

    private func makePanel(_ wc: WidgetConfig) {
        let panel = WidgetPanel(
            contentRect: clampedRect(wc),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        applyWindowTraits(panel)
        let v = WidgetView(widgetId: wc.id, kind: wc.kind)
        panel.contentView = v
        panel.delegate = self
        panels[wc.id] = panel
        views[wc.id] = v
        if wc.visible { panel.orderFrontRegardless() }
    }

    private func applyWindowTraits(_ panel: NSPanel) {
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)  // S1 PASS
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]                 // W5
        panel.isOpaque = false
        // W3 히트영역: 알파 백킹은 0.01에서도 회색 상자가 미세하게 보임(Boss 실측 2026-06-12)
        // → 완전 투명 + ignoresMouseEvents 명시(false)로 창 전체 히트.
        //    비문서 tri-state지만 macOS 26.4에서 투명영역 클릭 동작 실측 확인(2026-06-12).
        //    OS 업데이트 후 빈 곳 클릭이 죽으면 폴백: backgroundColor = black alpha 0.005
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false      // W1 필수 — 기본 true면 비활성 시 소멸
        panel.isReleasedWhenClosed = false   // 숨김 토글 크래시 방지
    }

    // 화면 밖 좌표는 표시만 보정 — 영속값은 덮지 않는다 (P1)
    private func clampedRect(_ wc: WidgetConfig) -> NSRect {
        var r = NSRect(x: wc.x, y: wc.y, width: wc.size, height: wc.size)
        let visible = NSScreen.screens.contains { $0.frame.intersects(r) }
        if !visible, let main = NSScreen.main {
            r.origin = NSPoint(x: main.visibleFrame.midX - r.width / 2,
                               y: main.visibleFrame.midY - r.height / 2)
        }
        return r
    }

    // MARK: - 메뉴바

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = AppDelegate.statusIcon()
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()
        menu.delegate = self
        for wc in ConfigStore.shared.config.widgets {
            let title = wc.id == "claude" ? "Claude 위젯" : (wc.id == "codex" ? "Codex 위젯" : wc.id)
            let item = NSMenuItem(title: title, action: #selector(toggleWidget(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = wc.id
            item.state = wc.visible ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let anim = NSMenuItem(title: "애니메이션", action: #selector(toggleAnimations), keyEquivalent: "")
        anim.target = self
        anim.state = ConfigStore.shared.config.animationsEnabled ? .on : .off
        menu.addItem(anim)
        let login = NSMenuItem(title: "로그인 시 자동 시작", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = ConfigStore.shared.config.launchAtLogin == true ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "DeskPin 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc func toggleWidget(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let panel = panels[id],
              let wc = ConfigStore.shared.widget(id) else { return }
        let nowVisible = !wc.visible
        ConfigStore.shared.update(id) { $0.visible = nowVisible }
        if nowVisible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        rebuildStatusMenu()
    }

    @objc func toggleAnimations() {
        ConfigStore.shared.config.animationsEnabled.toggle()
        ConfigStore.shared.scheduleSave()
        rebuildStatusMenu()
        views.values.forEach { $0.needsDisplay = true }
    }

    // 메뉴바 아이콘 — 클로드 정면 실루엣을 18pt template로 런타임 드로잉
    private static func statusIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let cell: CGFloat = 18.0 / 13.0
            NSColor.black.setFill()
            let cells: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (2, 2, 8, 6), (0, 4, 2, 2), (10, 4, 2, 2),
                (2, 8, 1, 2), (4, 8, 1, 2), (7, 8, 1, 2), (9, 8, 1, 2),
            ]
            for c in cells {
                NSRect(x: c.0 * cell, y: c.1 * cell, width: c.2 * cell, height: c.3 * cell).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: - 로그인 자동 시작 (P2 — SMAppService 우선, ad-hoc 불확실 시 LaunchAgent 폴백)

    private var agentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/local.jinwoo.deskpin.plist")
    }

    @objc func toggleLaunchAtLogin() {
        if ConfigStore.shared.config.launchAtLogin == true { disableLaunchAtLogin() }
        else { enableLaunchAtLogin() }
        rebuildStatusMenu()
    }

    private func enableLaunchAtLogin() {
        var method: String?
        do {
            try SMAppService.mainApp.register()
            if SMAppService.mainApp.status == .enabled { method = "sma" }
        } catch {
            slog("SMAppService register 실패: \(error.localizedDescription)")
        }
        if method == nil, writeLaunchAgent() { method = "agent" }
        ConfigStore.shared.config.launchAtLogin = (method != nil)
        ConfigStore.shared.config.loginMethod = method
        ConfigStore.shared.scheduleSave()
        slog("launchAtLogin enable -> method=\(method ?? "실패") smStatus=\(SMAppService.mainApp.status.rawValue)")
    }

    private func disableLaunchAtLogin() {
        switch ConfigStore.shared.config.loginMethod {
        case "agent": try? FileManager.default.removeItem(at: agentPlistURL)
        default: try? SMAppService.mainApp.unregister()
        }
        ConfigStore.shared.config.launchAtLogin = false
        ConfigStore.shared.config.loginMethod = nil
        ConfigStore.shared.scheduleSave()
        slog("launchAtLogin disable")
    }

    private func writeLaunchAgent() -> Bool {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key><string>local.jinwoo.deskpin</string>
        \t<key>ProgramArguments</key><array><string>/Applications/DeskPin.app/Contents/MacOS/DeskPin</string></array>
        \t<key>RunAtLoad</key><true/>
        \t<key>LimitLoadToSessionType</key><string>Aqua</string>
        </dict>
        </plist>
        """
        do {
            try FileManager.default.createDirectory(
                at: agentPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try plist.write(to: agentPlistURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            slog("LaunchAgent 작성 실패: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - 방어 코드 (D1: sleep/wake·디스플레이 재구성 후 상태 유실 대응)

    private func watchScreenAndWake() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.reassertTraits() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.reassertTraits() }
    }

    private func reassertTraits() {
        reasserting = true
        defer { reasserting = false }   // windowDidMove는 setFrame에서 동기 발송 — 플래그로 충분
        for (id, panel) in panels {
            applyWindowTraits(panel)
            if views[id]?.isResizingNow == true { continue }   // 리사이즈 드래그 중엔 frame 불간섭
            if let wc = ConfigStore.shared.widget(id) {
                panel.setFrame(clampedRect(wc), display: true)
                if wc.visible { panel.orderFrontRegardless() }
            }
        }
        slog("reassert traits (screen change / wake)")
    }

    // MARK: - 애니메이션 타이머 (240ms, 데모와 동일 박자)

    private func startTimer() {
        // 리뷰 반영: scheduledTimer는 .default 모드 전용 — 메뉴 트래킹 중 애니메이션이 얼지 않게 .common 등록
        let t = Timer(timeInterval: 0.24, repeats: true) { [weak self] _ in
            guard let self, ConfigStore.shared.config.animationsEnabled else { return }
            for (id, v) in self.views where self.panels[id]?.isVisible == true { v.tick() }
        }
        t.tolerance = 0.06   // 전력 가드 — 시스템이 박자를 묶어 깨울 수 있게
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - NSWindowDelegate — performDrag 이동 저장 경로 (I2)

    func windowDidMove(_ n: Notification) {
        guard !reasserting,   // 클램프 표시 보정이 영속값을 덮지 않게 (P1)
              let win = n.object as? WidgetPanel,
              let id = panels.first(where: { $0.value === win })?.key else { return }
        ConfigStore.shared.update(id) {
            $0.x = win.frame.origin.x
            $0.y = win.frame.origin.y
            $0.size = win.frame.width   // 리사이즈 중단 시 x/y·size 비일관 영속 방지
        }
    }
}
