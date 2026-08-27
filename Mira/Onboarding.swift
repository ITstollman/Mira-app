import AVKit
import DecartSDK
import PhotosUI
import SwiftUI

/// The first ninety seconds, in order: the mark lands, you see what it does, you do it
/// yourself for thirty seconds, then we ask for money. Nothing here asks for an account —
/// we earn the right to ask by showing you yourself in the clothes first.
struct OnboardingView: View {
    var done: () -> Void

    enum Step: String, CaseIterable { case reveal, hero, pick, trial }
    // ponytail: dev:hero / dev:pick / dev:trial drop straight into a stage so the reel
    // doesn't have to be watched to reach the one being worked on.
    @State private var step: Step = Step.allCases.last { Dev.has("dev:\($0)") } ?? .reveal
    @State private var pitching = false

    var body: some View {
        ZStack {
            M.cream.ignoresSafeArea()
            switch step {
            case .reveal: Reveal { go(.hero) }.transition(.opacity)
            case .hero:   Hero { go(.pick) }.transition(.opacity)
            case .pick, .trial: Trial(trying: step == .trial,
                                     start: { go(.trial) },
                                     over:  pitch)
                    .transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: $pitching, onDismiss: done) { PaywallView() }
    }

    private func pitch() {
        Onboard.pitched = true
        pitching = true
    }

    private func go(_ s: Step) {
        withAnimation(.easeInOut(duration: 0.45)) { step = s }
    }
}

// MARK: - 1. the reveal

/// Full-bleed logo reveal. ponytail: `reveal.mp4` isn't shot yet, so the animated
/// fallback below is what ships until it is — drop the file into Mira/ and it takes over
/// with no code change.
private struct Reveal: View {
    var over: () -> Void
    @State private var bloom = false
    @State private var sweep = false
    @State private var named = false

    private let size: CGFloat = 156

    var body: some View {
        Reel(name: "reveal", ended: over) {
            ZStack {
                M.cream.ignoresSafeArea()
                VStack(spacing: 26) {
                    MiraMark(size: size)
                        .overlay {
                            // the gloss travelling across the plate, same trick the logo art uses
                            Capsule()
                                .fill(.white.opacity(0.75))
                                .frame(width: size * 0.26, height: size * 1.9)
                                .rotationEffect(.degrees(24))
                                .blur(radius: size * 0.09)
                                .offset(x: sweep ? size : -size)
                                .blendMode(.plusLighter)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.235, style: .continuous))
                        .scaleEffect(bloom ? 1 : 0.62)
                        .opacity(bloom ? 1 : 0)

                    Text("MIRA")
                        .font(M.display(38, .light))
                        .kerning(named ? 15 : 3)
                        .foregroundStyle(M.ink)
                        .opacity(named ? 1 : 0)
                }
            }
            .task {
                withAnimation(.spring(response: 0.85, dampingFraction: 0.6)) { bloom = true }
                withAnimation(.easeInOut(duration: 1.0).delay(0.45)) { sweep = true }
                withAnimation(.easeOut(duration: 0.8).delay(0.7)) { named = true }
                try? await Task.sleep(for: .seconds(2.7))
                over()
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: over)          // nobody watches a splash twice
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Skip the intro")
    }
}

// MARK: - 2. what it is

private struct Hero: View {
    var go: () -> Void
    @State private var showing = false

