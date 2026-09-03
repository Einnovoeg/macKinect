import Foundation
import CoreGraphics

/// Output formats supported by the 3D scanner. Each format includes a file
/// extension and a short label used by the SwiftUI picker.
enum PointCloudFormat: String, CaseIterable, Identifiable {
    case plyAscii
    case plyBinary
    case obj
    case xyz

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plyAscii: return "PLY (ASCII)"
        case .plyBinary: return "PLY (Binary)"
        case .obj: return "Wavefront OBJ"
        case .xyz: return "XYZ Point Cloud"
        }
    }

    var fileExtension: String { "ply" }

    /// Some formats can carry per-vertex color. When color is missing, the
    /// exporter falls back to grayscale derived from depth.
    var supportsColor: Bool {
        switch self {
        case .plyAscii, .plyBinary, .obj, .xyz: return true
        }
    }
}

/// Configuration for a single capture request, including optional batch
/// parameters used to collect multiple frames in one session.
struct ScanCaptureRequest {
    var frameCount: Int = 1
    var intervalSeconds: Double = 0.5
    var pointCloudFormat: PointCloudFormat = .plyAscii
    var runRegistration: Bool = false
    var writeColorPpm: Bool = true
    var writeIrPgm: Bool = true
    var writeDepthPgm: Bool = true
}

/// Snapshot of a single frame that the scanner can persist, reproject, and
/// later feed into registration.
struct ScanFrame: Codable {
    let index: Int
    let width: Int
    let height: Int
    let generation: Int
    let timestamp: String
    let rgbPath: String?
    let depthPath: String?
    let irPath: String?
    let pointCloudPath: String?
    let pointCount: Int
}

/// A persisted scanner session, including the ordered list of captured frames
/// and a registration summary written next to the captured files.
struct ScanSessionManifest: Codable {
    let sessionId: String
    let createdAt: String
    let generation: Int
    let format: String
    let registered: Bool
    let frames: [ScanFrame]
    let mergedPointCloud: String?
    let mergedPointCount: Int
}

/// Result of a capture or merge request, surfaced back to the UI layer.
struct ScanOperationResult {
    let sessionDirectory: URL
    let frameCount: Int
    let totalPoints: Int
    let mergedPointCount: Int
    let format: PointCloudFormat
    let registered: Bool
    let message: String
}

/// Pure-data container for a back-projected point cloud. Holding it as a
/// value type keeps registration output independent of the bridge frame
/// lifetimes.
struct PointCloud {
    struct Point {
        var x: Double
        var y: Double
        var z: Double
        var r: UInt8
        var g: UInt8
        var b: UInt8
    }

    var points: [Point]

    var isEmpty: Bool { points.isEmpty }
    var count: Int { points.count }
}

/// 3D-scanner facade. Captures frames, writes per-frame artifacts, runs
/// optional ICP registration between consecutive frames, and produces a
/// merged point cloud covering the whole session.
final class KinectScanner {
    static let shared = KinectScanner()

    private let intrinsicsProvider: (Int, Int, Int) -> (fx: Double, fy: Double, cx: Double, cy: Double)
    private let captureRoot: URL

    init(
        intrinsicsProvider: @escaping (Int, Int, Int) -> (fx: Double, fy: Double, cx: Double, cy: Double) = KinectScanner.defaultIntrinsics,
        captureRoot: URL? = nil
    ) {
        self.intrinsicsProvider = intrinsicsProvider
        if let captureRoot {
            self.captureRoot = captureRoot
        } else {
            self.captureRoot = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures", isDirectory: true)
                .appendingPathComponent("KinectCaptures", isDirectory: true)
        }
    }

    // MARK: - Public entry points

    /// Capture a single frame and write a complete scan bundle. The directory
    /// layout mirrors the legacy `captureScanBundle` so existing automation
    /// keeps working.
    func captureSingle(
        frameProvider: () -> KinectFrameSnapshot?,
        generation: Int,
        format: PointCloudFormat = .plyAscii
    ) throws -> ScanOperationResult {
        let request = ScanCaptureRequest(pointCloudFormat: format)
        return try capture(request: request, frameProvider: frameProvider, generation: generation)
    }

