import DecartSDK
import SwiftUI

struct MirrorView: View {
    @Environment(Studio.self) private var studio
    @Environment(Account.self) private var account
    @Environment(FitStore.self) private var fits
    @StateObject private var cam = Camera()
    @StateObject private var clip = Clip()
    @State private var mirror = LiveMirror()

    @State private var closet = Dev.has("dev:closet")
    @State private var lookbook = Dev.has("dev:lookbook")
    @State private var flash = false
    @State private var captured: Look? = Dev.has("dev:look") ? Look(garment: Catalog.all[2], size: .m, shot: nil) : nil
    @State private var nudge: CGSize = .zero
    @State private var dragging: CGSize = .zero
    @State private var paywall = Dev.has("dev:paywall")
    @State private var topup = Dev.has("dev:topup")
    @State private var profile = Dev.has("dev:profile")
    @State private var pitched = false
    /// How long the running session was bought for — the ring needs a denominator.
    @State private var window = 1

    var body: some View {
        ZStack {
            if let track = mirror.track {
                RTCMLVideoViewWrapper(track: track, layoutMode: .fill).ignoresSafeArea()
            } else if cam.live {
                CameraPreview(session: cam.session).ignoresSafeArea()
            } else {
                MirrorFallback().overlay { if cam.denied { deniedNote } }
            }

            // the drawn garment is the stand-in; when the stream is up you're wearing it for real
            if mirror.track == nil { garment }

            chrome

            if flash { Color.white.ignoresSafeArea().transition(.opacity) }
        }
        .background(M.cream)
        .task { await account.sync() }   // the wallet on screen is the server's, not ours
        .onAppear {
            cam.start()
            // the offer lands before the first look — once per launch, not every time
            // this view comes back from a cover. ponytail: a free user who burns their
            // sparks meets it again on the next cold start, which is the point.
            if !account.subscribed && !pitched && !Onboard.pitched { paywall = true; pitched = true }
        }
        .fullScreenCover(isPresented: $paywall) { PaywallView() }
        .sheet(isPresented: $topup) { TopupSheet() }
        .sheet(isPresented: $profile) {
            ProfileSheet(topup: { profile = false; after { topup = true } },
                         pro:   { profile = false; after { paywall = true } },
                         looks: { profile = false; after { lookbook = true } })
        }
        .sheet(isPresented: $closet) { ClosetSheet() }
        // picking is the whole gesture — see follow()
        .onChange(of: studio.picked) { _, _ in Task { await follow() } }
        // session over (you stopped it, or the seconds ran out): the local camera comes back
        .onChange(of: mirror.phase) { _, phase in if phase == .off { cam.start() } }
        .sheet(isPresented: $lookbook) { LookbookView() }
        .fullScreenCover(item: $captured) { LookView(look: $0) }
    }

    // MARK: the fit

