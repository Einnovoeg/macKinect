import CoreGraphics
import Foundation
import SwiftUI
import Vision

struct TrackingVector3: Equatable {
    static let zero = TrackingVector3(x: 0, y: 0, z: 0)

    let x: Float
    let y: Float
    let z: Float
}

enum TrackerRole: String, CaseIterable, Identifiable {
    case head
    case chest
    case hip
    case leftFoot
    case rightFoot
    case leftKnee
    case rightKnee
    case leftElbow
    case rightElbow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .head: return "Head"
        case .chest: return "Chest"
        case .hip: return "Hip"
        case .leftFoot: return "Left Foot"
        case .rightFoot: return "Right Foot"
        case .leftKnee: return "Left Knee"
        case .rightKnee: return "Right Knee"
        case .leftElbow: return "Left Elbow"
        case .rightElbow: return "Right Elbow"
        }
    }

    func oscPositionAddress(sendHead: Bool) -> String? {
        if self == .head {
            return sendHead ? "/tracking/trackers/head/position" : nil
        }
        guard let index = oscTrackerIndex else { return nil }
        return "/tracking/trackers/\(index)/position"
    }

    func oscRotationAddress(sendHead: Bool) -> String? {
        if self == .head {
            return sendHead ? "/tracking/trackers/head/rotation" : nil
        }
        guard let index = oscTrackerIndex else { return nil }
        return "/tracking/trackers/\(index)/rotation"
    }

    private var oscTrackerIndex: Int? {
        // VRChat treats OSC tracker slots as generic calibrated trackers. The
        // ordering below is stable and mirrors the documented set: hip, chest,
        // feet, knees, and elbows.
        switch self {
        case .hip: return 1
        case .chest: return 2
        case .leftFoot: return 3
        case .rightFoot: return 4
        case .leftKnee: return 5
        case .rightKnee: return 6
        case .leftElbow: return 7
        case .rightElbow: return 8
        case .head: return nil
        }
    }
}

enum TrackerPoseSource: String {
    case depth
    case estimated2D

    var title: String {
        switch self {
        case .depth: return "Depth"
        case .estimated2D: return "2D Estimate"
        }
    }
}

struct TrackerPose: Identifiable, Equatable {
    let role: TrackerRole
    let position: TrackingVector3
    let confidence: Float
    let source: TrackerPoseSource

    var id: String { role.rawValue }
}

struct VisionTrackedPoint {
    let normalized: CGPoint
    let confidence: Float
}

struct VisionTrackedFace: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    let landmarks: [CGPoint]
    let confidence: Float
}

struct VisionTrackedBody: Identifiable {
    let id = UUID()
    let joints: [VNRecognizedPointKey: VisionTrackedPoint]
    let trackers: [TrackerPose]
}

struct VisionTrackingResult {
    static let empty = VisionTrackingResult(
        faces: [],
        bodies: [],
        trackers: [],
        processedAt: nil,
        message: "Tracking idle",
        usesDepth: false
    )

    let faces: [VisionTrackedFace]
    let bodies: [VisionTrackedBody]
    let trackers: [TrackerPose]
    let processedAt: Date?
    let message: String
    let usesDepth: Bool

    var summary: String {
        if faces.isEmpty && bodies.isEmpty {
            return message
        }
        return "\(faces.count) face(s), \(bodies.count) body pose(s), \(trackers.count) tracker(s)"
    }
}

struct TrackingDepthFrame {
    let data: Data
    let width: Int
    let height: Int
    let generation: Int
}

/// Runs Apple Vision face/body detection off the main thread and converts
/// Kinect depth samples into approximate meter-space tracker points when a
/// depth frame is aligned with the RGB frame.
final class VisionTrackingService {
    private let queue = DispatchQueue(label: "com.mackinect.vision-tracking", qos: .userInitiated)
    private let stateLock = NSLock()
    private var processing = false
    private var lastProcessTime = Date.distantPast
    private let minimumInterval: TimeInterval = 1.0 / 12.0

