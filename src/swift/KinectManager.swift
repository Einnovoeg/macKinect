import Foundation
import SwiftUI
import AppKit
import CoreGraphics
import AVFoundation
import CoreAudio
import ImageIO
import SystemExtensions
import UniformTypeIdentifiers

enum KinectStreamType: Int, CaseIterable, Identifiable {
    case rgb = 0
    case ir = 1
    case depth = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .rgb: return "RGB"
        case .ir: return "Infrared"
        case .depth: return "Depth"
        }
    }

    var fileNameComponent: String {
        switch self {
        case .rgb: return "rgb"
        case .ir: return "infrared"
        case .depth: return "depth"
        }
    }
}

enum SystemMicMode: Int, CaseIterable, Identifiable {
    case processedMono = 0
    case rawArray4 = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .processedMono: return "Processed Mono"
        case .rawArray4: return "Raw 4-Ch Array"
        }
    }

    var detail: String {
        switch self {
        case .processedMono:
            return "Expose Kinect's beamformed noise-cancelled mono microphone. This is the most compatible choice for normal macOS apps."
        case .rawArray4:
            return "Expose the four raw Kinect v1 microphone channels as a 4-channel input. Use this only when you specifically need the unprocessed array."
        }
    }
}

enum StillImageFormat: String, CaseIterable, Identifiable {
    case jpeg
    case png
    case tiff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .tiff: return "TIFF"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .tiff: return "tiff"
        }
    }

    var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        case .tiff: return .tiff
        }
    }

    var supportsQuality: Bool {
        switch self {
        case .jpeg:
            return true
        case .png, .tiff:
            return false
        }
    }
}

enum VideoQualityPreset: String, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    func averageBitRate(width: Int, height: Int) -> Int {
        let pixels = max(width * height, 320 * 240)
        switch self {
        case .low:
            return max(700_000, Int(Double(pixels) * 1.8))
        case .medium:
            return max(2_000_000, Int(Double(pixels) * 4.0))
        case .high:
            return max(6_000_000, Int(Double(pixels) * 9.0))
        }
    }
}

struct KinectDeviceRecord: Identifiable {
    let generation: Int
    let serial: String
    let name: String

    var id: String { "\(generation):\(serial)" }
    var generationLabel: String { generation == 2 ? "Kinect v2" : "Kinect v1" }
}

private final class SystemExtensionRequestObserver: NSObject, OSSystemExtensionRequestDelegate {
    private let approvalHandler: () -> Void
    private let finishHandler: (OSSystemExtensionRequest.Result) -> Void
    private let failureHandler: (NSError) -> Void

    init(
        approvalHandler: @escaping () -> Void,
        finishHandler: @escaping (OSSystemExtensionRequest.Result) -> Void,
        failureHandler: @escaping (NSError) -> Void
    ) {
        self.approvalHandler = approvalHandler
        self.finishHandler = finishHandler
        self.failureHandler = failureHandler
    }

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        _ = request
        _ = existing
        _ = ext
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        _ = request
        approvalHandler()
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        _ = request
        finishHandler(result)
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        _ = request
        failureHandler(error as NSError)
    }
}

/// Coordinates the SwiftUI interface, the Objective-C bridge, media export,
/// and optional system camera/microphone installation flow.
final class KinectManager: ObservableObject {
    @Published var devices: [KinectDeviceRecord] = []
    @Published var selectedDeviceID: String = ""

    @Published var connected = false
    @Published var streaming = false
    @Published var status = "Idle"

    @Published var streamType: KinectStreamType = .rgb {
        didSet {
            bridge?.setStreamType(streamType.rawValue)
        }
    }

    @Published var tiltAngle = 0
    @Published var ledMode = 1
    @Published var mirror = true
    @Published var autoExposure = true
    @Published var autoWhiteBalance = true
    @Published var nearMode = false
    @Published var manualExposureUs = 33333
    @Published var irBrightness = 20

    @Published var audioEnabled = false
    @Published var audioLevel: Float = 0
    @Published var audioStreamActive = false
    @Published var recentDiagnostics: [String] = []

    @Published var supportsMotor = false
    @Published var supportsLed = false
    @Published var supportsAudioInput = false
    @Published var supportsDepth = false
    @Published var supportsIr = false

    @Published var publishToSystem = false
    @Published var systemAudioHalInstalled = false
    @Published var systemCameraDalInstalled = false
    @Published var systemCameraExtensionAvailable = false
    @Published var systemCameraExtensionInstalled = false
    @Published var systemCameraExtensionActive = false
    @Published var systemCameraExtensionAwaitingApproval = false
    @Published var systemCameraStreamType: KinectStreamType = .rgb
    @Published var systemMicMode: SystemMicMode = .processedMono
    @Published var systemMicPublished = false
    @Published var systemCameraPublished = false
    @Published var systemPublishedMicName = ""
    @Published var systemPublishedCameraName = ""
    @Published var systemPublishNote = "Not active"
    @Published var systemIntegrationInstallInProgress = false
    @Published var systemPreferenceApplyInProgress = false
    @Published var systemIntegrationInstallResult = ""
    @Published var obsInstalled = false
    @Published var obsKinectPluginInstalled = false
    @Published var obsVirtualCameraPublished = false
    @Published var obsVirtualCameraName = ""
    @Published var obsSyphonPublishingEnabled = false
    @Published var obsIntegrationNote = "OBS integration has not been checked yet."
    @Published var lastCapturePath = ""
    @Published var lastCapturePointCount = 0
    @Published var scannerBusy = false
    @Published var trackingEnabled = false
    @Published var trackingFacesEnabled = true
    @Published var trackingBodyEnabled = true
    @Published var trackingOverlayVisible = true
    @Published var trackingDepthFusionEnabled = true
    @Published var trackingAllowEstimatedTrackers = false
    @Published var trackingOSCEnabled = false
    @Published var trackingOSCHost = "127.0.0.1"
    @Published var trackingOSCPort = 9000
    @Published var trackingOSCSendHead = false
    @Published var trackingOSCStatus = "OSC export off"
    @Published var trackingResult = VisionTrackingResult.empty
    @Published var trackingStatus = VisionTrackingResult.empty.message

    @Published var stillImageFormat: StillImageFormat = .jpeg
    @Published var stillImageQuality = 0.92
    @Published var videoQualityPreset: VideoQualityPreset = .medium
    @Published var isRecordingVideo = false
    @Published var recordingVideoSeconds: Double = 0
    @Published var lastVideoPath = ""

    private var bridge: KinectBridge?
    private var currentDevice: KinectDeviceRecord?
    private var lastFrame: KinectFrame?
    private var lastFrameCaptureDate: Date?
    private var videoRecorder: PreviewMovieRecorder?
    private var recordingStreamType: KinectStreamType?
    private var videoRecordStartDate: Date?
    private let trackingService = VisionTrackingService()
    private let oscTrackerSender = OSCTrackerSender()
    private var pendingSystemExtensionObserver: SystemExtensionRequestObserver?
    private var startupCompleted = false
    private let systemAudioHalDisplayName = "KinectAudioHAL.driver"
    private let systemCameraDalDisplayName = "KinectCameraDAL.plugin"
    private let systemCameraExtensionIdentifier = "com.mackinect.app.cameraextension"
    private let integrationDefaultsDomain = "com.mackinect.integration"
    private let systemIntegrationPreferencesPlistPath = "/Library/Preferences/com.mackinect.integration.plist"
    private let systemCameraStreamKey = "SystemCameraStream"
    private let systemMicModeKey = "SystemMicrophoneMode"
    private let systemAudioHalPath = "/Library/Audio/Plug-Ins/HAL/KinectAudioHAL.driver"
    private let systemCameraPluginPath = "/Library/CoreMediaIO/Plug-Ins/DAL/KinectCameraDAL.plugin"
    private let userAudioHalPath = NSHomeDirectory() + "/Library/Audio/Plug-Ins/HAL/KinectAudioHAL.driver"
    private let obsAppBundlePath = "/Applications/OBS.app"
    private let obsUserPluginPath = NSHomeDirectory() + "/Library/Application Support/obs-studio/plugins"
    private let obsSceneCollectionName = "macKinect"
    private let obsSceneName = "Kinect"
    private let obsSyphonSourceName = "Kinect Camera"
    private var lastAudioRuntimeTrace = ""
    private var lastAudioDebugTrace = ""
    private var lastSystemIntegrationTrace = ""
    private var lastOBSIntegrationTrace = ""

    init() {
        bridge = KinectBridge.sharedInstance()
        loadIntegrationPreferences()
    }

    func performInitialLoadIfNeeded() {
        guard !startupCompleted else { return }
        startupCompleted = true
        trace("startup", "Performing initial device and integration refresh.")
        refreshDevices()
        refreshSystemIntegrationStatus()
        refreshOBSIntegrationStatus()
    }

    func refreshDevices() {
        guard let bridge else { return }
        let records = (bridge.discoverDevices() as? [[String: Any]] ?? []).compactMap { dict -> KinectDeviceRecord? in
            guard
                let generation = coerceInt(dict["generation"]),
                let serial = dict["serial"] as? String,
                let name = dict["name"] as? String
            else { return nil }
            return KinectDeviceRecord(generation: generation, serial: serial, name: name)
        }.sorted {
            if $0.generation != $1.generation {
                return $0.generation < $1.generation
            }
            let lhsIdentity = $0.serial.isEmpty ? $0.name : $0.serial
            let rhsIdentity = $1.serial.isEmpty ? $1.name : $1.serial
            return lhsIdentity.localizedCaseInsensitiveCompare(rhsIdentity) == .orderedAscending
        }
        devices = records

        if let selected = devices.first(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = selected.id
        } else {
            selectedDeviceID = devices.first?.id ?? ""
        }

        let selectedLabel = devices.first(where: { $0.id == selectedDeviceID })?.name ?? "none"
        trace("devices", "Discovered \(devices.count) device(s); selected=\(selectedLabel).")
    }

