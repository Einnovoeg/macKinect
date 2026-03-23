import Foundation

/// Writes high-signal runtime diagnostics to a persistent user log so hardware,
/// HAL, and system-integration problems can be debugged after the fact.
final class DiagnosticsLogger {
    static let shared = DiagnosticsLogger()

    private let encoder = ISO8601DateFormatter()
    private let queue = DispatchQueue(label: "com.mackinect.diagnostics", qos: .utility)
    private let fileManager = FileManager.default

    private(set) var logFileURL: URL

    private init() {
        let baseDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("macKinect", isDirectory: true)
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        logFileURL = baseDirectory.appendingPathComponent("macKinect-diagnostics.log")
    }

    func log(category: String, message: String) {
        let timestamp = encoder.string(from: Date())
        let line = "[\(timestamp)] [\(category)] \(message)\n"
        queue.async { [fileManager, logFileURL] in
            let data = Data(line.utf8)
            if !fileManager.fileExists(atPath: logFileURL.path) {
                try? data.write(to: logFileURL, options: .atomic)
                return
            }

            guard let handle = try? FileHandle(forWritingTo: logFileURL) else {
                return
            }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}
