import DecartSDK
import SwiftUI

struct MirrorView: View {
    @Environment(Studio.self) private var studio
    @Environment(Account.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    /// Seconds on the house, when the onboarding is running this screen for the first
    /// try. nil is the real thing: the wallet decides how long, and there is no offer
    /// waiting on the other side of the session.
    var trial: Int?
    /// Came in with something already picked — from the home screen's history, where
    /// the choosing already happened. Then the closet is in the way, not the way in.
    var straight = false
    /// Out of the mirror — home, or on to the offer if this was the trial.
    let back: () -> Void

    @StateObject private var cam = Camera()
    @StateObject private var clip = Clip()
    @State private var mirror = LiveMirror()

    @State private var closet = Dev.has("dev:closet") || Dev.has("dev:link")
    @State private var flash = false
    @State private var gallery = Dev.has("dev:look")
    /// The shot on its way to the pile. A still that just vanishes leaves you wondering
    /// whether anything was saved at all.
    @State private var flying: UIImage?
    @State private var landed = false
    @State private var paywall = Dev.has("dev:paywall")
    @State private var topup = Dev.has("dev:topup")
    /// The greeting paywall is up, so the closet is waiting behind it.
    @State private var pitched = false
    /// Landing here once, not every time a cover closes over us.
    @State private var greeted = false
    /// Left once. The window closing and the back button mean the same thing, and both
    /// get here — the first one through is the one that counts.
    @State private var over = false
    /// The last thing our lens saw before the SDK took it. The linking screen stands on
    /// this, so handing the camera over doesn't blank the mirror out from under her.
    @State private var held: UIImage?

    var body: some View {
        ZStack {
            // not "is it connected" — "is there a picture yet". They are seconds apart
            // and the gap between them is the one nobody could explain.
            if let track = mirror.track, mirror.flowing {
                RTCMLVideoViewWrapper(track: track, layoutMode: .fill).ignoresSafeArea()
            } else if mirror.phase != .off, let w = studio.wearing {
                Linking(garment: w, waiting: mirror.doing, behind: held).transition(.opacity)
            } else if cam.live {
                CameraPreview(session: cam.session).ignoresSafeArea()
            } else {
                MirrorFallback().overlay { if cam.denied { deniedNote } }
            }

            chrome

            if flash { Color.white.ignoresSafeArea().transition(.opacity) }
        }
        // the shot flying to the pile. Positioned in the same safe-area space as the
        // chrome, so the landing point is the trailing slot's centre.
        .overlay {
            if let flying {
                GeometryReader { g in
                    Image(uiImage: flying)
                        .resizable().scaledToFill()
                        .frame(width: landed ? 38 : 232, height: landed ? 51 : 310)
                        .clipShape(RoundedRectangle(cornerRadius: landed ? 10 : 28, style: .continuous))
                        .opacity(landed ? 0 : 1)
                        .position(x: landed ? g.size.width - 61 : g.size.width / 2,
                                  y: landed ? g.size.height - 60 : g.size.height / 2)
                }
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: mirror.phase)
        .animation(.easeInOut(duration: 0.35), value: mirror.flowing)
        .background(M.cream)
        .task { await account.sync() }   // the wallet on screen is the server's, not ours
        .onAppear {
            cam.start()
            clip.kept = film
            // Both sinks stay wired for the life of the screen; the clip drops what it
            // isn't filming. Only one of the two ever produces at a time — the camera is
            // stopped before a session starts — so they can share one writer.
            cam.filming = { [clip] in clip.append($0) }
            mirror.onEachFrame { [clip] in clip.append($0) }
            guard !greeted else { return }
            greeted = true
            // The offer lands before the first look; otherwise the closet opens itself,
            // because picking *is* the go button and there is nothing else to press.
            // ponytail: a free user who burns their sparks meets the offer again on the
            // next cold start, which is the point.
            // the trial has not been earned yet — the offer comes after it, not before
            if trial != nil { closet = true }
            else if !account.subscribed && !Onboard.pitched { paywall = true; pitched = true }
            else if straight { Task { await follow() } }
            else { closet = true }
        }
        .fullScreenCover(isPresented: $paywall, onDismiss: greet) { PaywallView() }
        .sheet(isPresented: $topup) { TopupSheet() }
        .sheet(isPresented: $closet) { ClosetSheet(starter: trial != nil) }
        // picking is the whole gesture — see follow()
        .onChange(of: studio.picked) { _, _ in Task { await follow() } }
        // session over (you stopped it, or the seconds ran out): the local camera comes back
        .onChange(of: mirror.phase) { was, phase in
            guard phase == .off else { return }
            cam.start()
            held = nil          // ours again; the next link grabs a fresh one
            // the free thirty seconds just ran out, which is the whole shape of the
            // onboarding: show them themselves in it, then ask
            if trial != nil, was == .live { finish() }
        }
        // A mirror nobody is standing in front of still bills by the second, and the
        // camera is the SDK's while it runs — so leaving the app settles up. Filming
        // stops too: a recording that outlives the screen it was started on films the
        // home screen, and whatever the user opens next.
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            clip.stop()
            guard mirror.phase != .off else { return }
            Task { if let settled = await mirror.stop() { account.adopt(settled) } }
        }
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
                Button(action: leave) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 21, weight: .semibold))
                        .ghost()
                }
                .accessibilityLabel("Back")

                Spacer()

                // the only thing that ever joins the four, and only to say the mirror is on.
                // ponytail: the clock is money, but a stopwatch running on your own face reads
                // as pressure, not feedback — so it stays a dot until the last ten seconds,
                // which is the only stretch where the number is news. Tap either to stop.
                if mirror.phase != .off {
                    Button { toggleLive() } label: {
                        // "live" is a claim about the picture, not about the socket. The
                        // screen behind this already waits for a frame; the pill was the
                        // one thing still saying yes during the wait.
                        if !mirror.flowing {
                            LivePill(word: "linking", tint: M.mute)
                        } else if mirror.secondsLeft <= 10 {
                            Countdown(left: mirror.secondsLeft, of: 10)
                        } else {
                            LivePill()
                        }
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.25), value: mirror.flowing)
                    .animation(.easeInOut(duration: 0.25), value: mirror.secondsLeft <= 10)
                    .accessibilityLabel(mirror.flowing ? "\(mirror.secondsLeft) seconds left" : "Linking")
                    .accessibilityHint("Stop the live mirror")
                    .transition(.scale.combined(with: .opacity))
                }

                Spacer()

                FlipButton(cam: cam, mirror: mirror)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            // invisible is not the same as gone: at opacity 0 these still took the tap,
            // so a thumb reaching for the frame edge could hang up the session mid-clip
            .opacity(clip.rolling ? 0 : 1)
            .allowsHitTesting(!clip.rolling)

            // ponytail: whichever spoke last wins the one slot. Two pills stacked on
            // your own face is worse than the second message waiting.
            if let trouble = clip.trouble ?? mirror.trouble {
                note(trouble) { clip.trouble = nil; mirror.trouble = nil }
                    .padding(.top, 10)
                    .opacity(clip.rolling ? 0 : 1)
            }

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
                .allowsHitTesting(!clip.rolling)

                Spacer()
                Shutter(shot: capture, roll: clip.start, cut: clip.stop, rolling: clip.rolling)
                Spacer()

                // what you've taken, stacked where it lands. Empty it is just the spacer
                // that keeps the shutter on the centre line.
                Group {
                    if studio.looks.isEmpty {
                        Color.clear
                    } else {
                        Pile(looks: studio.looks) { tap(); gallery = true }
                            .opacity(clip.rolling ? 0 : 1)
                            .allowsHitTesting(!clip.rolling)
                    }
                }
                .frame(width: 54, height: 54)
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 22)
        }
        .animation(.easeInOut(duration: 0.22), value: clip.rolling)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: mirror.phase)
        // ponytail: anchored on the chrome, not beside topup and closet — three
        // isPresented sheets on one view is where SwiftUI starts dropping one.
        // wearing it again from in here is just a change of clothes — the session is
        // already up, so picking swaps the piece without a reconnect. See follow().
        .sheet(isPresented: $gallery) { LooksSheet { g in studio.wear(g); gallery = false } }
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

            // ponytail: the trial is on the house — one fitting is $0.30 of compute and
            // the cheapest demo we will ever run. No wallet check, nothing to settle.
            let seconds = trial ?? min(Spend.maxLiveSeconds, Spend.liveSeconds(forSparks: account.sparks))
            guard trial != nil || seconds >= Spend.perFitting else { return short() }

            // one frame off the sensor before we let go of it, so the wait happens over
            // the room she is standing in rather than over a blank screen
            held = await cam.still()
            cam.stop()
            let settled = await mirror.start(w, size: studio.size, seconds: seconds, front: cam.front)
            guard trial == nil else { return }
            if let settled {
                account.adopt(settled)
            } else {
                // Refused or never came up. Whatever the local number said, ask.
                await account.sync()
                if account.sparks < Spend.perFitting { short() }
            }
        }
    }

    /// Leaving with the stream still up would keep billing for a mirror nobody is
    /// standing in front of, so it settles up on the way out.
    private func leave() {
        tap()
        clip.stop()
        Task {
            if let settled = await mirror.stop(), trial == nil { account.adopt(settled) }
            finish()
        }
    }

    private func finish() {
        guard !over else { return }
        over = true
        back()
    }

    /// The greeting is out of the way — now show what there is to wear.
    private func greet() {
        guard pitched else { return }
        pitched = false
        if straight { Task { await follow() } } else { closet = true }
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

    private func note(_ text: String, clear: @escaping () -> Void) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(M.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(Capsule().fill(.white))
            .shadow(color: M.rouge.opacity(0.12), radius: 8, y: 3)
            .transition(.opacity)
            .onTapGesture { withAnimation { clear() } }
    }

    private func capture() {
        guard let w = studio.wearing else { return }
        // The shutter is free: live, it saves a frame the session already paid for, and
        // otherwise it is the camera with a drawing over it. Nothing renders, nothing costs.
        // ponytail: a photograph is charged by the server on /v1/look, which nothing here
        // calls yet. Point this at it for a proper still render and the charge comes with it.
        tap(.heavy)
        withAnimation(.easeIn(duration: 0.06)) { flash = true }

        // the flash runs on a clock, not on the shutter callback — `cam.shoot` waits for the
        // next frame off the sensor, and a session that stalls left the screen white for good
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.easeOut(duration: 0.32)) { flash = false }
        }

        // Taking it is keeping it. The old cover asked, and asking meant the mirror
        // went away while you answered — which is the one thing this screen must not do.
        // Throwing one out lives in the lookbook now.
        let keep: (UIImage?) -> Void = { img in
            // No frame — pressed before the stream landed, or the camera is off. A look
            // with nothing in it is a blank tile in the grid forever, so it isn't kept.
            guard let img else { return mirror.trouble = "Nothing to catch yet" }
            studio.keep(Look(garment: w, size: studio.size, shot: img))
            fly(img)
        }
        if live { keep(mirror.snapshot()) } else { cam.shoot(keep) }
    }

    /// The clip is finished and sitting in the temporary directory. Give it a home and an
    /// identity in one go, then let it land in the pile the same way a still does.
    private func film(_ temp: URL) {
        guard let w = studio.wearing else {
            try? FileManager.default.removeItem(at: temp)
            return
        }
        let id = UUID()
        guard let home = Vault.adopt(temp, as: id) else {
            return clip.trouble = "Couldn't keep that clip"
        }
        Task {
            let poster = await Poster.frame(home)
            // ponytail: no camera-roll copy. It lives in the pile like every still does,
            // and Share hands the mp4 to Photos on request without a permission prompt
            // the first time somebody holds the shutter.
            studio.keep(Look(id: id, garment: w, size: studio.size, shot: poster, film: home))
            fly(poster)
        }
    }

    /// Shrink it into the pile so the save is something you watched happen.
    private func fly(_ img: UIImage?) {
        guard let img else { return }
        flying = img
        landed = false
        // The overlay has to exist at its big centre size for one frame first — SwiftUI
        // does not animate the geometry a view is *inserted* with, so setting both in the
        // same tick made the shot appear already shrunk into the pile, i.e. not at all.
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { landed = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { flying = nil }
    }
}

