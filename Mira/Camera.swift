import AVFoundation
import CoreImage
import SwiftUI

/// Camera feed + a freeze-frame grab. No photo output: we already have the frames.
final class Camera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var live = false
    @Published var denied = false

    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "ai.mira.camera")
    private let ctx = CIContext()

    /// Which lens is live. The back one opens first: a try-on wants your whole body in
    /// frame and that is further away than an arm. Flip to the selfie lens for a look
    /// at the neckline.
    @Published private(set) var front = false
    // ponytail: touched from two queues, worst case is one dropped/duplicated frame grab.
    private var pendingShot: ((UIImage?) -> Void)?

    /// Every frame off the sensor, for whoever is filming. Nil when nobody is.
    // ponytail: set on main, read on `queue` — same trade as `pendingShot`, and the worst
    // case is the same: one frame at either end of a clip.
    var filming: (@Sendable (CVPixelBuffer) -> Void)?

    func start() {
        guard !live else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { if ok { self.configure() } else { self.denied = true } }
            }
        default:
            denied = true
        }
    }

    func stop() {
        guard live else { return }
        live = false
        queue.async { self.session.stopRunning() }
    }

    func flip() {
        front.toggle()
        let front = front
        queue.async {
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.addInput(front)
            self.orient(front)
            self.session.commitConfiguration()
        }
    }

    /// Hands back the next frame off the sensor. nil on Simulator / no permission.
    func shoot(_ done: @escaping (UIImage?) -> Void) {
        guard live else { done(nil); return }
        pendingShot = done
    }

    /// The same frame, awaited — for the handover to the SDK, where the caller wants
    /// something to leave on screen before it lets go of the lens.
    ///
    /// Half a second and then nil: a running session hands over a frame in 33ms, but an
    /// interrupted one hands over nothing at all, and a mirror that will not start
    /// because it is waiting on a picture nobody needs is the worse failure.
    func still() async -> UIImage? {
        guard live else { return nil }
        return await withCheckedContinuation { c in
            var resumed = false                     // both paths land on main
            func settle(_ img: UIImage?) {
                guard !resumed else { return }
                resumed = true
                c.resume(returning: img)
            }
            shoot(settle)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settle(nil) }
        }
    }

    private func configure() {
        denied = false
        let front = front              // read on main; the queue never touches @Published state
        queue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            self.addInput(front)
            if self.session.outputs.isEmpty {
                self.output.alwaysDiscardsLateVideoFrames = true
                self.output.setSampleBufferDelegate(self, queue: self.queue)
                if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
            }
            self.orient(front)
            self.session.commitConfiguration()
            self.session.startRunning()
            DispatchQueue.main.async { self.live = self.session.isRunning }
        }
    }

    private func addInput(_ front: Bool) {
        guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video,
                                                position: front ? .front : .back),
              let input = try? AVCaptureDeviceInput(device: dev),
              session.canAddInput(input) else { return }
        session.addInput(input)
    }

    private func orient(_ front: Bool) {
        for c in session.connections {
            if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
            if c.isVideoMirroringSupported {
                c.automaticallyAdjustsVideoMirroring = false
                c.isVideoMirrored = front
            }
        }
    }

    func captureOutput(_ o: AVCaptureOutput, didOutput sb: CMSampleBuffer, from c: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        // The connection is already rotated and mirrored, so these go into a clip upright.
        filming?(pb)
        guard pendingShot != nil else { return }
        let ci = CIImage(cvPixelBuffer: pb)
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return }
        let img = UIImage(cgImage: cg)
        DispatchQueue.main.async {
            let done = self.pendingShot
            self.pendingShot = nil
            done?(img)
        }
    }
}

/// Turns the camera around. Whichever side owns the lens right now is the side that
/// turns: our own preview when nothing is streaming, the SDK's capturer when it is.
struct FlipButton: View {
    @ObservedObject var cam: Camera
    var mirror: LiveMirror?

    var body: some View {
        Button {
            tap()
            if let mirror, mirror.phase != .off { Task { await mirror.flip() } } else { cam.flip() }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 18, weight: .semibold))
                .ghost()
        }
        .accessibilityLabel(showingFront ? "Switch to the back camera" : "Switch to the selfie camera")
    }

    private var showingFront: Bool {
        if let mirror, mirror.phase != .off { return mirror.front }
        return cam.front
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class View: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> View {
        let v = View()
        v.preview.session = session
        v.preview.videoGravity = .resizeAspectFill
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ v: View, context: Context) {}
}

/// No camera (Simulator, permission off): a flat, soft-lit dressing room.
struct MirrorFallback: View {
    var body: some View {
        ZStack {
            M.blush
            Capsule().fill(M.cream).frame(width: 320, height: 700).offset(y: -30)
        }
        .ignoresSafeArea()
    }
}
