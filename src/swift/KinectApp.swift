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
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settingsManager)
                .frame(minWidth: 640, minHeight: 520)
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject var manager: KinectManager
    var body: some View {
        TabView {
            // Full system integration moved here as well as left panel — not removed, duplicated for menu bar access
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("System Camera / Mic").font(.headline)
                    Text("Publish Kinect as system devices. Also available in the main window System tab.").font(.caption).foregroundStyle(.secondary)
                    SystemSettingsContent(manager: manager)
                }.padding(16)
            }
            .tabItem { Label("System", systemImage: "gearshape.2") }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Hardware").font(.headline)
                    HardwareSettingsContent(manager: manager)
                }.padding(16)
            }
            .tabItem { Label("Hardware", systemImage: "slider.horizontal.3") }
        }
        .padding(8)
    }
}

// Reuse the same systemIntegrationSection logic but as a separate view for Settings
private struct SystemSettingsContent: View {
    @ObservedObject var manager: KinectManager
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mirror the main window's systemIntegrationSection but simplified for Settings
            Text(manager.systemPublishNote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(manager.obsIntegrationNote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(manager.systemIntegrationInstallInProgress ? "Installing..." : "Install Integration") { manager.installSystemIntegration() }
                    .buttonStyle(.borderedProminent).disabled(manager.systemIntegrationInstallInProgress)
                Button("Re-check") { manager.refreshSystemIntegrationStatus() }.buttonStyle(.bordered)
            }
            HStack {
                Button("Launch OBS Virtual Camera") { manager.launchOBSVirtualCamera() }.buttonStyle(.bordered).disabled(!manager.obsInstalled)
                Button("Open OBS Plugins") {
                    if let url = URL(string: "file://\(manager.obsPluginsFolderPath)") { NSWorkspace.shared.open(url) }
                }.buttonStyle(.bordered).disabled(!manager.obsInstalled)
            }
            // Full details are still in main window System tab; this is a quick access duplicate
            Text("Full controls, logs, and diagnostics remain in the main window System tab.").font(.caption2).foregroundStyle(.secondary)
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
            Toggle("Near Mode", isOn: Binding(get: { manager.nearMode }, set: manager.setNearMode)).disabled(!manager.supportsDepth || !manager.canApplyImageControls)
            HStack { Text("Tilt \(manager.tiltAngle)°"); Spacer(); Slider(value: Binding(get: { Double(manager.tiltAngle) }, set: { manager.setTilt(Int($0)) }), in: -30...30, step: 1).disabled(!manager.supportsMotor) }
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}