// MARK: - pieces

/// The SDK takes the camera the moment we ask for a session, so there is nothing to
/// reflect until the stream lands. Show the piece breathing rather than an empty room.
private struct Linking: View {
    let garment: Garment
    /// Decart's queue, when there is one. Silence otherwise.
    let waiting: String?
    /// The mirror as it was a moment ago. Nil on Simulator and with the camera off,
    /// which is the old cream screen.
    let behind: UIImage?
    @State private var breathing = false

    var body: some View {
        ZStack {
            M.cream.ignoresSafeArea()
            if let behind {
                // held, not live — the SDK has the lens. Blurred so it reads as the room
                // rather than as a camera that froze, and scrimmed so the piece on top
                // of it stays the thing you are looking at.
                Image(uiImage: behind)
                    .resizable().scaledToFill()
                    .blur(radius: 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(M.cream.opacity(0.45))
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            VStack(spacing: 30) {
                GarmentLayer(garment: garment)
                    .frame(width: 200, height: 270)
                    .scaleEffect(breathing ? 1.05 : 0.95)
                    .opacity(breathing ? 1 : 0.7)
                    .shadow(color: M.rouge.opacity(0.16), radius: 28, y: 14)

                VStack(spacing: 7) {
                    Text("putting it on you")
                        .tracked(10, 2.2)
                        .foregroundStyle(M.mute)
                    if let waiting {
                        Text(waiting)
                            .tracked(8, 1.6)
                            .foregroundStyle(M.mute.opacity(0.7))
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: waiting)
            }
        }
        // ponytail: a breath, not a percentage — the SDK doesn't report connect progress.
        .onAppear {
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) { breathing = true }
        }
    }
}

/// Proof the mirror is on, and nothing more. Says "linking" in grey until it is.
private struct LivePill: View {
    var word = "live"
    var tint = M.rose
    @State private var beat = false

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(tint).frame(width: 8, height: 8).opacity(beat ? 1 : 0.3)
            Text(word).tracked(9, 1.8).foregroundStyle(M.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(.white))
        .shadow(color: M.rouge.opacity(0.14), radius: 10, y: 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { beat = true }
        }
    }
}

/// The last few shots, stacked like prints dropped on a table, newest square on top.
/// Tap to open the lookbook — nothing about taking a picture should take the mirror away.
private struct Pile: View {
    let looks: [Look]
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            ZStack {
                ForEach(Array(looks.prefix(3).enumerated()), id: \.element.id) { i, l in
                    Snap(look: l, side: 38)
                        .rotationEffect(.degrees([0, 7, -8][i]))
                        .zIndex(Double(3 - i))
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.4, dampingFraction: 0.62), value: looks.count)
        .accessibilityLabel("Your looks, \(looks.count) taken")
        .accessibilityHint("Opens the lookbook")
    }
}

