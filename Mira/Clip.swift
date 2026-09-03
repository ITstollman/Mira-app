import AVFoundation
import SwiftUI

/// Hold the shutter and Mira films what you're looking at.
///
/// Frames, not the display. ReplayKit filmed the screen, which put the chrome in the clip
/// and — worse — left the try-on out of it: the SDK draws the remote track into a layer
/// display capture doesn't composite, so the mp4 came back with the plain camera in it.
/// Both sources already hand us CVPixelBuffers (``Camera/captureOutput(_:didOutput:from:)``
/// and ``FrameTap/render(frame:)``) and only one of them produces at a time — MirrorView
/// stops the camera before going live — so both can feed one writer without interleaving.
@MainActor final class Clip: ObservableObject {
    @Published private(set) var rolling = false
    /// Anything the filming did that the user has to be told about. The mirror shows it.
    @Published var trouble: String?

    /// The finished mp4, still in the temporary directory. Whoever sets this owns it and
    /// must move it somewhere that survives, or bin it.
    var kept: ((URL) -> Void)?

    private let tape = Tape()

    func start() {
        guard !rolling else { return }
        rolling = true
        tape.open()
    }

    /// Cuts and keeps the mp4. A hold too short to catch a single frame leaves nothing
    /// behind and says nothing, same as before.
    func stop() {
        guard rolling else { return }
        rolling = false
        tape.close { [weak self] url, trouble in
            Task { @MainActor in
                guard let self else {
                    if let url { try? FileManager.default.removeItem(at: url) }
                    return
                }
                if let trouble { self.trouble = trouble }
                if let url { self.kept?(url) }
            }
        }
    }

    /// Every frame from whichever source is feeding the mirror. Called off the main thread
    /// — LiveKit's renderer, the camera queue — and near-free when nobody is filming.
    nonisolated func append(_ buffer: CVPixelBuffer) { tape.append(buffer) }
}

/// The writer, off the main actor: frames arrive on LiveKit's render thread and on the
/// camera's queue, and neither can be made to wait on it.
private final class Tape: @unchecked Sendable {
    private let q = DispatchQueue(label: "ai.mira.clip")
    private let lock = NSLock()
    private var filming = false          // lock

    // q only, all of it
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var pixels: AVAssetWriterInputPixelBufferAdaptor?
    private var size: (w: Int, h: Int)?
    private var opened: CMTime?
    private var count = 0

    func open() { lock.lock(); filming = true; lock.unlock() }

    func append(_ buffer: CVPixelBuffer) {
        // The sinks stay wired for the life of the screen, so every frame lands here
        // whether or not anyone is filming. A lock, not a queue hop: hopping would retain
        // the buffer and starve the capture pool for the 99% of frames nobody wants.
        lock.lock(); let on = filming; lock.unlock()
        guard on else { return }
        // ponytail: one clock for both sources rather than plumbing each one's own
        // timestamp through. The frame is handed over the instant it arrives, so the
        // difference is under a frame.
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        q.async { self.write(buffer, at: now) }
    }

    func close(_ done: @escaping @Sendable (URL?, String?) -> Void) {
        lock.lock(); filming = false; lock.unlock()
        q.async {
            guard let writer = self.writer, let input = self.input, self.count > 0 else {
                self.scrap()
                done(nil, nil)
                return
            }
            let file = writer.outputURL
            self.clear()                 // the next hold can start while this one writes out
            input.markAsFinished()
            writer.finishWriting {
                guard writer.status == .completed else {
                    try? FileManager.default.removeItem(at: file)
                    done(nil, writer.error?.localizedDescription ?? "Couldn't film that")
                    return
                }
                done(file, nil)
            }
        }
    }

    private func write(_ buffer: CVPixelBuffer, at now: CMTime) {
        if writer == nil { begin(with: buffer, at: now) }
        guard let writer, let input, let pixels, let size, let opened,
              writer.status == .writing else { return }
        // ponytail: the writer is fixed to the first frame. A reconnect that comes back at
        // another resolution gets dropped rather than stretched — rare, and a short clip
        // beats a squashed one.
        guard CVPixelBufferGetWidth(buffer) == size.w,
              CVPixelBufferGetHeight(buffer) == size.h else { return }
        // Real time: a frame the encoder isn't ready for is dropped, never waited on.
        guard input.isReadyForMoreMediaData else { return }
        pixels.append(buffer, withPresentationTime: now - opened)
        count += 1
    }

    private func begin(with buffer: CVPixelBuffer, at now: CMTime) {
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("mira-\(UUID().uuidString).mp4")
        guard let writer = try? AVAssetWriter(outputURL: file, fileType: .mp4) else { return }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            // ponytail: four bits a pixel a second. Enough for a fifteen-second share;
            // raise it if the tulle ever looks blocky.
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: w * h * 4]
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { return }
        writer.add(input)
        // nil attributes: the adaptor takes whatever the source hands it — 420v off the
        // camera, whatever the SDK's decoder returns — instead of us guessing a format.
        let pixels = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                          sourcePixelBufferAttributes: nil)
        guard writer.startWriting() else { return }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer
        self.input = input
        self.pixels = pixels
        self.size = (w, h)
        self.opened = now
    }

    private func scrap() {
        if let writer {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: writer.outputURL)
        }
        clear()
    }

    private func clear() {
        writer = nil; input = nil; pixels = nil; size = nil; opened = nil; count = 0
    }
}
