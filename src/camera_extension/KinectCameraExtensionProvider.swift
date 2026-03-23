import Foundation
import CoreMediaIO
import CoreMedia
import CoreVideo
import CoreFoundation
import IOKit.audio
import os.log

private enum CameraExtensionStreamType: Int {
    case rgb = 0
    case infrared = 1
    case depth = 2
}

private enum CameraExtensionPreferences {
    static let domain = "com.mackinect.integration"
    static let streamKey = "SystemCameraStream"

    // The camera extension runs outside the app's user session, so it prefers
    // the shared /Library/Preferences copy written by the installer/apply flow.
    static func preferredStreamType() -> CameraExtensionStreamType {
        let key = streamKey as CFString
        let domainRef = domain as CFString
        let candidates: [(CFString, CFString)] = [
            (kCFPreferencesAnyUser, kCFPreferencesCurrentHost),
            (kCFPreferencesAnyUser, kCFPreferencesAnyHost),
            (kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        ]

        for (user, host) in candidates {
            if let value = CFPreferencesCopyValue(key, domainRef, user, host) {
                let resolved = (value as? NSNumber)?.intValue
                    ?? Int((value as? String) ?? "")
                if let resolved,
                   let streamType = CameraExtensionStreamType(rawValue: resolved) {
                    return streamType
                }
            }
        }

        let defaults = UserDefaults(suiteName: domain)
        return CameraExtensionStreamType(rawValue: defaults?.integer(forKey: streamKey) ?? 0) ?? .rgb
    }
}

private enum CameraExtensionConstants {
    static let outputWidth = 640
    static let outputHeight = 480
    static let frameRate = 30
    static let manufacturer = "macKinect"
    static let deviceName = "Kinect"
    static let streamName = "Kinect Camera"
    static let modelName = "Kinect Camera Extension"
    static let deviceID = UUID(uuidString: "620F0EC0-43E2-4A6B-8F7A-7A5B3483D001")!
    static let streamID = UUID(uuidString: "620F0EC0-43E2-4A6B-8F7A-7A5B3483D002")!
}

private func intValue(_ value: Any?) -> Int? {
    if let int = value as? Int { return int }
    if let number = value as? NSNumber { return number.intValue }
    if let string = value as? String { return Int(string) }
    return nil
}

final class MacKinectCameraExtensionDeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!

    private let bridge = KinectBridge.sharedInstance()
    private var streamSource: MacKinectCameraExtensionStreamSource!
    private let streamQueue = DispatchQueue(label: "com.mackinect.cameraextension.stream", qos: .userInteractive)

    private var bufferPool: CVPixelBufferPool?
    private var bufferAuxAttributes: NSDictionary?
    private var videoDescription: CMFormatDescription?
    private var timer: DispatchSourceTimer?
    private var runningClientCount: UInt32 = 0
    private var fallbackPhase: UInt32 = 0

