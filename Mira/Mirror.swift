import CoreImage
import DecartSDK
@preconcurrency import LiveKit
import SwiftUI

/// The live mirror: your camera goes up to Decart, you come back wearing the thing.
///
/// Media is WebRTC straight to Decart — our server only mints the short-lived token
/// and caps the session, which is what caps the spend.
@Observable @MainActor
final class LiveMirror {
    enum Phase: Equatable { case off, linking, live }

    private(set) var phase: Phase = .off
    private(set) var track: VideoTrack?
    private(set) var secondsLeft = 0
    /// Last thing that went wrong, in words worth showing. Nil when all is well.
    var trouble: String?

    /// Which lens is going up. Mirrors ``Camera/front`` so the switch survives the
    /// handover from our preview to the SDK's capturer.
    private(set) var front = false

    private var manager: DecartRealtimeManager?
    /// Held so the camera can still be turned around mid-session — the SDK owns the
    /// lens once it's connected, so ours can't.
    private var local: RealtimeMediaStream?
    /// The receipt for the sparks this session was charged. Quoting it is the only way
    /// to get the unused ones back.
    private var grant: String?
    private var pumps: [Task<Void, Never>] = []
    private let tap = FrameTap()

    private static let model = Models.realtime(.lucyVton3_5)

    /// Starts a session no longer than `seconds` — the server clamps it too, and charges
    /// for it up front. Returns the wallet balance the server came back with, or nil if
    /// nothing was charged because nothing started.
    @discardableResult
    func start(_ garment: Garment, size: Size, seconds: Int, front: Bool = false) async -> Int? {
        guard phase == .off else { return nil }
        phase = .linking
        trouble = nil
        self.front = front
        do {
            let token = try await API.mirrorToken(seconds: seconds)
            // Paid for. From here every way out has to hand the unused seconds back,
            // including the ones where the stream never comes up at all.
            grant = token.grant
            secondsLeft = token.seconds

            let client = DecartClient(decartConfiguration: .init(apiKey: token.value))
            let manager = try client.createRealtimeManager(options: .init(
                model: Self.model,
                initialPrompt: prompt(garment, size),
                resolution: .p720))
            self.manager = manager
            listen(to: manager)

            let local = client.createLocalCameraStream(model: Self.model,
                                                       position: front ? .front : .back)
            self.local = local
            attach(try await manager.connect(localStream: local))
            phase = .live
            countdown(from: token.seconds)
            return token.sparks
        } catch {
            trouble = error.localizedDescription
            return await stop()
        }
    }

    /// Turns the lens around without dropping the session — reconnecting would cost a
    /// second charge for the same thirty seconds.
    func flip() async {
        guard phase == .live,
              let track = local?.videoTrack as? LocalVideoTrack,
              let camera = track.capturer as? CameraCapturer,
              (try? await camera.switchCameraPosition()) == true else { return }
        front = camera.position == .front
        // MirrorMode.auto flips the front lens only, and the processor can't see the
        // switch happen — the SDK's own docs say to tell it.
        (track.processor as? MirroringVideoProcessor)?.cameraPosition = camera.position
    }

    /// Swap the garment mid-session. Cheaper than reconnecting, and the point of the thing.
    func wear(_ garment: Garment, size: Size) async {
        guard let manager, phase == .live else { return }
        do {
            try await manager.setPrompt(prompt(garment, size))
            trouble = nil
        } catch {
            trouble = "couldn't swap that one in"
        }
    }

    /// Gives back the seconds that were never used and returns the wallet balance the
    /// server settled on — nil when there was nothing to give back or nobody to tell.
    @discardableResult
    func stop() async -> Int? {
        let unused = max(0, secondsLeft)
        let receipt = grant
        await teardown()
        guard let receipt else { return nil }
        return try? await API.refund(grant: receipt, seconds: unused)
    }

    /// The last frame that came back down — what the shutter saves while live.
    func snapshot() -> UIImage? { tap.snapshot() }

    // MARK: -

    private func prompt(_ g: Garment, _ size: Size) -> DecartPrompt {
        DecartPrompt(text: "\(g.prompt) Worn with \(size.fit).", referenceImageData: reference(g))
    }

    /// lucy-vton-3.5 wants a reference image, and house pieces have no photograph — so it
    /// gets a render of the swatch instead.
    // ponytail: a flat silhouette is a weak reference and the try-on will show it. Put real
    // product shots in catalog.json (and `shot` on Garment) and this branch goes away.
    private func reference(_ g: Garment) -> Data? {
        if let shot = g.shot { return shot }
        let renderer = ImageRenderer(content:
            GarmentLayer(garment: g).frame(width: 512, height: 768).background(.white))
        renderer.scale = 1
        return renderer.uiImage?.pngData()
    }

    private func listen(to m: DecartRealtimeManager) {
        pumps.append(Task { [weak self] in
            for await state in m.events where state.connectionState == .error {
                self?.trouble = "the mirror dropped"
            }
        })
        pumps.append(Task { [weak self] in
            for await stream in m.remoteStreamUpdates { self?.attach(stream) }
        })
    }

    private func attach(_ stream: RealtimeMediaStream) {
        track?.remove(videoRenderer: tap)
        track = stream.videoTrack
        track?.add(videoRenderer: tap)
    }

    private func countdown(from n: Int) {
        secondsLeft = n
        pumps.append(Task { [weak self] in
            while let mirror = self, mirror.secondsLeft > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard let mirror = self, !Task.isCancelled else { return }
                mirror.secondsLeft -= 1
            }
            await self?.teardown()
        })
    }

    private func teardown() async {
        grant = nil
        local = nil
        pumps.forEach { $0.cancel() }
        pumps = []
        track?.remove(videoRenderer: tap)
        track = nil
        secondsLeft = 0
        phase = .off
        let going = manager
        manager = nil
        await going?.disconnect()
    }
}

/// Keeps the newest frame off the remote track so the shutter has something to save.
// ponytail: holds the buffer, not a copy — a recycled frame could tear the odd snapshot.
// Copy on render if that ever shows up in a saved look.
final class FrameTap: NSObject, VideoRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private let ctx = CIContext()
    private var last: CVPixelBuffer?

    @MainActor var isAdaptiveStreamEnabled: Bool { false }
    @MainActor var adaptiveStreamSize: CGSize { .zero }

    nonisolated func render(frame: VideoFrame) {
        guard let buffer = frame.toCVPixelBuffer() else { return }
        lock.lock(); last = buffer; lock.unlock()
    }

    func snapshot() -> UIImage? {
        lock.lock(); let buffer = last; lock.unlock()
        guard let buffer else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cg = ctx.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
