import AppKit

// DESIGN.md W1~W5, I1~I4 — 위젯 창과 입력 처리.
// Phase 0 실측 반영: 레벨 desktopIcon+1(클릭 수신 PASS), alpha 백킹(PASS), 수동 리사이즈(시스템 .resizable FAIL).

final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// 공식 모션 스프라이트 (tools/make_sprites.swift·key_motion.swift 산출물, 번들 Resources)
enum JuggleSprites {
    static let clawd = load("clawd", "juggle")
    static let cody = load("cody", "juggle")
    static let clawdDetective = load("clawd", "detective")
    static func frames(for kind: WidgetKind) -> [NSImage] { kind == .codex ? cody : clawd }

    // 범용 모션 라이브러리 (우클릭 메뉴로 갈아끼움) — 지연 로드 캐시
    private static var cache: [String: [NSImage]] = [:]
    static func motionFrames(_ character: String, _ motion: String) -> [NSImage] {
        let key = "\(character)/\(motion)"
        if let c = cache[key] { return c }
        let f = load(character, motion)
        cache[key] = f
        return f
    }
    private static func load(_ name: String, _ motion: String) -> [NSImage] {
        var a: [NSImage] = []
        var i = 0
        while let url = Bundle.main.url(forResource: String(format: "%@_%@_%02d", name, motion, i),
                                        withExtension: "png"),
              let img = NSImage(contentsOf: url) {
            a.append(img)
            i += 1
        }
        return a
    }
}

final class WidgetView: NSView {
    let widgetId: String
    let kind: WidgetKind

    // 생활 사이클 상태 — 위젯마다 독립 (랜덤 길이로 자연 비동기)
    private var beat = Int.random(in: 0...30)
    private var phase: LifePhase = .idle          // 집 위젯 사이클: 대기→출근→타자→꾸벅→취침→복귀 (공놀이는 전용 위젯 전담, 2026-06-13)
    private var phaseBeat = 0
    private var phaseDur = 20 + Int.random(in: 0...25)
    private var charX: CGFloat = Sprites.idleX

    // 공놀이(저글링) 상태 (.play 전용)
    private var ballX: CGFloat = Sprites.playX + 5.6
    private var ballLift: CGFloat = 1.7   // 지면 기준 공 높이 (셀)
    private var ballRight = true          // 공이 캐릭터 오른쪽에 있는 박자
    private var playPoseKind = 0          // 0 기울임 접촉 / 1 직립 ¾ / 2 정면 피크

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
                let title = wc.id == "claude" ? "Clawd (Claude)"
                    : (wc.id == "codex" ? "Cody (Codex)"
                    : (wc.id == "juggle" ? "Clawd 저글링"
                    : (wc.id == "detective" ? "Clawd 탐정 (돋보기)" : wc.id)))
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
        if kind == .clawdLoop || kind == .detectiveLoop {   // 모션 루프 전용 — 단계 없음
            needsDisplay = true
            return
        }
        phaseBeat += 1
        switch phase {
        case .idle:
            if phaseBeat >= phaseDur { enter(.walkToDesk) }   // 하루 루틴 고정 (2026-06-13)
        case .play:
            // 비트맵 스프라이트 모드: 영상 추출 프레임을 그대로 루프 (3바퀴 후 출근)
            let bitmapCount = JuggleSprites.frames(for: kind).count
            if bitmapCount > 0 {
                if phaseBeat >= bitmapCount * 3 { enter(.walkToDesk) }
                needsDisplay = true
                break
            }
            // ↓ 셀 기반 폴백 키프레임: 반 사이클 4박자 = 접촉(기울임·무릎) → 상승(직립¾) → 피크(정면 양팔) → 낙하
            let half = 4
            let cross = phaseBeat / half
            let b = phaseBeat % half
            let xc = charX + 3.3
            if cross >= 6 {
                // 마지막 접촉 후 공이 책상 쪽으로 데굴데굴 — 출근
                playPoseKind = 1
                ballRight = true
                ballLift = max(0, ballLift - 1.0)
                ballX += 0.7
                if phaseBeat >= 6 * half + 6 { enter(.walkToDesk) }
            } else {
                let fromRight = cross % 2 == 0        // 이번 반 사이클의 공 출발 쪽
                let off: [CGFloat] = [3.3, 1.8, 0.0, -1.8]   // 코끝 밀착(낮게) → 정수리 위 → 반대쪽 낙하
                let lifts: [CGFloat] = [0.9, 3.2, 4.6, 3.2]
                ballX = xc + (fromRight ? off[b] : -off[b]) - 0.5
                ballLift = lifts[b]
                playPoseKind = b == 0 ? 0 : (b == 2 ? 2 : 1)
                ballRight = (b == 3) ? !fromRight : fromRight   // 낙하 박자엔 다음 접촉 쪽을 바라봄
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
            charX = min(Sprites.idleX, charX + Sprites.walkSpeed)
            if charX >= Sprites.idleX { enter(.idle) }       // 기상 후 마당으로 — 한숨 돌리고 다시 출근
        }
        needsDisplay = true
    }

