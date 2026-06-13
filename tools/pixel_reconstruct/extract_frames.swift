import AVFoundation
import AppKit

// Usage: swift extract_frames.swift <input.mov> <outdir>
let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: extract_frames.swift <input.mov> <outdir>")
    exit(1)
}
let url = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let asset = AVURLAsset(url: url)
let sem = DispatchSemaphore(value: 0)

Task {
    do {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            print("ERROR: no video track"); exit(2)
        }
        let fps = try await track.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)
        let size = try await track.load(.naturalSize)
        print("META nominalFPS=\(fps) duration=\(CMTimeGetSeconds(duration)) size=\(Int(size.width))x\(Int(size.height))")

        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()

        var idx = 0
        let ctx = CIContext()
        while let sample = output.copyNextSampleBuffer() {
            guard let pb = CMSampleBufferGetImageBuffer(sample) else { continue }
            let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
            let ci = CIImage(cvPixelBuffer: pb)
            guard let cg = ctx.createCGImage(ci, from: ci.extent) else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            let name = String(format: "f%05d_%.4f.png", idx, pts)
            try png.write(to: outDir.appendingPathComponent(name))
            idx += 1
        }
        if reader.status == .failed {
            print("ERROR: reader failed: \(String(describing: reader.error))"); exit(3)
        }
        print("DONE frames=\(idx)")
        sem.signal()
    } catch {
        print("ERROR: \(error)"); exit(4)
    }
}
sem.wait()
