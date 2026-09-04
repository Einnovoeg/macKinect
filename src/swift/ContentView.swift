import SwiftUI
import CoreGraphics
import AppKit
import Combine

struct ContentView: View {
    @StateObject private var manager = KinectManager()

    @State private var rgbImage: CGImage?
    @State private var irImage: CGImage?
    @State private var depthImage: CGImage?
    @State private var selectedSidebarSection: SidebarSection = .control

    // A lightweight polling timer keeps the SwiftUI preview responsive without
    // forcing the bridge layer to push frames onto the UI thread.
    private let frameTimer = Timer.publish(every: 0.033, on: .main, in: .common)
    @State private var frameTimerConnection: Cancellable?

    private enum SidebarSection: String, CaseIterable, Identifiable {
        case control = "Control"
        case capture = "Capture"
        case tracking = "Tracking"
        case hardware = "Hardware"

        var id: String { rawValue }
    }

    var body: some View {
        ZStack(alignment: .top) {
            backgroundView

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    controlsPanel
                        .frame(width: 392)
                        .fixedSize(horizontal: true, vertical: false)

                    previewPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(16)
                .padding(.bottom, 8)

                // Static footer — never invalidated by streaming
                HStack {
                    Text("Kinect v1/v2 camera, depth, infrared, audio, and scanner control for macOS.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .transaction { $0.animation = nil }
                    Spacer()
                    Text("v\(appVersion)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.35))
                        .transaction { $0.animation = nil }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.18))
                .transaction { $0.animation = nil }
            }
        }
        .tint(Color(red: 0.12, green: 0.79, blue: 0.93))
        .frame(minWidth: 1280, minHeight: 820)
        .transaction { $0.animation = nil }
        .onAppear {
            manager.performInitialLoadIfNeeded()
            updateFrameTimerConnection()
        }
        .onDisappear {
            frameTimerConnection?.cancel()
            frameTimerConnection = nil
        }
        .onChange(of: manager.streaming) {
            updateFrameTimerConnection()
        }
        .onReceive(frameTimer) { _ in
            var txn = Transaction()
            txn.animation = nil
            txn.disablesAnimations = true
            withTransaction(txn) {
                guard let frame = manager.pollFrame() else { return }
                let newRgbImage = frame.rgbData.rgbCGImage(width: frame.width, height: frame.height)
                rgbImage = newRgbImage
                irImage = frame.irData.grayCGImage(width: frame.width, height: frame.height)
                depthImage = frame.depthData.depthCGImage(width: frame.width, height: frame.height)

                if let newRgbImage {
                    manager.processTrackingFrame(
                        newRgbImage,
                        depthData: frame.depthData,
                        width: frame.width,
                        height: frame.height
                    )
                }

                if let image = selectedPreviewImage {
                    manager.appendPreviewFrameForRecording(image, streamType: manager.streamType)
                    manager.publishPreviewFrameToOBS(image)
                }
            }
        }
    }

    private func updateFrameTimerConnection() {
        if manager.streaming {
            if frameTimerConnection == nil {
                frameTimerConnection = frameTimer.connect()
            }
        } else {
            frameTimerConnection?.cancel()
            frameTimerConnection = nil
        }
    }

