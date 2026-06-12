import AVFoundation
import AppKit

// 영상 → 저글링 스프라이트 (v3: 원본 픽셀 보존 + 외곽 flood-fill 키잉 + 디프린지)
// v1의 결함 수정판: ① 어두운 AA 테두리 → 투명 인접 침식 2회 ② 밝은 회색 줄 → 외곽 연결 시 제거
// 몸 안의 눈/공 체커는 외곽과 비연결이라 보존된다.
// usage: make_sprites <video> <outdir> <startSec> <frameCount>

let args = CommandLine.arguments
guard args.count >= 5 else {
    print("usage: make_sprites <video> <outdir> <startSec> <frameCount>")
    exit(1)
}
let videoURL = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])
let startSec = Double(args[3]) ?? 5.0
let frameCount = Int(args[4]) ?? 15
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let cropRect = CGRect(x: 217, y: 250, width: 160, height: 108)  // 캐릭터+공 (580×512 기준)

let asset = AVURLAsset(url: videoURL)
let gen = AVAssetImageGenerator(asset: asset)
gen.requestedTimeToleranceBefore = .zero
gen.requestedTimeToleranceAfter = .zero

func rgba(_ cg: CGImage) -> (buf: [UInt8], w: Int, h: Int)? {
    let w = cg.width, h = cg.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (buf, w, h)
}

// 배경 후보: 어두운 무채색만 (밝은 회색은 공 그라데이션을 먹으므로 여기서 다루지 않음 —
// 모션블러 잔상 등 회색 덩어리는 아래 연결 성분 분석에서 제거)
func isBackgroundish(_ b: [UInt8], _ i: Int) -> Bool {
    let r = Int(b[i]), g = Int(b[i + 1]), bl = Int(b[i + 2])
    let mx = max(r, g, bl), mn = min(r, g, bl)
    return mx < 70 && (mx - mn) < 16
}

func isWarm(_ b: [UInt8], _ i: Int) -> Bool {
    let r = Int(b[i]), g = Int(b[i + 1]), bl = Int(b[i + 2])
    return r > g && g >= bl - 20 && r > 105 && (r - min(g, bl)) > 25
}

func process(_ cg: CGImage) -> (buf: [UInt8], w: Int, h: Int)? {
    guard var (buf, w, h) = rgba(cg) else { return nil }
    // ① 외곽 연결 배경 flood fill 제거
    var visited = [Bool](repeating: false, count: w * h)
    var stack: [Int] = []
    for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
    for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }
    while let p = stack.popLast() {
        if p < 0 || p >= w * h || visited[p] { continue }
        visited[p] = true
        let i = p * 4
        guard buf[i + 3] != 0, isBackgroundish(buf, i) else { continue }
        buf[i] = 0; buf[i + 1] = 0; buf[i + 2] = 0; buf[i + 3] = 0
        let x = p % w, y = p / w
        if x > 0 { stack.append(p - 1) }
        if x < w - 1 { stack.append(p + 1) }
        if y > 0 { stack.append(p - w) }
        if y < h - 1 { stack.append(p + w) }
    }
    // ②′ 연결 성분 정리 — 순백(공)도 따뜻한 색(몸)도 없는 회색 덩어리(모션블러 잔상 등) 통삭제
    var compId = [Int](repeating: -1, count: w * h)
    var nextId = 0
    for start in 0..<(w * h) where buf[start * 4 + 3] != 0 && compId[start] == -1 {
        var hasAnchor = false
        var members: [Int] = []
        var bfs = [start]
        compId[start] = nextId
        while let p = bfs.popLast() {
            members.append(p)
            let i = p * 4
            let r = Int(buf[i]), g = Int(buf[i + 1]), bl = Int(buf[i + 2])
            let mx = max(r, g, bl), mn = min(r, g, bl)
            if mn > 225 { hasAnchor = true }                                  // 공 순백
            if r > g && g >= bl - 20 && r > 105 && (mx - mn) > 25 { hasAnchor = true } // 몸 테라코타
            let x = p % w, y = p / w
            for q in [x > 0 ? p - 1 : -1, x < w - 1 ? p + 1 : -1,
                      y > 0 ? p - w : -1, y < h - 1 ? p + w : -1] {
                if q >= 0, compId[q] == -1, buf[q * 4 + 3] != 0 {
                    compId[q] = nextId
                    bfs.append(q)
                }
            }
        }
        if !hasAnchor {
            for p in members {
                let i = p * 4
                buf[i] = 0; buf[i + 1] = 0; buf[i + 2] = 0; buf[i + 3] = 0
            }
        }
        nextId += 1
    }

    // (디프린지 제거 — 격자 양자화가 다수결로 AA를 흡수하므로 불필요, 오히려 실루엣을 갉음)
    return (buf, w, h)
}