    /// Capture multiple frames spaced by `request.intervalSeconds` and write
    /// them into a single session directory. If `request.runRegistration` is
    /// true, consecutive frames are ICP-registered into a merged cloud.
    func capture(
        request: ScanCaptureRequest,
        frameProvider: () -> KinectFrameSnapshot?,
        generation: Int
    ) throws -> ScanOperationResult {
        let sessionDir = try makeSessionDirectory()
        var frames: [ScanFrame] = []
        var totalPoints = 0
        var pointClouds: [PointCloud] = []
        var latestFormat: PointCloudFormat = request.pointCloudFormat
        var merged: PointCloud = PointCloud(points: [])

        let count = max(1, request.frameCount)
        let interval = max(0.0, request.intervalSeconds)

        for index in 0..<count {
            guard let snapshot = frameProvider() else {
                if index == 0 {
                    throw NSError(domain: "KinectScanner", code: 3001, userInfo: [NSLocalizedDescriptionKey: "No frame available for capture."])
                }
                break
            }
            let frame = try writeFrameArtifacts(
                snapshot: snapshot,
                index: index,
                sessionDir: sessionDir,
                request: request,
                generation: generation
            )
            frames.append(frame)
            totalPoints += frame.pointCount
            if let cloud = try? buildPointCloud(snapshot: snapshot, generation: generation) {
                pointClouds.append(cloud)
            }
            latestFormat = request.pointCloudFormat

            if index < count - 1, interval > 0 {
                Thread.sleep(forTimeInterval: interval)
            }
        }

        if request.runRegistration, pointClouds.count >= 2 {
            do {
                merged = try PointCloudMerger.mergeConsecutive(pointClouds)
            } catch {
                merged = PointCloud(points: pointClouds.flatMap { $0.points })
            }
        } else {
            merged = PointCloud(points: pointClouds.flatMap { $0.points })
        }

        var mergedPath: String? = nil
        if !merged.isEmpty {
            let mergedURL = sessionDir.appendingPathComponent("merged.\(latestFormat.fileExtension)")
            try write(pointCloud: merged, format: latestFormat, to: mergedURL)
            mergedPath = mergedURL.path
        }

        let manifest = ScanSessionManifest(
            sessionId: sessionDir.lastPathComponent,
            createdAt: timestampForManifest(date: Date()),
            generation: generation,
            format: latestFormat.rawValue,
            registered: request.runRegistration && pointClouds.count >= 2,
            frames: frames,
            mergedPointCloud: mergedPath,
            mergedPointCount: merged.count
        )

        let manifestURL = sessionDir.appendingPathComponent("session.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: manifestURL, options: .atomic)

        return ScanOperationResult(
            sessionDirectory: sessionDir,
            frameCount: frames.count,
            totalPoints: totalPoints,
            mergedPointCount: merged.count,
            format: latestFormat,
            registered: manifest.registered,
            message: "Captured \(frames.count) frame(s) into \(sessionDir.lastPathComponent)."
        )
    }

    /// Merge every subdirectory under `sessionsRoot` that contains a
    /// `session.json` into a single point cloud. The combined cloud is
    /// written into `outputURL` using `format`.
    func mergeSessions(
        sessionsRoot: URL,
        outputURL: URL,
        format: PointCloudFormat
    ) throws -> Int {
        let fileManager = FileManager.default
        let entries = try fileManager.contentsOfDirectory(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var combined: [PointCloud.Point] = []
        for entry in entries {
            let manifestURL = entry.appendingPathComponent("session.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }
            let mergedURL = entry.appendingPathComponent("merged.ply")
            guard fileManager.fileExists(atPath: mergedURL.path) else { continue }
            let cloud = try loadPointCloud(from: mergedURL)
            combined.append(contentsOf: cloud.points)
        }
        let merged = PointCloud(points: combined)
        try write(pointCloud: merged, format: format, to: outputURL)
        return merged.count
    }

    // MARK: - Frame artifact writing

    private func writeFrameArtifacts(
        snapshot: KinectFrameSnapshot,
        index: Int,
        sessionDir: URL,
        request: ScanCaptureRequest,
        generation: Int
    ) throws -> ScanFrame {
        let frameDir = sessionDir.appendingPathComponent(String(format: "frame-%03d", index), isDirectory: true)
        try FileManager.default.createDirectory(at: frameDir, withIntermediateDirectories: true)

        let timestamp = timestampForManifest(date: Date())
        var rgbPath: String? = nil
        var depthPath: String? = nil
        var irPath: String? = nil
        var pointCloudPath: String? = nil
        var pointCount = 0

        let pixelCount = snapshot.width * snapshot.height
        if request.writeColorPpm, snapshot.rgb.count >= pixelCount * 3 {
            let url = frameDir.appendingPathComponent("color.ppm")
            try writePPM(rgb: snapshot.rgb, width: snapshot.width, height: snapshot.height, to: url)
            rgbPath = url.path
        }
        if request.writeDepthPgm, snapshot.depth.count >= pixelCount * 2 {
            let url = frameDir.appendingPathComponent("depth_mm.pgm")
            try writePGM16(depth: snapshot.depth, width: snapshot.width, height: snapshot.height, to: url)
            depthPath = url.path
        }
        if request.writeIrPgm, snapshot.ir.count >= pixelCount {
            let url = frameDir.appendingPathComponent("infrared.pgm")
            try writePGM8(gray: snapshot.ir, width: snapshot.width, height: snapshot.height, to: url)
            irPath = url.path
        }

        if snapshot.depth.count >= pixelCount * 2 {
            do {
                let cloud = try buildPointCloud(snapshot: snapshot, generation: generation)
                pointCount = cloud.count
                let url = frameDir.appendingPathComponent("cloud.\(request.pointCloudFormat.fileExtension)")
                try write(pointCloud: cloud, format: request.pointCloudFormat, to: url)
                pointCloudPath = url.path
            } catch {
                pointCount = 0
            }
        }

        return ScanFrame(
            index: index,
            width: snapshot.width,
            height: snapshot.height,
            generation: generation,
            timestamp: timestamp,
            rgbPath: rgbPath,
            depthPath: depthPath,
            irPath: irPath,
            pointCloudPath: pointCloudPath,
            pointCount: pointCount
        )
    }

    // MARK: - Image and point cloud helpers

    private func writePPM(rgb: Data, width: Int, height: Int, to url: URL) throws {
        let expected = width * height * 3
        var output = Data("P6\n\(width) \(height)\n255\n".utf8)
        output.append(rgb.prefix(expected))
        try output.write(to: url, options: .atomic)
    }

    private func writePGM8(gray: Data, width: Int, height: Int, to url: URL) throws {
        let expected = width * height
        var output = Data("P5\n\(width) \(height)\n255\n".utf8)
        output.append(gray.prefix(expected))
        try output.write(to: url, options: .atomic)
    }

    private func writePGM16(depth: Data, width: Int, height: Int, to url: URL) throws {
        let pixelCount = width * height
        let expected = pixelCount * 2
        guard depth.count >= expected else {
            throw NSError(domain: "KinectScanner", code: 3002, userInfo: [NSLocalizedDescriptionKey: "Depth frame is incomplete."])
        }
        var bytes = [UInt8](repeating: 0, count: expected)
        depth.withUnsafeBytes { rawBuffer in
            let typed = rawBuffer.bindMemory(to: UInt16.self)
            for i in 0..<pixelCount {
                let value = UInt16(littleEndian: typed[i])
                bytes[i * 2] = UInt8((value >> 8) & 0xFF)
                bytes[i * 2 + 1] = UInt8(value & 0xFF)
            }
        }
        var output = Data("P5\n\(width) \(height)\n65535\n".utf8)
        output.append(contentsOf: bytes)
        try output.write(to: url, options: .atomic)
    }

    func buildPointCloud(snapshot: KinectFrameSnapshot, generation: Int) throws -> PointCloud {
        let pixelCount = snapshot.width * snapshot.height
        let expectedDepth = pixelCount * 2
        guard snapshot.depth.count >= expectedDepth else {
            throw NSError(domain: "KinectScanner", code: 3003, userInfo: [NSLocalizedDescriptionKey: "Depth frame is incomplete."])
        }
        let intrinsics = intrinsicsProvider(snapshot.width, snapshot.height, generation)
        let hasRgb = snapshot.rgb.count >= pixelCount * 3
        let hasIr = snapshot.ir.count >= pixelCount
        var points: [PointCloud.Point] = []
        points.reserveCapacity(pixelCount)

        snapshot.depth.withUnsafeBytes { rawBuffer in
            let depth = rawBuffer.bindMemory(to: UInt16.self)
            for y in 0..<snapshot.height {
                for x in 0..<snapshot.width {
                    let index = y * snapshot.width + x
                    let d = UInt16(littleEndian: depth[index])
                    if d < 350 || d > 6000 { continue }
                    let z = Double(d) / 1000.0
                    let worldX = (Double(x) - intrinsics.cx) / intrinsics.fx * z
                    let worldY = (Double(y) - intrinsics.cy) / intrinsics.fy * z
                    let r: UInt8
                    let g: UInt8
                    let b: UInt8
                    if hasRgb {
                        let rgbIndex = index * 3
                        r = snapshot.rgb[rgbIndex]
                        g = snapshot.rgb[rgbIndex + 1]
                        b = snapshot.rgb[rgbIndex + 2]
                    } else if hasIr {
                        let v = snapshot.ir[index]
                        r = v
                        g = v
                        b = v
                    } else {
                        let t = min(max((Double(d) - 350.0) / 5650.0, 0.0), 1.0)
                        let v = UInt8((1.0 - t) * 255.0)
                        r = v
                        g = v
                        b = v
                    }
                    points.append(PointCloud.Point(x: worldX, y: worldY, z: z, r: r, g: g, b: b))
                }
            }
        }
        return PointCloud(points: points)
    }

    // MARK: - Format writers

    func write(pointCloud: PointCloud, format: PointCloudFormat, to url: URL) throws {
        switch format {
        case .plyAscii: try writePLYAscii(pointCloud, to: url)
        case .plyBinary: try writePLYBinary(pointCloud, to: url)
        case .obj: try writeOBJ(pointCloud, to: url)
        case .xyz: try writeXYZ(pointCloud, to: url)
        }
    }

    private func writePLYAscii(_ cloud: PointCloud, to url: URL) throws {
        let header = """
        ply
        format ascii 1.0
        element vertex \(cloud.count)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header

        """
        var body = String()
        body.reserveCapacity(cloud.count * 26)
        for p in cloud.points {
            body += "\(p.x) \(p.y) \(p.z) \(p.r) \(p.g) \(p.b)\n"
        }
        try (header + body).write(to: url, atomically: true, encoding: .ascii)
    }

    private func writePLYBinary(_ cloud: PointCloud, to url: URL) throws {
        let header = """
        ply
        format binary_little_endian 1.0
        element vertex \(cloud.count)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header

        """
        var data = Data(header.utf8)
        data.reserveCapacity(data.count + cloud.count * 12)
        for p in cloud.points {
            var x = Float(p.x)
            var y = Float(p.y)
            var z = Float(p.z)
            withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &y) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &z) { data.append(contentsOf: $0) }
            data.append(p.r)
            data.append(p.g)
            data.append(p.b)
        }
        try data.write(to: url, options: .atomic)
    }

    private func writeOBJ(_ cloud: PointCloud, to url: URL) throws {
        var body = String()
        body.reserveCapacity(cloud.count * 32)
        for p in cloud.points {
            // OBJ does not natively support per-vertex RGB. Write a material
            // group marker and the vertex with no normal; downstream tools can
            // derive color from a sibling .ply export.
            body += "v \(p.x) \(p.y) \(p.z) \(Double(p.r) / 255.0) \(Double(p.g) / 255.0) \(Double(p.b) / 255.0)\n"
        }
        try body.write(to: url, atomically: true, encoding: .ascii)
    }

    private func writeXYZ(_ cloud: PointCloud, to url: URL) throws {
        var body = String()
        body.reserveCapacity(cloud.count * 32)
        for p in cloud.points {
            body += "\(p.x) \(p.y) \(p.z) \(p.r) \(p.g) \(p.b)\n"
        }
        try body.write(to: url, atomically: true, encoding: .ascii)
    }

    private func loadPointCloud(from url: URL) throws -> PointCloud {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .ascii) else { return PointCloud(points: []) }
        return try parseASCIIPLY(text)
    }

