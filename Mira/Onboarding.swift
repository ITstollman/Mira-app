import AVKit
import DecartSDK
import PhotosUI
import SwiftUI

/// The first ninety seconds, in order: the mark lands, you see what it does, you do it
/// yourself for thirty seconds, then we ask for money. Nothing here asks for an account —
/// we earn the right to ask by showing you yourself in the clothes first.
struct OnboardingView: View {
    var done: () -> Void

    enum Step: String, CaseIterable { case reveal, hero, trial }
    // ponytail: dev:hero / dev:trial drop straight into a stage so the reel doesn't
    // have to be watched to reach the one being worked on.
    @State private var step: Step = Step.allCases.last { Dev.has("dev:\($0)") } ?? .reveal
    @State private var pitching = false

    /// One fitting, on the house — long enough to change twice and see it happen. The
    /// whole pre-payment giveaway, and it is what the wallet opens with too.
    static let freeSeconds = Spend.perFitting

    var body: some View {
        ZStack {
            M.cream.ignoresSafeArea()
            switch step {
            case .reveal: Reveal { go(.hero) }.transition(.opacity)
            case .hero:   Hero { go(.trial) }.transition(.opacity)
            // the actual screen, not a rehearsal of it: same closet, same shutter, same
            // countdown. A first try that teaches a layout the app doesn't have is a
            // tutorial for somebody else's app.
            case .trial:  MirrorView(trial: Self.freeSeconds, back: pitch)
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
    /// Where the reel is, so the packshot can keep up with what she has on.
    @State private var at = 0.0

    // ponytail: one flag, a delay per element. No phase enum, no timers.
    private func reveal(_ delay: Double, _ response: Double = 0.6) -> Animation {
        .spring(response: response, dampingFraction: 0.82).delay(delay)
    }

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
                    .blur(radius: showing ? 0 : 7)
                    .offset(y: showing ? 0 : 16)
                    .animation(reveal(0.05, 0.75), value: showing)

                Spacer(minLength: 24)

                // the same cut the App Store preview runs: one mirror, three pieces,
                // no cut away. A stranger deciding whether to spend thirty seconds
                // should see the morph the store promised them.
                Reel(name: "morph", loop: true, time: { at = $0 }) { DemoPlaceholder() }
                    .frame(width: w, height: w * 16 / 9)
                    .overlay(alignment: .bottomLeading) { ProductChip(showing: showing, at: at) }
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(.white, lineWidth: 5))
                    .shadow(color: M.rouge.opacity(showing ? 0.18 : 0), radius: 26, y: 14)
                    .scaleEffect(showing ? 1 : 0.88)
                    .opacity(showing ? 1 : 0)
                    .animation(reveal(0.28, 0.8), value: showing)

                Spacer(minLength: 24)

                Text("No account. One fitting on us.")
                    .tracked(9, 1.8)
                    .foregroundStyle(M.mute.opacity(0.7))
                    .padding(.bottom, 14)
                    .opacity(showing ? 1 : 0)
                    .animation(reveal(0.86), value: showing)

                Button { tap(.medium); go() } label: {
                    HStack(spacing: 12) {
                        // our camera, not SF Symbols' — the same one the home screen
                        // wears. It is pink art, so it needed a white halo to survive
                        // a rose fill; on rouge it reads on its own and the halo is
                        // only there to keep the edge crisp.
                        Image("Camera")
                            .resizable().scaledToFit()
                            .frame(width: 30, height: 30)
                            .shadow(color: .white.opacity(0.55), radius: 4)
                        Text("Live try on").tracked(13, 2.8)
                    }
                    // ponytail: white here, not M.onRose. That token is ink because it
                    // rides M.rose at sixteen other call sites; this is the one button
                    // on a rouge fill, where white measures 4.20:1 and ink only 3.50:1.
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Capsule().fill(M.rouge))
                    .shadow(color: M.rouge.opacity(0.30), radius: 18, y: 8)
                    // The moat. Rose on cream is 1.86:1, so the old fill read as a
                    // tinted area rather than an object — emphasis by isolation instead
                    // of by size: a cream gap nothing else on the screen has, then the
                    // brand pink as a ring around it.
                    .overlay(Capsule().strokeBorder(M.cream, lineWidth: 4).padding(-4))
                    .overlay(Capsule().strokeBorder(M.rose, lineWidth: 2).padding(-6))
                }
                // 24, not 30: the rings spend 6pt of the old margin.
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .opacity(showing ? 1 : 0)
                .offset(y: showing ? 0 : 26)
                .animation(reveal(0.72, 0.7), value: showing)
            }
            .frame(maxWidth: .infinity)
        }
        .background(M.cream)
        .onAppear { showing = true }
    }
}