    func process(
        image: CGImage,
        depthFrame: TrackingDepthFrame?,
        detectFaces: Bool,
        detectBodies: Bool,
        allowEstimatedTrackers: Bool,
        completion: @escaping (VisionTrackingResult) -> Void
    ) {
        guard detectFaces || detectBodies else {
            completion(.empty)
            return
        }

        stateLock.lock()
        let now = Date()
        guard !processing, now.timeIntervalSince(lastProcessTime) >= minimumInterval else {
            stateLock.unlock()
            return
        }
        processing = true
        lastProcessTime = now
        stateLock.unlock()

        queue.async { [weak self] in
            defer { self?.markIdle() }

            var requests: [VNRequest] = []
            var faceRequest: VNDetectFaceLandmarksRequest?
            var bodyRequest: VNDetectHumanBodyPoseRequest?

            if detectFaces {
                let request = VNDetectFaceLandmarksRequest()
                faceRequest = request
                requests.append(request)
            }

            if detectBodies {
                let request = VNDetectHumanBodyPoseRequest()
                bodyRequest = request
                requests.append(request)
            }

            do {
                let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
                try handler.perform(requests)

                let faces = (faceRequest?.results ?? []).map {
                    VisionTrackedFace(
                        boundingBox: $0.boundingBox,
                        landmarks: Self.landmarkPoints(from: $0),
                        confidence: $0.confidence
                    )
                }

                let projector = Self.makeDepthProjector(
                    depthFrame: depthFrame,
                    imageWidth: image.width,
                    imageHeight: image.height
                )

                var flattenedTrackers: [TrackerPose] = []
                let bodies = (bodyRequest?.results ?? []).compactMap { observation -> VisionTrackedBody? in
                    let recognized = (try? observation.recognizedPoints(.all)) ?? [:]
                    var joints: [VNRecognizedPointKey: VisionTrackedPoint] = [:]
                    for (joint, point) in recognized where point.confidence >= 0.25 {
                        joints[joint.rawValue] = VisionTrackedPoint(normalized: point.location, confidence: point.confidence)
                    }
                    guard !joints.isEmpty else { return nil }

                    let trackers = Self.makeTrackers(
                        from: joints,
                        projector: projector,
                        allowEstimatedTrackers: allowEstimatedTrackers
                    )
                    flattenedTrackers.append(contentsOf: trackers)
                    return VisionTrackedBody(joints: joints, trackers: trackers)
                }

                completion(VisionTrackingResult(
                    faces: faces,
                    bodies: bodies,
                    trackers: flattenedTrackers,
                    processedAt: Date(),
                    message: faces.isEmpty && bodies.isEmpty ? "No face or body pose found" : "Tracking active",
                    usesDepth: flattenedTrackers.contains { $0.source == .depth }
                ))
            } catch {
                completion(VisionTrackingResult(
                    faces: [],
                    bodies: [],
                    trackers: [],
                    processedAt: Date(),
                    message: "Tracking failed: \(error.localizedDescription)",
                    usesDepth: false
                ))
            }
        }
    }

    func reset() {
        stateLock.lock()
        processing = false
        lastProcessTime = .distantPast
        stateLock.unlock()
    }

    private func markIdle() {
        stateLock.lock()
        processing = false
        stateLock.unlock()
    }

    private static func landmarkPoints(from face: VNFaceObservation) -> [CGPoint] {
        guard let landmarks = face.landmarks else { return [] }
        let regions = [
            landmarks.faceContour,
            landmarks.leftEye,
            landmarks.rightEye,
            landmarks.leftEyebrow,
            landmarks.rightEyebrow,
            landmarks.nose,
            landmarks.outerLips,
            landmarks.innerLips
        ]

        return regions.compactMap { $0 }.flatMap { region in
            (0..<region.pointCount).map { index in
                let point = region.normalizedPoints[index]
                return CGPoint(
                    x: face.boundingBox.minX + CGFloat(point.x) * face.boundingBox.width,
                    y: face.boundingBox.minY + CGFloat(point.y) * face.boundingBox.height
                )
            }
        }
    }