    func parseASCIIPLY(_ text: String) throws -> PointCloud {
        var vertexCount = 0
        var headerEnded = false
        var properties: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            if headerEnded { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("element vertex") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 3, let n = Int(parts[2]) {
                    vertexCount = n
                }
            } else if trimmed.hasPrefix("property") {
                let parts = trimmed.split(separator: " ")
                if let name = parts.last {
                    properties.append(String(name))
                }
            } else if trimmed == "end_header" {
                headerEnded = true
            }
        }
        guard headerEnded else { return PointCloud(points: []) }

        let xIndex = properties.firstIndex(of: "x")
        let yIndex = properties.firstIndex(of: "y")
        let zIndex = properties.firstIndex(of: "z")
        let rIndex = properties.firstIndex(of: "red")
        let gIndex = properties.firstIndex(of: "green")
        let bIndex = properties.firstIndex(of: "blue")

        var points: [PointCloud.Point] = []
        points.reserveCapacity(vertexCount)
        var iterated = 0
        for line in text.split(whereSeparator: \.isNewline) {
            if iterated >= vertexCount { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("ply") || trimmed.hasPrefix("format") || trimmed.hasPrefix("element") || trimmed.hasPrefix("property") || trimmed.hasPrefix("end_header") || trimmed.hasPrefix("comment") {
                continue
            }
            let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard tokens.count >= properties.count else { continue }
            func value(at index: Int?) -> Double {
                guard let index, index < tokens.count else { return 0 }
                return Double(tokens[index]) ?? 0
            }
            func byte(at index: Int?) -> UInt8 {
                guard let index, index < tokens.count else { return 0 }
                return UInt8(min(255, max(0, Int(Double(tokens[index]) ?? 0))))
            }
            points.append(PointCloud.Point(
                x: value(at: xIndex),
                y: value(at: yIndex),
                z: value(at: zIndex),
                r: byte(at: rIndex),
                g: byte(at: gIndex),
                b: byte(at: bIndex)
            ))
            iterated += 1
        }
        return PointCloud(points: points)
    }