func recolorIndigo(_ buf: inout [UInt8], _ w: Int, _ h: Int) {
    for p in 0..<(w * h) {
        let i = p * 4
        guard buf[i + 3] > 0 else { continue }
        let r = Double(buf[i]), g = Double(buf[i + 1]), bl = Double(buf[i + 2])
        if r > g, g >= bl - 12, r > 95, r - bl > 25 {   // r-b 차이 조건 — 공 흰색(거의 무채색) 오염 방지
            let lum = min(1.2, (r + g + bl) / 3.0 / 175.0)
            buf[i] = UInt8(min(255, 100 * lum))
            buf[i + 1] = UInt8(min(255, 112 * lum))
            buf[i + 2] = UInt8(min(255, 243 * lum))
        }
    }
}

// 공 중심 탐지 — 순백 픽셀 무게중심 (공만 mn>205 보유)
func ballCentroid(_ buf: [UInt8], _ w: Int, _ h: Int) -> (x: Double, y: Double, count: Int) {
    var sx = 0.0, sy = 0.0
    var n = 0
    for p in 0..<(w * h) {
        let i = p * 4
        guard buf[i + 3] != 0 else { continue }
        if min(buf[i], min(buf[i + 1], buf[i + 2])) > 205 {
            sx += Double(p % w); sy += Double(p / w); n += 1
        }
    }
    return n > 0 ? (sx / Double(n), sy / Double(n), n) : (0, 0, 0)
}

// 격자 위상 전수 탐색 — 칸 순도(눈 검정≥60%·몸 warm≥80% 칸 수)가 최대가 되는 (pitch, phase)
func calibrateByPurity(_ buf: [UInt8], _ w: Int, _ h: Int) -> (pitch: Double, phx: Double, phy: Double) {
    var best: (score: Int, p: Double, px: Double, py: Double) = (-1, 12, 0, 0)
    // 저글링 스프라이트는 기본 12px가 아니라 더 미세한 픽셀 단위(Boss 관찰 "픽셀 세분화" — 실측 눈≈8px)
    for pitch in [3.9, 4.0, 5.8, 5.9, 6.0, 6.1, 7.9, 8.0, 11.9, 12.0] {
        var py = 0.0
        while py < pitch {
            var px = 0.0
            while px < pitch {
                var score = 0
                var gy = 0
                while Double(gy) * pitch + py + pitch <= Double(h) {
                    var gx = 0
                    while Double(gx) * pitch + px + pitch <= Double(w) {
                        let x0 = Int(Double(gx) * pitch + px), y0 = Int(Double(gy) * pitch + py)
                        let x1 = Int(Double(gx + 1) * pitch + px), y1 = Int(Double(gy + 1) * pitch + py)
                        var warm = 0, dark = 0, total = 0
                        for y in y0..<min(y1, h) {
                            for x in x0..<min(x1, w) {
                                total += 1
                                let i = (y * w + x) * 4
                                guard buf[i + 3] != 0 else { continue }
                                if isWarm(buf, i) { warm += 1 }
                                else if max(buf[i], max(buf[i + 1], buf[i + 2])) < 115 { dark += 1 }
                            }
                        }
                        if total > 0 {
                            if dark * 100 >= total * 60 { score += 10 }   // 눈이 한 칸에 모임
                            if warm * 100 >= total * 85 { score += 1 }
                        }
                        gx += 1
                    }
                    gy += 1
                }
                if score > best.score { best = (score, pitch, px, py) }
                px += 1
            }
            py += 1
        }
    }
    return (best.p, best.px, best.py)
}