    private static func makeDepthProjector(
        depthFrame: TrackingDepthFrame?,
        imageWidth: Int,
        imageHeight: Int
    ) -> ((CGPoint) -> TrackingVector3?)? {
        guard
            let depthFrame,
            depthFrame.width == imageWidth,
            depthFrame.height == imageHeight,
            depthFrame.data.count >= depthFrame.width * depthFrame.height * MemoryLayout<UInt16>.size
        else {
            return nil
        }

        let intrinsics = pointCloudIntrinsics(
            width: depthFrame.width,
            height: depthFrame.height,
            generation: depthFrame.generation
        )
        let depthBytes = depthFrame.data

        return { normalizedPoint in
            let x = Int((normalizedPoint.x * CGFloat(depthFrame.width - 1)).rounded())
            let y = Int(((1.0 - normalizedPoint.y) * CGFloat(depthFrame.height - 1)).rounded())
            guard let depthMeters = medianDepthMeters(
                data: depthBytes,
                width: depthFrame.width,
                height: depthFrame.height,
                centerX: x,
                centerY: y
            ) else {
                return nil
            }

            let worldX = (Double(x) - intrinsics.cx) / intrinsics.fx * depthMeters
            let worldY = (intrinsics.cy - Double(y)) / intrinsics.fy * depthMeters
            return TrackingVector3(x: Float(worldX), y: Float(worldY), z: Float(depthMeters))
        }
    }

    private static func medianDepthMeters(
        data: Data,
        width: Int,
        height: Int,
        centerX: Int,
        centerY: Int
    ) -> Double? {
        let minX = max(0, centerX - 3)
        let maxX = min(width - 1, centerX + 3)
        let minY = max(0, centerY - 3)
        let maxY = min(height - 1, centerY + 3)
        var samples: [UInt16] = []
        samples.reserveCapacity(49)

        data.withUnsafeBytes { rawBuffer in
            let depth = rawBuffer.bindMemory(to: UInt16.self)
            for y in minY...maxY {
                for x in minX...maxX {
                    let value = UInt16(littleEndian: depth[y * width + x])
                    if value >= 350 && value <= 6000 {
                        samples.append(value)
                    }
                }
            }
        }

        guard !samples.isEmpty else { return nil }
        samples.sort()
        return Double(samples[samples.count / 2]) / 1000.0
    }

    private static func makeTrackers(
        from joints: [VNRecognizedPointKey: VisionTrackedPoint],
        projector: ((CGPoint) -> TrackingVector3?)?,
        allowEstimatedTrackers: Bool
    ) -> [TrackerPose] {
        let specs: [(TrackerRole, VisionTrackedPoint?)] = [
            (.head, firstAvailable(joints, [.nose, .leftEye, .rightEye, .neck])),
            (.chest, average(joints, [.neck, .leftShoulder, .rightShoulder])),
            (.hip, average(joints, [.root, .leftHip, .rightHip])),
            (.leftFoot, firstAvailable(joints, [.leftAnkle])),
            (.rightFoot, firstAvailable(joints, [.rightAnkle])),
            (.leftKnee, firstAvailable(joints, [.leftKnee])),
            (.rightKnee, firstAvailable(joints, [.rightKnee])),
            (.leftElbow, firstAvailable(joints, [.leftElbow])),
            (.rightElbow, firstAvailable(joints, [.rightElbow]))
        ]

        return specs.compactMap { role, point in
            guard let point else { return nil }
            if let projected = projector?(point.normalized) {
                return TrackerPose(role: role, position: projected, confidence: point.confidence, source: .depth)
            }
            guard allowEstimatedTrackers else { return nil }
            return TrackerPose(
                role: role,
                position: estimatedPosition(from: point.normalized),
                confidence: point.confidence,
                source: .estimated2D
            )
        }
    }

    private static func firstAvailable(
        _ joints: [VNRecognizedPointKey: VisionTrackedPoint],
        _ names: [VNHumanBodyPoseObservation.JointName]
    ) -> VisionTrackedPoint? {
        for name in names {
            if let point = joints[name.rawValue] {
                return point
            }
        }
        return nil
    }

    private static func average(
        _ joints: [VNRecognizedPointKey: VisionTrackedPoint],
        _ names: [VNHumanBodyPoseObservation.JointName]
    ) -> VisionTrackedPoint? {
        let points = names.compactMap { joints[$0.rawValue] }
        guard !points.isEmpty else { return nil }
        let x = points.reduce(CGFloat(0)) { $0 + $1.normalized.x } / CGFloat(points.count)
        let y = points.reduce(CGFloat(0)) { $0 + $1.normalized.y } / CGFloat(points.count)
        let confidence = points.reduce(Float(0)) { $0 + $1.confidence } / Float(points.count)
        return VisionTrackedPoint(normalized: CGPoint(x: x, y: y), confidence: confidence)
    }