    var body: some View {
        GeometryReader { g in
            // 9:16 portrait, about two thirds of the width
            let w = min(g.size.width * 0.64, 280)

            VStack(spacing: 0) {
                Text("Wear it before\nyou buy it.")
                    .font(M.display(40, .light))
                    .foregroundStyle(M.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 24)
                    .padding(.top, 44)
                    .opacity(showing ? 1 : 0)

                Spacer(minLength: 24)

                Reel(name: "demo", loop: true) { DemoPlaceholder() }
                    .frame(width: w, height: w * 16 / 9)
                    .overlay(alignment: .bottomLeading) { ProductChip() }
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(.white, lineWidth: 5))
                    .shadow(color: M.rouge.opacity(0.18), radius: 26, y: 14)
                    .scaleEffect(showing ? 1 : 0.94)
                    .opacity(showing ? 1 : 0)

                Spacer(minLength: 24)

                Text("No account. Thirty seconds on us.")
                    .tracked(9, 1.8)
                    .foregroundStyle(M.mute.opacity(0.7))
                    .padding(.bottom, 14)
                    .opacity(showing ? 1 : 0)

                Button { tap(.medium); go() } label: {
                    Text("Live try on")
                        .tracked(13, 2.8)
                        .foregroundStyle(M.onRose)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(Capsule().fill(M.rose))
                        .shadow(color: M.rouge.opacity(0.28), radius: 18, y: 8)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 24)
                .opacity(showing ? 1 : 0)
                .offset(y: showing ? 0 : 18)
            }
            .frame(maxWidth: .infinity)
        }
        .background(M.cream)
        .onAppear { withAnimation(.spring(response: 0.8, dampingFraction: 0.78)) { showing = true } }
    }
}

/// The garment in the reel, so it reads as a try-on and not a video of a girl.
private struct ProductChip: View {
    var body: some View {
        Image("DemoProduct")
            .resizable().scaledToFill()
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(5)
            .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
            .padding(12)
    }
}

/// Stands in for demo.mp4: the shot we mean to take, drawn.
private struct DemoPlaceholder: View {
    @State private var shine = false

    var body: some View {
        ZStack {
            M.blush
            VStack(spacing: 16) {
                Image(systemName: "person.and.background.dotted")
                    .font(.system(size: 46, weight: .ultraLight))
                    .foregroundStyle(M.petal)
                Text("Your reel goes here")
                    .tracked(9, 1.6)
                    .foregroundStyle(M.mute.opacity(0.8))
            }
            Capsule()
                .fill(.white.opacity(0.5))
                .frame(width: 60, height: 620)
                .rotationEffect(.degrees(22))
                .blur(radius: 34)
                .offset(x: shine ? 220 : -220)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: false)) { shine = true }
        }
    }
}

// MARK: - 3 + 4. pick something, then thirty seconds of it

private struct Trial: View {
    let trying: Bool
    var start: () -> Void
    var over: () -> Void

    @Environment(Studio.self) private var studio
    @Environment(FitStore.self) private var fits
    @StateObject private var cam = Camera()
    @State private var mirror = LiveMirror()

    @State private var left = Self.window
    @State private var linking = false
    @State private var photo: PhotosPickerItem?
    @State private var pasting = false

    static let window = 30
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            if let track = mirror.track {
                RTCMLVideoViewWrapper(track: track, layoutMode: .fill).ignoresSafeArea()
            } else if cam.live {
                CameraPreview(session: cam.session).ignoresSafeArea()
            } else {
                MirrorFallback().ignoresSafeArea()
            }

