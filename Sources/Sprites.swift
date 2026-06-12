import AppKit

// 생활 사이클 씬 렌더 (2026-06-13 개편 — Boss 재결정: 모드 폐기, 작은 방 + 생활 루프)
// 셀 좌표계: top-down(뷰 isFlipped), 단위 = 셀. 방(scene)은 고정 18×9.2셀:
//   왼쪽 침대(0~4.8) · 가운데 마당 · 오른쪽 노트북 책상(13.6~18)
// 캐릭터 스프라이트는 charX(셀)만큼 평행이동, 걷기는 charX가 박자마다 전진.

enum WidgetKind: String, Codable { case clawd, codex }

enum LifePhase {
    case idle          // 마당에서 정면 대기 (팔 들썩+깜빡)
    case play          // 마당에서 공차기 (2026-06-13 추가 — Boss: "공차는거 너무 기여운디")
    case walkToDesk    // 오른쪽으로 출근
    case work          // 타자 (생각 멈춤 리듬 포함)
    case doze          // 책상에서 꾸벅 (눈 감고 z)
    case walkToBed     // 왼쪽으로 퇴근
    case sleep         // 침대에서 이불 덮고 취침 (zzz, 숨쉬기)
    case walkBack      // 다시 마당으로
}

struct Cell {
    let x, y, w, h: CGFloat
    let color: NSColor
    init(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor) {
        self.x = x; self.y = y; self.w = w; self.h = h; self.color = color
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
                  green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(hex & 0xFF) / 255.0, alpha: 1)
    }
}

enum Palette {
    static let clawdBody = NSColor(hex: 0xD97757)
    static let clawdDark = NSColor(hex: 0xBE6243)
    static let codexBody = NSColor(hex: 0x6470F3)
    static let codexDark = NSColor(hex: 0x4F5AD9)
    static let eye = NSColor.black
    static let wood = NSColor(hex: 0x7A5C44)
    static let mattress = NSColor(hex: 0x9DA7B8)
    static let pillow = NSColor(hex: 0xE2E2E6)
    static let blanket = NSColor(hex: 0x5E6E8C)
    static let laptopBase = NSColor(hex: 0xA7ADB8)
    static let screenBack = NSColor(hex: 0x444955)
    static let screenFace = NSColor(hex: 0x171C2C)
    static let cursorGreen = NSColor(hex: 0x7CE38B)
    static let zGray = NSColor(hex: 0x6E6A63)     // 크림 벽 위 가독 보정
}

struct SpriteFrame {
    let cells: [Cell]
    let zText: CGFloat?    // z 글리프 크기 배율 (nil이면 없음)
    let zX: CGFloat        // z baseline 셀 좌표
    let zY: CGFloat
}

enum Sprites {
    static let sceneW: CGFloat = 20       // 방 폭 — 넓혀서 여백·동선 확보 (2026-06-13 2차 튜닝)
    static let sceneH: CGFloat = 8.65     // 벽(0~8) + 바닥(8~8.5) + 여유 (지붕 제거 후 축소)
    static let offsetY: CGFloat = 0.15    // 캐릭터 축소 후 음수 y 셀이 없어 최소 여백만
    // 비율 튜닝(2026-06-13 2차, Boss: "캐릭터 지금도 커") — 0.66 → 0.55
    static let charScale: CGFloat = 0.55
    static let charYOff: CGFloat = 8 * (1 - 0.55)   // 발바닥을 바닥(y=8)에 고정
    static let idleX: CGFloat = 7.8
    static let deskX: CGFloat = 11.3
    static let bedX: CGFloat = 1.2
    static let walkSpeed: CGFloat = 0.45  // 셀/박자

    // 캐릭터 로컬 셀 → 씬 좌표 (flip → 축소 → 평행이동·바닥 고정)
    private static func place(_ cells: [Cell], at x: CGFloat, flip: Bool, width: CGFloat) -> [Cell] {
        cells.map { c in
            let lx = flip ? (width - c.x - c.w) : c.x
            return Cell(lx * charScale + x, c.y * charScale + charYOff,
                        c.w * charScale, c.h * charScale, c.color)
        }
    }

    private enum LegStyle { case standing, walking, kicking }
    private enum ArmStyle { case rest, typing }
    private enum EyeStyle { case open, closed }

