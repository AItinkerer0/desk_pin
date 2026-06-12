import AppKit

// DESIGN.md W1~W5, I1~I4 — 위젯 창과 입력 처리.
// Phase 0 실측 반영: 레벨 desktopIcon+1(클릭 수신 PASS), alpha 백킹(PASS), 수동 리사이즈(시스템 .resizable FAIL).

final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class WidgetView: NSView {
    let widgetId: String
    let kind: WidgetKind

    // 생활 사이클 상태 — 위젯마다 독립 (랜덤 길이로 자연 비동기)
    private var beat = Int.random(in: 0...30)
    private var phase: LifePhase = .play          // 하루는 공놀이로 시작 (대기 단계 제거, 2026-06-13)
    private var phaseBeat = 0
    private var phaseDur = Int.max
    private var charX: CGFloat = Sprites.playX

    // 공놀이(저글링) 상태 (.play 전용)
    private var ballX: CGFloat = Sprites.playX + 5.0
    private var ballLift: CGFloat = 2.4   // 지면 기준 공 높이 (셀)
    private var facingRight = true

    // 입력 상태
    private enum GrabKind { case corner, edgeH, edgeV }
    private var downScreen = NSPoint.zero
    private var downEvent: NSEvent?
    private var moved = false
    private var resizing = false
    private var grab: GrabKind = .corner
    private var resizeAnchor = NSPoint.zero    // 스크린 좌표(bottom-left), 고정되는 반대편 모서리

    var isResizingNow: Bool { resizing }       // reassertTraits가 드래그 중 setFrame을 피하도록 노출

    init(widgetId: String, kind: WidgetKind) {
        self.widgetId = widgetId
        self.kind = kind
        super.init(frame: .zero)
    }

    // I4: 우클릭·control-클릭 메뉴 — 메뉴바 아이콘이 노치에 가려져도 모든 제어 가능하게 전체 세트 제공
    override func menu(for event: NSEvent) -> NSMenu? { buildContextMenu() }

    private func buildContextMenu() -> NSMenu {
        let m = NSMenu()
        let hide = NSMenuItem(title: "숨기기", action: #selector(hideWidget), keyEquivalent: "")
        hide.target = self
        m.addItem(hide)
        let reset = NSMenuItem(title: "크기 초기화", action: #selector(resetSize), keyEquivalent: "")
        reset.target = self
        m.addItem(reset)
        m.addItem(.separator())
        if let delegate = NSApp.delegate as? AppDelegate {
            for wc in ConfigStore.shared.config.widgets {
                let title = wc.id == "claude" ? "Clawd (Claude)" : (wc.id == "codex" ? "Cody (Codex)" : wc.id)
                let item = NSMenuItem(title: title, action: #selector(AppDelegate.toggleWidget(_:)), keyEquivalent: "")
                item.target = delegate
                item.representedObject = wc.id
                item.state = wc.visible ? .on : .off
                m.addItem(item)
            }
            let anim = NSMenuItem(title: "애니메이션", action: #selector(AppDelegate.toggleAnimations), keyEquivalent: "")
            anim.target = delegate
            anim.state = ConfigStore.shared.config.animationsEnabled ? .on : .off
            m.addItem(anim)
            let login = NSMenuItem(title: "로그인 시 자동 시작", action: #selector(AppDelegate.toggleLaunchAtLogin), keyEquivalent: "")
            login.target = delegate
            login.state = ConfigStore.shared.config.launchAtLogin == true ? .on : .off
            m.addItem(login)
        }
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "DeskPin 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        return m
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }   // I1

    func tick() {
        guard window?.occlusionState.contains(.visible) == true else { return }   // 전력 가드
        beat += 1
        phaseBeat += 1
        switch phase {
        case .idle:
            if phaseBeat >= phaseDur { enter(.walkToDesk) }   // 하루 루틴 고정 (2026-06-13)
        case .play:
            // 저글링: 코끝에서 2박자에 한 번 통통, 3번 튀기면 몸 돌려 반대쪽 (영상 모션)
            let juggleEnd = 16
            if phaseBeat <= juggleEnd {
                let bounce = phaseBeat / 2
                facingRight = (bounce / 3) % 2 == 0
                ballX = facingRight ? charX + 5.0 : charX - 0.7
                ballLift = (phaseBeat % 2 == 1) ? 3.5 : 2.4
            } else {
                // 공이 떨어져 책상 쪽으로 데굴데굴 — 놀이 끝, 출근
                facingRight = true
                ballLift = max(0, ballLift - 1.2)
                ballX += 0.7
                if phaseBeat >= juggleEnd + 5 { enter(.walkToDesk) }
            }
        case .returnHome:
            charX = max(Sprites.idleX, charX - Sprites.walkSpeed)
            if charX <= Sprites.idleX { enter(.walkToDesk) }   // (현재 미사용 경로)
        case .walkToDesk:
            charX = min(Sprites.deskX, charX + Sprites.walkSpeed)
            if charX >= Sprites.deskX { enter(.work) }
        case .work:
            if phaseBeat >= phaseDur { enter(.doze) }
        case .doze:
            if phaseBeat >= phaseDur { enter(.walkToBed) }
        case .walkToBed:
            charX = max(Sprites.bedX, charX - Sprites.walkSpeed)
            if charX <= Sprites.bedX { enter(.sleep) }
        case .sleep:
            if phaseBeat >= phaseDur { enter(.walkBack) }
        case .walkBack:
            charX = min(Sprites.playX, charX + Sprites.walkSpeed)
            if charX >= Sprites.playX { enter(.play) }       // 일어나면 공차러
        }
        needsDisplay = true
    }

    private func enter(_ p: LifePhase) {
        phase = p
        phaseBeat = 0
        switch p {
        case .idle: phaseDur = 15 + Int.random(in: 0...15)    // ≈4~7초 (2026-06-13: "넘 길어" 단축)
        case .work: phaseDur = 30 + Int.random(in: 0...25)    // ≈7~13초
        case .doze: phaseDur = 10 + Int.random(in: 0...8)
        case .sleep: phaseDur = 30 + Int.random(in: 0...30)   // ≈7~14초
        case .play:
            phaseDur = .max                                   // 저글링 단계가 자체 종료
            ballX = charX + 5.0                               // 코끝 위치
            ballLift = 2.4
            facingRight = true
        default: phaseDur = .max                              // 걷기는 위치 도달로 종료
        }
    }

    // MARK: - 그리기

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.shouldAntialias = false

        // W3 alpha 백킹은 창 배경(applyWindowTraits)에서 처리 — 뷰 fill은 회색 박스로 비침(실측)

        let f = Sprites.scene(kind: kind, phase: phase, beat: beat, charX: charX,
                              ballX: ballX, ballLift: ballLift, facingRight: facingRight)
        let cell = min(bounds.width / Sprites.sceneW, bounds.height / Sprites.sceneH)
        let ox = (bounds.width - Sprites.sceneW * cell) / 2
        let oy = (bounds.height - Sprites.sceneH * cell) / 2
        for c in f.cells {
            c.color.setFill()
            NSRect(x: ox + c.x * cell,
                   y: oy + (c.y + Sprites.offsetY) * cell,
                   width: c.w * cell,
                   height: c.h * cell).fill()
        }
        if let zScale = f.zText {
            ctx.shouldAntialias = true
            let font = NSFont.monospacedSystemFont(ofSize: cell * zScale, weight: .bold)
            // 데모의 fillText는 baseline 기준 — flipped draw(at:)은 top-left라 ascender로 환산
            let y = oy + (f.zY + Sprites.offsetY) * cell - font.ascender
            ("z" as NSString).draw(
                at: NSPoint(x: ox + f.zX * cell, y: y),
                withAttributes: [.font: font, .foregroundColor: Palette.zGray])
        }
    }

    // MARK: - 입력 (I2/I3: 클릭=실행, 임계값 초과=performDrag 이동, 가장자리 밴드=수동 리사이즈)

    private func bandWidth() -> CGFloat { max(6, min(16, bounds.width * 0.12)) }

    private func inEdgeBand(_ p: NSPoint) -> Bool {
        let b = bandWidth()
        return p.x < b || p.x > bounds.width - b || p.y < b || p.y > bounds.height - b
    }

    override func mouseDown(with event: NSEvent) {
        guard let win = window else { return }
        if event.modifierFlags.contains(.control) {
            NSMenu.popUpContextMenu(buildContextMenu(), with: event, for: self)
            return
        }
        let p = convert(event.locationInWindow, from: nil)
        downScreen = NSEvent.mouseLocation
        downEvent = event
        moved = false
        let b = bandWidth()
        let left = p.x < b, right = p.x > bounds.width - b
        let top = p.y < b, bottom = p.y > bounds.height - b
        resizing = left || right || top || bottom
        if resizing {
            // 리뷰 반영: edge 그랩은 직교축 거리가 축소 하한이 되는 Chebyshev 버그가 있어 그랩 종류를 분류
            grab = ((left || right) && (top || bottom)) ? .corner : ((left || right) ? .edgeH : .edgeV)
            let f = win.frame
            resizeAnchor = NSPoint(x: downScreen.x < f.midX ? f.maxX : f.minX,
                                   y: downScreen.y < f.midY ? f.maxY : f.minY)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let win = window else { return }
        let cur = NSEvent.mouseLocation
        if resizing {
            moved = true
            let dx = abs(cur.x - resizeAnchor.x)
            let dy = abs(cur.y - resizeAnchor.y)
            let raw: CGFloat
            switch grab {
            case .corner: raw = max(dx, dy)
            case .edgeH: raw = dx     // 좌/우 변 그랩 — 가로축만
            case .edgeV: raw = dy     // 상/하 변 그랩 — 세로축만
            }
            let side = max(32, min(1024, raw))
            let x = cur.x >= resizeAnchor.x ? resizeAnchor.x : resizeAnchor.x - side
            let y = cur.y >= resizeAnchor.y ? resizeAnchor.y : resizeAnchor.y - side
            win.setFrame(NSRect(x: x, y: y, width: side, height: side), display: true)
        } else if !moved, hypot(cur.x - downScreen.x, cur.y - downScreen.y) > 5 {
            moved = true
            if let de = downEvent { win.performDrag(with: de) }   // 이후 저장은 windowDidMove에서
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let win = window else { return }
        if resizing && moved {
            ConfigStore.shared.update(widgetId) {
                $0.x = win.frame.origin.x
                $0.y = win.frame.origin.y
                $0.size = win.frame.width
            }
        } else if !moved {
            launchTarget()   // 리뷰 반영: 밴드 안 무이동 클릭도 클릭 — 데드존(기본 36%) 제거
        }
        resizing = false
    }

    // MARK: - 커서 (I3: cursorUpdate+activeAlways 금지 — mouseMoved에서 직접 set)

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if inEdgeBand(p) { resizeCursor(for: p).set() } else { NSCursor.arrow.set() }
    }

    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    private func resizeCursor(for p: NSPoint) -> NSCursor {
        let b = bandWidth()
        let left = p.x < b, right = p.x > bounds.width - b
        let top = p.y < b, bottom = p.y > bounds.height - b    // isFlipped: y 작음 = 화면 위쪽
        let pos: NSCursor.FrameResizePosition
        switch (left, right, top, bottom) {
        case (true, _, true, _): pos = .topLeft
        case (_, true, true, _): pos = .topRight
        case (true, _, _, true): pos = .bottomLeft
        case (_, true, _, true): pos = .bottomRight
        case (true, _, _, _): pos = .left
        case (_, true, _, _): pos = .right
        case (_, _, true, _): pos = .top
        default: pos = .bottom
        }
        return NSCursor.frameResize(position: pos, directions: .all)
    }

    // MARK: - 동작

    private func launchTarget() {
        guard let wc = ConfigStore.shared.widget(widgetId) else { return }
        var url = URL(fileURLWithPath: wc.appPath)
        if !FileManager.default.fileExists(atPath: wc.appPath),
           let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: wc.bundleId) {
            url = resolved   // L1: 경로 실패 시 bundle id로 복구
        }
        let conf = NSWorkspace.OpenConfiguration()
        conf.addsToRecentItems = false
        let bundleId = wc.bundleId
        NSWorkspace.shared.openApplication(at: url, configuration: conf) { _, err in
            if let err {
                slog("launch error \(bundleId): \(err.localizedDescription)")
                if let running = NSRunningApplication
                    .runningApplications(withBundleIdentifier: bundleId).first {
                    running.activate(options: [])
                }
            }
        }
        slog("launch \(widgetId) -> \(url.path)")
    }

    @objc private func hideWidget() {
        ConfigStore.shared.update(widgetId) { $0.visible = false }
        window?.orderOut(nil)
        NotificationCenter.default.post(name: .deskPinConfigChanged, object: nil)
    }

    @objc private func resetSize() {
        guard let win = window else { return }
        win.setFrame(NSRect(origin: win.frame.origin, size: NSSize(width: 160, height: 160)), display: true)
        ConfigStore.shared.update(widgetId) { $0.size = 160 }
    }
}

extension Notification.Name {
    static let deskPinConfigChanged = Notification.Name("DeskPinConfigChanged")
}
