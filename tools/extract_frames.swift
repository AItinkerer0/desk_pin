import AVFoundation
import AppKit

// usage: extract_frames <input.mov|input.gif> <outdir> [count]
// mov: count장을 균등 간격으로 추출 / gif: 전체 프레임 추출
let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: extract_frames <input> <outdir> [count]")
    exit(1)
}
let url = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])
let count = args.count > 3 ? (Int(args[3]) ?? 8) : 8
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func savePNG(_ cg: CGImage, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: outDir.appendingPathComponent(name))
}

if url.pathExtension.lowercased() == "gif" {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        print("cannot open gif"); exit(2)
    }
    let n = CGImageSourceGetCount(src)
    print("gif frames: \(n)")
    let base = url.deletingPathExtension().lastPathComponent
    for i in 0..<n {
        if let cg = CGImageSourceCreateImageAtIndex(src, i, nil) {
            savePNG(cg, String(format: "%@_%03d.png", base, i))
        }
    }
} else {
    let asset = AVURLAsset(url: url)
    let gen = AVAssetImageGenerator(asset: asset)
    gen.requestedTimeToleranceBefore = .zero
    gen.requestedTimeToleranceAfter = .zero
    gen.appliesPreferredTrackTransform = true
    let secs = CMTimeGetSeconds(asset.duration)
    print("duration: \(secs)s")
    let base = url.deletingPathExtension().lastPathComponent
    for i in 0..<count {
        let t = CMTime(seconds: secs * Double(i) / Double(count), preferredTimescale: 600)
        if let cg = try? gen.copyCGImage(at: t, actualTime: nil) {
            savePNG(cg, String(format: "%@_%03d.png", base, i))
        }
    }
}
print("done -> \(outDir.path)")