// 위상만 재탐색 (프레임별 — 캐릭터가 움직여 위상이 프레임마다 다름)
func calibratePhase(_ buf: [UInt8], _ w: Int, _ h: Int, pitch: Double) -> (phx: Double, phy: Double) {
    var best: (score: Int, px: Double, py: Double) = (-1, 0, 0)
    var py = 0.0
    while py < pitch {
        var px = 0.0
        while px < pitch {
            var score = 0
            var gy = 0
            while Double(gy) * pitch + py + pitch <= Double(h) {
                var gx = 0
                while Double(gx) * pitch + px + pitch <= Double(w) {
                    let x0 = Int(Double(gx) * pitch + px), y0 = Int(Double(gy) * pitch + py)
                    let x1 = Int(Double(gx + 1) * pitch + px), y1 = Int(Double(gy + 1) * pitch + py)
                    var warm = 0, dark = 0, total = 0
                    for y in y0..<min(y1, h) {
                        for x in x0..<min(x1, w) {
                            total += 1
                            let i = (y * w + x) * 4
                            guard buf[i + 3] != 0 else { continue }
                            if isWarm(buf, i) { warm += 1 }
                            else if max(buf[i], max(buf[i + 1], buf[i + 2])) < 115 { dark += 1 }
                        }
                    }
                    if total > 0 {
                        if dark * 100 >= total * 80 { score += 10 }
                        if warm * 100 >= total * 90 { score += 1 }
                    }
                    gx += 1
                }
                gy += 1
            }
            if score > best.score { best = (score, px, py) }
            px += 1
        }
        py += 1
    }
    return (best.px, best.py)
}

// (구) 눈 블록 기반 보정 — 잘못된 덩어리를 잡는 사례가 있어 calibrateByPurity로 대체
func findEyeGrid(_ buf: [UInt8], _ w: Int, _ h: Int) -> (pitch: Double, phx: Double, phy: Double)? {
    var seen = [Bool](repeating: false, count: w * h)
    var best: (area: Int, minX: Int, minY: Int, maxX: Int, maxY: Int)?
    for start in 0..<(w * h) where !seen[start] {
        let si = start * 4
        guard buf[si + 3] != 0, max(buf[si], max(buf[si + 1], buf[si + 2])) < 70 else { continue }
        var stack = [start]
        seen[start] = true
        var minX = w, minY = h, maxX = 0, maxY = 0, area = 0
        while let p = stack.popLast() {
            area += 1
            let x = p % w, y = p / w
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
            for q in [x > 0 ? p - 1 : -1, x < w - 1 ? p + 1 : -1,
                      y > 0 ? p - w : -1, y < h - 1 ? p + w : -1] {
                guard q >= 0, !seen[q] else { continue }
                let qi = q * 4
                if buf[qi + 3] != 0, max(buf[qi], max(buf[qi + 1], buf[qi + 2])) < 70 {
                    seen[q] = true
                    stack.append(q)
                }
            }
        }
        let bw = maxX - minX + 1, bh = maxY - minY + 1
        // 눈 후보: 아트 1픽셀(±) 크기의 정사각형 덩어리
        if area >= 60, area <= 260, bw >= 9, bw <= 15, bh >= 9, bh <= 15 {
            if best == nil || area > best!.area { best = (area, minX, minY, maxX, maxY) }
        }
    }
    guard let e = best else { return nil }
    let pitch = Double((e.maxX - e.minX + 1) + (e.maxY - e.minY + 1)) / 2
    return (pitch,
            Double(e.minX).truncatingRemainder(dividingBy: pitch),
            Double(e.minY).truncatingRemainder(dividingBy: pitch))
}

// 몸을 격자 칸 단위로 재구성 — 들쭉날쭉한 AA 가장자리를 칸으로 스냅
var dbgBlack = 0
var dbgBody = 0
var dbgVerbose = false