    func connectSelectedDevice() {
        if publishToSystem {
            status = "Turn off Publish to macOS Apps before opening the Kinect in macKinect."
            trace("device", "Connect request denied because system publish is enabled.")
            return
        }
        guard let bridge else { return }
        guard let selected = devices.first(where: { $0.id == selectedDeviceID }) else {
            status = "No device selected."
            trace("device", "Connect requested without a selected device.")
            return
        }

        trace("device", "Opening \(selected.generationLabel) \(selected.serial.isEmpty ? selected.name : selected.serial).")

        if isRecordingVideo {
            stopVideoRecording()
        }
        if streaming {
            bridge.stopStream()
        }
        streaming = false
        audioStreamActive = false
        audioLevel = 0

        if !bridge.openDevice(withGeneration: selected.generation, serial: selected.serial) {
            clearDeviceSession(closeBridge: true)
            let hint = bridge.lastError().trimmingCharacters(in: .whitespacesAndNewlines)
            if hint.isEmpty {
                status = "Failed to open \(selected.generationLabel) \(selected.serial)."
            } else {
                status = "Failed to open \(selected.generationLabel) \(selected.serial): \(hint)"
            }
            trace("device", "Open failed: \(hint.isEmpty ? "unknown error" : hint)")
            return
        }

        connected = true
        currentDevice = selected
        lastFrame = nil
        lastFrameCaptureDate = nil
        updateCapabilities()
        normalizeFeatureState()
        applyCurrentSettings()
        refreshAudioRuntimeState()
        startStreaming()
        if streaming {
            status = "Connected and streaming from \(selected.generationLabel) \(selected.serial)."
        } else {
            status = "Connected to \(selected.generationLabel) \(selected.serial), but stream did not start."
        }
        trace(
            "device",
            "Open succeeded; streaming=\(streaming), audioSupported=\(supportsAudioInput), depthSupported=\(supportsDepth), irSupported=\(supportsIr)."
        )
    }

    func disconnect() {
        stopVideoRecording()
        clearDeviceSession(closeBridge: true)
        status = "Disconnected."
        trace("device", "Device session disconnected.")
    }

    func startStreaming() {
        if publishToSystem {
            status = "Turn off Publish to macOS Apps before starting a live macKinect stream."
            trace("device", "Start stream request denied because system publish is enabled.")
            return
        }
        guard connected else {
            status = "Connect a device first."
            return
        }
        if streaming {
            refreshAudioRuntimeState()
            return
        }
        bridge?.startStream()
        streaming = bridge?.isStreaming() ?? false
        if streaming {
            if audioEnabled && supportsAudioInput {
                _ = bridge?.setAudioEnabled(true)
            }
            refreshAudioRuntimeState()
            status = "Streaming started."
        } else {
            refreshAudioRuntimeState()
            status = "Could not start stream."
        }
    }

    func stopStreaming() {
        stopVideoRecording()
        bridge?.stopStream()
        streaming = false
        refreshAudioRuntimeState()
        status = "Streaming stopped."
    }

    func pollFrame() -> KinectFrame? {
        guard streaming else {
            refreshAudioRuntimeState()
            return nil
        }
        let frame = bridge?.pollFrame()
        if let frame {
            lastFrame = frame
            lastFrameCaptureDate = Date()
        }
        refreshAudioRuntimeState()
        return frame
    }

    func applyCurrentSettings() {
        guard bridge != nil else { return }
        bridge?.setStreamType(streamType.rawValue)
        if supportsMotor {
            bridge?.setTilt(tiltAngle)
        }
        if supportsLed {
            bridge?.setLed(ledMode)
        }
        if shouldApplyImageControlFlags {
            bridge?.setMirror(mirror)
            bridge?.setAutoExposure(autoExposure)
            bridge?.setAutoWhiteBalance(autoWhiteBalance)
            bridge?.setNearMode(nearMode)
            bridge?.setManualExposureUs(manualExposureUs)
            bridge?.setIrBrightness(irBrightness)
        } else {
            trace("device", "Skipping mirror/exposure/IR control flags for this backend to avoid unsafe v1 control transfers.")
        }
    }

    func setTilt(_ value: Int) {
        tiltAngle = max(-30, min(30, value))
        bridge?.setTilt(tiltAngle)
    }

    func setLed(_ value: Int) {
        ledMode = max(0, min(6, value))
        bridge?.setLed(ledMode)
    }

    func setMirror(_ value: Bool) {
        mirror = value
        if shouldApplyImageControlFlags {
            bridge?.setMirror(value)
        }
    }

    func setAutoExposure(_ value: Bool) {
        autoExposure = value
        if shouldApplyImageControlFlags {
            bridge?.setAutoExposure(value)
        }
    }

    func setAutoWhiteBalance(_ value: Bool) {
        autoWhiteBalance = value
        if shouldApplyImageControlFlags {
            bridge?.setAutoWhiteBalance(value)
        }
    }

    func setNearMode(_ value: Bool) {
        nearMode = value
        if shouldApplyImageControlFlags {
            bridge?.setNearMode(value)
        }
    }

    func setManualExposure(_ value: Int) {
        manualExposureUs = max(1000, min(200000, value))
        if shouldApplyImageControlFlags {
            bridge?.setManualExposureUs(manualExposureUs)
        }
    }

    func setIrBrightness(_ value: Int) {
        irBrightness = max(1, min(50, value))
        if shouldApplyImageControlFlags {
            bridge?.setIrBrightness(irBrightness)
        }
    }

    func setTrackingEnabled(_ value: Bool) {
        trackingEnabled = value
        if !value {
            trackingService.reset()
            trackingResult = .empty
            trackingStatus = VisionTrackingResult.empty.message
        } else {
            trackingStatus = "Waiting for RGB frame"
        }
    }

