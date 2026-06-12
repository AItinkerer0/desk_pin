import AppKit

// DeskPin — 데스크탑 픽셀 런처 위젯. 엔트리포인트(B1: main.swift top-level 고정).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