    private func enter(_ p: LifePhase) {
        phase = p
        phaseBeat = 0
        switch p {
        case .idle: phaseDur = 25 + Int.random(in: 0...20)    // 0.1s 박자 ≈2.5~4.5초
        case .work: phaseDur = 35 + Int.random(in: 0...25)    // 0.1s 박자 기준 ≈3.5~6초
        case .doze: phaseDur = 30 + Int.random(in: 0...15)    // ≈3~4.5초 (Boss: "조는 거 좀만 더 길게")
        case .sleep: phaseDur = 35 + Int.random(in: 0...25)   // ≈3.5~6초
        case .play:
            phaseDur = .max                                   // 저글링 단계가 자체 종료
            ballX = charX + 6.1                               // 첫 접촉 — 오른쪽 코끝 밀착
            ballLift = 0.9
            ballRight = true
            playPoseKind = 0
        default: phaseDur = .max                              // 걷기는 위치 도달로 종료
        }
    }

    // MARK: - 그리기

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.shouldAntialias = false

        // W3 alpha 백킹은 창 배경(applyWindowTraits)에서 처리 — 뷰 fill은 회색 박스로 비침(실측)

        // 모션 루프 전용 위젯 — 추출 프레임만 꽉 채워 재생 (방·단계 없음, 원본과 1:1)
        if kind == .clawdLoop || kind == .detectiveLoop {
            let motion = ConfigStore.shared.widget(widgetId)?.motion
                ?? (kind == .detectiveLoop ? "detective" : "juggle")
            let frames = JuggleSprites.motionFrames("clawd", motion)
            guard !frames.isEmpty else { return }
            ctx.imageInterpolation = .none
            let img = frames[beat % frames.count]
            let aspect = img.size.height / img.size.width
            let dw = bounds.width
            let dh = dw * aspect
            img.draw(in: NSRect(x: 0, y: bounds.height - dh, width: dw, height: dh),
                     from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: true, hints: nil)
            return
        }

        let bitmapFrames = phase == .play ? JuggleSprites.frames(for: kind) : []
        let f = Sprites.scene(kind: kind, phase: phase, beat: beat, charX: charX,
                              ballX: ballX, ballLift: ballLift,
                              ballRight: ballRight,
                              playPose: bitmapFrames.isEmpty ? playPoseKind : -1)
        let cell = min(bounds.width / Sprites.sceneW, bounds.height / Sprites.sceneH)
        let ox = (bounds.width - Sprites.sceneW * cell) / 2
        let oy = (bounds.height - Sprites.sceneH * cell) / 2
        // 픽셀 격자 스냅 (2026-06-13 Boss: "픽셀이 영상이랑 달라") — 셀 경계를 디바이스 픽셀에
        // 정렬해 굵기 들쭉날쭉/시접 제거. 영상의 균일한 픽셀 질감 재현.
        let bs = window?.backingScaleFactor ?? 2
        for c in f.cells {
            c.color.setFill()
            let x0 = ((ox + c.x * cell) * bs).rounded() / bs
            let y0 = ((oy + (c.y + Sprites.offsetY) * cell) * bs).rounded() / bs
            let x1 = ((ox + (c.x + c.w) * cell) * bs).rounded() / bs
            let y1 = ((oy + (c.y + c.h + Sprites.offsetY) * cell) * bs).rounded() / bs
            NSRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).fill()
        }
        if !bitmapFrames.isEmpty {
            // 영상 추출 프레임 — 12 video px = 아트 1px, 캐릭터 스케일에 맞춰 변환, 보간 없이(픽셀 보존)
            ctx.imageInterpolation = .none
            let img = bitmapFrames[phaseBeat % bitmapFrames.count]
            let cw = img.size.width / 12.0 * Sprites.charScale
            let chh = img.size.height / 12.0 * Sprites.charScale
            img.draw(in: NSRect(x: ox + (charX - 0.6) * cell,
                                y: oy + (8.18 + Sprites.offsetY) * cell - chh * cell,
                                width: cw * cell, height: chh * cell),
                     from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: true, hints: nil)
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
