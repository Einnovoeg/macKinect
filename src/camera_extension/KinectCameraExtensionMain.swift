import Foundation
import CoreMediaIO

@main
struct KinectCameraExtensionMain {
    static func main() {
        let providerSource = MacKinectCameraExtensionProviderSource(clientQueue: nil)
        CMIOExtensionProvider.startService(provider: providerSource.provider)
        CFRunLoopRun()
    }
}