func quantizeBody(_ buf: inout [UInt8], _ w: Int, _ h: Int,
                  pitch: Double, phx: Double, phy: Double,
                  bodyLight: (UInt8, UInt8, UInt8), bodyShade: (UInt8, UInt8, UInt8),
                  shadeLumCut: Int) {
    let cols = Int((Double(w) - phx) / pitch) + 1
    let rows = Int((Double(h) - phy) / pitch) + 1
    var kind = [[Int]](repeating: [Int](repeating: 0, count: cols), count: rows)   // 0 빈칸 1 몸(밝음) 2 검정후보 4 몸(그늘)
    var warmPct = [[Int]](repeating: [Int](repeating: 0, count: cols), count: rows)

    func cellRect(_ gx: Int, _ gy: Int) -> (Int, Int, Int, Int)? {
        let x0 = max(0, Int(phx + Double(gx) * pitch))
        let y0 = max(0, Int(phy + Double(gy) * pitch))
        let x1 = min(w, Int(phx + Double(gx + 1) * pitch))
        let y1 = min(h, Int(phy + Double(gy + 1) * pitch))
        return (x1 > x0 && y1 > y0) ? (x0, y0, x1, y1) : nil
    }

    for gy in 0..<rows {
        for gx in 0..<cols {
            guard let (x0, y0, x1, y1) = cellRect(gx, gy) else { continue }
            var warm = 0, dark = 0, lumSum = 0
            let total = (x1 - x0) * (y1 - y0)
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let i = (y * w + x) * 4
                    guard buf[i + 3] != 0 else { continue }
                    if isWarm(buf, i) {
                        warm += 1
                        lumSum += (Int(buf[i]) + Int(buf[i + 1]) + Int(buf[i + 2])) / 3
                    } else if max(buf[i], max(buf[i + 1], buf[i + 2])) < 115 { dark += 1 }   // 압축 영상의 눈은 70보다 밝음
                }
            }
            warmPct[gy][gx] = warm * 100 / total
            // 눈(검정)은 별도 블롭 패스가 전담 — 여기서는 어두운 칸도 몸/빈칸으로만 정리
            if dark * 100 >= total * 40 { kind[gy][gx] = 2 }
            else if warm * 100 >= total * 35 {
                kind[gy][gx] = (lumSum / max(1, warm)) < shadeLumCut ? 4 : 1   // 그늘/밝은 면 투톤
            }
        }
    }
    // 윤곽 정리: 어두운 칸은 내부면 몸으로(위에 눈 블롭이 덧칠됨), 윤곽이면 warm 비율로 몸/빈칸
    for gy in 0..<rows {
        for gx in 0..<cols {
            guard kind[gy][gx] == 2 else { continue }
            let touchesEmpty = (gy == 0 || kind[gy - 1][gx] == 0) || (gy == rows - 1 || kind[gy + 1][gx] == 0)
                || (gx == 0 || kind[gy][gx - 1] == 0) || (gx == cols - 1 || kind[gy][gx + 1] == 0)
            kind[gy][gx] = touchesEmpty ? (warmPct[gy][gx] >= 20 ? 1 : 0) : 1
        }
    }
    var out = [UInt8](repeating: 0, count: w * h * 4)
    for gy in 0..<rows {
        for gx in 0..<cols {
            guard kind[gy][gx] != 0, let (x0, y0, x1, y1) = cellRect(gx, gy) else { continue }
            let c = kind[gy][gx] == 4 ? bodyShade : bodyLight
            dbgBody += 1
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let i = (y * w + x) * 4
                    out[i] = c.0; out[i + 1] = c.1; out[i + 2] = c.2; out[i + 3] = 255
                }
            }
        }
    }
    buf = out
}

// 영상과 같은 모양의 체커 축구공 합성 (지름 24px, 8px 체커, 둥근 실루엣)
func makeBallStamp() -> (buf: [UInt8], size: Int) {
    let S = 26
    var b = [UInt8](repeating: 0, count: S * S * 4)
    let c = Double(S) / 2 - 0.5
    for y in 0..<S {
        for x in 0..<S {
            let dx = Double(x) - c, dy = Double(y) - c
            guard dx * dx + dy * dy <= 12.0 * 12.0 else { continue }
            let i = (y * S + x) * 4
            let darkCell = ((x + 5) / 8 + (y + 3) / 8) % 2 == 0
            if darkCell { b[i] = 0x1E; b[i + 1] = 0x20; b[i + 2] = 0x24 }
            else { b[i] = 0xF4; b[i + 1] = 0xF2; b[i + 2] = 0xEC }
            b[i + 3] = 255
        }
    }
    return (b, S)
}

func makeImage(_ buf: inout [UInt8], _ w: Int, _ h: Int) -> CGImage? {
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    return ctx.makeImage()
}

func savePNG(_ cg: CGImage, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: outDir.appendingPathComponent(name))
}

// Pass A: 전 프레임 정제 + 공 중심 기록
var frames: [(buf: [UInt8], w: Int, h: Int, cx: Double, cy: Double, white: Int)] = []
for i in 0..<frameCount {
    let t = CMTime(seconds: startSec + Double(i) * 0.1, preferredTimescale: 600)
    guard let full = try? gen.copyCGImage(at: t, actualTime: nil),
          let crop = full.cropping(to: cropRect),
          let (buf, w, h) = process(crop) else {
        print("frame \(i) 실패"); continue
    }
    let c = ballCentroid(buf, w, h)
    frames.append((buf, w, h, c.x, c.y, c.count))
    print(String(format: "f%02d ball=(%.0f,%.0f) white=%d", i, c.x, c.y, c.count))   // 루프 이음새 점검용
}

