import SwiftUI
import AppKit

struct KinectAppUI: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .navigationTitle("macKinect")
        }
        .windowStyle(.titleBar)

        Settings {
            AppSettingsView()
                .frame(minWidth: 720, minHeight: 560)
        }
    }
}

private struct AppSettingsView: View {
    var body: some View {
        TabView {
            SettingsTrackingPane()
                .tabItem { Label("Tracking", systemImage: "eye") }
            SettingsHardwarePane()
                .tabItem { Label("Hardware", systemImage: "slider.horizontal.3") }
            SettingsSystemPane()
                .tabItem { Label("System", systemImage: "gearshape.2") }
        }
        .padding(12)
    }
}

private struct SettingsTrackingPane: View {
    @StateObject private var manager = KinectManager()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tracking").font(.headline)
                Text("Vision-based face, body, and hand tracking. Kinect depth is fused for 3D when available. More AI models can be added — file an issue.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                // Reuse the same tracking toggles as main window but in settings
                TrackingSettingsContent(manager: manager)
            }.padding(8)
        }
        .onAppear { manager.performInitialLoadIfNeeded() }
    }
}

private struct SettingsHardwarePane: View {
    @StateObject private var manager = KinectManager()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Hardware").font(.headline)
                Text("Mirror, exposure, white balance, near mode, IR brightness, and tilt. Applied to the live backend when a device is connected.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HardwareSettingsContent(manager: manager)
            }.padding(8)
        }
        .onAppear { manager.performInitialLoadIfNeeded() }
    }
}

private struct SettingsSystemPane: View {
    @StateObject private var manager = KinectManager()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("System Camera / Mic").font(.headline)
                Text("Publish Kinect as system devices. This mirrors the System controls — use either place. For ad-hoc builds, OBS Virtual Camera is the reliable webcam.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                SystemSettingsContent(manager: manager)
            }.padding(8)
        }
        .onAppear { manager.performInitialLoadIfNeeded() }
    }
}

private struct TrackingSettingsContent: View {
    @ObservedObject var manager: KinectManager
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable Tracking", isOn: Binding(get: { manager.trackingEnabled }, set: manager.setTrackingEnabled)).help("Vision on RGB stream.")
            Toggle("Face", isOn: $manager.trackingFacesEnabled).disabled(!manager.trackingEnabled)
            Toggle("Body Pose", isOn: $manager.trackingBodyEnabled).disabled(!manager.trackingEnabled)
            Toggle("Hand Pose", isOn: $manager.trackingHandsEnabled).disabled(!manager.trackingEnabled)
            Toggle("Show Overlay", isOn: $manager.trackingOverlayVisible).disabled(!manager.trackingEnabled)
            Divider().overlay(Color.white.opacity(0.08))
            HStack(spacing: 8) {
                Text("\(manager.trackingResult.faces.count) face").font(.caption2).foregroundStyle(.secondary)
                Text("\(manager.trackingResult.bodies.count) body").font(.caption2).foregroundStyle(.secondary)
                Text(manager.trackingStatus).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SystemSettingsContent: View {
    @ObservedObject var manager: KinectManager
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("System Microphone Mode", selection: $manager.systemMicMode) {
                ForEach(SystemMicMode.allCases) { mode in Text(mode.title).tag(mode) }
            }.pickerStyle(.segmented)
            Toggle("Publish Kinect to macOS app device list", isOn: $manager.publishToSystem)
            HStack {
                Button(manager.systemIntegrationInstallInProgress ? "Installing..." : "Install Integration") { manager.installSystemIntegration() }
                    .buttonStyle(.borderedProminent).disabled(manager.systemIntegrationInstallInProgress)
                Button("Re-check") { manager.refreshSystemIntegrationStatus() }.buttonStyle(.bordered)
                Button("Release Hardware") { manager.releaseHardwareForSystemIntegration() }.buttonStyle(.bordered).disabled(!manager.connected && !manager.streaming)
            }
            HStack {
                Button("Launch OBS Virtual Camera") { manager.launchOBSVirtualCamera() }.buttonStyle(.borderedProminent).disabled(!manager.obsInstalled)
                Text(manager.obsIntegrationNote).font(.caption2).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Text(manager.systemPublishNote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !manager.systemIntegrationInstallResult.isEmpty {
                Text(manager.systemIntegrationInstallResult).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct HardwareSettingsContent: View {
    @ObservedObject var manager: KinectManager
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Mirror", isOn: Binding(get: { manager.mirror }, set: manager.setMirror)).disabled(!manager.canApplyImageControls)
            Toggle("Auto Exposure", isOn: Binding(get: { manager.autoExposure }, set: manager.setAutoExposure)).disabled(!manager.canApplyImageControls)
            Toggle("Auto White Balance", isOn: Binding(get: { manager.autoWhiteBalance }, set: manager.setAutoWhiteBalance)).disabled(!manager.canApplyImageControls)
            Toggle("Near Mode", isOn: Binding(get: { manager.nearMode }, set: manager.setNearMode)).disabled(!manager.supportsDepth || !manager.canApplyImageControls)
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text("Tilt \(manager.tiltAngle)°").font(.caption); Spacer(); Text("\(manager.tiltAngle)°").font(.caption2).monospacedDigit() }
                Slider(value: Binding(get: { Double(manager.tiltAngle) }, set: { manager.setTilt(Int($0)) }), in: -30...30, step: 1).disabled(!manager.supportsMotor)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text("IR Brightness \(manager.irBrightness)").font(.caption); Spacer() }
                Slider(value: Binding(get: { Double(manager.irBrightness) }, set: { manager.setIrBrightness(Int($0)) }), in: 1...50, step: 1).disabled(!manager.canApplyImageControls)
            }
            Divider().overlay(Color.white.opacity(0.08))
            Text("Direct mic: \(manager.directMicrophoneSupportDetail)").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Use Kinect microphone inside macKinect", isOn: Binding(get: { manager.audioEnabled }, set: manager.setAudioEnabled)).disabled(!manager.supportsAudioInput)
            HStack { Text("Input level").font(.caption); ProgressView(value: Double(manager.audioLevel)).frame(maxWidth: .infinity); Text(String(format: "%.2f", manager.audioLevel)).font(.caption2).monospacedDigit().frame(width: 44) }
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}
