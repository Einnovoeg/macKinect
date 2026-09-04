import SwiftUI
import AppKit

struct KinectAppUI: App {
    @StateObject private var settingsManager = KinectManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .navigationTitle("macKinect")
                .environmentObject(settingsManager)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("macKinect Settings…") {
                    if #available(macOS 14.0, *) {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } else {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }

        Settings {
            AppSettingsView()
                .environmentObject(settingsManager)
                .frame(minWidth: 640, minHeight: 520)
        }
    }
}

// MARK: - App Settings (moved from left panel System tab)
private struct AppSettingsView: View {
    @EnvironmentObject var manager: KinectManager

    var body: some View {
        TabView {
            SystemSettingsPane(manager: manager)
                .tabItem { Label("System", systemImage: "gearshape.2") }
            HardwareSettingsPane(manager: manager)
                .tabItem { Label("Hardware", systemImage: "slider.horizontal.3") }
            AboutPane()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SystemSettingsPane: View {
    @ObservedObject var manager: KinectManager
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("System Camera / Mic Integration")
                    .font(.headline)
                Text("System integration publishes Kinect as macOS devices. For ad-hoc builds, the reliable path is OBS Virtual Camera.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SystemIntegrationSectionView(manager: manager)
            }
            .padding(8)
        }
    }
}

private struct HardwareSettingsPane: View {
    @ObservedObject var manager: KinectManager
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Hardware Controls")
                    .font(.headline)
                Text("Mirror, exposure, white balance, near mode, IR brightness, and tilt are applied to the live backend when a device is connected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Reuse the same controls as left panel hardware section but in settings
                HardwareControlsView(manager: manager)
            }
            .padding(8)
        }
    }
}

private struct AboutPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("macKinect").font(.title2.weight(.bold))
            Text("Kinect v1/v2 camera, depth, infrared, audio, and scanner control for macOS.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Support: buymeacoffee.com/einnovoeg").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }
}

// Lightweight wrappers to reuse existing cardSection content without duplicating
private struct SystemIntegrationSectionView: View {
    @ObservedObject var manager: KinectManager
    var body: some View {
        // This will be populated by extracting the systemIntegrationSection content
        // For now, show a placeholder that directs to the main window System tab
        VStack(alignment: .leading, spacing: 8) {
            Text("Use the main window's System tab for full camera/mic routing, or set options here:").font(.caption)
            Picker("System Microphone Mode", selection: $manager.systemMicMode) {
                ForEach(SystemMicMode.allCases) { mode in Text(mode.title).tag(mode) }
            }.pickerStyle(.segmented)
            Toggle("Publish Kinect to macOS app device list", isOn: $manager.publishToSystem)
            HStack {
                Button(manager.systemIntegrationInstallInProgress ? "Installing..." : "Install Integration") {
                    manager.installSystemIntegration()
                }.buttonStyle(.borderedProminent).disabled(manager.systemIntegrationInstallInProgress)
                Button("Re-check") { manager.refreshSystemIntegrationStatus() }.buttonStyle(.bordered)
            }
            Text(manager.systemPublishNote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(manager.obsIntegrationNote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct HardwareControlsView: View {
    @ObservedObject var manager: KinectManager
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Mirror", isOn: Binding(get: { manager.mirror }, set: manager.setMirror)).disabled(!manager.canApplyImageControls)
            Toggle("Auto Exposure", isOn: Binding(get: { manager.autoExposure }, set: manager.setAutoExposure)).disabled(!manager.canApplyImageControls)
            Toggle("Auto White Balance", isOn: Binding(get: { manager.autoWhiteBalance }, set: manager.setAutoWhiteBalance)).disabled(!manager.canApplyImageControls)
            Toggle("Near Mode", isOn: Binding(get: { manager.nearMode }, set: manager.setNearMode)).disabled(!manager.supportsDepth || !manager.canApplyImageControls)
            HStack {
                Text("Tilt \(manager.tiltAngle)°"); Spacer()
                Slider(value: Binding(get: { Double(manager.tiltAngle) }, set: { manager.setTilt(Int($0)) }), in: -30...30, step: 1).disabled(!manager.supportsMotor)
            }
            HStack {
                Text("IR Brightness \(manager.irBrightness)"); Spacer()
                Slider(value: Binding(get: { Double(manager.irBrightness) }, set: { manager.setIrBrightness(Int($0)) }), in: 1...50, step: 1).disabled(!manager.canApplyImageControls)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}