            // no live stream yet: the drawn piece is the stand-in, same as the mirror does
            if mirror.track == nil, let w = studio.wearing {
                GeometryReader { g in
                    // the panel eats the bottom third while picking, so the body sits higher then
                    let feed = g.size.height - (trying ? 130 : 330)
                    GarmentLayer(garment: w, scale: studio.size.scale * fits.fit.scale)
                        .frame(width: g.size.width * 0.58, height: feed * 0.74)
                        .position(x: g.size.width / 2, y: feed * 0.56)
                        .id(w.id)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            if trying {
                VStack {
                    HStack {
                        Countdown(left: left, of: Self.window)
                        if linking {
                            Text("Linking…")
                                .tracked(9, 1.6)
                                .foregroundStyle(M.mute)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(.white))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    Spacer()
                    // thirty seconds is only a test drive if you can change your mind in it
                    rail

                    // the countdown is a ceiling, not a turnstile — leave whenever you're sold
                    Button { tap(.medium); finish() } label: {
                        Text("Continue")
                            .tracked(12, 2.6)
                            .foregroundStyle(M.onRose)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Capsule().fill(M.rose))
                            .shadow(color: M.rouge.opacity(0.3), radius: 16, y: 7)
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                }
            } else {
                picker.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            FlipButton(cam: cam, mirror: mirror).padding(.horizontal, 20)
        }
        .background(M.cream)
        .onAppear { cam.start() }
        .onReceive(clock) { _ in
            guard trying else { return }
            // 0 is the terminal state — without it the tick keeps re-firing finish()
            // behind the paywall, stopping a stopped session once a second
            if left > 1 { left -= 1 } else if left == 1 { left = 0; finish() }
        }
        .onChange(of: trying) { _, on in if on { Task { await live() } } }
        .sheet(isPresented: $pasting) { LinkSheet() }
        .onChange(of: studio.mine.first?.id) { _, _ in if !trying { start() } }
        .onChange(of: photo) { _, item in Task { await load(item) } }
    }

    /// Swap pieces mid-trial. No panel, no chrome — the feed stays the whole screen.
    private var rail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Catalog.all.prefix(8)) { g in
                    Button { studio.wear(g); Task { await mirror.wear(g, size: studio.size) } } label: {
                        GarmentLayer(garment: g)
                            .frame(width: 42, height: 54)
                            .padding(7)
                            .background(Circle().fill(.white.opacity(studio.wearing?.id == g.id ? 1 : 0.72)))
                            .overlay(Circle().strokeBorder(M.rose,
                                                           lineWidth: studio.wearing?.id == g.id ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(g.name)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: the overlay that asks

    private var picker: some View {
        VStack(spacing: 0) {
            Capsule().fill(M.shell).frame(width: 38, height: 5).padding(.top, 10).padding(.bottom, 16)

            Text("Put something on")
                .font(M.display(26, .light))
                .foregroundStyle(M.ink)
            Text("Pick a piece, use a photo, or paste a link")
                .tracked(9, 1.5)
                .foregroundStyle(M.mute)
                .padding(.top, 6)
                .padding(.bottom, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Catalog.all.prefix(8)) { g in
                        Button { studio.wear(g); start() } label: { Chip(garment: g) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
            }
            .padding(.bottom, 16)

            VStack(spacing: 10) {
                PhotosPicker(selection: $photo, matching: .images) {
                    Way(icon: "photo.on.rectangle.angled", label: "Your photos")
                }
                Button { tap(); pasting = true } label: {
                    Way(icon: "link", label: "Paste a link", shops: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                .fill(.white)
                .shadow(color: M.rouge.opacity(0.16), radius: 24, y: -6)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: the thirty seconds

    /// ponytail: the trial is on the house — thirty seconds is $0.60 of compute and it is
    /// the cheapest demo we will ever run. No `account.spend` here on purpose.
    private func live() async {
        guard let w = studio.wearing else { return }
        linking = true
        cam.stop()
        await mirror.start(w, size: studio.size, seconds: Self.window, front: cam.front)
        linking = false
        // the SDK never came up (simulator, no key, no network) — the drawn piece carries
        // the thirty seconds instead, which is still a demo
        if mirror.phase == .off { cam.start() }
    }

    private func finish() {
        Task {
            _ = await mirror.stop()
            tap(.medium)
            over()
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        studio.add(Garment(photo: data))
    }
}

// MARK: - pieces

/// Counting down. The ring is the honest bit — you can watch the seconds you paid for
/// run out. Used by the trial and by the mirror.
struct Countdown: View {
    let left: Int
    let of: Int

    var body: some View {
        ZStack {
            Circle().fill(.white)
            Circle().strokeBorder(M.shell, lineWidth: 3).padding(3)
            Circle()
                .trim(from: 0, to: CGFloat(left) / CGFloat(of))
                .stroke(left <= 5 ? M.rouge : M.rose, style: .init(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(4.5)
                .animation(.linear(duration: 1), value: left)
            Text("\(left)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(M.ink)
                .contentTransition(.numericText(countsDown: true))
        }
        .frame(width: 50, height: 50)
        .shadow(color: M.rouge.opacity(0.16), radius: 10, y: 4)
        .accessibilityLabel("\(left) seconds left")
    }
}

private struct Chip: View {
    let garment: Garment

    var body: some View {
        VStack(spacing: 7) {
            GarmentLayer(garment: garment)
                .frame(width: 62, height: 78)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(M.blush))
            Text(garment.name)
                .font(M.ui(10, .medium))
                .foregroundStyle(M.ink)
                .lineLimit(1)
        }
        .frame(width: 82)
    }
}

private struct Way: View {
    let icon: String
    let label: String
    /// Puts the shops we can read a link from inside the button that reads links.
    var shops = false

    var body: some View {
        VStack(spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(M.rose)
                Text(label).font(M.ui(13, .medium)).foregroundStyle(M.ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            if shops { BrandRow() }
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 14)
        // radius 24 on a bare row is a capsule, and still reads right once the shops
        // make it three times as tall — one shape covers both
        .background(shape.fill(M.cream))
        .overlay(shape.strokeBorder(M.shell, lineWidth: 1.2))
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 24, style: .continuous) }
}

// MARK: - the reels

/// The shops a link can come from, as their own square marks rather than a line of
/// words — a row of little icons reads as "these stores work here" at a glance,
/// which a sentence does not. The last tile says the list is not the limit.
struct BrandRow: View {
    /// Name for the screen reader, slug for the catalog. They differ: "H&M" is not a
    /// filename. A nil slug is the tile that stands for everywhere else.
    static let shops: [(name: String, slug: String?)] = [
        ("Zara", "zara"), ("Mango", "mango"), ("H&M", "hm"),
        ("ASOS", "asos"), ("Revolve", "revolve"), ("and 99 more stores", nil),
    ]

    var tile: CGFloat = 44
    /// How many fit on a line — six across inside the picker's full-width button,
    /// three stacked inside the narrow card in the closet.
    var columns = 6
    var gap: CGFloat = 7

    var body: some View {
        VStack(spacing: gap) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(rows[r], id: \.name) { shop in
                        BrandTile(name: shop.name, slug: shop.slug, side: tile)
                    }
                }
            }
        }
        .fixedSize()
    }

    private var rows: [[(name: String, slug: String?)]] {
        stride(from: 0, to: Self.shops.count, by: columns).map {
            Array(Self.shops[$0 ..< min($0 + columns, Self.shops.count)])
        }
    }
}

private struct BrandTile: View {
    let name: String
    /// nil for the overflow tile: blush and a count, so five logos don't read as a
    /// list of five.
    let slug: String?
    let side: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: side * 0.27, style: .continuous)
    }

    var body: some View {
        ZStack {
            shape.fill(slug == nil ? M.blush : .white)
            if let slug {
                // the shop's own square mark, filling the tile — it *is* the icon, not a
                // logo sitting on a card. Our type only if the artwork ever goes missing.
                if let art = UIImage(named: "shop-\(slug)") {
                    Image(uiImage: art).resizable().scaledToFill()
                } else {
                    // a wordmark set in our own face is nominative use and needs nobody's
                    // permission — a facsimile of their logotype would need a licence
                    Text(name.uppercased())
                        .font(M.ui(side * 0.18, .bold)).kerning(0.3)
                        .foregroundStyle(M.ink.opacity(0.62))
                        .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 4)
                }
            } else {
                Text("+99")
                    .font(M.ui(side * 0.3, .semibold)).kerning(-0.2)
                    .foregroundStyle(M.ink.opacity(0.72))
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .overlay(shape.strokeBorder(M.shell, lineWidth: 1))
        .accessibilityLabel(name)
    }
}

/// A bundled mp4, full-bleed and silent. Falls back to `placeholder` when the file
/// isn't in the bundle, so the flow is walkable before either reel is shot.
struct Reel<Placeholder: View>: View {
    let name: String
    var loop = false
    var ended: () -> Void = {}
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "mp4") {
            Film(url: url, loop: loop, ended: ended)
        } else {
            placeholder()
        }
    }
}

private struct Film: UIViewRepresentable {
    let url: URL
    let loop: Bool
    let ended: () -> Void

    final class Host: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var film: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Coordinator {
        var watch: NSObjectProtocol?
        deinit { if let watch { NotificationCenter.default.removeObserver(watch) } }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Host {
        let v = Host()
        let player = AVPlayer(url: url)
        player.isMuted = true
        v.film.player = player
        v.film.videoGravity = .resizeAspectFill
        context.coordinator.watch = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { _ in
            if loop {
                player.seek(to: .zero)
                player.play()
            } else {
                ended()
            }
        }
        player.play()
        return v
    }

    func updateUIView(_ v: Host, context: Context) {}
}
