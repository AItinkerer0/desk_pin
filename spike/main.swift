import AppKit

// DeskPin Phase 0 spike — DESIGN.md §6 S1~S5 실측용 최소 창.
// usage: deskpin_spike [x] [y] [level]   (level: "desktopIcon+1" | "normal-1")
// 판정 근거는 /tmp/deskpin_spike.log 에 쌓인다.

let logPath = "/tmp/deskpin_spike.log"
func slog(_ s: String) {
    let line = "\(Date()) \(s)\n"
    if let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile()
        h.write(line.data(using: .utf8)!)
        try? h.close()
    } else {
        try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
    }
    print(s)
}

final class SpikeView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // 중앙 절반 = 불투명(아이콘 영역 가정), 바깥 = alpha 백킹만 (S4 투명영역 히트 테스트)
    func centerRect() -> NSRect { bounds.insetBy(dx: bounds.width / 4, dy: bounds.height / 4) }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let zone = centerRect().contains(p) ? "CENTER" : "EDGE_ALPHA"
        slog("mouseDown zone=\(zone) at=\(Int(p.x)),\(Int(p.y))")
    }
    override func rightMouseDown(with event: NSEvent) { slog("rightMouseDown") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.02).setFill()   // W3 alpha 백킹
        bounds.fill()
        NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.34, alpha: 1).setFill()
        centerRect().fill()
    }
}

final class SpikePanel: NSPanel {
    override var canBecomeKey: Bool { false }   // W1: .resizable이 켜는 기본 true를 명시적으로 차단
    override var canBecomeMain: Bool { false }
}

final class SpikeDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var panel: SpikePanel!

    func applicationDidFinishLaunching(_ n: Notification) {
        let a = CommandLine.arguments
        let x = a.count > 1 ? (Double(a[1]) ?? 200) : 200
        let y = a.count > 2 ? (Double(a[2]) ?? 200) : 200
        let levelName = a.count > 3 ? a[3] : "desktopIcon+1"

        panel = SpikePanel(
            contentRect: NSRect(x: x, y: y, width: 160, height: 160),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],   // S3: 시스템 리사이즈 경로
            backing: .buffered, defer: false)

        let lvl = levelName == "normal-1"
            ? Int(CGWindowLevelForKey(.normalWindow)) - 1
            : Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        panel.level = NSWindow.Level(rawValue: lvl)                      // S1
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]  // W5
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 32, height: 32)
        panel.contentAspectRatio = NSSize(width: 1, height: 1)          // D2 정사각

        let v = SpikeView()
        v.wantsLayer = true
        panel.contentView = v
        panel.delegate = self
        panel.orderFrontRegardless()                                     // W1: makeKey 금지

        slog("spike up level=\(lvl) (\(levelName)) frame=\(panel.frame) canBecomeKey=\(panel.canBecomeKey)")
    }

    func windowDidResize(_ n: Notification) { slog("windowDidResize frame=\(panel.frame)") }
    func windowDidMove(_ n: Notification) { slog("windowDidMove frame=\(panel.frame)") }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // bare binary라 Info.plist 없음 — LSUIElement 대응
let delegate = SpikeDelegate()
app.delegate = delegate
slog("starting args=\(CommandLine.arguments.dropFirst().joined(separator: " "))")
app.run()
