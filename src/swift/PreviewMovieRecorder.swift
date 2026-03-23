import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo

/// Records the currently displayed preview stream to a lightweight H.264 MOV.
/// The recorder accepts already-rendered CGImages so the GUI, still capture,
/// and video capture paths all share the same preview pipeline.
final class PreviewMovieRecorder {
    let outputURL: URL

    private let width: Int
    private let height: Int
    private let writerTimeScale: Int32 = 600
    private let minFrameStep = CMTime(value: 1, timescale: 240)
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var frameIndex: Int64 = 0
    private var started = false
    private var recordingStartDate: Date?
    private var lastPresentationTime = CMTime.invalid

    init(outputURL: URL, width: Int, height: Int, qualityPreset: VideoQualityPreset) throws {
        self.outputURL = outputURL
        self.width = max(2, width & ~1)
        self.height = max(2, height & ~1)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: qualityPreset.averageBitRate(width: self.width, height: self.height),
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoMaxKeyFrameIntervalKey: 30
        ]

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: self.width,
            AVVideoHeightKey: self.height,
            AVVideoCompressionPropertiesKey: compression
        ]

        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: self.width,
            kCVPixelBufferHeightKey as String: self.height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)

        guard writer.canAdd(input) else {
            throw NSError(domain: "PreviewMovieRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video writer input"])
        }
        writer.add(input)
    }

    func appendFrame(_ image: CGImage) -> Bool {
        if !started {
            guard writer.startWriting() else {
                return false
            }
            writer.startSession(atSourceTime: .zero)
            started = true
            recordingStartDate = Date()
            lastPresentationTime = .zero
        }

        guard input.isReadyForMoreMediaData else {
            return false
        }
        guard let pixelBuffer = makePixelBuffer(from: image) else {
            return false
        }

        let time = nextPresentationTime()
        let ok = adaptor.append(pixelBuffer, withPresentationTime: time)
        if ok {
            frameIndex += 1
            lastPresentationTime = time
        }
        return ok
    }

    func finish(completion: @escaping (Error?) -> Void) {
        guard started else {
            writer.cancelWriting()
            completion(nil)
            return
        }

        input.markAsFinished()
        writer.finishWriting {
            switch self.writer.status {
            case .completed:
                completion(nil)
            case .failed, .cancelled:
                completion(self.writer.error ?? NSError(domain: "PreviewMovieRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Video writer did not complete"] ))
            default:
                completion(nil)
            }
        }
    }

    private func nextPresentationTime() -> CMTime {
        guard let recordingStartDate else {
            return .zero
        }
        if frameIndex == 0 {
            return .zero
        }

        // Use wall-clock deltas when possible, but guarantee monotonic sample
        // times so AVAssetWriter never sees duplicate or reversed timestamps.
        let elapsed = max(0.0, Date().timeIntervalSince(recordingStartDate))
        var candidate = CMTime(seconds: elapsed, preferredTimescale: writerTimeScale)
        if !CMTIME_IS_VALID(lastPresentationTime) {
            return candidate
        }
        if CMTimeCompare(candidate, lastPresentationTime) <= 0 {
            candidate = CMTimeAdd(lastPresentationTime, minFrameStep)
        }
        return candidate
    }

    private func makePixelBuffer(from image: CGImage) -> CVPixelBuffer? {
        var pixelBufferOut: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool else { return nil }
        let rc = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBufferOut)
        guard rc == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let ctx = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        // Clear first so odd-sized source frames that were rounded up to even
        // encoder dimensions do not leave stale pixels in the padded edge.
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .none

        let drawRect = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.draw(image, in: drawRect)
        return pixelBuffer
    }
}