// 격자 보정(frame 0의 눈 기준) + 몸 색 중앙값 + 합성 체커볼
let R = 17
guard let f0 = frames.first else { exit(2) }
let grid = calibrateByPurity(f0.buf, f0.w, f0.h)
print(String(format: "grid pitch=%.1f phase=(%.0f,%.0f)", grid.pitch, grid.phx, grid.phy))
// 투톤 음영: f0의 warm 픽셀을 명도순 정렬 — 밝은 면/그늘 면 대표색과 경계 명도 산출
var warms: [(Int, Int, Int, Int)] = []   // (r,g,b,lum)
for p in 0..<(f0.w * f0.h) {
    let i = p * 4
    if f0.buf[i + 3] != 0, isWarm(f0.buf, i) {
        let r = Int(f0.buf[i]), g = Int(f0.buf[i + 1]), b = Int(f0.buf[i + 2])
        warms.append((r, g, b, (r + g + b) / 3))
    }
}
warms.sort { $0.3 < $1.3 }
let shadeRef = warms[warms.count / 8]                 // 하위 ~12% 명도 = 그늘 대표
let lightRef = warms[warms.count * 2 / 3]             // 상위쪽 = 밝은 면 대표
let bodyLight = (UInt8(lightRef.0), UInt8(lightRef.1), UInt8(lightRef.2))
let bodyShade = (UInt8(shadeRef.0), UInt8(shadeRef.1), UInt8(shadeRef.2))
let shadeLumCut = (shadeRef.3 + lightRef.3) / 2
print("tone light=\(lightRef) shade=\(shadeRef) cut=\(shadeLumCut)")
let (ballBuf, ballS) = makeBallStamp()

