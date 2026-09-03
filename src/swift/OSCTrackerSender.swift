import Foundation
import Network

/// Minimal UDP OSC sender for VRChat-style tracker endpoints.
///
/// The app deliberately does not start any network output until the user enables
/// OSC export. When enabled, this class only sends UDP packets to the configured
/// host/port and does not listen for inbound traffic.
final class OSCTrackerSender {
    private let queue = DispatchQueue(label: "com.mackinect.osc-tracker", qos: .utility)
    private var connection: NWConnection?
    private var currentHost = ""
    private var currentPort: UInt16 = 0

    func sendTrackers(_ trackers: [TrackerPose], host: String, port: UInt16, sendHead: Bool) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, port > 0 else { return }

        queue.async { [weak self] in
            guard let self else { return }
            self.ensureConnection(host: trimmedHost, port: port)

            for tracker in trackers {
                guard let positionAddress = tracker.role.oscPositionAddress(sendHead: sendHead) else { continue }
                self.sendVector3(tracker.position, address: positionAddress)

                // VRChat accepts Euler angles at matching rotation endpoints.
                // Kinect-derived orientation is not reliable yet, so publish a
                // neutral rotation instead of inventing noisy limb rotations.
                if let rotationAddress = tracker.role.oscRotationAddress(sendHead: sendHead) {
                    self.sendVector3(.zero, address: rotationAddress)
                }
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.connection?.cancel()
            self?.connection = nil
            self?.currentHost = ""
            self?.currentPort = 0
        }
    }

    private func ensureConnection(host: String, port: UInt16) {
        if connection != nil, currentHost == host, currentPort == port {
            return
        }

        connection?.cancel()
        currentHost = host
        currentPort = port

        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port) ?? .any
        let connection = NWConnection(host: nwHost, port: nwPort, using: .udp)
        connection.start(queue: queue)
        self.connection = connection
    }

    private func sendVector3(_ vector: TrackingVector3, address: String) {
        guard let connection else { return }
        let packet = OSCMessage.vector3(address: address, vector: vector).encoded()
        connection.send(content: packet, completion: .contentProcessed { _ in })
    }
}

private struct OSCMessage {
    let address: String
    let typeTags: String
    let values: [Float]

    static func vector3(address: String, vector: TrackingVector3) -> OSCMessage {
        OSCMessage(address: address, typeTags: ",fff", values: [vector.x, vector.y, vector.z])
    }

    func encoded() -> Data {
        var data = Data()
        data.appendOSCString(address)
        data.appendOSCString(typeTags)
        for value in values {
            data.appendOSCFloat(value)
        }
        return data
    }
}

private extension Data {
    mutating func appendOSCString(_ value: String) {
        append(Data(value.utf8))
        append(0)
        while count % 4 != 0 {
            append(0)
        }
    }

    mutating func appendOSCFloat(_ value: Float) {
        var bigEndianBits = value.bitPattern.bigEndian
        Swift.withUnsafeBytes(of: &bigEndianBits) { rawBuffer in
            append(contentsOf: rawBuffer)
        }
    }
}