    func processTrackingFrame(_ image: CGImage, depthData: Data? = nil, width: Int = 0, height: Int = 0) {
        guard trackingEnabled else { return }
        let detectFaces = trackingFacesEnabled
        let detectBody = trackingBodyEnabled
        let generation = currentDevice?.generation ?? 1

        let depthFrame: TrackingDepthFrame?
        if let depthData, width > 0, height > 0 {
            depthFrame = TrackingDepthFrame(data: depthData, width: width, height: height, generation: generation)
        } else {
            depthFrame = nil
        }

        let allowEstimated = trackingAllowEstimatedTrackers

        trackingService.process(
            image: image,
            depthFrame: depthFrame,
            detectFaces: detectFaces,
            detectBodies: detectBody,
            allowEstimatedTrackers: allowEstimated
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.trackingEnabled else { return }
                self.trackingResult = result
                self.trackingStatus = result.summary
            }
        }
    }

    func setAudioEnabled(_ value: Bool) {
        guard supportsAudioInput else {
            audioEnabled = false
            audioStreamActive = false
            status = "Kinect microphone input is not available for this device/backend."
            trace("audio", "Direct microphone request denied: \(directMicrophoneSupportDetail)")
            return
        }

        if value && publishToSystem {
            audioEnabled = false
            audioStreamActive = false
            status = "Disable system publish before using the direct Kinect microphone inside macKinect."
            trace("audio", "Direct microphone request denied because system publish is enabled.")
            return
        }

        audioEnabled = value
        let applied = bridge?.setAudioEnabled(value) ?? false
        refreshAudioRuntimeState()
        trace(
            "audio",
            "Direct microphone request value=\(value) applied=\(applied) connected=\(connected) streaming=\(streaming)."
        )

        if value {
            if !connected {
                status = "Connect a device first to enable audio."
            } else if streaming {
                status = applied ? "Microphone stream enabled." : "Microphone could not start in this session."
            } else {
                status = "Microphone armed. Start streaming to activate audio."
            }
        } else {
            status = "Microphone stream disabled."
        }
    }

    func setSystemCameraStreamType(_ value: KinectStreamType) {
        systemCameraStreamType = value
        persistLocalIntegrationPreferences()
        status = "System camera stream set to \(value.title). Apply system settings or re-run Install Integration to push it into macOS services."
        trace("system-camera", "System camera stream changed to \(value.title).")
    }

    func setSystemMicMode(_ value: SystemMicMode) {
        systemMicMode = value
        persistLocalIntegrationPreferences()
        status = "System microphone mode set to \(value.title). Apply system settings or re-run Install Integration to push it into macOS services."
        trace("system-audio", "System microphone mode changed to \(value.title).")
    }

    /// Store the user's preferred system integration settings locally first.
    /// A separate privileged sync step pushes them into /Library/Preferences so
    /// HAL and camera-extension processes running outside the app user session
    /// can actually observe the same values.
    private func persistLocalIntegrationPreferences() {
        let defaults = UserDefaults(suiteName: integrationDefaultsDomain)
        defaults?.set(systemCameraStreamType.rawValue, forKey: systemCameraStreamKey)
        defaults?.set(systemMicMode.rawValue, forKey: systemMicModeKey)
        defaults?.synchronize()
    }

    func applySystemIntegrationPreferences() {
        guard !systemPreferenceApplyInProgress else { return }
        guard systemAudioHalInstalled || systemCameraDalInstalled || systemCameraExtensionInstalled || systemCameraExtensionAvailable else {
            systemIntegrationInstallResult = "Install system integration first, then apply shared camera/microphone settings."
            status = systemIntegrationInstallResult
            return
        }

        systemPreferenceApplyInProgress = true
        systemIntegrationInstallResult = "Applying shared system integration preferences..."
        status = systemIntegrationInstallResult

        let selectedCameraStream = systemCameraStreamType.rawValue
        let selectedMicMode = systemMicMode.rawValue
        let shouldRestartAudio = systemAudioHalInstalled || systemMicPublished
        let shouldRestartCameraServices = systemCameraDalInstalled || systemCameraPublished

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.runSystemIntegrationPreferenceSync(
                preferencesPlistPath: self.systemIntegrationPreferencesPlistPath,
                systemCameraStreamValue: selectedCameraStream,
                systemMicModeValue: selectedMicMode,
                restartAudioServices: shouldRestartAudio,
                restartCameraServices: shouldRestartCameraServices
            )

            DispatchQueue.main.async {
                self.systemPreferenceApplyInProgress = false
                self.systemIntegrationInstallResult = result.message
                self.status = result.message
                self.refreshSystemIntegrationStatus(requestEnable: self.publishToSystem)
            }
        }
    }

    func releaseHardwareForSystemIntegration() {
        stopVideoRecording()
        audioEnabled = false
        obsSyphonPublishingEnabled = false
        OBSSyphonPublisher.sharedInstance().stop()
        clearDeviceSession(closeBridge: true)
        status = "Released Kinect hardware for system camera/microphone integration."
        trace("system", "Released Kinect hardware so system integrations can claim the device.")
    }

    var obsPluginsFolderPath: String {
        obsUserPluginPath
    }

    func launchOBSVirtualCamera() {
        refreshOBSIntegrationStatus()

        guard obsInstalled else {
            obsIntegrationNote = "OBS.app is not installed in /Applications, so the OBS Virtual Camera fallback is unavailable."
            status = "OBS is not installed."
            trace("obs", obsIntegrationNote)
            return
        }

        do {
            try ensureOBSSceneCollection()
        } catch {
            obsIntegrationNote = "Could not prepare the OBS scene collection: \(error.localizedDescription)"
            status = "Failed to configure OBS."
            trace("obs", obsIntegrationNote)
            return
        }

        obsSyphonPublishingEnabled = OBSSyphonPublisher.sharedInstance().isAvailable

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-na", obsAppBundlePath, "--args",
            "--collection", obsSceneCollectionName,
            "--scene", obsSceneName,
            "--startvirtualcam"
        ]

        do {
            try process.run()
            status = "Launching OBS with Virtual Camera enabled."
            if obsSyphonPublishingEnabled {
                obsIntegrationNote = "OBS is launching with the macKinect Syphon scene and Virtual Camera enabled. Keep the preview streaming so OBS receives live frames."
            } else if obsKinectPluginInstalled {
                obsIntegrationNote = "OBS is launching with Virtual Camera enabled. Add or enable the Kinect source inside OBS if it is not already active."
            } else {
                obsIntegrationNote = "OBS is launching with Virtual Camera enabled, but Syphon publishing is unavailable and no obs-kinect-style Kinect source plugin was detected."
            }
        } catch {
            obsIntegrationNote = "Could not launch OBS: \(error.localizedDescription)"
            status = "Failed to launch OBS."
            trace("obs", obsIntegrationNote)
        }
    }

    func publishPreviewFrameToOBS(_ image: CGImage) {
        guard obsSyphonPublishingEnabled else { return }
        let publisher = OBSSyphonPublisher.sharedInstance()
        if !publisher.publishCGImage(image) {
            obsSyphonPublishingEnabled = false
            if let errorMessage = publisher.lastErrorMessage, !errorMessage.isEmpty {
                obsIntegrationNote = "OBS frame publishing stopped: \(errorMessage)"
            } else {
                obsIntegrationNote = "OBS frame publishing stopped because the Syphon publisher failed."
            }
        }
    }

    func setSystemPublish(_ value: Bool) {
        if value && (audioEnabled || connected || streaming) {
            releaseHardwareForSystemIntegration()
            status = "Released the live Kinect session so the published macOS microphone/camera path can claim the device."
        }
        publishToSystem = value
        trace("system", "System publish toggled to \(value).")
        let bundledSystemExtensionPath = Bundle.main.bundlePath + "/Contents/Library/SystemExtensions/\(systemCameraExtensionIdentifier).systemextension"
        let canActivateSystemExtension = systemCameraExtensionAvailable && Self.cameraExtensionActivationFailureReason(
            appBundlePath: Bundle.main.bundlePath,
            extensionBundlePath: bundledSystemExtensionPath
        ) == nil
        if canActivateSystemExtension {
            if value {
                activateSystemCameraExtension(triggeredByInstall: false)
            } else if systemCameraExtensionInstalled {
                deactivateSystemCameraExtension()
            }
        }
        refreshSystemIntegrationStatus(requestEnable: value)
    }

    func installSystemIntegration() {
        guard !systemIntegrationInstallInProgress else { return }

        let fileManager = FileManager.default
        let pluginRoot = Bundle.main.builtInPlugInsPath
        let bundledSystemExtensionPath = Bundle.main.bundlePath + "/Contents/Library/SystemExtensions/\(systemCameraExtensionIdentifier).systemextension"
        let hasBundledSystemExtension = fileManager.fileExists(atPath: bundledSystemExtensionPath)
        let cameraExtensionActivationFailureReason = hasBundledSystemExtension
            ? Self.cameraExtensionActivationFailureReason(
                appBundlePath: Bundle.main.bundlePath,
                extensionBundlePath: bundledSystemExtensionPath
            )
            : nil

        guard let pluginRoot else {
            systemIntegrationInstallResult = hasBundledSystemExtension
                ? "Audio HAL plugins path is unavailable, but the camera extension is bundled."
                : "App bundle plugins path is unavailable."
            return
        }

        let bundledAudioHalPath = (pluginRoot as NSString).appendingPathComponent("HAL/\(systemAudioHalDisplayName)")
        if !fileManager.fileExists(atPath: bundledAudioHalPath) {
            systemIntegrationInstallResult = "Bundled audio HAL plugin not found in app package."
            refreshSystemIntegrationStatus()
            return
        }

        let bundledCameraDalPath = (pluginRoot as NSString).appendingPathComponent("DAL/\(systemCameraDalDisplayName)")
        let includeCameraDal =
            fileManager.fileExists(atPath: bundledCameraDalPath) &&
            (!hasBundledSystemExtension || cameraExtensionActivationFailureReason != nil)
        let appFrameworksPath = Bundle.main.privateFrameworksPath
        let bundledFirmwarePath = Bundle.main.bundlePath + "/Contents/Resources/libfreenect/audios.bin"
        let firmwareSourcePath = fileManager.fileExists(atPath: bundledFirmwarePath) ? bundledFirmwarePath : nil
        let signingInfo = Self.currentCodeSigningInfo(bundlePath: Bundle.main.bundlePath)

        if signingInfo?.isAdHoc == true || signingInfo?.authority == nil {
            systemIntegrationInstallResult = "Install requires a macOS code-signing identity. This app build is ad hoc signed, so CoreAudio and camera plugins would be ignored."
            refreshSystemIntegrationStatus()
            return
        }

        systemIntegrationInstallInProgress = true
        if hasBundledSystemExtension && cameraExtensionActivationFailureReason == nil {
            systemIntegrationInstallResult = "Installing audio HAL and preparing camera extension activation..."
        } else if includeCameraDal {
            systemIntegrationInstallResult = "Installing system integration components..."
        } else {
            systemIntegrationInstallResult = "Installing audio HAL only (no bundled camera integration found in app package)..."
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.runSystemIntegrationInstall(
                audioHalSourcePath: bundledAudioHalPath,
                cameraDalSourcePath: includeCameraDal ? bundledCameraDalPath : nil,
                appFrameworksPath: appFrameworksPath,
                firmwareSourcePath: firmwareSourcePath,
                codesignIdentity: signingInfo?.authority ?? "-",
                preferencesPlistPath: self.systemIntegrationPreferencesPlistPath,
                systemCameraStreamValue: self.systemCameraStreamType.rawValue,
                systemMicModeValue: self.systemMicMode.rawValue
            )

            DispatchQueue.main.async {
                if !result.success {
                    self.systemIntegrationInstallInProgress = false
                    self.systemIntegrationInstallResult = result.message
                    self.refreshSystemIntegrationStatus(requestEnable: self.publishToSystem)
                    return
                }

                if hasBundledSystemExtension && cameraExtensionActivationFailureReason == nil {
                    self.systemIntegrationInstallResult = "Audio HAL installed. Requesting camera extension activation..."
                    self.activateSystemCameraExtension(triggeredByInstall: true)
                    return
                }

                self.systemIntegrationInstallInProgress = false
                if includeCameraDal {
                    if let cameraExtensionActivationFailureReason {
                        self.systemIntegrationInstallResult = "\(result.message) Camera extension activation is unavailable (\(cameraExtensionActivationFailureReason)). Installed DAL fallback where supported."
                    } else {
                        self.systemIntegrationInstallResult = result.message
                    }
                } else {
                    self.systemIntegrationInstallResult = "\(result.message) No bundled camera integration was found, so only microphone publishing is available."
                }
                self.refreshSystemIntegrationStatus(requestEnable: self.publishToSystem)
            }
        }
    }

    func updateCapabilities() {
        guard let caps = bridge?.deviceCapabilities() as? [String: Any] else { return }
        supportsMotor = caps["supportsMotor"] as? Bool ?? false
        supportsLed = caps["supportsLed"] as? Bool ?? false
        supportsAudioInput = caps["supportsAudioInput"] as? Bool ?? false
        supportsDepth = caps["supportsDepth"] as? Bool ?? false
        supportsIr = caps["supportsIr"] as? Bool ?? false
    }

    private func loadIntegrationPreferences() {
        let defaults = UserDefaults(suiteName: integrationDefaultsDomain)
        systemCameraStreamType = KinectStreamType(rawValue: defaults?.integer(forKey: systemCameraStreamKey) ?? KinectStreamType.rgb.rawValue) ?? .rgb
        systemMicMode = SystemMicMode(rawValue: defaults?.integer(forKey: systemMicModeKey) ?? SystemMicMode.processedMono.rawValue) ?? .processedMono
    }

    func refreshSystemIntegrationStatus() {
        refreshSystemIntegrationStatus(requestEnable: publishToSystem)
    }

    private func refreshSystemIntegrationStatus(requestEnable: Bool) {
        defer {
            let summary = "halInstalled=\(systemAudioHalInstalled), dalInstalled=\(systemCameraDalInstalled), cameraExtensionActive=\(systemCameraExtensionActive), micPublished=\(systemMicPublished), cameraPublished=\(systemCameraPublished), publishRequested=\(publishToSystem), note=\(systemPublishNote)"
            traceIfChanged("system", summary, key: &lastSystemIntegrationTrace)
        }

        let fileManager = FileManager.default
        let bundledAudioHalPath = Bundle.main.bundlePath + "/Contents/PlugIns/HAL/\(systemAudioHalDisplayName)"
        let bundledCameraDalPath = Bundle.main.bundlePath + "/Contents/PlugIns/DAL/\(systemCameraDalDisplayName)"
        let bundledCameraExtensionPath = Bundle.main.bundlePath + "/Contents/Library/SystemExtensions/\(systemCameraExtensionIdentifier).systemextension"

        let bundledAudioHalAvailable = fileManager.fileExists(atPath: bundledAudioHalPath)
        let bundledCameraDalAvailable = fileManager.fileExists(atPath: bundledCameraDalPath)
        let bundledCameraExtensionAvailable = fileManager.fileExists(atPath: bundledCameraExtensionPath)
        let installedAudioHalAvailable = fileManager.fileExists(atPath: systemAudioHalPath)
        let installedCameraPluginAvailable = fileManager.fileExists(atPath: systemCameraPluginPath)
        let cameraExtensionState = Self.currentSystemExtensionState(identifier: systemCameraExtensionIdentifier)
        let cameraExtensionActivationFailureReason = bundledCameraExtensionAvailable
            ? Self.cameraExtensionActivationFailureReason(
                appBundlePath: Bundle.main.bundlePath,
                extensionBundlePath: bundledCameraExtensionPath
            )
            : nil
        let appSigningInfo = Self.currentCodeSigningInfo(bundlePath: Bundle.main.bundlePath)
        let audioHalSignatureIssue = installedAudioHalAvailable
            ? Self.installedBundleSigningIssue(
                bundlePath: systemAudioHalPath,
                expectedTeamIdentifier: appSigningInfo?.teamIdentifier
            )
            : nil
        let cameraDalSignatureIssue = installedCameraPluginAvailable
            ? Self.installedBundleSigningIssue(
                bundlePath: systemCameraPluginPath,
                expectedTeamIdentifier: appSigningInfo?.teamIdentifier
            )
            : nil

        systemAudioHalInstalled = installedAudioHalAvailable
        systemCameraDalInstalled = installedCameraPluginAvailable
        systemCameraExtensionAvailable = bundledCameraExtensionAvailable
        systemCameraExtensionInstalled = cameraExtensionState != nil
        systemCameraExtensionActive = cameraExtensionState?.active ?? false
        if systemCameraExtensionInstalled || systemCameraExtensionActive {
            systemCameraExtensionAwaitingApproval = false
        }

        let publishedMicName = Self.firstPublishedMicrophoneName()
        let publishedCameraName = Self.firstPublishedCameraName()
        systemMicPublished = publishedMicName != nil
        systemCameraPublished = publishedCameraName != nil
        systemPublishedMicName = publishedMicName ?? ""
        systemPublishedCameraName = publishedCameraName ?? ""
        refreshOBSIntegrationStatus()

        let hasAnySystemIntegration =
            bundledCameraExtensionAvailable ||
            systemCameraExtensionInstalled ||
            installedAudioHalAvailable ||
            installedCameraPluginAvailable
        publishToSystem = requestEnable && hasAnySystemIntegration

        if !bundledAudioHalAvailable {
            systemPublishNote = "Bundled audio HAL plugin is missing from this app package."
            return
        }

        if systemCameraExtensionAwaitingApproval {
            systemPublishNote = "Camera extension activation is waiting for approval in System Settings > General > Login Items & Extensions > Camera Extensions."
            return
        }

        if bundledCameraExtensionAvailable && cameraExtensionActivationFailureReason == nil {
            if !installedAudioHalAvailable {
                systemPublishNote = "Audio HAL is not installed yet. Click 'Install Integration' to install the microphone driver and activate the camera extension."
                return
            }
            if !systemCameraExtensionInstalled {
                systemPublishNote = "Camera extension is bundled but not activated yet. Click 'Install Integration' to activate it."
                return
            }
            if systemCameraExtensionInstalled && !systemCameraExtensionActive {
                let rawState = cameraExtensionState?.rawState ?? "inactive"
                systemPublishNote = "Camera extension is installed but not active (\(rawState)). Toggle system publish on or re-run install."
                return
            }
            if systemCameraExtensionActive && !systemCameraPublished {
                systemPublishNote = "Camera extension is active but the 'Kinect' camera is not published yet. Release hardware from the app, then reopen camera apps."
                return
            }
            if !systemMicPublished {
                systemPublishNote = "Camera extension is active, but the audio HAL is not yet published as a microphone. Re-run install and restart audio services."
                return
            }

            if publishToSystem {
                systemPublishNote = "System camera/microphone publishing enabled via camera extension (\(systemPublishedCameraName) / \(systemPublishedMicName))."
            } else {
                systemPublishNote = "System camera/microphone integration is ready via camera extension (\(systemPublishedCameraName) / \(systemPublishedMicName))."
            }
            return
        }

        if let cameraExtensionActivationFailureReason,
           !bundledCameraDalAvailable && !installedCameraPluginAvailable {
            systemPublishNote = cameraExtensionActivationFailureReason
            return
        }

        if !bundledCameraDalAvailable && !installedCameraPluginAvailable {
            systemPublishNote = "Bundled camera integration is missing from this app package. Microphone integration can still be installed."
            return
        }

        if !installedAudioHalAvailable && !installedCameraPluginAvailable {
            systemPublishNote = "System integration is not installed yet. Click 'Install System Integration' to install bundled components."
            return
        }

        if let audioHalSignatureIssue, !systemMicPublished {
            systemPublishNote = "Audio HAL is installed but macOS may ignore it because \(audioHalSignatureIssue). Re-run Install Integration from an app build signed with your Apple Developer certificate."
            return
        }

        if installedAudioHalAvailable && !systemMicPublished {
            if let reloadDiagnostic = audioHalReloadDiagnostic() {
                systemPublishNote = reloadDiagnostic
            } else {
                systemPublishNote = "Audio HAL is installed but no 'Kinect' microphone is published. Note: Only Kinect v1 has a microphone (Kinect v2 has no audio). Ensure: (1) Kinect v1 is connected with external power, (2) hardware is released from this app, (3) run Install Integration and restart audio services."
            }
            return
        }

        if let cameraDalSignatureIssue, !systemCameraPublished {
            systemPublishNote = "Camera DAL is installed but macOS may ignore it because \(cameraDalSignatureIssue). Re-run Install Integration from this signed app build."
            return
        }

        if installedCameraPluginAvailable && !systemCameraPublished {
            if let cameraExtensionActivationFailureReason {
                systemPublishNote = "Camera extension activation is unavailable (\(cameraExtensionActivationFailureReason)). DAL fallback is installed, but no 'Kinect' camera is currently published."
            } else {
                systemPublishNote = "Camera DAL is installed but no 'Kinect' camera is published. Note: Legacy DAL cameras are blocked by macOS 12.1+ security policies. The camera extension (preferred) requires a provisioning profile with System Extension capability."
            }
            return
        }

        if installedAudioHalAvailable && !installedCameraPluginAvailable {
            systemPublishNote = publishToSystem
                ? "System microphone integration enabled. Camera integration requires a provisioning profile with System Extension capability for the camera extension."
                : "System microphone integration is ready. Camera integration requires a provisioning profile with System Extension capability (https://developer.apple.com/system-extensions/)."
            return
        }

        if !installedAudioHalAvailable && installedCameraPluginAvailable {
            systemPublishNote = publishToSystem
                ? "System camera integration enabled via DAL fallback (limited). Microphone integration requires the Kinect Audio HAL plugin."
                : "System camera integration is ready via DAL fallback (limited). Note: DAL cameras are blocked on macOS 12.1+. Microphone integration requires the Kinect Audio HAL plugin."
            return
        }

        if publishToSystem {
            if let cameraExtensionActivationFailureReason {
                systemPublishNote = "System camera/microphone publishing enabled via DAL fallback (\(systemPublishedCameraName) / \(systemPublishedMicName)). Camera extension activation is unavailable: \(cameraExtensionActivationFailureReason)"
            } else {
                systemPublishNote = "System camera/microphone publishing enabled (\(systemPublishedCameraName) / \(systemPublishedMicName))."
            }
        } else {
            if let cameraExtensionActivationFailureReason {
                systemPublishNote = "System camera/microphone integration is ready via DAL fallback (\(systemPublishedCameraName) / \(systemPublishedMicName)). Camera extension activation is unavailable: \(cameraExtensionActivationFailureReason)"
            } else {
                systemPublishNote = "System camera/microphone integration is ready (\(systemPublishedCameraName) / \(systemPublishedMicName))."
            }
        }
    }

    private func refreshOBSIntegrationStatus() {
        obsInstalled = FileManager.default.fileExists(atPath: obsAppBundlePath)
        obsKinectPluginInstalled = Self.obsKinectPluginInstalled(userPluginPath: obsUserPluginPath, appBundlePath: obsAppBundlePath)
        let virtualCameraName = Self.firstPublishedNamedCamera(containing: "OBS Virtual Camera")
        obsVirtualCameraPublished = virtualCameraName != nil
        obsVirtualCameraName = virtualCameraName ?? ""
        let syphonPublisherAvailable = OBSSyphonPublisher.sharedInstance().isAvailable

        if !obsInstalled {
            obsIntegrationNote = "OBS.app is not installed, so the OBS Virtual Camera fallback is unavailable."
            traceIfChanged("obs", obsIntegrationNote, key: &lastOBSIntegrationTrace)
            return
        }

        if syphonPublisherAvailable {
            if obsVirtualCameraPublished {
                obsIntegrationNote = "OBS Virtual Camera is published. Launch OBS with the macKinect scene to route the live preview through Syphon."
            } else {
                obsIntegrationNote = "OBS is installed and Syphon publishing is available. Launch OBS Virtual Camera to expose the live preview as a system webcam."
            }
            traceIfChanged("obs", obsIntegrationNote, key: &lastOBSIntegrationTrace)
            return
        }

        if !obsKinectPluginInstalled {
            if obsVirtualCameraPublished {
                obsIntegrationNote = "OBS Virtual Camera is published, but no obs-kinect-style Kinect source plugin was detected. The camera can be exposed once OBS has a Kinect-capable source."
            } else {
                obsIntegrationNote = "OBS is installed, but no obs-kinect-style Kinect source plugin was detected in OBS plugins yet."
            }
            traceIfChanged("obs", obsIntegrationNote, key: &lastOBSIntegrationTrace)
            return
        }

        if obsVirtualCameraPublished {
            obsIntegrationNote = "OBS Virtual Camera is published. Start or configure the OBS Kinect source to route Kinect video into macOS apps."
        } else {
            obsIntegrationNote = "OBS Kinect plugin detected. Launch OBS and start Virtual Camera to expose the Kinect feed as a system webcam."
        }
        traceIfChanged("obs", obsIntegrationNote, key: &lastOBSIntegrationTrace)
    }

    private func ensureOBSSceneCollection() throws {
        let fileManager = FileManager.default
        let baseDirectory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("obs-studio", isDirectory: true)
            .appendingPathComponent("basic", isDirectory: true)
            .appendingPathComponent("scenes", isDirectory: true)
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let sourceUUID = UUID().uuidString.lowercased()
        let sceneUUID = UUID().uuidString.lowercased()

        let sceneCollection: [String: Any] = [
            "name": obsSceneCollectionName,
            "current_scene": obsSceneName,
            "current_program_scene": obsSceneName,
            "scene_order": [
                ["name": obsSceneName]
            ],
            "sources": [
                [
                    "prev_ver": 536_870_914,
                    "name": obsSceneName,
                    "uuid": sceneUUID,
                    "id": "scene",
                    "versioned_id": "scene",
                    "settings": [
                        "id_counter": 1,
                        "custom_size": false,
                        "items": [
                            [
                                "name": obsSyphonSourceName,
                                "source_uuid": sourceUUID,
                                "visible": true,
                                "locked": false,
                                "rot": 0.0,
                                "scale_ref": ["x": 1280.0, "y": 720.0],
                                "align": 5,
                                "bounds_type": 0,
                                "bounds_align": 0,
                                "bounds_crop": false,
                                "crop_left": 0,
                                "crop_top": 0,
                                "crop_right": 0,
                                "crop_bottom": 0,
                                "id": 1,
                                "group_item_backup": false,
                                "pos": ["x": 0.0, "y": 0.0],
                                "pos_rel": ["x": -1.0, "y": -1.0],
                                "scale": ["x": 1.0, "y": 1.0],
                                "scale_rel": ["x": 1.0, "y": 1.0],
                                "bounds": ["x": 0.0, "y": 0.0],
                                "bounds_rel": ["x": 0.0, "y": 0.0],
                                "scale_filter": "disable",
                                "blend_method": "default",
                                "blend_type": "normal",
                                "show_transition": ["duration": 0],
                                "hide_transition": ["duration": 0],
                                "private_settings": [:]
                            ]
                        ]
                    ],
                    "mixers": 0,
                    "sync": 0,
                    "flags": 0,
                    "volume": 1.0,
                    "balance": 0.5,
                    "enabled": true,
                    "muted": false,
                    "push-to-mute": false,
                    "push-to-mute-delay": 0,
                    "push-to-talk": false,
                    "push-to-talk-delay": 0,
                    "hotkeys": ["OBSBasic.SelectScene": []],
                    "deinterlace_mode": 0,
                    "deinterlace_field_order": 0,
                    "monitoring_type": 0,
                    "canvas_uuid": "6c69626f-6273-4c00-9d88-c5136d61696e",
                    "private_settings": [:]
                ],
                [
                    "prev_ver": 536_870_914,
                    "name": obsSyphonSourceName,
                    "uuid": sourceUUID,
                    "id": "syphon-input",
                    "versioned_id": "syphon-input",
                    "settings": [
                        "app_name": OBSSyphonPublisher.sharedInstance().appName,
                        "name": OBSSyphonPublisher.sharedInstance().serverName
                    ],
                    "mixers": 255,
                    "sync": 0,
                    "flags": 0,
                    "volume": 1.0,
                    "balance": 0.5,
                    "enabled": true,
                    "muted": false,
                    "push-to-mute": false,
                    "push-to-mute-delay": 0,
                    "push-to-talk": false,
                    "push-to-talk-delay": 0,
                    "hotkeys": [:],
                    "deinterlace_mode": 0,
                    "deinterlace_field_order": 0,
                    "monitoring_type": 0,
                    "private_settings": [:]
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: sceneCollection, options: [.prettyPrinted, .sortedKeys])
        let collectionURL = baseDirectory.appendingPathComponent("\(obsSceneCollectionName).json")
        try data.write(to: collectionURL, options: .atomic)
    }

    private struct PrivilegedInstallResult {
        let success: Bool
        let message: String
    }

    private struct BundleCodeSigningInfo {
        let authority: String?
        let teamIdentifier: String?
        let isAdHoc: Bool
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private struct InstalledSystemExtensionState {
        let enabled: Bool
        let active: Bool
        let rawState: String
    }

    private func activateSystemCameraExtension(triggeredByInstall: Bool) {
        guard systemCameraExtensionAvailable else {
            if triggeredByInstall {
                systemIntegrationInstallInProgress = false
                systemIntegrationInstallResult = "Bundled camera extension is not present in this app package."
            }
            return
        }
        let bundledSystemExtensionPath = Bundle.main.bundlePath + "/Contents/Library/SystemExtensions/\(systemCameraExtensionIdentifier).systemextension"
        if let failureReason = Self.cameraExtensionActivationFailureReason(
            appBundlePath: Bundle.main.bundlePath,
            extensionBundlePath: bundledSystemExtensionPath
        ) {
            systemIntegrationInstallInProgress = false
            systemIntegrationInstallResult = "Camera extension activation is unavailable: \(failureReason)"
            refreshSystemIntegrationStatus(requestEnable: publishToSystem)
            return
        }

        let observer = SystemExtensionRequestObserver(
            approvalHandler: { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.systemIntegrationInstallInProgress = false
                    self.systemCameraExtensionAwaitingApproval = true
                    self.publishToSystem = true
                    self.systemIntegrationInstallResult = "Camera extension activation requires approval in System Settings > General > Login Items & Extensions > Camera Extensions."
                    self.refreshSystemIntegrationStatus(requestEnable: true)
                }
            },
            finishHandler: { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.systemIntegrationInstallInProgress = false
                    self.systemCameraExtensionAwaitingApproval = false
                    self.publishToSystem = true
                    switch result {
                    case .completed:
                        self.systemIntegrationInstallResult = "Camera extension activated."
                    case .willCompleteAfterReboot:
                        self.systemIntegrationInstallResult = "Camera extension activation will complete after reboot."
                    @unknown default:
                        self.systemIntegrationInstallResult = "Camera extension activation completed with an unknown result."
                    }
                    self.pendingSystemExtensionObserver = nil
                    self.refreshSystemIntegrationStatus(requestEnable: true)
                }
            },
            failureHandler: { [weak self] error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.systemIntegrationInstallInProgress = false
                    self.systemCameraExtensionAwaitingApproval = false
                    self.systemIntegrationInstallResult = "Camera extension activation failed: \(error.localizedDescription)"
                    self.pendingSystemExtensionObserver = nil
                    self.refreshSystemIntegrationStatus(requestEnable: self.publishToSystem)
                }
            }
        )

        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: systemCameraExtensionIdentifier,
            queue: .main
        )
        request.delegate = observer
        pendingSystemExtensionObserver = observer
        systemIntegrationInstallInProgress = true
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    private func deactivateSystemCameraExtension() {
        let observer = SystemExtensionRequestObserver(
            approvalHandler: { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.systemIntegrationInstallInProgress = false
                    self.systemIntegrationInstallResult = "Camera extension deactivation requires approval in System Settings."
                    self.pendingSystemExtensionObserver = nil
                }
            },
            finishHandler: { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.systemIntegrationInstallInProgress = false
                    self.systemCameraExtensionAwaitingApproval = false
                    self.publishToSystem = false
                    self.systemIntegrationInstallResult = "Camera extension deactivated."
                    self.pendingSystemExtensionObserver = nil
                    self.refreshSystemIntegrationStatus(requestEnable: false)
                }
            },
            failureHandler: { [weak self] error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.systemIntegrationInstallInProgress = false
                    self.systemIntegrationInstallResult = "Camera extension deactivation failed: \(error.localizedDescription)"
                    self.pendingSystemExtensionObserver = nil
                    self.refreshSystemIntegrationStatus(requestEnable: self.publishToSystem)
                }
            }
        )

        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: systemCameraExtensionIdentifier,
            queue: .main
        )
        request.delegate = observer
        pendingSystemExtensionObserver = observer
        systemIntegrationInstallInProgress = true
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    private static func currentSystemExtensionState(identifier: String) -> InstalledSystemExtensionState? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
        process.arguments = ["list"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outputData, encoding: .utf8) else {
            return nil
        }

        for line in output.split(whereSeparator: \.isNewline) where line.contains(identifier) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if fields.count >= 6 {
                let stateField = fields.last?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) ?? ""
                return InstalledSystemExtensionState(
                    enabled: fields[0] == "*",
                    active: fields[1] == "*",
                    rawState: stateField
                )
            }

            let stateStart = line.lastIndex(of: "[") ?? line.startIndex
            let stateField = line[stateStart...].trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            return InstalledSystemExtensionState(
                enabled: line.contains("[activated enabled]"),
                active: line.contains("\t*\t"),
                rawState: stateField
            )
        }

        return nil
    }

    private static func currentCodeSigningInfo(bundlePath: String) -> BundleCodeSigningInfo? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=2", bundlePath]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outputData, encoding: .utf8) else {
            return nil
        }

        var authority: String?
        var teamIdentifier: String?
        var isAdHoc = false

        for line in output.split(whereSeparator: \.isNewline) {
            if authority == nil, line.hasPrefix("Authority=") {
                authority = String(line.dropFirst("Authority=".count))
                continue
            }
            if line.hasPrefix("TeamIdentifier=") {
                let value = String(line.dropFirst("TeamIdentifier=".count))
                if !value.isEmpty, value != "not set" {
                    teamIdentifier = value
                }
                continue
            }
            if line.hasPrefix("Signature="), line.localizedCaseInsensitiveContains("adhoc") {
                isAdHoc = true
            }
        }

        return BundleCodeSigningInfo(authority: authority, teamIdentifier: teamIdentifier, isAdHoc: isAdHoc)
    }

    private static func bundledCameraExtensionMachServiceName(bundlePath: String) -> String? {
        let infoPlistPath = bundlePath + "/Contents/Info.plist"
        guard
            let info = NSDictionary(contentsOfFile: infoPlistPath) as? [String: Any],
            let extensionInfo = info["CMIOExtension"] as? [String: Any],
            let machServiceName = extensionInfo["CMIOExtensionMachServiceName"] as? String,
            !machServiceName.isEmpty
        else {
            return nil
        }
        return machServiceName
    }

    private static func bundleHasEntitlement(bundlePath: String, key: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-d", "--entitlements", ":-", bundlePath]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return false
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return false
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outputData, encoding: .utf8) else {
            return false
        }

        return output.contains("<key>\(key)</key>")
    }

    private static func cameraExtensionActivationFailureReason(
        appBundlePath: String,
        extensionBundlePath: String
    ) -> String? {
        let appSigningInfo = currentCodeSigningInfo(bundlePath: appBundlePath)
        let extensionSigningInfo = currentCodeSigningInfo(bundlePath: extensionBundlePath)
        let machServiceName = bundledCameraExtensionMachServiceName(bundlePath: extensionBundlePath)

        if let appSigningInfo, appSigningInfo.isAdHoc {
            return "Camera extension activation requires a valid Apple Developer certificate (ad hoc signing is insufficient). Build with a provisioning profile that includes the System Extension capability."
        }
        if let extensionSigningInfo, extensionSigningInfo.isAdHoc {
            return "Camera extension is ad hoc signed and cannot be activated. Re-build with a valid Apple Developer certificate and provisioning profile."
        }
        if let appTeam = appSigningInfo?.teamIdentifier,
           let extensionTeam = extensionSigningInfo?.teamIdentifier,
           appTeam != extensionTeam {
            return "App and camera extension use different team identifiers (\(appTeam) vs \(extensionTeam)). Both must be signed by the same Apple Developer team."
        }
        if let extensionTeam = extensionSigningInfo?.teamIdentifier,
           let machServiceName,
           !machServiceName.hasPrefix(extensionTeam + ".") {
            return "Camera extension mach service '\(machServiceName)' does not match signing team \(extensionTeam). The extension identifier must be prefixed with the team ID."
        }
        if !bundleHasEntitlement(bundlePath: appBundlePath, key: "com.apple.developer.system-extension.install") {
            return "App is missing the System Extension entitlement. A provisioning profile with the 'System Extension' capability is required. Visit https://developer.apple.com/system-extensions/ to request this capability."
        }
        return nil
    }

    private static func installedBundleSigningIssue(bundlePath: String, expectedTeamIdentifier: String?) -> String? {
        guard let signingInfo = currentCodeSigningInfo(bundlePath: bundlePath) else {
            return "its signature could not be inspected"
        }
        if signingInfo.isAdHoc {
            return "it is ad hoc signed"
        }
        if let expectedTeamIdentifier,
           let actualTeamIdentifier = signingInfo.teamIdentifier,
           actualTeamIdentifier != expectedTeamIdentifier {
            return "it is signed for team \(actualTeamIdentifier) instead of \(expectedTeamIdentifier)"
        }
        return nil
    }

    private static func firstPublishedCameraName() -> String? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.first(where: {
            $0.localizedName.range(of: "kinect", options: .caseInsensitive) != nil
        })?.localizedName
    }

    private static func firstPublishedNamedCamera(containing nameFragment: String) -> String? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.first(where: {
            $0.localizedName.range(of: nameFragment, options: .caseInsensitive) != nil
        })?.localizedName
    }

    private static func firstPublishedMicrophoneName() -> String? {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var devicesSize: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(systemObject, &devicesAddress, 0, nil, &devicesSize) == noErr else {
            return nil
        }
        guard devicesSize >= UInt32(MemoryLayout<AudioDeviceID>.stride) else {
            return nil
        }

        let deviceCount = Int(devicesSize) / MemoryLayout<AudioDeviceID>.stride
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            systemObject,
            &devicesAddress,
            0,
            nil,
            &devicesSize,
            &deviceIDs
        ) == noErr else {
            return nil
        }

        for deviceID in deviceIDs where deviceHasInputStreams(deviceID) {
            guard let name = audioObjectName(deviceID),
                  name.range(of: "kinect", options: .caseInsensitive) != nil else {
                continue
            }
            return name
        }
        return nil
    }

    private static func obsKinectPluginInstalled(userPluginPath: String, appBundlePath: String) -> Bool {
        let fileManager = FileManager.default
        let candidateRoots = [
            userPluginPath,
            appBundlePath + "/Contents/PlugIns"
        ]

        for root in candidateRoots where fileManager.fileExists(atPath: root) {
            guard let enumerator = fileManager.enumerator(atPath: root) else {
                continue
            }
            for case let entry as String in enumerator {
                let lowercasedEntry = entry.lowercased()
                if lowercasedEntry.contains("obs-kinect") {
                    return true
                }
            }
        }

        return false
    }

    private static func deviceHasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamsSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &streamsAddress, 0, nil, &streamsSize) == noErr else {
            return false
        }
        return streamsSize >= UInt32(MemoryLayout<AudioStreamID>.stride)
    }

    private static func audioObjectName(_ objectID: AudioObjectID) -> String? {
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.stride)
        var unmanagedName: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &unmanagedName) {
            AudioObjectGetPropertyData(objectID, &nameAddress, 0, nil, &size, $0)
        }
        guard status == noErr, let unmanagedName else {
            return nil
        }
        return unmanagedName.takeUnretainedValue() as String
    }

    private func audioHalReloadDiagnostic() -> String? {
        guard let runningDriverElapsed = Self.runningProcessElapsedSeconds(commandFragment: "Core Audio Driver (KinectAudioHAL.driver)") else {
            return nil
        }

        let candidateBinaries = [
            systemAudioHalPath + "/Contents/MacOS/KinectAudioHAL",
            userAudioHalPath + "/Contents/MacOS/KinectAudioHAL"
        ]

        let newestInstalledBinary = candidateBinaries.compactMap(Self.fileModificationDate(atPath:)).max()
        guard let newestInstalledBinary else {
            return nil
        }

        let runningDriverStart = Date().addingTimeInterval(-runningDriverElapsed)
        if newestInstalledBinary.timeIntervalSince(runningDriverStart) > 2 {
            return "Audio HAL on disk is newer than the running Core Audio driver process. Sign out/in or reboot to reload Core Audio."
        }
        return nil
    }

    private static func fileModificationDate(atPath path: String) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

    private static func runningProcessElapsedSeconds(commandFragment: String) -> TimeInterval? {
        let processIDs = matchingProcessIDs(commandFragment: commandFragment)
        for processID in processIDs {
            if let elapsedSeconds = processElapsedSeconds(processID: processID) {
                return elapsedSeconds
            }
        }
        return nil
    }

    private static func matchingProcessIDs(commandFragment: String) -> [String] {
        let escapedPattern = NSRegularExpression.escapedPattern(for: commandFragment)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", escapedPattern]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return []
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: outputData, encoding: .utf8) else {
            return []
        }

        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func processElapsedSeconds(processID: String) -> TimeInterval? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "etimes=", "-p", processID]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }

        guard let output = String(data: outputData, encoding: .utf8) else {
            return nil
        }

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { TimeInterval($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .first
    }

    // System integration is staged in /tmp first so install_name_tool and
    // codesign can mutate a writable copy before the final privileged install.
    private static func runSystemIntegrationInstall(
        audioHalSourcePath: String,
        cameraDalSourcePath: String?,
        appFrameworksPath: String?,
        firmwareSourcePath: String?,
        codesignIdentity: String,
        preferencesPlistPath: String,
        systemCameraStreamValue: Int,
        systemMicModeValue: Int
    ) -> PrivilegedInstallResult {
        var commands: [String] = []
        let effectiveCodesignIdentity = codesignIdentity.isEmpty ? "-" : codesignIdentity
        let systemHalPath = "/Library/Audio/Plug-Ins/HAL/KinectAudioHAL.driver"

        // Use mktemp-created staging directories inside the privileged shell so
        // the install does not rely on predictable /tmp paths that another
        // local process could pre-create or race.
        commands.append("cleanup() { [ -n \"${STAGED_DAL_ROOT:-}\" ] && /bin/rm -rf \"$STAGED_DAL_ROOT\"; [ -n \"${STAGED_HAL_ROOT:-}\" ] && /bin/rm -rf \"$STAGED_HAL_ROOT\"; }")
        commands.append("trap cleanup EXIT")
        commands.append("STAGED_TMP_BASE=\"${TMPDIR:-/tmp}\"")
        commands.append("STAGED_HAL_ROOT=$(/usr/bin/mktemp -d \"${STAGED_TMP_BASE%/}/KinectAudioHAL-install.XXXXXX\")")
        commands.append("STAGED_HAL=\"$STAGED_HAL_ROOT/KinectAudioHAL.driver\"")
        commands.append("STAGED_HAL_FRAMEWORKS=\"$STAGED_HAL/Contents/Frameworks\"")
        commands.append("STAGED_HAL_BINARY=\"$STAGED_HAL/Contents/MacOS/KinectAudioHAL\"")
        commands.append("STAGED_HAL_FIRMWARE_DIR=\"$STAGED_HAL/Contents/Resources/libfreenect\"")
        commands.append("/usr/bin/ditto \(shellQuote(audioHalSourcePath)) \"$STAGED_HAL\"")
        if let appFrameworksPath {
            commands.append("/bin/mkdir -p \"$STAGED_HAL_FRAMEWORKS\"")
            let halFrameworkCopyScript = """
if [ -d \(shellQuote(appFrameworksPath)) ]; then \
for pattern in libfreenect*.dylib libusb-1.0*.dylib libturbojpeg*.dylib; do \
for lib in \(shellQuote(appFrameworksPath))/$pattern; do \
[ -e "$lib" ] || continue; \
/usr/bin/ditto "$lib" "$STAGED_HAL_FRAMEWORKS"/$(basename "$lib"); \
done; \
done; \
fi
"""
            commands.append(halFrameworkCopyScript)
        }
        if let firmwareSourcePath {
            commands.append("/bin/mkdir -p \"$STAGED_HAL_FIRMWARE_DIR\"")
            commands.append("/usr/bin/ditto \(shellQuote(firmwareSourcePath)) \"$STAGED_HAL_FIRMWARE_DIR/audios.bin\"")
        }
        commands.append("if [ -f \"$STAGED_HAL_BINARY\" ]; then /usr/bin/install_name_tool -add_rpath @loader_path/../Frameworks \"$STAGED_HAL_BINARY\" >/dev/null 2>&1 || true; fi")
        let halBinaryFixupScript = """
if [ -f "$STAGED_HAL_BINARY" ]; then \
for dep in "$STAGED_HAL_FRAMEWORKS"/libfreenect*.dylib "$STAGED_HAL_FRAMEWORKS"/libusb-1.0*.dylib "$STAGED_HAL_FRAMEWORKS"/libturbojpeg*.dylib; do \
[ -e "$dep" ] || continue; \
base=$(basename "$dep"); \
/usr/bin/install_name_tool -change @executable_path/../Frameworks/$base @rpath/$base "$STAGED_HAL_BINARY" || true; \
done; \
/usr/bin/install_name_tool -change /opt/homebrew/opt/libusb/lib/libusb-1.0.0.dylib @rpath/libusb-1.0.0.dylib "$STAGED_HAL_BINARY" || true; \
/usr/bin/install_name_tool -change /opt/homebrew/opt/jpeg-turbo/lib/libturbojpeg.0.dylib @rpath/libturbojpeg.0.dylib "$STAGED_HAL_BINARY" || true; \
fi
"""
        commands.append(halBinaryFixupScript)
        let halLibraryFixupScript = """
for lib in "$STAGED_HAL_FRAMEWORKS"/libfreenect*.dylib; do \
[ -e "$lib" ] || continue; \
base=$(basename "$lib"); \
/usr/bin/install_name_tool -id @loader_path/$base "$lib" || true; \
/usr/bin/install_name_tool -change @executable_path/../Frameworks/libusb-1.0.0.dylib @loader_path/libusb-1.0.0.dylib "$lib" || true; \
done; \
for lib in "$STAGED_HAL_FRAMEWORKS"/libusb-1.0*.dylib "$STAGED_HAL_FRAMEWORKS"/libturbojpeg*.dylib; do \
[ -e "$lib" ] || continue; \
base=$(basename "$lib"); \
/usr/bin/install_name_tool -id @loader_path/$base "$lib" || true; \
done
"""
        commands.append(halLibraryFixupScript)
        commands.append("/usr/bin/codesign --force --deep --sign \(shellQuote(effectiveCodesignIdentity)) --timestamp=none \"$STAGED_HAL\"")
        commands.append("/usr/bin/codesign --verify --verbose=2 --deep \"$STAGED_HAL\"")
        commands.append("/bin/rm -rf \(shellQuote(systemHalPath))")
        commands.append("/usr/bin/ditto \"$STAGED_HAL\" \(shellQuote(systemHalPath))")

        if let cameraDalSourcePath {
            let systemDalPath = "/Library/CoreMediaIO/Plug-Ins/DAL/KinectCameraDAL.plugin"

            commands.append("STAGED_DAL_ROOT=$(/usr/bin/mktemp -d \"${STAGED_TMP_BASE%/}/KinectCameraDAL-install.XXXXXX\")")
            commands.append("STAGED_DAL_PLUGIN=\"$STAGED_DAL_ROOT/KinectCameraDAL.plugin\"")
            commands.append("STAGED_DAL_FRAMEWORKS=\"$STAGED_DAL_PLUGIN/Contents/Frameworks\"")
            commands.append("STAGED_DAL_BINARY=\"$STAGED_DAL_PLUGIN/Contents/MacOS/KinectCameraDAL\"")
            commands.append("/usr/bin/ditto \(shellQuote(cameraDalSourcePath)) \"$STAGED_DAL_PLUGIN\"")
            if let appFrameworksPath {
                commands.append("/bin/mkdir -p \"$STAGED_DAL_FRAMEWORKS\"")
                let frameworkCopyScript = """
if [ -d \(shellQuote(appFrameworksPath)) ]; then \
for pattern in libfreenect.0*.dylib libfreenect2*.dylib libusb-1.0*.dylib libturbojpeg*.dylib; do \
for lib in \(shellQuote(appFrameworksPath))/$pattern; do \
[ -e "$lib" ] || continue; \
/usr/bin/ditto "$lib" "$STAGED_DAL_FRAMEWORKS"/$(basename "$lib"); \
done; \
done; \
fi
"""
                commands.append(frameworkCopyScript)
            }
            commands.append("if [ -f \"$STAGED_DAL_BINARY\" ]; then /usr/bin/install_name_tool -add_rpath @loader_path/../Frameworks \"$STAGED_DAL_BINARY\" >/dev/null 2>&1 || true; fi")
            commands.append("if [ -f \"$STAGED_DAL_BINARY\" ]; then /usr/bin/install_name_tool -change /opt/homebrew/opt/libusb/lib/libusb-1.0.0.dylib @rpath/libusb-1.0.0.dylib \"$STAGED_DAL_BINARY\" || true; fi")
            commands.append("if [ -f \"$STAGED_DAL_BINARY\" ]; then /usr/bin/install_name_tool -change /opt/homebrew/opt/jpeg-turbo/lib/libturbojpeg.0.dylib @rpath/libturbojpeg.0.dylib \"$STAGED_DAL_BINARY\" || true; fi")
            let dalLibraryFixupScript = """
for lib in "$STAGED_DAL_FRAMEWORKS"/libfreenect*.dylib; do \
[ -e "$lib" ] || continue; \
base=$(basename "$lib"); \
/usr/bin/install_name_tool -id @loader_path/$base "$lib" || true; \
/usr/bin/install_name_tool -change @executable_path/../Frameworks/libusb-1.0.0.dylib @loader_path/libusb-1.0.0.dylib "$lib" || true; \
done; \
for lib in "$STAGED_DAL_FRAMEWORKS"/libfreenect2*.dylib; do \
[ -e "$lib" ] || continue; \
base=$(basename "$lib"); \
/usr/bin/install_name_tool -id @loader_path/$base "$lib" || true; \
/usr/bin/install_name_tool -change @executable_path/../Frameworks/libusb-1.0.0.dylib @loader_path/libusb-1.0.0.dylib "$lib" || true; \
/usr/bin/install_name_tool -change @executable_path/../Frameworks/libturbojpeg.0.dylib @loader_path/libturbojpeg.0.dylib "$lib" || true; \
done; \
for lib in "$STAGED_DAL_FRAMEWORKS"/libusb-1.0*.dylib "$STAGED_DAL_FRAMEWORKS"/libturbojpeg*.dylib; do \
[ -e "$lib" ] || continue; \
base=$(basename "$lib"); \
/usr/bin/install_name_tool -id @loader_path/$base "$lib" || true; \
done
"""
            commands.append(dalLibraryFixupScript)
            commands.append("/usr/bin/codesign --force --deep --sign \(shellQuote(effectiveCodesignIdentity)) --timestamp=none \"$STAGED_DAL_PLUGIN\"")
            commands.append("/usr/bin/codesign --verify --verbose=2 --deep \"$STAGED_DAL_PLUGIN\"")
            commands.append("/bin/rm -rf \(shellQuote(systemDalPath))")
            commands.append("/usr/bin/ditto \"$STAGED_DAL_PLUGIN\" \(shellQuote(systemDalPath))")
        }

        commands.append("/usr/bin/defaults write \(shellQuote(preferencesPlistPath)) SystemCameraStream -int \(systemCameraStreamValue)")
        commands.append("/usr/bin/defaults write \(shellQuote(preferencesPlistPath)) SystemMicrophoneMode -int \(systemMicModeValue)")
        commands.append("/usr/bin/killall coreaudiod >/dev/null 2>&1 || true")
        commands.append("/usr/bin/killall VDCAssistant AppleCameraAssistant >/dev/null 2>&1 || true")
        return runPrivilegedShellCommand(commands: commands, successMessage: "System integration installed. You can now enable system publish.")
    }

    private static func runSystemIntegrationPreferenceSync(
        preferencesPlistPath: String,
        systemCameraStreamValue: Int,
        systemMicModeValue: Int,
        restartAudioServices: Bool,
        restartCameraServices: Bool
    ) -> PrivilegedInstallResult {
        var commands: [String] = [
            "/usr/bin/defaults write \(shellQuote(preferencesPlistPath)) SystemCameraStream -int \(systemCameraStreamValue)",
            "/usr/bin/defaults write \(shellQuote(preferencesPlistPath)) SystemMicrophoneMode -int \(systemMicModeValue)"
        ]
        if restartAudioServices {
            commands.append("/usr/bin/killall coreaudiod >/dev/null 2>&1 || true")
        }
        if restartCameraServices {
            commands.append("/usr/bin/killall VDCAssistant AppleCameraAssistant >/dev/null 2>&1 || true")
        }
        return runPrivilegedShellCommand(commands: commands, successMessage: "Shared system camera/microphone settings applied.")
    }

    /// Centralize privileged shell execution so install and preference-sync
    /// flows surface the same cancellation and error handling behavior.
    private static func runPrivilegedShellCommand(
        commands: [String],
        successMessage: String
    ) -> PrivilegedInstallResult {
        let shellCommand = "PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH; set -eu; umask 022; " + commands.joined(separator: "; ")
        let escapedCommand = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScriptSource = "do shell script \"\(escapedCommand)\" with administrator privileges"

        guard let script = NSAppleScript(source: appleScriptSource) else {
            return PrivilegedInstallResult(success: false, message: "Could not create privileged installer request.")
        }

        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "Unknown install error."
            if code == -128 {
                return PrivilegedInstallResult(success: false, message: "Operation was canceled.")
            }
            return PrivilegedInstallResult(success: false, message: "Install failed: \(message)")
        }

        return PrivilegedInstallResult(success: true, message: successMessage)
    }

    private func refreshAudioRuntimeState() {
        let active = bridge?.audioEnabled() ?? false
        audioStreamActive = active
        audioLevel = active ? (bridge?.audioLevel() ?? 0) : 0
        let summary = String(
            format: "supported=%@ enabled=%@ active=%@ level=%.3f connected=%@ streaming=%@",
            supportsAudioInput.description,
            audioEnabled.description,
            active.description,
            audioLevel,
            connected.description,
            streaming.description
        )
        traceIfChanged("audio", summary, key: &lastAudioRuntimeTrace)
        if active, let debug = bridge?.audioDebugSummary() {
            traceIfChanged("audio-debug", debug, key: &lastAudioDebugTrace)
        }
    }

    func captureStillImage(_ image: CGImage, streamType: KinectStreamType) {
        do {
            let captureDir = captureRootDirectory().appendingPathComponent(Self.captureTimestamp(), isDirectory: true)
            try FileManager.default.createDirectory(at: captureDir, withIntermediateDirectories: true)

            let fileName = "still-\(streamType.fileNameComponent).\(stillImageFormat.fileExtension)"
            let fileURL = captureDir.appendingPathComponent(fileName)
            try writeStillImage(image, to: fileURL, format: stillImageFormat, quality: stillImageQuality)

            lastCapturePath = captureDir.path
            status = "Image captured: \(fileURL.lastPathComponent)"
        } catch {
            status = "Image capture failed: \(error.localizedDescription)"
        }
    }

    func startVideoRecording(_ image: CGImage, streamType: KinectStreamType) {
        guard connected, streaming else {
            status = "Connect and start streaming before recording video."
            return
        }
        guard !isRecordingVideo else {
            status = "Video recording is already in progress."
            return
        }

        do {
            let captureDir = captureRootDirectory().appendingPathComponent(Self.captureTimestamp(), isDirectory: true)
            try FileManager.default.createDirectory(at: captureDir, withIntermediateDirectories: true)

            let fileURL = captureDir.appendingPathComponent("video-\(streamType.fileNameComponent).mov")
            let recorder = try PreviewMovieRecorder(
                outputURL: fileURL,
                width: image.width,
                height: image.height,
                qualityPreset: videoQualityPreset
            )

            guard recorder.appendFrame(image) else {
                throw NSError(domain: "KinectManager", code: 2001, userInfo: [NSLocalizedDescriptionKey: "Could not write the first video frame"])
            }

            videoRecorder = recorder
            recordingStreamType = streamType
            videoRecordStartDate = Date()
            recordingVideoSeconds = 0
            isRecordingVideo = true
            lastVideoPath = fileURL.path
            lastCapturePath = captureDir.path
            status = "Recording \(streamType.title) video (\(videoQualityPreset.title))."
        } catch {
            status = "Video recording failed to start: \(error.localizedDescription)"
        }
    }

    func appendPreviewFrameForRecording(_ image: CGImage, streamType: KinectStreamType) {
        guard isRecordingVideo else { return }
        guard recordingStreamType == streamType else { return }
        guard let videoRecorder else { return }

        if videoRecorder.appendFrame(image) {
            if let videoRecordStartDate {
                recordingVideoSeconds = Date().timeIntervalSince(videoRecordStartDate)
            }
        }
    }

    func stopVideoRecording() {
        guard let recorder = videoRecorder else {
            isRecordingVideo = false
            recordingStreamType = nil
            videoRecordStartDate = nil
            recordingVideoSeconds = 0
            return
        }

        let outputPath = recorder.outputURL.path
        videoRecorder = nil
        isRecordingVideo = false
        recordingStreamType = nil
        videoRecordStartDate = nil

        recorder.finish { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.recordingVideoSeconds = 0
                if let error {
                    self.status = "Video recording failed: \(error.localizedDescription)"
                } else {
                    self.lastVideoPath = outputPath
                    self.status = "Video saved: \((outputPath as NSString).lastPathComponent)"
                }
            }
        }
    }

    private func writeStillImage(_ image: CGImage, to url: URL, format: StillImageFormat, quality: Double) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw NSError(domain: "KinectManager", code: 2002, userInfo: [NSLocalizedDescriptionKey: "Could not create image destination"])
        }

        let options: [CFString: Any]
        if format.supportsQuality {
            options = [kCGImageDestinationLossyCompressionQuality: min(max(quality, 0.05), 1.0)]
        } else {
            options = [:]
        }

        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "KinectManager", code: 2003, userInfo: [NSLocalizedDescriptionKey: "Could not finalize image file"])
        }
    }

    func captureScanBundle() {
        guard !scannerBusy else {
            status = "3D scanner capture already in progress."
            return
        }
        guard connected else {
            status = "Connect a device first."
            return
        }

        let now = Date()
        let freshFrame = bridge?.pollFrame()
        let frame: KinectFrame
        if let freshFrame {
            frame = freshFrame
            lastFrame = freshFrame
            lastFrameCaptureDate = now
        } else if
            let cached = lastFrame,
            let capturedAt = lastFrameCaptureDate,
            now.timeIntervalSince(capturedAt) <= 1.0 {
            frame = cached
        } else {
            status = "No recent frame available. Wait for streaming to deliver a fresh frame."
            return
        }

        // Copy frame payloads immediately so scanning is not dependent on bridge object lifetimes.
        let rgbData = Data(frame.rgbData)
        let depthData = Data(frame.depthData)
        let irData = Data(frame.irData)
        let width = frame.width
        let height = frame.height
        let generation = currentDevice?.generation ?? 1
        guard width > 0, height > 0 else {
            status = "Invalid frame dimensions."
            return
        }

        let pixelCount = width * height
        let expectedRgbBytes = pixelCount * 3
        let expectedDepthBytes = pixelCount * MemoryLayout<UInt16>.size
        let expectedIrBytes = pixelCount

        let captureDir = captureRootDirectory().appendingPathComponent(Self.captureTimestamp(), isDirectory: true)
        scannerBusy = true
        status = "Capturing 3D scan..."

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.createDirectory(at: captureDir, withIntermediateDirectories: true)

                var wroteColor = false
                var wroteDepth = false
                var wroteIr = false
                var points = 0

                if rgbData.count >= expectedRgbBytes {
                    try self.writeColorPPM(rgbData, width: width, height: height, to: captureDir.appendingPathComponent("color.ppm"))
                    wroteColor = true
                }

                if depthData.count >= expectedDepthBytes {
                    try self.writeDepthPGM(depthData, width: width, height: height, to: captureDir.appendingPathComponent("depth_mm.pgm"))
                    wroteDepth = true
                    points = try self.writePointCloudPLY(
                        depthData: depthData,
                        rgbData: rgbData,
                        irData: irData,
                        width: width,
                        height: height,
                        generation: generation,
                        to: captureDir.appendingPathComponent("scan.ply")
                    )
                }

                if irData.count >= expectedIrBytes {
                    try self.writeIrPGM(irData, width: width, height: height, to: captureDir.appendingPathComponent("infrared.pgm"))
                    wroteIr = true
                }

                DispatchQueue.main.async {
                    self.scannerBusy = false
                    self.lastCapturePath = captureDir.path
                    self.lastCapturePointCount = points
                    self.status = "Capture saved (\(wroteColor ? "RGB" : "-")/\(wroteDepth ? "Depth" : "-")/\(wroteIr ? "IR" : "-"), points: \(points)"
                }
            } catch {
                DispatchQueue.main.async {
                    self.scannerBusy = false
                    self.status = "Capture failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func captureRootDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("KinectCaptures", isDirectory: true)
    }

    private func writeColorPPM(_ data: Data, width: Int, height: Int, to url: URL) throws {
        let pixelCount = width * height
        let expected = pixelCount * 3
        var output = Data("P6\n\(width) \(height)\n255\n".utf8)
        output.append(data.prefix(expected))
        try output.write(to: url, options: .atomic)
    }

    private func writeIrPGM(_ data: Data, width: Int, height: Int, to url: URL) throws {
        let pixelCount = width * height
        let expected = pixelCount
        var output = Data("P5\n\(width) \(height)\n255\n".utf8)
        output.append(data.prefix(expected))
        try output.write(to: url, options: .atomic)
    }

    private func writeDepthPGM(_ data: Data, width: Int, height: Int, to url: URL) throws {
        let pixelCount = width * height
        let expected = pixelCount * MemoryLayout<UInt16>.size
        guard data.count >= expected else {
            throw NSError(domain: "KinectManager", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Depth frame is incomplete"])
        }

        var bytes = [UInt8](repeating: 0, count: expected)
        data.withUnsafeBytes { rawBuffer in
            let depth = rawBuffer.bindMemory(to: UInt16.self)
            for i in 0..<pixelCount {
                let value = UInt16(littleEndian: depth[i])
                bytes[i * 2] = UInt8((value >> 8) & 0xFF)
                bytes[i * 2 + 1] = UInt8(value & 0xFF)
            }
        }

        var output = Data("P5\n\(width) \(height)\n65535\n".utf8)
        output.append(contentsOf: bytes)
        try output.write(to: url, options: .atomic)
    }

    private func writePointCloudPLY(
        depthData: Data,
        rgbData: Data,
        irData: Data,
        width: Int,
        height: Int,
        generation: Int,
        to url: URL
    ) throws -> Int {
        let pixelCount = width * height
        let expectedDepthBytes = pixelCount * MemoryLayout<UInt16>.size
        guard depthData.count >= expectedDepthBytes else {
            throw NSError(domain: "KinectManager", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Depth frame is incomplete"])
        }

        let intrinsics = pointCloudIntrinsics(width: width, height: height, generation: generation)
        let hasRgb = rgbData.count >= pixelCount * 3
        let hasIr = irData.count >= pixelCount

        let rgbBytes: [UInt8] = hasRgb ? Array(rgbData.prefix(pixelCount * 3)) : []
        let irBytes: [UInt8] = hasIr ? Array(irData.prefix(pixelCount)) : []

        var valid = 0
        var body = String()
        body.reserveCapacity(pixelCount * 26)

        depthData.withUnsafeBytes { rawBuffer in
            let depth = rawBuffer.bindMemory(to: UInt16.self)
            for y in 0..<height {
                for x in 0..<width {
                    let index = y * width + x
                    let d = UInt16(littleEndian: depth[index])
                    if d < 350 || d > 6000 {
                        continue
                    }

                    // Export points in meters so the generated PLY can be used
                    // directly by common DCC and scanning tools.
                    let z = Double(d) / 1000.0
                    let worldX = (Double(x) - intrinsics.cx) / intrinsics.fx * z
                    let worldY = (Double(y) - intrinsics.cy) / intrinsics.fy * z

                    let r: UInt8
                    let g: UInt8
                    let b: UInt8
                    if hasRgb {
                        let rgbIndex = index * 3
                        r = rgbBytes[rgbIndex]
                        g = rgbBytes[rgbIndex + 1]
                        b = rgbBytes[rgbIndex + 2]
                    } else if hasIr {
                        let v = irBytes[index]
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

                    body += "\(worldX) \(worldY) \(z) \(r) \(g) \(b)\n"
                    valid += 1
                }
            }
        }

        let header = """
        ply
        format ascii 1.0
        element vertex \(valid)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header

        """
        try (header + body).write(to: url, atomically: true, encoding: .ascii)
        return valid
    }

    private func pointCloudIntrinsics(width: Int, height: Int, generation: Int) -> (fx: Double, fy: Double, cx: Double, cy: Double) {
        if generation == 2, width == 512, height == 424 {
            return (365.456, 365.456, 254.878, 205.395)
        }
        return (594.214, 591.040, 339.307, 242.739)
    }

    private static func captureTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func clearDeviceSession(closeBridge: Bool) {
        if closeBridge {
            bridge?.closeDevice()
        } else {
            bridge?.stopStream()
        }
        connected = false
        streaming = false
        audioEnabled = false
        audioStreamActive = false
        audioLevel = 0
        currentDevice = nil
        lastFrame = nil
        lastFrameCaptureDate = nil
        trackingResult = .empty
        trackingStatus = trackingEnabled ? "Waiting for RGB frame" : VisionTrackingResult.empty.message
        trackingService.reset()
        resetCapabilities()
        trace("device", "Cleared device session; closeBridge=\(closeBridge).")
    }

    private func resetCapabilities() {
        supportsMotor = false
        supportsLed = false
        supportsAudioInput = false
        supportsDepth = false
        supportsIr = false
    }

    private func normalizeFeatureState() {
        guard supportsAudioInput else {
            audioEnabled = false
            audioStreamActive = false
            audioLevel = 0
            return
        }
    }

    private var shouldApplyImageControlFlags: Bool {
        // libfreenect v1 control transfers (mirror/exposure/near/IR) can
        // dereference a null USB handle on recent macOS builds, causing a
        // crash inside libusb_control_transfer during device connect. Disable
        // those control writes for Kinect v1 until a safe subdevice path exists.
        return currentDevice?.generation == 2
    }

    var canApplyImageControls: Bool {
        shouldApplyImageControlFlags
    }

    var imageControlSupportDetail: String {
        switch currentDevice?.generation {
        case 2:
            return "Image control flags are available for Kinect v2 in the current backend."
        case 1:
            return "Mirror, exposure, white balance, near mode, and infrared brightness are temporarily disabled for Kinect v1 on current macOS builds because the underlying libfreenect control transfer path can crash."
        default:
            return "Connect a device to determine which image controls are available."
        }
    }

    var diagnosticsLogPath: String {
        DiagnosticsLogger.shared.logFileURL.path
    }

    var unifiedMicrophoneStatus: String {
        if systemMicPublished {
            return "System Published"
        }
        if audioStreamActive {
            return "Direct Active"
        }
        if audioEnabled {
            return "Direct Armed"
        }
        if supportsAudioInput {
            return "Direct Ready"
        }
        return "Unavailable"
    }

    var ledModeDisplayName: String {
        Self.ledModeDisplayName(for: ledMode)
    }

    static func ledModeDisplayName(for mode: Int) -> String {
        switch mode {
        case 0: return "Off"
        case 1: return "Green"
        case 2: return "Red"
        case 3: return "Amber"
        case 4, 5: return "Blink Green"
        case 6: return "Blink Red/Amber"
        default: return "Unknown"
        }
    }

    var directMicrophoneSupportDetail: String {
        if supportsAudioInput {
            return "Direct Kinect microphone capture is available in this session."
        }

        let generation = currentDevice?.generation ?? devices.first(where: { $0.id == selectedDeviceID })?.generation
        switch generation {
        case 2:
            return "Direct Kinect v2 microphone capture is not implemented in the current backend. Use the published system microphone path instead."
        case 1:
            return "Direct Kinect v1 microphone capture needs the libfreenect audio firmware file audios.bin. If that firmware is missing, direct microphone capture stays unavailable."
        default:
            return "Connect a Kinect device to determine whether direct microphone capture is available."
        }
    }

    private func trace(_ category: String, _ message: String) {
        DiagnosticsLogger.shared.log(category: category, message: message)
        let line = "[\(category)] \(message)"
        DispatchQueue.main.async {
            self.recentDiagnostics.append(line)
            if self.recentDiagnostics.count > 16 {
                self.recentDiagnostics.removeFirst(self.recentDiagnostics.count - 16)
            }
        }
    }

    private func traceIfChanged(_ category: String, _ message: String, key: inout String) {
        guard key != message else { return }
        key = message
        trace(category, message)
    }
}
