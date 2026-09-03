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
    /// Frames are actually arriving. Connected is not the same as visible — the socket
    /// comes up a beat before the first picture does, and that beat is the one where
    /// somebody is staring at nothing wondering if they broke it.
    private(set) var flowing = false
    private(set) var secondsLeft = 0
    /// Last thing that went wrong, in words worth showing. Nil when all is well.
    var trouble: String?
    /// What the link is doing while it comes up — a place in Decart's queue, mostly.
    /// The linking screen says this instead of sitting there looking hung.
    private(set) var waiting: String?

    /// The sub-line while there is still nothing to look at. Says the queue if there is
    /// one, then says we're through it and waiting on pictures.
    var doing: String? {
        if let waiting { return waiting }
        return phase == .live && !flowing ? "almost there" : nil
    }

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
        let t0 = ContinuousClock.now
        do {
            let token = try await API.mirrorToken(seconds: seconds)
            leg("token", t0)
            // Paid for. From here every way out has to hand the unused seconds back,
            // including the ones where the stream never comes up at all.
            grant = token.grant
            secondsLeft = token.seconds

            let client = DecartClient(decartConfiguration: .init(apiKey: token.value))
            let manager = try client.createRealtimeManager(options: .init(
                model: Self.model,
                initialPrompt: prompt(garment, size),
                // ponytail: the model is landscape (1280x720) and MirrorView fills a
                // portrait screen, so ~74% of every frame is cropped away. 1080p is the
                // only knob that puts pixels back — drop to .p720 if the link can't hold it.
                resolution: .p1080,
                // Simulcast is for an SFU choosing between many viewers. There is one
                // viewer here and it always wants the top layer, so the extra encodings
                // are phone battery and uplink spent on frames nobody watches.
                // ponytail: set it back to true if Decart ever subscribes to a lower layer.
                media: .init(video: .init(simulcast: false))))
            self.manager = manager
            listen(to: manager)

            let local = client.createLocalCameraStream(model: Self.model,
                                                       position: front ? .front : .back)
            self.local = local
            leg("camera", t0)
            tap.onFirstFrame { [weak self] size in
                Task { @MainActor in
                    guard let self else { return }
                    self.leg("first frame", t0)
                    self.shown(size)
                    withAnimation(.easeInOut(duration: 0.3)) { self.flowing = true }
                }
            }
            attach(try await manager.connect(localStream: local))
            leg("connect", t0)
            phase = .live
            countdown(from: token.seconds)
            watchForFirstFrame()
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

    /// Every frame that comes back down, for whoever is filming. Nil when nobody is.
    func onEachFrame(_ body: (@Sendable (CVPixelBuffer) -> Void)?) { tap.onEachFrame(body) }

    // MARK: -

    /// A typed piece has no photograph, so it goes up on the sentence alone — and
    /// enriched, which is what turns "a red slip dress" into the paragraph of colour,
    /// fabric and cut the model actually wants. Catalog and scraped prompts are already
    /// written that way and have a reference to be held to, so they go up as written.
    private func prompt(_ g: Garment, _ size: Size) -> DecartPrompt {
        DecartPrompt(text: "\(g.prompt) Worn with \(size.fit).",
                     referenceImageData: g.isWords ? nil : reference(g),
                     enrich: g.isWords)
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

    /// Where the seconds before the first picture actually go. Four legs — our token
    /// mint, handing the camera over, Decart's connect, and the wait for a frame after
    /// it — because "a few seconds" is not a number anybody can act on.
    // ponytail: a print, not telemetry. If this has to come off phones in the wild it
    // wants an event on the server, not the console.
    private func leg(_ name: String, _ since: ContinuousClock.Instant) {
        #if DEBUG
        let d = ContinuousClock.now - since
        let s = Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
        print(String(format: "mirror  %@%@ +%.2fs", name, String(repeating: " ", count: max(0, 12 - name.count)), s))
        #endif
    }

    /// What comes back down, and how much of it survives being poured into a portrait
    /// screen. MirrorView renders `.fill`, so the sides are cropped off and what is left
    /// is blown back up; ``Clip`` writes the same frame whole, at its native size. That
    /// difference — not the model — is why a saved clip looks sharper than the live view.
    // ponytail: a print, like `leg`. The composition is a design call and it should be
    // made against the real number off a real phone, not against this arithmetic.
    private func shown(_ size: CGSize) {
        #if DEBUG
        guard size.width > 0, size.height > 0 else { return }
        let screen = UIScreen.main.bounds.size
        let fill = max(screen.width / size.width, screen.height / size.height)
        let kept = (screen.width / fill) * (screen.height / fill) / (size.width * size.height)
        print(String(format: "mirror  frame       %.0fx%.0f — %.0f%% of it on screen, upscaled %.2fx",
                     size.width, size.height, kept * 100, fill * UIScreen.main.scale))
        #endif
    }

    private func listen(to m: DecartRealtimeManager) {
        pumps.append(Task { [weak self] in
            for await state in m.events { self?.take(state) }
        })
        pumps.append(Task { [weak self] in
            for await stream in m.remoteStreamUpdates { self?.attach(stream) }
        })
        // The SDK measures the link every second. Saying so beats letting someone
        // conclude the model is bad when it is their café wifi.
        pumps.append(Task { [weak self] in
            for await report in m.connectionQualityUpdates {
                guard let self, !report.warmingUp else { continue }
                switch report.quality {
                case .critical: trouble = "your connection is struggling"
                case .poor:     trouble = "weak connection — this will look soft"
                case .fair, .good: if trouble?.hasPrefix("weak") == true
                                    || trouble?.hasPrefix("your connection") == true { trouble = nil }
                }
            }
        })
    }

    /// Every state the SDK reports, not just the one that means failure. The SDK
    /// reconnects itself up to ten times, so `.reconnecting` is a caption, not a bug —
    /// but `.disconnected` after we were live means it gave up, and the seconds we are
    /// still counting are being billed for nothing.
    private func take(_ state: DecartRealtimeState) {
        waiting = state.queuePosition.map { "\($0) ahead of you" }
        switch state.connectionState {
        case .connected, .generating:
            trouble = nil
        case .reconnecting:
            trouble = "reconnecting"
        case .error:
            trouble = "the mirror dropped"
        case .disconnected:
            if phase == .live { Task { await stop() } }
        case .connecting, .idle:
            break
        }
    }

    private func attach(_ stream: RealtimeMediaStream) {
        track?.remove(videoRenderer: tap)
        track = stream.videoTrack
        track?.add(videoRenderer: tap)
    }

    /// Connected and billing but nothing coming down is the worst way to spend somebody's
    /// minutes. Give it a fair run, then say so and hand the rest back.
    // ponytail: 12s is a guess sitting next to the SDK's own 15s connect timeout. If real
    // sessions take longer to first frame, this is the number to move.
    private func watchForFirstFrame() {
        pumps.append(Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let mirror = self, !Task.isCancelled,
                  mirror.phase == .live, !mirror.flowing else { return }
            mirror.trouble = "the stream never came through"
            await mirror.stop()
        })
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
        flowing = false
        waiting = nil
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
    private var first: (@Sendable (CGSize) -> Void)?
    private var each: (@Sendable (CVPixelBuffer) -> Void)?

    /// Called once, on the next frame that renders, with what size it came in at.
    /// Re-arms each session.
    func onFirstFrame(_ body: @escaping @Sendable (CGSize) -> Void) {
        lock.lock(); first = body; lock.unlock()
    }

    /// Called on every frame until it's cleared. This is the clip.
    func onEachFrame(_ body: (@Sendable (CVPixelBuffer) -> Void)?) {
        lock.lock(); each = body; lock.unlock()
    }

    @MainActor var isAdaptiveStreamEnabled: Bool { false }
    @MainActor var adaptiveStreamSize: CGSize { .zero }

    nonisolated func render(frame: VideoFrame) {
        guard let buffer = frame.toCVPixelBuffer() else { return }
        lock.lock()
        last = buffer
        let announce = first
        let relay = each
        first = nil
        lock.unlock()
        announce?(CGSize(width: CVPixelBufferGetWidth(buffer),
                         height: CVPixelBufferGetHeight(buffer)))
        relay?(buffer)
    }

    func snapshot() -> UIImage? {
        lock.lock(); let buffer = last; lock.unlock()
        guard let buffer else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cg = ctx.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