    override init() {
        super.init()

        self.device = CMIOExtensionDevice(
            localizedName: CameraExtensionConstants.deviceName,
            deviceID: CameraExtensionConstants.deviceID,
            legacyDeviceID: "com.mackinect.camera",
            source: self
        )
        self.streamSource = MacKinectCameraExtensionStreamSource(device: self.device)

        do {
            try self.device.addStream(self.streamSource.stream)
        } catch {
            fatalError("Failed to add camera extension stream: \(error.localizedDescription)")
        }

        self.configureBufferPool()
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            deviceProperties.transportType = kIOAudioDeviceTransportTypeUSB
        }
        if properties.contains(.deviceModel) {
            deviceProperties.model = CameraExtensionConstants.modelName
        }
        return deviceProperties
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
        _ = deviceProperties
    }

    func startStreaming() {
        runningClientCount += 1
        guard timer == nil else { return }

        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: streamQueue)
        timer.schedule(deadline: .now(), repeating: 1.0 / Double(CameraExtensionConstants.frameRate), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            self?.produceFrame()
        }
        timer.resume()
        self.timer = timer
    }

    func stopStreaming() {
        if runningClientCount > 1 {
            runningClientCount -= 1
            return
        }

        runningClientCount = 0
        timer?.cancel()
        timer = nil
        bridge.stopStream()
        bridge.closeDevice()
    }

    private func configureBufferPool() {
        var description: CMFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: Int32(CameraExtensionConstants.outputWidth),
            height: Int32(CameraExtensionConstants.outputHeight),
            extensions: nil,
            formatDescriptionOut: &description
        )
        videoDescription = description

        let pixelBufferAttributes: NSDictionary = [
            kCVPixelBufferWidthKey: CameraExtensionConstants.outputWidth,
            kCVPixelBufferHeightKey: CameraExtensionConstants.outputHeight,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, pixelBufferAttributes, &pool)
        bufferPool = pool
        bufferAuxAttributes = [kCVPixelBufferPoolAllocationThresholdKey: 6]
    }

    private func produceFrame() {
        let streamType = CameraExtensionPreferences.preferredStreamType()
        let frameDuration = CMTime(value: 1, timescale: Int32(CameraExtensionConstants.frameRate))
        let currentTime = CMClockGetTime(CMClockGetHostTimeClock())

        guard let pixelBuffer = makePixelBuffer() else {
            os_log(.error, "Camera extension could not allocate a pixel buffer.")
            return
        }

        let renderedFrame = renderCurrentFrame(streamType: streamType, into: pixelBuffer)
        if !renderedFrame {
            renderFallbackFrame(into: pixelBuffer)
        }

        guard let sampleBuffer = makeSampleBuffer(
            imageBuffer: pixelBuffer,
            presentationTimeStamp: currentTime,
            duration: frameDuration
        ) else {
            os_log(.error, "Camera extension could not create a sample buffer.")
            return
        }

        streamSource.stream.send(
            sampleBuffer,
            discontinuity: renderedFrame ? [] : [.time],
            hostTimeInNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
    }

    private func makePixelBuffer() -> CVPixelBuffer? {
        guard let bufferPool else { return nil }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault,
            bufferPool,
            bufferAuxAttributes,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }
        return pixelBuffer
    }

    private func makeSampleBuffer(imageBuffer: CVPixelBuffer, presentationTimeStamp: CMTime, duration: CMTime) -> CMSampleBuffer? {
        guard let videoDescription else { return nil }

        var timing = CMSampleTimingInfo()
        timing.duration = duration
        timing.presentationTimeStamp = presentationTimeStamp
        timing.decodeTimeStamp = .invalid

        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: imageBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: videoDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr else {
            return nil
        }
        return sampleBuffer
    }

    private func renderCurrentFrame(streamType: CameraExtensionStreamType, into pixelBuffer: CVPixelBuffer) -> Bool {
        guard ensureBridgeReady(for: streamType), let frame = bridge.pollFrame() else {
            return false
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return false
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let destination = baseAddress.assumingMemoryBound(to: UInt8.self)
        memset(destination, 0, bytesPerRow * CameraExtensionConstants.outputHeight)

        switch streamType {
        case .rgb:
            return frame.rgbData.withUnsafeBytes { rawBuffer in
                guard let source = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return false }
                let pixelCount = frame.width * frame.height
                guard rawBuffer.count >= pixelCount * 3 else { return false }
                renderRGB(source, width: frame.width, height: frame.height, destination: destination, destinationBytesPerRow: bytesPerRow)
                return true
            }
        case .infrared:
            return frame.irData.withUnsafeBytes { rawBuffer in
                guard let source = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return false }
                let pixelCount = frame.width * frame.height
                guard rawBuffer.count >= pixelCount else { return false }
                renderMonochrome(source, width: frame.width, height: frame.height, destination: destination, destinationBytesPerRow: bytesPerRow)
                return true
            }
        case .depth:
            return frame.depthData.withUnsafeBytes { rawBuffer in
                guard let source = rawBuffer.bindMemory(to: UInt16.self).baseAddress else { return false }
                let pixelCount = frame.width * frame.height
                guard rawBuffer.count >= pixelCount * MemoryLayout<UInt16>.stride else { return false }
                renderDepth(source, width: frame.width, height: frame.height, destination: destination, destinationBytesPerRow: bytesPerRow)
                return true
            }
        }
    }

    private func ensureBridgeReady(for streamType: CameraExtensionStreamType) -> Bool {
        bridge.setStreamType(streamType.rawValue)
        if bridge.isStreaming() {
            return true
        }

        let devices = (bridge.discoverDevices() as? [[String: Any]] ?? [])
            .sorted { (lhs, rhs) in
                (intValue(lhs["generation"]) ?? 0) > (intValue(rhs["generation"]) ?? 0)
            }

        for device in devices {
            guard
                let generation = intValue(device["generation"]),
                let serial = device["serial"] as? String
            else {
                continue
            }

            if bridge.openDevice(withGeneration: generation, serial: serial) {
                bridge.setStreamType(streamType.rawValue)
                bridge.startStream()
                if bridge.isStreaming() {
                    return true
                }
            }
        }

        return false
    }

    private func renderRGB(
        _ source: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        destination: UnsafeMutablePointer<UInt8>,
        destinationBytesPerRow: Int
    ) {
        for y in 0..<CameraExtensionConstants.outputHeight {
            let sourceY = min(height - 1, y * height / CameraExtensionConstants.outputHeight)
            let destinationRow = destination.advanced(by: y * destinationBytesPerRow)
            for x in 0..<CameraExtensionConstants.outputWidth {
                let sourceX = min(width - 1, x * width / CameraExtensionConstants.outputWidth)
                let sourceOffset = (sourceY * width + sourceX) * 3
                let destinationOffset = x * 4
                destinationRow[destinationOffset + 0] = source[sourceOffset + 2]
                destinationRow[destinationOffset + 1] = source[sourceOffset + 1]
                destinationRow[destinationOffset + 2] = source[sourceOffset + 0]
                destinationRow[destinationOffset + 3] = 255
            }
        }
    }

    private func renderMonochrome(
        _ source: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        destination: UnsafeMutablePointer<UInt8>,
        destinationBytesPerRow: Int
    ) {
        for y in 0..<CameraExtensionConstants.outputHeight {
            let sourceY = min(height - 1, y * height / CameraExtensionConstants.outputHeight)
            let destinationRow = destination.advanced(by: y * destinationBytesPerRow)
            for x in 0..<CameraExtensionConstants.outputWidth {
                let sourceX = min(width - 1, x * width / CameraExtensionConstants.outputWidth)
                let intensity = source[sourceY * width + sourceX]
                let destinationOffset = x * 4
                destinationRow[destinationOffset + 0] = intensity
                destinationRow[destinationOffset + 1] = intensity
                destinationRow[destinationOffset + 2] = intensity
                destinationRow[destinationOffset + 3] = 255
            }
        }
    }

    private func renderDepth(
        _ source: UnsafePointer<UInt16>,
        width: Int,
        height: Int,
        destination: UnsafeMutablePointer<UInt8>,
        destinationBytesPerRow: Int
    ) {
        for y in 0..<CameraExtensionConstants.outputHeight {
            let sourceY = min(height - 1, y * height / CameraExtensionConstants.outputHeight)
            let destinationRow = destination.advanced(by: y * destinationBytesPerRow)
            for x in 0..<CameraExtensionConstants.outputWidth {
                let sourceX = min(width - 1, x * width / CameraExtensionConstants.outputWidth)
                let depthMillimeters = Int(source[sourceY * width + sourceX])
                let intensity: UInt8
                if depthMillimeters <= 0 {
                    intensity = 0
                } else {
                    let clamped = min(depthMillimeters, 8000)
                    intensity = UInt8(max(0, 255 - (clamped * 255 / 8000)))
                }

                let destinationOffset = x * 4
                destinationRow[destinationOffset + 0] = intensity
                destinationRow[destinationOffset + 1] = intensity
                destinationRow[destinationOffset + 2] = intensity
                destinationRow[destinationOffset + 3] = 255
            }
        }
    }

    private func renderFallbackFrame(into pixelBuffer: CVPixelBuffer) {
        fallbackPhase = (fallbackPhase + 1) % UInt32(CameraExtensionConstants.outputHeight)

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let destination = baseAddress.assumingMemoryBound(to: UInt8.self)
        memset(destination, 0, bytesPerRow * CameraExtensionConstants.outputHeight)

        for y in 0..<CameraExtensionConstants.outputHeight {
            let row = destination.advanced(by: y * bytesPerRow)
            let highlightRow = Int(fallbackPhase) == y
            for x in 0..<CameraExtensionConstants.outputWidth {
                let inGrid = (x % 64 == 0) || (y % 64 == 0)
                let value: UInt8 = highlightRow ? 180 : (inGrid ? 40 : 0)
                let offset = x * 4
                row[offset + 0] = value
                row[offset + 1] = value
                row[offset + 2] = value
                row[offset + 3] = 255
            }
        }
    }
}

final class MacKinectCameraExtensionStreamSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private weak var device: CMIOExtensionDevice?
    private let streamFormat: CMIOExtensionStreamFormat

    init(device: CMIOExtensionDevice) {
        var description: CMFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: Int32(CameraExtensionConstants.outputWidth),
            height: Int32(CameraExtensionConstants.outputHeight),
            extensions: nil,
            formatDescriptionOut: &description
        )

        self.device = device
        self.streamFormat = CMIOExtensionStreamFormat(
            formatDescription: description!,
            maxFrameDuration: CMTime(value: 1, timescale: Int32(CameraExtensionConstants.frameRate)),
            minFrameDuration: CMTime(value: 1, timescale: Int32(CameraExtensionConstants.frameRate)),
            validFrameDurations: nil
        )
        super.init()

        self.stream = CMIOExtensionStream(
            localizedName: CameraExtensionConstants.streamName,
            streamID: CameraExtensionConstants.streamID,
            direction: .source,
            clockType: .hostTime,
            source: self
        )
    }

    func attachDevice(_ device: CMIOExtensionDevice) {
        self.device = device
    }

    var formats: [CMIOExtensionStreamFormat] {
        [streamFormat]
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            streamProperties.frameDuration = CMTime(value: 1, timescale: Int32(CameraExtensionConstants.frameRate))
        }
        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        _ = streamProperties
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        _ = client
        return true
    }

    func startStream() throws {
        guard let deviceSource = device?.source as? MacKinectCameraExtensionDeviceSource else {
            throw NSError(domain: "MacKinectCameraExtension", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing device source"])
        }
        deviceSource.startStreaming()
    }

    func stopStream() throws {
        guard let deviceSource = device?.source as? MacKinectCameraExtensionDeviceSource else {
            throw NSError(domain: "MacKinectCameraExtension", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing device source"])
        }
        deviceSource.stopStreaming()
    }
}

final class MacKinectCameraExtensionProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private let deviceSource = MacKinectCameraExtensionDeviceSource()

    init(clientQueue: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            fatalError("Failed to register Kinect camera extension device: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {
        _ = client
    }

    func disconnect(from client: CMIOExtensionClient) {
        _ = client
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let providerProperties = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            providerProperties.manufacturer = CameraExtensionConstants.manufacturer
        }
        return providerProperties
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {
        _ = providerProperties
    }
}