    private var garment: some View {
        GeometryReader { g in
            ZStack {
                if let w = studio.wearing {
                    GarmentLayer(garment: w, scale: studio.size.scale * fits.fit.scale)
                        .frame(width: g.size.width * 0.60, height: g.size.height * 0.62)
                        .position(x: g.size.width / 2, y: g.size.height * 0.47)
                        .offset(x: nudge.width + dragging.width, y: nudge.height + dragging.height)
                        .id(w.id)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.84).combined(with: .opacity),
                            removal: .scale(scale: 1.10).combined(with: .opacity)))
                }
            }
            .contentShape(Rectangle())
            // drag to line it up with your body, double-tap to re-center
            .gesture(
                DragGesture()
                    .onChanged { dragging = $0.translation }
                    .onEnded { _ in nudge.width += dragging.width; nudge.height += dragging.height; dragging = .zero }
            )
            .onTapGesture(count: 2) {
                tap()
                withAnimation(.spring) { nudge = .zero }
            }
        }
        .ignoresSafeArea()
    }

    /// Camera off: the whole promise is dark, so say so and point at the one fix.
    private var deniedNote: some View {
        VStack(spacing: 14) {
            Text("Mira needs the camera to put it on you")
                .font(M.display(21))
                .multilineTextAlignment(.center)
                .foregroundStyle(M.ink)
            Button {
                tap()
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            } label: {
                Text("Open Settings")
                    .tracked(11, 2.4)
                    .foregroundStyle(M.onRose)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(M.rose))
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: chrome

    /// Four controls floating on the camera and nothing else — the point of the screen
    /// is the reflection, and every panel we used to park down here was covering the
    /// half of you that the clothes are on. Everything that was in that panel lives in
    /// the closet now.
    private var chrome: some View {
        VStack(spacing: 0) {
            HStack {
                Button { tap(); profile = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(M.ink)
                        .puck()
                }
                .accessibilityLabel("Settings")

                Spacer()

                // the only thing that ever joins the four: the clock, while it is running,
                // because those seconds are money. Tap it to cut the session short.
                if mirror.phase != .off {
                    Button { toggleLive() } label: {
                        Countdown(left: mirror.secondsLeft, of: window)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(mirror.secondsLeft) seconds left")
                    .accessibilityHint("Stop the live mirror")
                    .transition(.scale.combined(with: .opacity))
                }

                Spacer()

                FlipButton(cam: cam, mirror: mirror)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .opacity(clip.rolling ? 0 : 1)

            if let trouble = mirror.trouble { note(trouble).padding(.top, 10) }

            Spacer()

            HStack {
                Button { tap(); closet = true } label: {
                    Image(systemName: "hanger")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(M.ink)
                        .puck(54)
                }
                .accessibilityLabel("The closet")
                .opacity(clip.rolling ? 0 : 1)

                Spacer()
                Shutter(shot: capture, roll: clip.start, cut: clip.stop, rolling: clip.rolling)
                Spacer()

                // keeps the shutter on the centre line now that nothing lives over here
                Color.clear.frame(width: 54, height: 54)
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 22)
        }
        .animation(.easeInOut(duration: 0.22), value: clip.rolling)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: mirror.phase)
    }

    // MARK: going live

    private var live: Bool { mirror.phase == .live }

    /// One camera, one owner: the SDK captures for itself, so ours steps aside.
    ///
    /// The server keeps the books — it charges when it mints the token and refunds what
    /// the session didn't use, and every answer carries the balance we then show. The
    /// local number only decides how long a session to ask for.
    private func toggleLive() {
        tap(.medium)
        Task {
            guard mirror.phase == .off else {
                if let settled = await mirror.stop() { account.adopt(settled) }
                return
            }
            guard let w = studio.wearing else { return }

            let seconds = min(Spend.maxLiveSeconds, Spend.liveSeconds(forSparks: account.sparks))
            guard seconds >= 10 else { return short() }
            window = seconds

            cam.stop()
            if let settled = await mirror.start(w, size: studio.size, seconds: seconds, front: cam.front) {
                account.adopt(settled)
            } else {
                // Refused or never came up. Whatever the local number said, ask.
                await account.sync()
                if account.sparks < Spend.sparks(forLiveSeconds: 10) { short() }
            }
        }
    }

    /// Not enough for the shortest session worth running.
    private func short() {
        tap(.heavy)
        if account.subscribed { topup = true } else { paywall = true }
    }

    /// Picking a piece *is* the go button — there isn't another one. Nothing running:
    /// this starts a session. Something running: it just changes clothes, no reconnect
    /// and no second charge.
    private func follow() async {
        guard let w = studio.wearing else { return }
        if mirror.phase == .off { toggleLive() } else { await mirror.wear(w, size: studio.size) }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(M.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(Capsule().fill(.white))
            .shadow(color: M.rouge.opacity(0.12), radius: 8, y: 3)
            .transition(.opacity)
            .onTapGesture { withAnimation { mirror.trouble = nil } }
    }

    private func capture() {
        guard let w = studio.wearing else { return }
        // The shutter is free: live, it saves a frame the session already paid for, and
        // otherwise it is the camera with a drawing over it. Nothing renders, nothing costs.
        // ponytail: `Spend.look` is charged by the server on /v1/look, which nothing here
        // calls yet. Point this at it for a proper still render and the charge comes with it.
        tap(.heavy)
        withAnimation(.easeIn(duration: 0.06)) { flash = true }

        let keep: (UIImage?) -> Void = { img in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.easeOut(duration: 0.32)) { flash = false }
                captured = Look(garment: w, size: studio.size, shot: img)
            }
        }
        if live { keep(mirror.snapshot()) } else { cam.shoot(keep) }
    }
}

// MARK: - pieces

struct Shutter: View {
    var shot: () -> Void
    var roll: () -> Void
    var cut: () -> Void
    var rolling: Bool
    @State private var down = false

    var body: some View {
        ZStack {
            Circle().fill(M.blush).frame(width: 76, height: 76)
            Circle().fill(.white).frame(width: 65, height: 65)
            // the still turns into a stop tile while it films, the way every camera does it
            RoundedRectangle(cornerRadius: rolling ? 7 : 27.5, style: .continuous)
                .fill(M.rose)
                .frame(width: rolling ? 26 : 55, height: rolling ? 26 : 55)
        }
        .scaleEffect(down ? 0.9 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: rolling)
        .onTapGesture {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { down = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { withAnimation(.spring) { down = false } }
            shot()
        }
        // hold it and it films instead; letting go cuts. No second button on the screen.
        .onLongPressGesture(minimumDuration: 0.4) {
            tap(.medium)
            roll()
        } onPressingChanged: { pressing in
            if !pressing { cut() }
        }
        // ponytail: labels only on the shape-only controls; the text and icon ones
        // announce themselves. Full audit when we ship past TestFlight.
        .accessibilityElement()
        .accessibilityLabel("Take a look")
        .accessibilityHint("Hold to film")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { shot() }
    }
}

/// Present one sheet as another closes — SwiftUI drops the second otherwise.
private func after(_ work: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
}