    private static func estimatedPosition(from normalizedPoint: CGPoint) -> TrackingVector3 {
        TrackingVector3(
            x: Float((normalizedPoint.x - 0.5) * 2.0),
            y: Float((normalizedPoint.y - 0.5) * 2.0),
            z: 2.0
        )
    }

    private static func pointCloudIntrinsics(width: Int, height: Int, generation: Int) -> (fx: Double, fy: Double, cx: Double, cy: Double) {
        if generation == 2, width == 512, height == 424 {
            return (365.456, 365.456, 254.878, 205.395)
        }
        return (594.214, 591.040, 339.307, 242.739)
    }
}

struct TrackingOverlayView: View {
    let result: VisionTrackingResult
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            let imageRect = aspectFitRect(imageSize: imageSize, containerSize: geometry.size)
            Canvas { context, _ in
                drawFaces(in: context, imageRect: imageRect)
                drawBodies(in: context, imageRect: imageRect)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawFaces(in context: GraphicsContext, imageRect: CGRect) {
        for face in result.faces {
            let rect = convertNormalizedRect(face.boundingBox, imageRect: imageRect)
            var path = Path(roundedRect: rect, cornerRadius: 6)
            context.stroke(path, with: .color(.green.opacity(0.9)), lineWidth: 2)

            for landmark in face.landmarks {
                let point = convertNormalizedPoint(landmark, imageRect: imageRect)
                let rect = CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)
                context.fill(Path(ellipseIn: rect), with: .color(.green.opacity(0.85)))
            }

            let labelRect = CGRect(x: rect.minX, y: max(imageRect.minY, rect.minY - 20), width: 96, height: 18)
            path = Path(roundedRect: labelRect, cornerRadius: 4)
            context.fill(path, with: .color(.black.opacity(0.55)))
            context.draw(
                Text("Face \(Int(face.confidence * 100))%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green),
                at: CGPoint(x: labelRect.midX, y: labelRect.midY)
            )
        }
    }

    private func drawBodies(in context: GraphicsContext, imageRect: CGRect) {
        for body in result.bodies {
            for connection in Self.bodyConnections {
                guard
                    let start = body.joints[connection.0],
                    let end = body.joints[connection.1]
                else { continue }

                var path = Path()
                path.move(to: convertNormalizedPoint(start.normalized, imageRect: imageRect))
                path.addLine(to: convertNormalizedPoint(end.normalized, imageRect: imageRect))
                context.stroke(path, with: .color(Color(red: 0.12, green: 0.79, blue: 0.93).opacity(0.95)), lineWidth: 3)
            }

            for joint in body.joints.values {
                let point = convertNormalizedPoint(joint.normalized, imageRect: imageRect)
                let radius = CGFloat(max(3.5, Double(joint.confidence) * 6.0))
                let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.95)))
            }