    private var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.08, blue: 0.12),
                    Color(red: 0.02, green: 0.03, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle radial glows — no blur squares, clipped to avoid overlap artifacts
            RadialGradient(colors: [Color(red: 0.12, green: 0.79, blue: 0.93).opacity(0.10), .clear],
                           center: .topTrailing, startRadius: 80, endRadius: 420)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            RadialGradient(colors: [.white.opacity(0.04), .clear],
                           center: .bottomLeading, startRadius: 60, endRadius: 360)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .drawingGroup(opaque: false)
    }

    private var previewPanel: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Live Preview")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)

                    streamSelector
                        .frame(maxWidth: 360, alignment: .leading)
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Button {
                        captureStillImageFromPreview()
                    } label: {
                        Label("Capture Image", systemImage: "camera")
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedPreviewImage == nil)
                    .help("Save the currently selected preview stream as a still image.")

                    Button {
                        toggleVideoRecordingFromPreview()
                    } label: {
                        Label(manager.isRecordingVideo ? "Stop Recording" : "Record Video",
                              systemImage: manager.isRecordingVideo ? "stop.circle.fill" : "record.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled((!manager.isRecordingVideo && selectedPreviewImage == nil) || !manager.streaming)
                    .help("Start or stop recording the current preview stream to a QuickTime movie.")
                }
            }
            .padding(14)
            .background(panelCardBackground)

            ZStack(alignment: .topLeading) {
                previewImage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    statusBadge(manager.connected ? "Connected" : "Disconnected",
                               color: manager.connected ? .green : .red)
                    if manager.streaming {
                        statusBadge("Streaming \(manager.streamType.title)", color: Color(red: 0.12, green: 0.79, blue: 0.93))
                    }
                    if manager.isRecordingVideo {
                        statusBadge("REC \(String(format: "%.1fs", manager.recordingVideoSeconds))", color: .red)
                    }
                    if manager.trackingEnabled {
                        statusBadge(manager.trackingStatus, color: .green)
                    }
                }
                .padding(12)
            }

            HStack(spacing: 12) {
                infoTile(title: "Mic", value: manager.unifiedMicrophoneStatus)
                infoTile(title: "Scanner", value: manager.scannerBusy ? "Capturing" : "Ready")
                infoTile(title: "DAL", value: manager.systemCameraDalInstalled ? "Installed" : "Missing")
                infoTile(title: "HAL", value: manager.systemAudioHalInstalled ? "Installed" : "Missing")
            }
        }
    }

    // MARK: - Left Panel (stable, no implicit animations)
    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSummarySection
            sidebarSectionPicker

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch selectedSidebarSection {
                    case .control:
                        devicesSection
                    case .capture:
                        mediaCaptureSection
                        scannerSection
                    case .tracking:
                        trackingSection
                    case .hardware:
                        cameraMotorSection
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            // Footer hint for settings — static, not inside scroll
            VStack(alignment: .leading, spacing: 4) {
                Divider().overlay(Color.white.opacity(0.08))
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("System settings in macKinect Settings (⌘,)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                    Spacer()
                    Button("Open…") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
                        .buttonStyle(.link)
                        .font(.caption2)
                }
            }
            .padding(.top, 8)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header Summary (fixed to prevent jitter)
    private var headerSummarySection: some View {
        cardSection {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("macKinect")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                                .transaction { $0.animation = nil }
                                .multilineTextAlignment(.leading)
                            // Subheading moved to bottom footer for static layout
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)

                        VStack(alignment: .trailing, spacing: 8) {
                            statusBadge(manager.connected ? "Ready" : "Idle",
                                        color: manager.connected ? Color(red: 0.12, green: 0.79, blue: 0.93) : .gray)
                                .fixedSize(horizontal: true, vertical: false)
                            Text("v\(appVersion)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.55))
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .animation(nil, value: manager.connected)

                    HStack(spacing: 8) {
                        quickActionButton("Refresh Devices", systemImage: "arrow.clockwise") {
                            manager.refreshDevices()
                        }
                        quickActionButton("Open Captures", systemImage: "folder") {
                            revealPath(manager.lastCapturePath.isEmpty ? captureRootPath : manager.lastCapturePath)
                        }
                    }

                    HStack(spacing: 8) {
                        Text("Quick Connect")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.62))
                            .frame(width: 88, alignment: .leading)
                            .fixedSize(horizontal: true, vertical: false)
                            .transaction { $0.animation = nil }

                        // Static placeholder to avoid dropdown text moving at 30Hz
                        Picker("Quick Device", selection: $manager.selectedDeviceID) {
                            if manager.devices.isEmpty {
                                Text("No Kinect detected").tag("")
                            }
                            ForEach(manager.devices) { device in
                                Text(device.generationLabel).tag(device.id)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .clipped()
                        .transaction { $0.animation = nil }
                        .help("Choose a Kinect and connect without leaving the summary card.")

                        // Shows "Connect" → "Connected" when the selected device is active
                        Group {
                            if manager.connected && manager.selectedDeviceID == manager.connectedDeviceID {
                                Button("Connected") {
                                    manager.disconnect()
                                }
                                .buttonStyle(.bordered)
                                .fixedSize(horizontal: true, vertical: false)
                                .help("Disconnect the current Kinect session.")
                            } else {
                                Button("Connect") {
                                    manager.connectSelectedDevice()
                                }
                                .buttonStyle(.borderedProminent)
                                .fixedSize(horizontal: true, vertical: false)
                                .disabled(manager.selectedDeviceID.isEmpty || manager.publishToSystem)
                                .help("Open the selected Kinect immediately. Disabled while Publish to macOS Apps is enabled.")
                            }
                        }
                        .animation(nil, value: manager.connected)
                    }
                    .animation(nil, value: manager.selectedDeviceID)
                    .animation(nil, value: manager.devices.count)
                }

                // Use flexible grid with transaction disabled globally to prevent jitter
                // 392pt - 28pt padding = 364pt available; 2 columns with 8pt spacing => ~178pt each
                LazyVGrid(columns: [GridItem(.flexible(minimum: 80), spacing: 8), GridItem(.flexible(minimum: 80), spacing: 8)], spacing: 8) {
                    infoTile(title: "Device", value: selectedDeviceSummary)
                    infoTile(title: "Stream", value: manager.streaming ? manager.streamType.title : "Stopped")
                    infoTile(title: "Mic", value: microphoneSummary)
                    infoTile(title: "System", value: systemSummary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transaction { $0.animation = nil }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sidebarSectionPicker: some View {
        Picker("Workspace", selection: $selectedSidebarSection) {
            ForEach(SidebarSection.allCases) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var devicesSection: some View {
        cardSection(title: "Control Center") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Picker("Device", selection: $manager.selectedDeviceID) {
                        if manager.devices.isEmpty {
                            Text("No Kinect detected").tag("")
                        }
                        ForEach(manager.devices) { device in
                            Text("\(device.generationLabel) • \(device.serial)").tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .help("Choose which Kinect the app should open for preview, capture, and hardware control.")

                    VStack(spacing: 8) {
                        Button("Refresh") { manager.refreshDevices() }
                            .buttonStyle(.bordered)
                            .help("Re-scan USB and backend device lists.")

                        Group {
                            if manager.connected && manager.selectedDeviceID == manager.connectedDeviceID {
                                Button("Disconnect") { manager.disconnect() }
                                    .buttonStyle(.bordered)
                                    .help("Close the current Kinect session so system integrations can claim the device.")
                            } else {
                                Button("Connect") { manager.connectSelectedDevice() }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(manager.selectedDeviceID.isEmpty || manager.publishToSystem)
                                    .help("Open the selected Kinect immediately. Disabled while Publish to macOS Apps is enabled because the published route must own the device.")
                            }
                        }
                        .animation(nil, value: manager.connected)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Preview Stream")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                    streamSelector
                        .help("Choose which live stream is shown in the preview and used for still/video capture.")
                }

                Button(manager.streaming ? "Stop Stream" : "Start Stream") {
                    manager.streaming ? manager.stopStreaming() : manager.startStreaming()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(!manager.connected || (!manager.streaming && manager.publishToSystem))
                .help("Start or stop the live device stream for preview, recording, and scanner capture. Starting is disabled while Publish to macOS Apps is enabled.")

                Text(manager.status)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(nil, value: manager.status)

                HStack(spacing: 8) {
                    statusBadge(manager.connected ? "Connected" : "Disconnected",
                               color: manager.connected ? .green : .red)
                    if manager.streaming {
                        statusBadge("Streaming \(manager.streamType.title)",
                                   color: Color(red: 0.12, green: 0.79, blue: 0.93))
                    }
                }

                HStack(spacing: 8) {
                    statusBadge(manager.supportsDepth ? "Depth Ready" : "No Depth",
                               color: manager.supportsDepth ? .green : .gray)
                    statusBadge(manager.supportsMotor ? "Motor" : "Fixed",
                               color: manager.supportsMotor ? Color(red: 0.12, green: 0.79, blue: 0.93) : .gray)
                    statusBadge(manager.supportsAudioInput ? "Audio In" : "No Audio",
                               color: manager.supportsAudioInput ? .green : .gray)
                }
            }
        }
    }

    private var mediaCaptureSection: some View {
        cardSection(title: "Capture Settings") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Use the preview toolbar on the right to capture stills and record video. This panel only controls output settings and recent files.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Picture")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    Picker("Picture Format", selection: $manager.stillImageFormat) {
                        ForEach(StillImageFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Choose the file format used when saving still images from the preview.")

                    if manager.stillImageFormat.supportsQuality {
                        HStack {
                            Text("Quality")
                                .foregroundStyle(.white.opacity(0.75))
                            Slider(value: $manager.stillImageQuality, in: 0.1...1.0)
                                .help("Adjust JPEG quality for still-image capture.")
                            Text("\(Int(manager.stillImageQuality * 100))")
                                .monospacedDigit()
                                .frame(width: 36, alignment: .trailing)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }

                Divider().overlay(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Video")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Format: QuickTime (.mov), H.264")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))

                    Picker("Video Quality", selection: $manager.videoQualityPreset) {
                        ForEach(VideoQualityPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Choose the preview video bitrate preset used by the built-in recorder.")

                    if !manager.lastVideoPath.isEmpty {
                        Text("Last video: \((manager.lastVideoPath as NSString).lastPathComponent)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        Button("Reveal Last Capture") {
                            revealPath(manager.lastCapturePath)
                        }
                        .buttonStyle(.link)
                     .help("Reveal the most recent capture directory in Finder.")


                        Button("Reveal Last Video") {
                            revealPath(manager.lastVideoPath)
                        }
                        .buttonStyle(.link)
                     .help("Reveal the most recent recorded video in Finder.")

                    }
                }
            }
        }
    }

    private var cameraMotorSection: some View {
        cardSection(title: "Camera + Motor") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Toggle("Mirror", isOn: Binding(get: { manager.mirror }, set: manager.setMirror))
                }
                .help("Mirror the live preview and captured output horizontally when supported by the backend.")

                HStack {
                    Toggle("Auto Exposure", isOn: Binding(get: { manager.autoExposure }, set: manager.setAutoExposure))
                }
                .help("Let the Kinect backend manage exposure automatically when the selected stream supports it.")

                HStack {
                    Toggle("Auto White Balance", isOn: Binding(get: { manager.autoWhiteBalance }, set: manager.setAutoWhiteBalance))
                }
                .help("Let the Kinect backend manage white balance automatically for RGB capture.")

                HStack {
                    Toggle("Near Mode", isOn: Binding(get: { manager.nearMode }, set: manager.setNearMode))
                }
                .help("Enable near mode for supported Kinect v1 depth devices.")

                settingSlider(label: "Tilt", valueText: "\(manager.tiltAngle)°") {
                    Slider(value: Binding(get: { Double(manager.tiltAngle) }, set: { manager.setTilt(Int($0)) }), in: -30...30, step: 1)
                }
                .help("Adjust the Kinect tilt motor angle when the connected device supports it.")

                HStack {
                    Text("LED")
                    Spacer()
                    Picker("LED Mode", selection: Binding(get: { manager.ledMode }, set: { manager.setLed($0) })) {
                        ForEach(0...6, id: \.self) { mode in
                            Text(KinectManager.ledModeDisplayName(for: mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .help("Change the Kinect status LED pattern when supported by the device.")
                }
                .foregroundStyle(.white.opacity(0.9))

                HStack {
                    settingSlider(label: "Manual Exposure", valueText: "\(manager.manualExposureUs) us") {
                        Slider(value: Binding(get: { Double(manager.manualExposureUs) }, set: { manager.setManualExposure(Int($0)) }), in: 1_000...200_000, step: 1_000)
                    }
                }
                .help("Set the manual RGB exposure value in microseconds when auto exposure is disabled.")

                HStack {
                    settingSlider(label: "IR Brightness", valueText: "\(manager.irBrightness)") {
                        Slider(value: Binding(get: { Double(manager.irBrightness) }, set: { manager.setIrBrightness(Int($0)) }), in: 1...50, step: 1)
                    }
                }
                .help("Adjust infrared brightness for supported Kinect backends.")
                
                if !manager.canApplyImageControls {
                    Text(manager.imageControlSupportDetail)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 4)
                }

                Divider().overlay(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Microphone")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    Text("Direct Kinect microphone capture used inside macKinect. This is device-level control, so it sits with the rest of the hardware settings.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))

                    Text("Direct mic and Publish to macOS Apps are mutually exclusive on the current backend. If you publish the Kinect to other apps, macKinect releases the live device session first.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))

                    HStack(spacing: 8) {
                        statusBadge(
                            "Direct Mic \(manager.unifiedMicrophoneStatus)",
                            color: manager.audioStreamActive ? .green : (manager.supportsAudioInput ? .orange : .gray),
                            help: manager.directMicrophoneSupportDetail
                        )
                    }

                    Toggle("Use Kinect microphone inside macKinect", isOn: Binding(
                        get: { manager.audioEnabled },
                        set: { manager.setAudioEnabled($0) }
                    ))
                     .help("Starts the direct Kinect microphone backend inside macKinect. This does not publish a microphone to other apps.")


                    Text(manager.directMicrophoneSupportDetail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))

                    HStack {
                        Text("Input level")
                            .foregroundStyle(.white.opacity(0.8))
                            .help("Live level meter for the direct macKinect microphone path only.")
                        ProgressView(value: min(max(Double(manager.audioLevel), 0), 1))
                            .frame(maxWidth: .infinity)
                            .help("Shows the current direct-input amplitude from the Kinect microphone path.")
                        Text(String(format: "%.2f", manager.audioLevel))
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                            .foregroundStyle(.white.opacity(0.8))
                            .help("Current direct-input level as a normalized scalar.")
                    }
                }
            }
        }
    }

    private var scannerSection: some View {
        cardSection(title: "3D Scanner") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Capture RGB / IR / depth images and generate a point cloud (PLY).")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))

                Button {
                    manager.captureScanBundle()
                } label: {
                    Label(manager.scannerBusy ? "Capturing..." : "Capture Scan Bundle", systemImage: "cube.transparent")
                }
                .buttonStyle(.borderedProminent)
                 .help("Capture the current RGB, infrared, and depth frames plus a simple point-cloud export bundle.")


                if manager.lastCapturePointCount > 0 {
                    Text("Last point cloud: \(manager.lastCapturePointCount) points")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }

                if !manager.lastCapturePath.isEmpty {
                    Text(manager.lastCapturePath)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(3)
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: manager.lastCapturePath)
                    }
                    .buttonStyle(.link)
                    .help("Reveal the latest scan bundle directory in Finder.")
                }
            }
        }
    }

    private var trackingSection: some View {
        cardSection(title: "Tracking — Vision + Kinect Depth") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable Tracking", isOn: Binding(
                    get: { manager.trackingEnabled },
                    set: { manager.setTrackingEnabled($0) }
                ))
                .help("Run native Vision tracking on the live Kinect RGB stream.")

                Toggle("Face Tracking", isOn: $manager.trackingFacesEnabled)
                    .disabled(!manager.trackingEnabled)
                    .help("Detect face rectangles in the live RGB stream.")

                Toggle("Body Pose Tracking", isOn: $manager.trackingBodyEnabled)
                    .disabled(!manager.trackingEnabled)
                    .help("Detect 2D human body joints in the live RGB stream. Kinect depth is fused when available for 3D.")

                Toggle("Hand Pose Tracking", isOn: Binding(
                    get: { manager.trackingHandsEnabled },
                    set: { manager.trackingHandsEnabled = $0 }
                ))
                .disabled(!manager.trackingEnabled)
                .help("Detect 2D hand joints (Vision VNDetectHumanHandPoseRequest). Requires Vision; no Kinect skeleton needed.")

                Toggle("Show Overlay", isOn: $manager.trackingOverlayVisible)
                    .disabled(!manager.trackingEnabled)
                    .help("Draw face boxes and body joints over the RGB preview.")
                Text("Kinect v1/v2 have no built-in macOS skeleton; this app uses Apple Vision (face, body, hand) on the RGB stream and fuses Kinect depth for 3D. More AI models (animal, object) can be added via Vision — file an issue if you need one.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    .transaction { $0.animation = nil }

                Divider().overlay(Color.white.opacity(0.08))

                HStack(spacing: 8) {
                    statusBadge("\(manager.trackingResult.faces.count) Face",
                               color: manager.trackingResult.faces.isEmpty ? .gray : .green)
                    statusBadge("\(manager.trackingResult.bodies.count) Body",
                               color: manager.trackingResult.bodies.isEmpty ? .gray : Color(red: 0.12, green: 0.79, blue: 0.93))
                }

                Text(manager.trackingStatus)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.9))

                Text("Overlay coordinates are aligned to the RGB stream. Switch Preview Stream to RGB when tuning tracking.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var systemIntegrationSection: some View {
        cardSection(title: "System Camera / Mic Integration") {
            VStack(alignment: .leading, spacing: 10) {
                Text("One place for microphone routing and publish status. Direct capture feeds this app; system publishing exposes the Kinect to other macOS apps.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Camera Route")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    Text("Native macOS camera publish is still experimental here. OBS Virtual Camera is the reliable camera path unless the camera extension is actually active.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))

                    // Badges wrap to avoid overflow at 392pt width
                    FlowBadgeRow {
                        statusBadge(
                            "CamExt \(manager.systemCameraExtensionAvailable ? (manager.systemCameraExtensionActive ? "Active" : (manager.systemCameraExtensionInstalled ? "Installed" : "Bundled")) : "Missing")",
                            color: manager.systemCameraExtensionActive ? .green : (manager.systemCameraExtensionAvailable ? .orange : .gray),
                            help: "The modern macOS camera system extension path. Active means the extension is approved and currently allowed to publish a camera."
                        )
                        statusBadge(
                            "DAL \(manager.systemCameraDalInstalled ? "Installed" : "Missing")",
                            color: manager.systemCameraDalInstalled ? .green : .gray,
                            help: "Legacy CoreMediaIO DAL camera plugin. This is the older fallback camera path and may be ignored by recent macOS releases."
                        )
                        statusBadge(
                            "Camera \(manager.systemCameraPublished ? "Published" : "Not Published")",
                            color: manager.systemCameraPublished ? .green : .orange,
                            help: "Whether macOS currently sees a published Kinect camera device that apps can open."
                        )
                    }

                    if !manager.systemCameraExtensionActive && !manager.systemCameraPublished {
                        Text("Native camera publish is not active on this machine right now. Treat OBS Virtual Camera as the supported camera route until the camera extension is properly signed and activated.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Microphone Route")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    Text("This area is now only about macOS-wide publishing. Direct microphone control lives in Hardware with the rest of the device controls.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))

                    FlowBadgeRow {
                        statusBadge(
                            "HAL \(manager.systemAudioHalInstalled ? "Installed" : "Missing")",
                            color: manager.systemAudioHalInstalled ? .green : .gray,
                            help: "CoreAudio HAL plugin that publishes the Kinect microphone to the rest of macOS."
                        )
                        statusBadge(
                            "System Mic \(manager.systemMicPublished ? "Published" : "Not Published")",
                            color: manager.systemMicPublished ? .green : .orange,
                            help: "Whether macOS currently sees the published Kinect microphone device for system-wide use."
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Publish to macOS Apps")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    Text("Use this only if you want other apps to see a Kinect microphone or camera. On this machine, microphone publish may work, but the native camera path should be considered experimental until the camera extension is active.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))

                    Toggle("Publish Kinect to macOS app device list", isOn: Binding(
                        get: { manager.publishToSystem },
                        set: { value in
                            deferOnMain {
                                manager.setSystemPublish(value)
                            }
                        }
                    ))
                    .help("Publishes the Kinect through the bundled system integration so other macOS apps can try to use it. This is separate from macKinect's own direct microphone path.")

                    Picker("System Microphone Mode", selection: Binding(
                        get: { manager.systemMicMode },
                        set: { value in
                            deferOnMain {
                                manager.setSystemMicMode(value)
                            }
                        }
                    )) {
                        ForEach(SystemMicMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Choose what the published Kinect microphone looks like to other macOS apps.")

                    Text(manager.systemMicMode.detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .help("Explains what the selected system microphone mode exposes to other macOS apps.")

                    if manager.systemCameraExtensionAvailable || manager.systemCameraDalInstalled || manager.systemCameraPublished {
                        Picker("System Camera Stream", selection: Binding(
                            get: { manager.systemCameraStreamType },
                            set: { value in
                                deferOnMain {
                                    manager.setSystemCameraStreamType(value)
                                }
                            }
                        )) {
                            ForEach(KinectStreamType.allCases) { stream in
                                Text(stream.title).tag(stream)
                            }
                        }
                        .pickerStyle(.segmented)
                        .help("Choose which Kinect stream the native system-camera path should expose when that path is available.")

                        if !manager.systemCameraExtensionActive && !manager.systemCameraPublished {
                            Text("This camera picker is retained for future native camera support, but on this machine it is not the recommended route yet.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    } else {
                        Text("Native system camera publish is currently unavailable here. Use OBS Virtual Camera for camera apps.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("OBS Fallback")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    Text("OBS is the most reliable camera route on this setup. The Bridge badge turns on only while macKinect is actively sending frames to OBS over Syphon.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))

                    FlowBadgeRow {
                        statusBadge(
                            "OBS \(manager.obsInstalled ? "Installed" : "Missing")",
                            color: manager.obsInstalled ? .green : .gray,
                            help: "Whether OBS.app is installed in /Applications."
                        )
                        statusBadge(
                            "OBS Plugin \(manager.obsKinectPluginInstalled ? "Detected" : (manager.obsSyphonPublishingEnabled || manager.obsInstalled ? "Optional" : "Missing"))",
                            color: (manager.obsKinectPluginInstalled || manager.obsSyphonPublishingEnabled) ? .green : .gray,
                            help: "Whether an OBS plugin capable of receiving Kinect content was detected. This is optional when the Syphon bridge is used — Syphon is the preferred path."
                        )
                        statusBadge(
                            "Bridge \(manager.obsSyphonPublishingEnabled ? "On" : "Off")",
                            color: manager.obsSyphonPublishingEnabled ? .green : .orange,
                            help: "Whether macKinect is currently publishing preview frames to OBS over Syphon."
                        )
                        statusBadge(
                            "Virtual Cam \(manager.obsVirtualCameraPublished ? "Published" : "Off")",
                            color: manager.obsVirtualCameraPublished ? .green : .orange,
                            help: "Whether OBS Virtual Camera is currently published as a webcam in macOS."
                        )
                    }
                }

                if manager.systemCameraPublished || manager.systemMicPublished {
                    VStack(alignment: .leading, spacing: 2) {
                        if manager.systemCameraPublished {
                            Text("Camera device: \(manager.systemPublishedCameraName)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        if manager.systemMicPublished {
                            Text("Microphone device: \(manager.systemPublishedMicName)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button(manager.systemIntegrationInstallInProgress ? "Installing..." : "Install Integration") {
                        deferOnMain {
                            manager.installSystemIntegration()
                        }
                    }
                     .buttonStyle(.borderedProminent)
                     .help("Install or reinstall the bundled system microphone driver and camera integration components.")


                    Button(manager.systemPreferenceApplyInProgress ? "Applying..." : "Apply System Settings") {
                        deferOnMain {
                            manager.applySystemIntegrationPreferences()
                        }
                    }
                     .buttonStyle(.bordered)
                     .help("Write the selected system camera/microphone settings into the shared macOS preferences domain so the HAL and camera extension can see them.")


                    Button("Re-check") {
                        deferOnMain {
                            manager.refreshSystemIntegrationStatus()
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh the published-device checks without reinstalling anything.")

                    Button("Release Hardware") {
                        deferOnMain {
                            manager.releaseHardwareForSystemIntegration()
                        }
                    }
                     .buttonStyle(.bordered)
                     .help("Close the current Kinect session so system integrations or OBS can claim the device.")

                }

                HStack(spacing: 8) {
                    Button("Launch OBS Virtual Camera") {
                        deferOnMain {
                            manager.launchOBSVirtualCamera()
                        }
                    }
                     .buttonStyle(.bordered)
                     .help("Launch OBS and request its Virtual Camera output. This is the practical fallback camera path on current macOS.")


                    Button("Open OBS Plugins") {
                        revealPath(manager.obsPluginsFolderPath)
                    }
                     .buttonStyle(.bordered)
                     .help("Open the user OBS plugins folder where an obs-kinect-style source plugin can be installed.")

                }

                Text(manager.systemPublishNote)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .help("High-level summary of the current system camera and microphone publish state.")
                Text(manager.obsIntegrationNote)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .help("Current OBS fallback state and what the app expects next.")
                if !manager.systemIntegrationInstallResult.isEmpty {
                    Text(manager.systemIntegrationInstallResult)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .help("Result of the last integration install or activation attempt.")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Diagnostics")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        Spacer()
                        Button("Reveal Log") {
                            revealPath(manager.diagnosticsLogPath)
                        }
                        .buttonStyle(.bordered)
                        .help("Open the persistent macKinect diagnostics log in Finder.")
                    }

                    Text(manager.diagnosticsLogPath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.5))
                        .textSelection(.enabled)
                        .help("Persistent log file containing audio, device, and integration traces for debugging.")

                    if manager.recentDiagnostics.isEmpty {
                        Text("No diagnostics captured yet.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(manager.recentDiagnostics.suffix(6).enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.white.opacity(0.72))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    private var selectedDeviceSummary: String {
        guard let device = manager.devices.first(where: { $0.id == manager.selectedDeviceID }) else {
            return manager.connected ? "Connected" : "Not selected"
        }
        if device.serial.isEmpty {
            return device.name
        }
        return "\(device.name) • \(device.serial)"
    }

    private var microphoneSummary: String {
        if manager.audioStreamActive {
            return "Active"
        }
        if manager.audioEnabled {
            return "Armed"
        }
        return manager.supportsAudioInput ? "Off" : "Unavailable"
    }

    private var systemSummary: String {
        if manager.systemCameraPublished || manager.systemMicPublished {
            return "Published"
        }
        if manager.systemCameraDalInstalled || manager.systemAudioHalInstalled || manager.systemCameraExtensionInstalled {
            return "Installed"
        }
        return "Inactive"
    }

    // Separate backgrounds to avoid nested square overlap
    private var panelCardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
    private var infoTileBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }

    private var streamSelector: some View {
        Picker("Stream", selection: Binding(
            get: { manager.streamType },
            set: { manager.streamType = $0 }
        )) {
            ForEach(KinectStreamType.allCases) { stream in
                Text(stream.title).tag(stream)
            }
        }
        .pickerStyle(.segmented)
    }

    private var selectedPreviewImage: CGImage? {
        switch manager.streamType {
        case .rgb:
            return rgbImage
        case .ir:
            return irImage
        case .depth:
            return depthImage
        }
    }

    private func captureStillImageFromPreview() {
        guard let image = selectedPreviewImage else { return }
        manager.captureStillImage(image, streamType: manager.streamType)
    }

    private func toggleVideoRecordingFromPreview() {
        if manager.isRecordingVideo {
            manager.stopVideoRecording()
            return
        }
        guard let image = selectedPreviewImage else { return }
        manager.startVideoRecording(image, streamType: manager.streamType)
    }

    @ViewBuilder
    private var previewImage: some View {
        switch manager.streamType {
        case .rgb:
            if let rgbImage {
                ZStack {
                    Image(decorative: rgbImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    if manager.trackingEnabled, manager.trackingOverlayVisible {
                        TrackingOverlayView(
                            result: manager.trackingResult,
                            imageSize: CGSize(width: rgbImage.width, height: rgbImage.height)
                        )
                    }
                }
            } else {
                PlaceholderView(title: "RGB Stream")
            }
        case .ir:
            if let irImage {
                Image(decorative: irImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                PlaceholderView(title: "Infrared Stream")
            }
        case .depth:
            if let depthImage {
                Image(decorative: depthImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                PlaceholderView(title: "Depth Stream")
            }
        }
    }

    @ViewBuilder
    private func cardSection<Content: View>(title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(panelCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func settingSlider<SliderView: View>(label: String, valueText: String, @ViewBuilder slider: () -> SliderView) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(label)
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.caption)
                    .monospacedDigit()
            }
            slider()
        }
    }

    private func statusBadge(_ text: String, color: Color, help: String? = nil) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.24), in: Capsule())
            .overlay(
                Capsule().stroke(color.opacity(0.45), lineWidth: 1)
            )
            .help(help ?? text)
            .animation(nil, value: text)
    }

    private func quickActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func infoTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .multilineTextAlignment(.leading)
                .transaction { $0.animation = nil }
            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
                .allowsTightening(true)
                .minimumScaleFactor(0.85)
                .transaction { $0.animation = nil }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(10)
        .background(infoTileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .transaction { $0.animation = nil }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private var captureRootPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("KinectCaptures", isDirectory: true)
            .path
    }

    private func revealPath(_ path: String) {
        guard !path.isEmpty else { return }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return }

        if isDirectory.boolValue {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }

    private func deferOnMain(_ action: @escaping () -> Void) {
        DispatchQueue.main.async(execute: action)
    }
}

private struct PlaceholderView: View {
    let title: String

    var body: some View {
        Rectangle()
            .fill(Color.black)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(title)
                        .foregroundColor(.white.opacity(0.75))
                        .font(.title3)
                }
            )
    }
}

// Horizontal wrapping for badges — prevents system tab text misalignment at 392pt
private struct FlowBadgeRow<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        // Scroll horizontally if overflow, otherwise left-aligned
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transaction { $0.animation = nil }
    }
}

private extension Data {
    // Preview rendering keeps the bridge payloads in their native formats and
    // converts them only when the active SwiftUI view needs a CGImage.
    func rgbCGImage(width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        guard count >= width * height * 3 else { return nil }

        guard let provider = CGDataProvider(data: self as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 24,
            bytesPerRow: width * 3,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    func grayCGImage(width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        guard count >= width * height else { return nil }

        guard let provider = CGDataProvider(data: self as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    func depthCGImage(width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        guard count >= width * height * 2 else { return nil }

        let sampleCount = width * height
        var gray = [UInt8](repeating: 0, count: sampleCount)
        withUnsafeBytes { rawBuffer in
            let depth = rawBuffer.bindMemory(to: UInt16.self)
            for i in 0..<sampleCount {
                let d = depth[i]
                if d == 0 {
                    gray[i] = 0
                } else {
                    let t = Swift.max(0.0, Swift.min(1.0, (Double(d) - 400.0) / 5600.0))
                    gray[i] = UInt8((1.0 - t) * 255.0)
                }
            }
        }

        let grayData = Data(gray)
        return grayData.grayCGImage(width: width, height: height)
    }
}
