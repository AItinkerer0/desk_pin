import Foundation

// DESIGN.md P1 — Application Support JSON, atomic write, schemaVersion, corrupt 시 .bak 격리.

struct WidgetConfig: Codable {
    var id: String
    var kind: WidgetKind
    var appPath: String
    var bundleId: String
    var x: Double
    var y: Double
    var size: Double
    var visible: Bool
    var motion: String?   // 루프 위젯의 모션 이름 (nil이면 kind 기본값) — 우클릭 메뉴로 변경
}

struct AppConfig: Codable {
    var schemaVersion: Int
    var animationsEnabled: Bool
    var widgets: [WidgetConfig]
    // 로그인 자동 시작 (optional — 구버전 config.json과 디코딩 호환)
    var launchAtLogin: Bool?     // nil = 미설정(최초 실행 시 기본 ON 등록)
    var loginMethod: String?     // "sma" | "agent" — 이중 등록 방지용 단일 기록
}

final class ConfigStore {
    static let shared = ConfigStore()

    private let dirURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DeskPin", isDirectory: true)
    private var fileURL: URL { dirURL.appendingPathComponent("config.json") }
    private var savePending: DispatchWorkItem?

    var config: AppConfig

    init() {
        if let data = try? Data(contentsOf: dirURL.appendingPathComponent("config.json")),
           let parsed = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = parsed
        } else {
            if FileManager.default.fileExists(atPath: dirURL.appendingPathComponent("config.json").path) {
                // 파손 격리 — 크래시 금지, 기본값으로 재시작 (DESIGN P1)
                let bak = dirURL.appendingPathComponent("config.json.bak")
                try? FileManager.default.removeItem(at: bak)   // 리뷰 반영: 기존 .bak 있으면 move가 throw
                try? FileManager.default.moveItem(
                    at: dirURL.appendingPathComponent("config.json"), to: bak)
                slog("config corrupt -> .bak 격리, 기본값 사용")
            }
            config = ConfigStore.defaultConfig()
            scheduleSave()   // 리뷰 반영: 첫 실행에도 디스크와 메모리 상태 일치
        }
        // 마이그레이션: 돋보기 탐정 위젯 (2026-06-13)
        if !config.widgets.contains(where: { $0.id == "detective" }) {
            config.widgets.append(WidgetConfig(
                id: "detective", kind: .detectiveLoop,
                appPath: "/Applications/Claude.app",
                bundleId: "com.anthropic.claudefordesktop",
                x: 1030, y: 180, size: 150, visible: true))
            scheduleSave()
        }
        // 공놀이 루프 위젯 부활(Boss 2026-06-13 오후, 도트복원판 도입) — 직전 "집 2채+탐정만" 구성 결정을 대체
        if !config.widgets.contains(where: { $0.id == "juggle" }) {
            config.widgets.append(WidgetConfig(
                id: "juggle", kind: .clawdLoop,
                appPath: "/Applications/Claude.app",
                bundleId: "com.anthropic.claudefordesktop",
                x: 1680, y: 605, size: 110, visible: true))
            scheduleSave()
        }
        // cody 공놀이 루프 위젯 (Boss 2026-06-13 오후)
        if !config.widgets.contains(where: { $0.id == "cody_juggle" }) {
            config.widgets.append(WidgetConfig(
                id: "cody_juggle", kind: .codexLoop,
                appPath: "/Applications/Codex.app",
                bundleId: "com.openai.codex",
                x: 1545, y: 605, size: 110, visible: true))
            scheduleSave()
        }
        // 모션 전환 기능 제거(2026-06-13)에 따른 청소 — 삭제된 모션을 가리키면 투명 렌더가 됨
        for i in config.widgets.indices where config.widgets[i].motion != nil {
            config.widgets[i].motion = nil
            scheduleSave()
        }
    }

    static func defaultConfig() -> AppConfig {
        AppConfig(schemaVersion: 1, animationsEnabled: true, widgets: [
            WidgetConfig(id: "claude", kind: .clawd,
                         appPath: "/Applications/Claude.app",
                         bundleId: "com.anthropic.claudefordesktop",
                         x: 1430, y: 180, size: 160, visible: true),
            WidgetConfig(id: "codex", kind: .codex,
                         appPath: "/Applications/Codex.app",
                         bundleId: "com.openai.codex",
                         x: 1640, y: 180, size: 160, visible: true),
        ])
    }

    func widget(_ id: String) -> WidgetConfig? {
        config.widgets.first { $0.id == id }
    }

    func update(_ id: String, _ mutate: (inout WidgetConfig) -> Void) {
        guard let i = config.widgets.firstIndex(where: { $0.id == id }) else { return }
        mutate(&config.widgets[i])
        scheduleSave()
    }

    func scheduleSave() {
        savePending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        savePending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        savePending?.cancel()
        savePending = nil
        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(config)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            slog("config save error: \(error.localizedDescription)")
        }
    }
}