    static func scene(kind: WidgetKind, phase: LifePhase, beat: Int, charX: CGFloat,
                      ballX: CGFloat = 0, ballLift: CGFloat = 0, kicking: Bool = false) -> SpriteFrame {
        var c = room(working: phase == .work && (beat % 14) < 10)
        var z: CGFloat? = nil
        var zX: CGFloat = 0, zY: CGFloat = 0

        switch phase {
        case .idle:
            c += front(kind, beat: beat, x: charX)
        case .play:
            c += side(kind, beat: beat, x: charX, flip: false,
                      legs: kicking ? .kicking : .walking, arms: .rest, eyes: .open)
            // 공 — 흰 몸체 + 어두운 패치, 날 때는 ballLift만큼 떠오름
            c.append(Cell(ballX, 7.3 - ballLift, 0.7, 0.7, NSColor(hex: 0xE8E6E0)))
            c.append(Cell(ballX + 0.18, 7.48 - ballLift, 0.3, 0.3, NSColor(hex: 0x3A3F4A)))
        case .walkToDesk, .walkBack:
            c += side(kind, beat: beat, x: charX, flip: false, legs: .walking, arms: .rest, eyes: .open)
        case .walkToBed:
            c += side(kind, beat: beat, x: charX, flip: true, legs: .walking, arms: .rest, eyes: .open)
        case .work:
            let typing = (beat % 14) < 10
            let blink = typing && beat % 9 == 0
            c += side(kind, beat: beat, x: charX, flip: false,
                      legs: .standing, arms: .typing, eyes: blink ? .closed : .open)
            if typing {
                let colors: [UInt32] = [0x7CE38B, 0xE8D27C, 0x9AA4FF, 0xE0E0E0]
                let n = (beat % 8) / 2 + 1
                for i in 0..<n {
                    c.append(Cell(18.52, 3.1 + CGFloat(i) * 0.85, 0.45, 0.4, NSColor(hex: colors[i % 4])))
                }
                let dA: CGFloat = beat % 2 == 1 ? 0 : -0.55
                let dB: CGFloat = beat % 2 == 1 ? -0.55 : 0
                if dA == 0 { c.append(Cell(16.1, 6.45, 0.4, 0.35, NSColor(hex: 0xE8E8E8))) }
                if dB == 0 { c.append(Cell(16.8, 6.5, 0.35, 0.3, NSColor(hex: 0xCFCFCF))) }
            } else {
                let dots = min(3, (beat % 14) - 9)
                if dots > 0 {
                    for i in 0..<dots {
                        // 점 크기(0.35)는 고정이므로 간격도 비스케일(0.65)로 — 붙으면 선처럼 보임(Boss 실측)
                        c.append(Cell(charX + 5.4 * charScale + CGFloat(i) * 0.65,
                                      charYOff - 1.15 * charScale, 0.35, 0.35, NSColor(hex: 0x75716A)))
                    }
                }
                c.append(Cell(18.52, 3.1, 0.45, 0.4, Palette.cursorGreen))
            }
        case .doze:
            c += side(kind, beat: beat, x: charX, flip: false, legs: .standing, arms: .rest, eyes: .closed)
            z = zScale(beat).map { $0 * 0.8 }
            zX = charX + 4.5 * charScale; zY = charYOff - 0.4
        case .sleep:
            c += lying(kind, beat: beat)
            z = zScale(beat).map { $0 * 0.8 }
            zX = 3.4; zY = 5.2
        }
        return SpriteFrame(cells: c, zText: z, zX: zX, zY: zY)
    }

    private static func zScale(_ beat: Int) -> CGFloat? {
        (beat % 8 < 4) ? ((10.0 + 2.0 * CGFloat(beat % 2)) / 12.0) : nil
    }

    // MARK: - 방 (상시 소품)