    // MARK: - Session directory

    private func makeSessionDirectory() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let dir = captureRoot.appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func timestampForManifest(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.string(from: date)
    }

    // MARK: - Intrinsics

    static func defaultIntrinsics(width: Int, height: Int, generation: Int) -> (fx: Double, fy: Double, cx: Double, cy: Double) {
        if generation == 2, width == 512, height == 424 {
            return (365.456, 365.456, 254.878, 205.395)
        }
        return (594.214, 591.040, 339.307, 242.739)
    }
}

/// Frame snapshot consumed by `KinectScanner`. Mirrors the fields of
/// `KinectFrame` that the scanner needs without coupling the scanner to the
/// Objective-C bridge.
struct KinectFrameSnapshot {
    let width: Int
    let height: Int
    let rgb: Data
    let depth: Data
    let ir: Data

    init(width: Int, height: Int, rgb: Data, depth: Data, ir: Data) {
        self.width = width
        self.height = height
        self.rgb = rgb
        self.depth = depth
        self.ir = ir
    }

    init?(frame: KinectFrame) {
        self.width = frame.width
        self.height = frame.height
        self.rgb = Data(frame.rgbData)
        self.depth = Data(frame.depthData)
        self.ir = Data(frame.irData)
        guard width > 0, height > 0 else { return nil }
    }
}