struct Shutter: View {
    var shot: () -> Void
    var roll: () -> Void
    var cut: () -> Void
    var rolling: Bool
    @State private var down = false
    @State private var began: Date?
    @State private var cutoff: Task<Void, Never>?

    /// A sweep with no end is decoration. Fifteen seconds is what Stories trained everyone
    /// to expect from this gesture, and it keeps the ReplayKit mp4 to a shareable size.
    private let cap: TimeInterval = 15

    var body: some View {
        ZStack {
            Circle().fill(M.blush).frame(width: 76, height: 76)

            // how much of the fifteen is gone, riding the blush band. ponytail: read off a
            // clock rather than animated — the shutter already runs two implicit animations
            // off `rolling`, and a fifteen-second linear one in the same subtree is a fight.
            if let began {
                TimelineView(.animation) { beat in
                    Circle()
                        .trim(from: 0, to: min(1, beat.date.timeIntervalSince(began) / cap))
                        .stroke(AngularGradient(colors: [M.rose, M.rouge, M.rose], center: .center),
                                style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 70.5, height: 70.5)
                }
            }

            Circle().fill(.white).frame(width: 65, height: 65)
            // the still turns into a stop tile while it films, the way every camera does it
            RoundedRectangle(cornerRadius: rolling ? 7 : 27.5, style: .continuous)
                .fill(M.rose)
                .frame(width: rolling ? 26 : 55, height: rolling ? 26 : 55)
        }
        // filming swells the whole thing, so the ring reads as the event and not as trim
        .scaleEffect(down ? 0.9 : rolling ? 1.12 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: rolling)
        .onChange(of: rolling) { _, on in
            cutoff?.cancel()
            began = on ? Date() : nil
            guard on else { cutoff = nil; return }
            // the ring finishing and the recording running on would be a lie
            cutoff = Task {
                try? await Task.sleep(nanoseconds: UInt64(cap * 1_000_000_000))
                guard !Task.isCancelled else { return }
                cut()
            }
        }
        // the fifteen-second cutoff outlives the screen otherwise, and fires into nothing
        .onDisappear { cutoff?.cancel(); cutoff = nil }
        .onTapGesture {
            // while it films this is a stop button, and it says so — firing the shutter
            // here put a white flash and a duplicate still into the middle of the clip
            guard !rolling else { return cut() }
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
        .accessibilityHint("Hold to film, up to fifteen seconds")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { shot() }
    }
}