    private static func room(working: Bool) -> [Cell] {
        var r: [Cell] = []
        // 집 골격 (2026-06-13, Boss: 지붕 제거) — 벽만
        r.append(Cell(0, 0, 20, 8, NSColor(hex: 0xB5A98F)))          // 안쪽 벽 — B 크림 베이지 (Boss 픽 2026-06-13)
        // 창문 — 밤하늘 + 달 + 별 (머리 높이와 겹치지 않게 위·오른쪽으로 이동, 2026-06-13)
        r.append(Cell(12.2, 0.7, 2.8, 2.3, NSColor(hex: 0x54493C)))
        r.append(Cell(12.4, 0.88, 2.4, 1.94, NSColor(hex: 0x232B47)))
        r.append(Cell(14.0, 1.1, 0.45, 0.45, NSColor(hex: 0xE8E4D8)))
        r.append(Cell(12.8, 1.35, 0.15, 0.15, NSColor(hex: 0xCDD2E0)))
        r.append(Cell(13.6, 2.1, 0.15, 0.15, NSColor(hex: 0xCDD2E0)))
        // 액자 (언덕 그림)
        r.append(Cell(4.3, 1.6, 1.5, 1.2, NSColor(hex: 0x54493C)))
        r.append(Cell(4.5, 1.78, 1.1, 0.84, NSColor(hex: 0x3E5A50)))
        r.append(Cell(5.25, 1.9, 0.22, 0.22, NSColor(hex: 0xD9C26B)))
        // 러그 (마당)
        r.append(Cell(6.9, 7.7, 5.2, 0.3, NSColor(hex: 0x8A5560)))
        // 침대 (왼쪽): 캐릭터(축소 후 키 ≈5.3셀)가 누울 수 있는 비례
        r.append(Cell(0.0, 3.6, 0.6, 4.4, Palette.wood))    // 헤드보드
        r.append(Cell(6.3, 5.6, 0.5, 2.4, Palette.wood))    // 풋보드
        r.append(Cell(0.5, 6.6, 6.0, 1.0, Palette.mattress))
        r.append(Cell(0.8, 5.9, 1.7, 0.8, Palette.pillow))
        r.append(Cell(0.7, 7.6, 0.5, 0.4, Palette.wood))
        r.append(Cell(5.9, 7.6, 0.5, 0.4, Palette.wood))
        // 노트북 책상 (오른쪽)
        r.append(Cell(15.6, 6.9, 4.4, 0.9, Palette.laptopBase))
        r.append(Cell(19.1, 2.6, 0.8, 4.3, Palette.screenBack))
        r.append(Cell(18.4, 2.8, 0.7, 4.0, Palette.screenFace))
        if !working {
            r.append(Cell(18.52, 3.1, 0.45, 0.4, Palette.cursorGreen))  // 대기 화면 커서
        }
        // 바닥 선반 (2026-06-13, Boss: "바닥도 있어야") — 밝은 윗선 + 어두운 몸체
        r.append(Cell(0, 8.0, 20, 0.18, NSColor(hex: 0x6A707C)))
        r.append(Cell(0, 8.18, 20, 0.32, NSColor(hex: 0x454B55)))
        return r
    }

    // MARK: - 정면 포즈 (대기)

    private static func front(_ kind: WidgetKind, beat: Int, x: CGFloat) -> [Cell] {
        let B = kind == .clawd ? Palette.clawdBody : Palette.codexBody
        var c: [Cell] = []
        let up: CGFloat = (beat % 4 < 2) ? 0 : -1
        let blink = beat % 9 == 0
        if kind == .codex {
            c.append(Cell(3, 0, 2, 1, B))
            c.append(Cell(7, 0, 2, 1, B))
            c.append(Cell(2, 1, 8, 5, B))
        } else {
            c.append(Cell(2, 0, 8, 6, B))
        }
        let ar: CGFloat = kind == .codex ? 3 : 2
        c.append(Cell(0, ar + up, 2, 2, B))
        c.append(Cell(10, ar + up, 2, 2, B))
        for lx: CGFloat in [2, 4, 7, 9] { c.append(Cell(lx, 6, 1, 2, B)) }
        if !blink {
            let er: CGFloat = kind == .codex ? 2 : 1
            c.append(Cell(3, er, 1, 1, Palette.eye))
            c.append(Cell(8, er, 1, 1, Palette.eye))
        }
        return place(c, at: x, flip: false, width: 12)
    }

    // MARK: - 옆모습 포즈 (걷기·타자·꾸벅) — 로컬(폭 10셀, 오른쪽 보기) 작성 후 flip/이동