/// The garment in the reel, so it reads as a try-on and not a video of a girl.
private struct ProductChip: View {
    var showing: Bool
    /// Seconds into morph.mp4.
    var at: Double

    /// [cut, packshot] — nil is the before, her own clothes, no chip. Measured off the
    /// footage frame by frame, then pulled 0.15s early: the morph is a dissolve, and the
    /// packshot should land as the piece arrives rather than after it has.
    /// ponytail: if the reel is ever recut, re-measure both.
    private static let cues: [(Double, String?)] =
        [(0, nil), (2.12, "CatalogPink"), (4.50, "CatalogYellow")]

    private var packshot: String? {
        Self.cues.last { $0.0 <= at }?.1
    }

    var body: some View {
        // portrait, not square: a packshot is a hanging garment and a square crop takes
        // the hem off. Same 1024:1536 card the store deck shows.
        Group {
            if let packshot {
                Image(packshot)
                    .resizable().scaledToFill()
                    .frame(width: 58, height: 87)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(5)
                    .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
                    // it arrives when she changes, so it should land rather than fade
                    .transition(.scale(scale: 0.7, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.7), value: packshot)
        .padding(12)
        .scaleEffect(showing ? 1 : 0.5, anchor: .bottomLeading)
        .opacity(showing ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.62).delay(0.62), value: showing)
    }
}

/// Stands in for demo.mp4: the shot we mean to take, drawn.
struct DemoPlaceholder: View {
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

// MARK: - the reels

/// The shops a link can come from, as their own square marks rather than a line of
/// words — a row of little icons reads as "these stores work here" at a glance,
/// which a sentence does not. The last tile says the list is not the limit.
struct BrandRow: View {
    /// Name for the screen reader, slug for the catalog. They differ: "H&M" is not a
    /// filename. A nil slug is the tile that stands for everywhere else.
    ///
    /// The five biggest places people actually buy clothes online: Shein is #1 in the US
    /// and near the top worldwide, Gap is the biggest US retailer behind it, and
    /// Zara/H&M/ASOS are the three every shopper recognises on sight. Ordered so the two
    /// coloured tiles sit apart — five wordmarks in a row otherwise read as one grey smear.
    /// ponytail: hardcoded. It becomes a fetched list the day marketing wants to sell a slot.
    static let shops: [(name: String, slug: String?)] = [
        ("Shein", "shein"), ("H&M", "hm"), ("Zara", "zara"),
        ("Gap", "gap"), ("ASOS", "asos"), ("and 99 more stores", nil),
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
    /// Seconds in, a few times a second. For anything that has to stay in step with the
    /// footage — the packshot on the onboarding reel is the only one so far.
    var time: (Double) -> Void = { _ in }
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "mp4") {
            Film(url: url, loop: loop, ended: ended, time: time)
        } else {
            placeholder()
        }
    }
}

private struct Film: UIViewRepresentable {
    let url: URL
    let loop: Bool
    let ended: () -> Void
    let time: (Double) -> Void

    final class Host: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var film: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Coordinator {
        var watch: NSObjectProtocol?
        var player: AVPlayer?
        var ticker: Any?
        deinit {
            if let watch { NotificationCenter.default.removeObserver(watch) }
            // the player holds this one, so it has to go back to the same player
            if let ticker { player?.removeTimeObserver(ticker) }
        }
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
        context.coordinator.player = player
        context.coordinator.ticker = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { t in time(t.seconds) }
        player.play()
        return v
    }

    func updateUIView(_ v: Host, context: Context) {}
}
