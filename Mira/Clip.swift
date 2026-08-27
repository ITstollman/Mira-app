import Photos
import ReplayKit
import SwiftUI

/// Hold the shutter and Mira films what you're looking at.
///
/// ponytail: ReplayKit records the display, so the chrome would be in the clip —
/// MirrorView fades it out while `rolling`. Writing frames by hand with AVAssetWriter
/// would buy back the status bar for about seventy lines, and would have to be done
/// twice: our own camera owns the frames when nothing is streaming, the SDK's view
/// owns them when something is. Do that when someone complains about the clock.
@MainActor final class Clip: ObservableObject {
    @Published private(set) var rolling = false

    private let rec = RPScreenRecorder.shared()

    func start() {
        guard !rolling, rec.isAvailable else { return }
        rec.isMicrophoneEnabled = false
        rec.startRecording { error in
            Task { @MainActor in self.rolling = error == nil }
        }
    }

    /// Cuts and drops the mp4 in the camera roll. A clip nobody saw is worth nothing,
    /// so a tap that didn't quite become a hold just leaves nothing behind.
    func stop() {
        guard rolling else { return }
        rolling = false
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mira-\(UUID().uuidString).mp4")
        rec.stopRecording(withOutput: url) { error in
            guard error == nil else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
            } completionHandler: { _, _ in
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