    private static func side(_ kind: WidgetKind, beat: Int, x: CGFloat, flip: Bool,
                             legs: LegStyle, arms: ArmStyle, eyes: EyeStyle) -> [Cell] {
        let B = kind == .clawd ? Palette.clawdBody : Palette.codexBody
        let D = kind == .clawd ? Palette.clawdDark : Palette.codexDark
        let t: CGFloat = kind == .codex ? 1 : 0
        var local: [Cell] = []

        if kind == .codex {
            local.append(Cell(1, 0, 2, 1, B))
            local.append(Cell(4, 0, 2, 1, B))
        }
        local.append(Cell(0, t, 8, 6 - t, B))
        local.append(Cell(0, t, 2, 6 - t, D))          // 등쪽 투톤 음영
        local.append(Cell(8, 2 + t, 2, 2, B))          // 주둥이

        switch eyes {
        case .open:
            // 2026-06-13 Boss: "옆모습 눈이 너무 커" — 1×1.4 → 0.85×1.05
            local.append(Cell(4.1, 1.15 + t, 0.85, 1.05, Palette.eye))
            local.append(Cell(7.1, 1.15 + t, 0.85, 1.05, Palette.eye))
        case .closed:
            local.append(Cell(4.1, 2.0 + t, 0.85, 0.22, Palette.eye))
            local.append(Cell(7.1, 2.0 + t, 0.85, 0.22, Palette.eye))
        }

        switch legs {
        case .standing:
            for lx: CGFloat in [1, 3, 5, 7] { local.append(Cell(lx, 6, 1, 2, B)) }
        case .walking:
            let lifted: [CGFloat] = beat % 2 == 0 ? [3, 7] : [1, 5]
            let planted: [CGFloat] = beat % 2 == 0 ? [1, 5] : [3, 7]
            for lx in planted { local.append(Cell(lx, 6, 1, 2, B)) }
            for lx in lifted { local.append(Cell(lx, 6, 1, 1.5, B)) }
        case .kicking:
            // 앞다리를 앞으로 쭉 뻗는 킥 — 나머지 셋은 버팀
            for lx: CGFloat in [1, 3, 5] { local.append(Cell(lx, 6, 1, 2, B)) }
            local.append(Cell(7.4, 6.0, 1.7, 0.85, B))
        }

        switch arms {
        case .rest:
            local.append(Cell(7.3, 4.9 + 0.3 * t, 2.0, 0.9, D))
            local.append(Cell(8.0, 4.6 + 0.3 * t, 2.3, 0.95, B))
        case .typing:
            let typing = (beat % 14) < 10
            let dA: CGFloat = typing ? (beat % 2 == 1 ? 0 : -0.55) : 0
            let dB: CGFloat = typing ? (beat % 2 == 1 ? -0.55 : 0) : 0
            local.append(Cell(7.3, 4.9 + 0.3 * t + dB, 2.0, 0.9, D))
            local.append(Cell(8.0, 4.6 + 0.3 * t + dA, 2.3, 0.95, B))
        }

        // flip(왼쪽 보기) → 축소 → 씬 좌표 이동
        return place(local, at: x, flip: flip, width: 10)
    }

    // MARK: - 침대 취침 포즈

    private static func lying(_ kind: WidgetKind, beat: Int) -> [Cell] {
        let B = kind == .clawd ? Palette.clawdBody : Palette.codexBody
        var c: [Cell] = []
        let breathe: CGFloat = (beat % 8 < 4) ? 0 : -0.12
        if kind == .codex {
            c.append(Cell(1.25, 5.05, 0.9, 0.35, B))    // 구름 머리 봉우리
        }
        // 서 있을 때 몸 부피(≈4.4×3.3셀)에 맞춘 덩치 — "누우면 작아지는 느낌" 보정 (2026-06-13)
        c.append(Cell(0.9, 5.35, 1.9, 1.5, B))          // 머리 (베개 위, 천장 보고 누움)
        c.append(Cell(1.65, 5.6, 0.25, 0.6, Palette.eye)) // 감은 눈 — 세로 대시 한 짝
        c.append(Cell(5.5, 6.1, 0.55, 0.55, B))         // 이불 밖으로 나온 발
        c.append(Cell(2.6, 5.5 + breathe, 3.0, 1.6, Palette.blanket))   // 이불 본체
        c.append(Cell(2.9, 5.15 + breathe, 1.6, 0.4, Palette.blanket))  // 가슴 둔덕 (배 부분 볼록)
        return c
    }
}