// Pass B: 모든 프레임의 공을 도장으로 교체 (모션블러 제거) — 중심 없으면 이웃 보간
for i in frames.indices {
    var (buf, w, h, cx, cy, white) = frames[i]
    if white < 10 {
        let prev = frames[..<i].last { $0.white >= 10 }
        let next = frames[(i + 1)...].first { $0.white >= 10 }
        if let p = prev, let n = next { cx = (p.cx + n.cx) / 2; cy = (p.cy + n.cy) / 2 }
        else if let p = prev { cx = p.cx; cy = p.cy }
        else if let n = next { cx = n.cx; cy = n.cy }
    }
    // 기존 공/잔상 지우기 — 공 반지름 원(13px) 안으로 한정 (사각 박스로 하면 인접한 눈까지 연쇄 삭제됨)
    let eraseR2 = 13 * 13
    for dy in -R...R {
        for dx in -R...R {
            guard dx * dx + dy * dy <= eraseR2 else { continue }
            let x = Int(cx) + dx, y = Int(cy) + dy
            guard x >= 0, x < w, y >= 0, y < h else { continue }
            let i4 = (y * w + x) * 4
            guard buf[i4 + 3] != 0, !isWarm(buf, i4) else { continue }
            let mn = Int(min(buf[i4], min(buf[i4 + 1], buf[i4 + 2])))
            if mn > 120 {
                buf[i4] = 0; buf[i4 + 1] = 0; buf[i4 + 2] = 0; buf[i4 + 3] = 0
            }
        }
    }
    // 어두운 픽셀(체커)은 지워진 자리에 연쇄로 붙은 것만, 역시 원 안에서만 삭제
    for _ in 0..<4 {
        for dy in -R...R {
            for dx in -R...R {
                guard dx * dx + dy * dy <= eraseR2 else { continue }
                let x = Int(cx) + dx, y = Int(cy) + dy
                guard x > 0, x < w - 1, y > 0, y < h - 1 else { continue }
                let i4 = (y * w + x) * 4
                guard buf[i4 + 3] != 0, !isWarm(buf, i4) else { continue }
                let p = y * w + x
                if buf[(p - 1) * 4 + 3] == 0 || buf[(p + 1) * 4 + 3] == 0 ||
                   buf[(p - w) * 4 + 3] == 0 || buf[(p + w) * 4 + 3] == 0 {
                    buf[i4] = 0; buf[i4 + 1] = 0; buf[i4 + 2] = 0; buf[i4 + 3] = 0
                }
            }
        }
    }
    dbgBlack = 0; dbgBody = 0
    // 캐릭터가 프레임마다 이동하므로 위상은 프레임별 재탐색 (pitch는 고정)
    let pre = buf   // 눈 오버레이용 원본 보존 (공은 이미 지워짐)
    let ph = calibratePhase(buf, w, h, pitch: grid.pitch)
    quantizeBody(&buf, w, h, pitch: grid.pitch, phx: ph.phx, phy: ph.phy,
                 bodyLight: bodyLight, bodyShade: bodyShade, shadeLumCut: shadeLumCut)
    // 눈 복원: pre의 어두운 내부 블롭(윤곽 비접촉, 눈 크기)만 찾아 격자 스냅 사각형으로 그림
    // — 픽셀 그대로 얹으면 AA 뭉개짐·윤곽 검은 선이 생김 (Boss 확대 짤 2026-06-13)
    var eyeSeen = [Bool](repeating: false, count: w * h)
    for start in 0..<(w * h) where !eyeSeen[start] {
        let si = start * 4
        guard pre[si + 3] != 0, !isWarm(pre, si),
              max(pre[si], max(pre[si + 1], pre[si + 2])) < 115 else { continue }
        var stack = [start]
        eyeSeen[start] = true
        var members: [Int] = []
        var edgeTouch = 0
        var minX = w, minY = h, maxX = 0, maxY = 0
        while let p = stack.popLast() {
            members.append(p)
            let x = p % w, y = p / w
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
            var touching = false
            for q in [x > 0 ? p - 1 : -1, x < w - 1 ? p + 1 : -1,
                      y > 0 ? p - w : -1, y < h - 1 ? p + w : -1] {
                guard q >= 0 else { touching = true; continue }
                let qi = q * 4
                if pre[qi + 3] == 0 { touching = true; continue }
                if !eyeSeen[q], !isWarm(pre, qi),
                   max(pre[qi], max(pre[qi + 1], pre[qi + 2])) < 115 {
                    eyeSeen[q] = true
                    stack.append(q)
                }
            }
            if touching { edgeTouch += 1 }
        }
        // 눈 판정: 내부 블롭(윤곽 접촉 15% 미만), 면적 25~160, 종횡비 정상
        let area = members.count
        let bw = maxX - minX + 1, bh = maxY - minY + 1
        guard area >= 25, area <= 160, edgeTouch * 100 < area * 15,
              bw <= 16, bh <= 16 else { continue }
        // 정규화: 모든 프레임에서 같은 크기(2×2칸)의 정사각 눈 — 중심을 격자에 스냅
        let p = grid.pitch
        let cx2 = Double(minX + maxX) / 2, cy2 = Double(minY + maxY) / 2
        let gx0 = ((cx2 - p - ph.phx) / p).rounded()
        let gy0 = ((cy2 - p - ph.phy) / p).rounded()
        let x0 = max(0, Int(ph.phx + gx0 * p)), y0 = max(0, Int(ph.phy + gy0 * p))
        let x1 = min(w, Int(ph.phx + (gx0 + 2) * p)), y1 = min(h, Int(ph.phy + (gy0 + 2) * p))
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * w + x) * 4
                guard buf[i + 3] != 0 else { continue }   // 몸 안쪽만
                buf[i] = 0x14; buf[i + 1] = 0x14; buf[i + 2] = 0x17
            }
        }
    }
    if i == 0 { print("f00 quantize: body=\(dbgBody) black=\(dbgBlack)") }
    // 합성 체커볼 부착 (영상과 같은 모양, 침식 없는 정원형)
    let bx = Int(cx) - ballS / 2, by = Int(cy) - ballS / 2
    for sy in 0..<ballS {
        for sx in 0..<ballS {
            let si = (sy * ballS + sx) * 4
            guard ballBuf[si + 3] != 0 else { continue }
            let x = bx + sx, y = by + sy
            guard x >= 0, x < w, y >= 0, y < h else { continue }
            let i4 = (y * w + x) * 4
            buf[i4] = ballBuf[si]; buf[i4 + 1] = ballBuf[si + 1]
            buf[i4 + 2] = ballBuf[si + 2]; buf[i4 + 3] = 255
        }
    }
    var clawdBuf = buf
    if let img = makeImage(&clawdBuf, w, h) { savePNG(img, String(format: "clawd_juggle_%02d.png", i)) }
    var codyBuf = buf
    recolorIndigo(&codyBuf, w, h)
    if let img = makeImage(&codyBuf, w, h) { savePNG(img, String(format: "cody_juggle_%02d.png", i)) }
}
print("done -> \(outDir.path)")