            for tracker in body.trackers {
                guard let normalized = normalizedPoint(for: tracker.role, in: body.joints) else { continue }
                let point = convertNormalizedPoint(normalized, imageRect: imageRect)
                let radius: CGFloat = tracker.source == .depth ? 8 : 6
                let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(.orange.opacity(0.95)), lineWidth: 2)
            }
        }
    }

    private func aspectFitRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - size.width) * 0.5,
            y: (containerSize.height - size.height) * 0.5,
            width: size.width,
            height: size.height
        )
    }

    private func convertNormalizedRect(_ rect: CGRect, imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + rect.minX * imageRect.width,
            y: imageRect.minY + (1.0 - rect.maxY) * imageRect.height,
            width: rect.width * imageRect.width,
            height: rect.height * imageRect.height
        )
    }

    private func convertNormalizedPoint(_ point: CGPoint, imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + point.x * imageRect.width,
            y: imageRect.minY + (1.0 - point.y) * imageRect.height
        )
    }

    private func normalizedPoint(
        for role: TrackerRole,
        in joints: [VNRecognizedPointKey: VisionTrackedPoint]
    ) -> CGPoint? {
        switch role {
        case .head:
            return firstAvailable(joints, [.nose, .leftEye, .rightEye, .neck])?.normalized
        case .chest:
            return average(joints, [.neck, .leftShoulder, .rightShoulder])?.normalized
        case .hip:
            return average(joints, [.root, .leftHip, .rightHip])?.normalized
        case .leftFoot:
            return joints[VNHumanBodyPoseObservation.JointName.leftAnkle.rawValue]?.normalized
        case .rightFoot:
            return joints[VNHumanBodyPoseObservation.JointName.rightAnkle.rawValue]?.normalized
        case .leftKnee:
            return joints[VNHumanBodyPoseObservation.JointName.leftKnee.rawValue]?.normalized
        case .rightKnee:
            return joints[VNHumanBodyPoseObservation.JointName.rightKnee.rawValue]?.normalized
        case .leftElbow:
            return joints[VNHumanBodyPoseObservation.JointName.leftElbow.rawValue]?.normalized
        case .rightElbow:
            return joints[VNHumanBodyPoseObservation.JointName.rightElbow.rawValue]?.normalized
        }
    }

    private func firstAvailable(
        _ joints: [VNRecognizedPointKey: VisionTrackedPoint],
        _ names: [VNHumanBodyPoseObservation.JointName]
    ) -> VisionTrackedPoint? {
        for name in names {
            if let point = joints[name.rawValue] {
                return point
            }
        }
        return nil
    }

    private func average(
        _ joints: [VNRecognizedPointKey: VisionTrackedPoint],
        _ names: [VNHumanBodyPoseObservation.JointName]
    ) -> VisionTrackedPoint? {
        let points = names.compactMap { joints[$0.rawValue] }
        guard !points.isEmpty else { return nil }
        let x = points.reduce(CGFloat(0)) { $0 + $1.normalized.x } / CGFloat(points.count)
        let y = points.reduce(CGFloat(0)) { $0 + $1.normalized.y } / CGFloat(points.count)
        let confidence = points.reduce(Float(0)) { $0 + $1.confidence } / Float(points.count)
        return VisionTrackedPoint(normalized: CGPoint(x: x, y: y), confidence: confidence)
    }

    private static let bodyConnections: [(VNRecognizedPointKey, VNRecognizedPointKey)] = [
        (VNHumanBodyPoseObservation.JointName.neck.rawValue, VNHumanBodyPoseObservation.JointName.root.rawValue),
        (VNHumanBodyPoseObservation.JointName.neck.rawValue, VNHumanBodyPoseObservation.JointName.leftShoulder.rawValue),
        (VNHumanBodyPoseObservation.JointName.neck.rawValue, VNHumanBodyPoseObservation.JointName.rightShoulder.rawValue),
        (VNHumanBodyPoseObservation.JointName.leftShoulder.rawValue, VNHumanBodyPoseObservation.JointName.leftElbow.rawValue),
        (VNHumanBodyPoseObservation.JointName.leftElbow.rawValue, VNHumanBodyPoseObservation.JointName.leftWrist.rawValue),
        (VNHumanBodyPoseObservation.JointName.rightShoulder.rawValue, VNHumanBodyPoseObservation.JointName.rightElbow.rawValue),
        (VNHumanBodyPoseObservation.JointName.rightElbow.rawValue, VNHumanBodyPoseObservation.JointName.rightWrist.rawValue),
        (VNHumanBodyPoseObservation.JointName.root.rawValue, VNHumanBodyPoseObservation.JointName.leftHip.rawValue),
        (VNHumanBodyPoseObservation.JointName.root.rawValue, VNHumanBodyPoseObservation.JointName.rightHip.rawValue),
        (VNHumanBodyPoseObservation.JointName.leftHip.rawValue, VNHumanBodyPoseObservation.JointName.leftKnee.rawValue),
        (VNHumanBodyPoseObservation.JointName.leftKnee.rawValue, VNHumanBodyPoseObservation.JointName.leftAnkle.rawValue),
        (VNHumanBodyPoseObservation.JointName.rightHip.rawValue, VNHumanBodyPoseObservation.JointName.rightKnee.rawValue),
        (VNHumanBodyPoseObservation.JointName.rightKnee.rawValue, VNHumanBodyPoseObservation.JointName.rightAnkle.rawValue)
    ]
}
