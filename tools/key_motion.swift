import AVFoundation
import AppKit

// 공식 에셋(흰 배경 gif/mov) → 위젯 스프라이트 시퀀스
// 흰 배경 flood 키잉 → 전 프레임 공통 bbox 크롭 → clawd 원본 + cody(테라코타→인디고) 저장.
// 화면 녹화와 달리 원본이 무손실이라 양자화·디프린지가 필요 없다.
// usage: key_motion <input.gif|mov> <outdir> <motionName> [maxFrames]

let args = CommandLine.arguments
guard args.count >= 4 else {
    print("usage: key_motion <input> <outdir> <motionName> [maxFrames]")
    exit(1)
}
let inputURL = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])
let motion = args[3]
let maxFrames = args.count > 4 ? (Int(args[4]) ?? 999) : 999
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func rgba(_ cg: CGImage) -> (buf: [UInt8], w: Int, h: Int)? {
    let w = cg.width, h = cg.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (buf, w, h)
}

// 흰/거의 흰 배경 — 외곽 연결분만 제거 (돋보기 렌즈 속 흰색 등 내부는 보존)
func keyWhite(_ buf: inout [UInt8], _ w: Int, _ h: Int) {
    var visited = [Bool](repeating: false, count: w * h)
    var stack: [Int] = []
    for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
    for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }
    while let p = stack.popLast() {
        if p < 0 || p >= w * h || visited[p] { continue }
        visited[p] = true
        let i = p * 4
        guard buf[i + 3] != 0,
              min(buf[i], min(buf[i + 1], buf[i + 2])) > 235 else { continue }
        buf[i] = 0; buf[i + 1] = 0; buf[i + 2] = 0; buf[i + 3] = 0
        let x = p % w, y = p / w
        if x > 0 { stack.append(p - 1) }
        if x < w - 1 { stack.append(p + 1) }
        if y > 0 { stack.append(p - w) }
        if y < h - 1 { stack.append(p + w) }
    }
}

// 테라코타 피부만 인디고로 (모자 검정/밤색, 돋보기 남색은 유지)
func recolorIndigo(_ buf: inout [UInt8], _ w: Int, _ h: Int) {
    for p in 0..<(w * h) {
        let i = p * 4
        guard buf[i + 3] > 0 else { continue }
        let r = Double(buf[i]), g = Double(buf[i + 1]), bl = Double(buf[i + 2])
        if r > 140, g > 80, g < 175, bl > 45, bl < 135, r > g, g > bl {
            let lum = min(1.2, (r + g + bl) / 3.0 / 175.0)
            buf[i] = UInt8(min(255, 100 * lum))
            buf[i + 1] = UInt8(min(255, 112 * lum))
            buf[i + 2] = UInt8(min(255, 243 * lum))
        }
    }
}

func savePNG(_ buf: inout [UInt8], _ w: Int, _ h: Int, _ name: String) {
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let img = ctx.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: img)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: outDir.appendingPathComponent(name))
}

// 프레임 로드 (gif 전체 / mov는 0.1s 간격)
var rawFrames: [CGImage] = []
if inputURL.pathExtension.lowercased() == "gif" {
    guard let src = CGImageSourceCreateWithURL(inputURL as CFURL, nil) else { exit(2) }
    let n = min(CGImageSourceGetCount(src), maxFrames)
    for i in 0..<n {
        if let cg = CGImageSourceCreateImageAtIndex(src, i, nil) { rawFrames.append(cg) }
    }
} else {
    let asset = AVURLAsset(url: inputURL)
    let gen = AVAssetImageGenerator(asset: asset)
    gen.requestedTimeToleranceBefore = .zero
    gen.requestedTimeToleranceAfter = .zero
    let secs = CMTimeGetSeconds(asset.duration)
    var t = 0.0
    while t < secs, rawFrames.count < maxFrames {
        if let cg = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) {
            rawFrames.append(cg)
        }
        t += 0.1
    }
}
print("frames: \(rawFrames.count)")

// 키잉 + 공통 bbox 산출
var keyed: [(buf: [UInt8], w: Int, h: Int)] = []
var minX = Int.max, minY = Int.max, maxX = 0, maxY = 0
for cg in rawFrames {
    guard var (buf, w, h) = rgba(cg) else { continue }
    keyWhite(&buf, w, h)
    for p in 0..<(w * h) where buf[p * 4 + 3] != 0 {
        let x = p % w, y = p / w
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
    keyed.append((buf, w, h))
}
minX = max(0, minX - 8); minY = max(0, minY - 8)
print("bbox: (\(minX),\(minY))-(\(maxX),\(maxY))")

for (idx, f) in keyed.enumerated() {
    let cw = min(f.w - 1, maxX + 8) - minX + 1
    let ch = min(f.h - 1, maxY + 8) - minY + 1
    var crop = [UInt8](repeating: 0, count: cw * ch * 4)
    for y in 0..<ch {
        for x in 0..<cw {
            let si = ((y + minY) * f.w + (x + minX)) * 4
            let di = (y * cw + x) * 4
            crop[di] = f.buf[si]; crop[di + 1] = f.buf[si + 1]
            crop[di + 2] = f.buf[si + 2]; crop[di + 3] = f.buf[si + 3]
        }
    }
    var clawd = crop
    savePNG(&clawd, cw, ch, String(format: "clawd_%@_%02d.png", motion, idx))
    var cody = crop
    recolorIndigo(&cody, cw, ch)
    savePNG(&cody, cw, ch, String(format: "cody_%@_%02d.png", motion, idx))
}
print("done -> \(outDir.path)")
