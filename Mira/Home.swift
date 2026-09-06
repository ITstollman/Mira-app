import SwiftUI

/// Where you land. One screen, one thing on it: the orb, high and pulsing. It does not
/// scroll — the settings sit in a corner, and what you've kept is a bar on the floor that
/// opens in its own window. A home screen with two equal choices on it has no home screen.
struct HomeView: View {
    @Environment(Studio.self) private var studio

    /// Into the mirror. True when a piece has already been chosen on the way — then
    /// the mirror shouldn't open the closet over the top of it.
    let start: (Bool) -> Void

    @State private var vault = Dev.has("dev:looks")
    @State private var profile = Dev.has("dev:profile")
    @State private var topup = Dev.has("dev:topup")
    @State private var paywall = Dev.has("dev:paywall")

    /// Where the stickers are. Starts finished when the intro isn't running, so there is
    /// never a frame of empty screen to catch.
    @State private var beat: Beat = Intro.skip ? .gone : .cold
    @State private var shown = Intro.skip

    var body: some View {
        ZStack {
            M.cream.ignoresSafeArea()
            hero
        }
        .overlay(alignment: .topTrailing) {
            Button { tap(); profile = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(M.ink)
                    .puck()
            }
            .accessibilityLabel("Settings")
            .padding(.horizontal, 20)
            .reveals(shown, by: 0.18)
        }
        // The bag empties, the page clears, the screen arrives. Once per launch — the orb
        // is live throughout, so this is never in the way of the only gesture here.
        .task {
            guard !Intro.skip else { return }
            Intro.played = true
            beat = .out
            // 0.72 for the last scrap to land, then a tenth of a second dead still — the
            // money frame, and the only part of this a person actually looks at
            try? await Task.sleep(for: .seconds(0.82))
            beat = .gone
            // the pull runs 0.24s off a 0.176s last delay, so the page is clear at ~0.42;
            // the title starts arriving under the last two scraps rather than after them
            try? await Task.sleep(for: .seconds(0.32))
            shown = true
        }
        // the history is both halves: what you kept, filed under what you were
        // wearing, and the way straight back into the wearing.
        .sheet(isPresented: $vault) {
            LooksSheet { g in
                studio.wear(g)
                vault = false
                after { start(true) }
            }
        }
        .fullScreenCover(isPresented: $paywall) { PaywallView() }
        .sheet(isPresented: $topup) { TopupSheet() }
        .sheet(isPresented: $profile) {
            ProfileSheet(topup: { profile = false; after { topup = true } },
                         pro:   { profile = false; after { paywall = true } })
        }
    }

    private var hero: some View {
        VStack(spacing: 0) {
            // capped, so the slack pools at the foot instead of splitting evenly: the orb
            // rides in the top half and the floor bar has the bottom to itself
            Spacer(minLength: 24).frame(maxHeight: 96)

            Text("Tap to try something on")
                .font(M.display(32))
                .foregroundStyle(M.rose)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)   // at AX2 it otherwise runs into both margins
                .padding(.horizontal, 24)
                .padding(.bottom, 72)   // clears the widest ring
                .reveals(shown, by: 0.12)

            // Over, not behind. The scraps land ON the page and on the sphere's shoulder,
            // which is what lets two of them graze it — the thing that makes this read as
            // paper on a table rather than pieces orbiting a ball. Scatter takes no hits
            // and is hidden from VoiceOver, so the orb is still the only thing here you
            // can touch.
            //
            // The sphere sits a hair small while the bag empties and springs to full as
            // the scraps come home, so it reads as swallowing them. The spring's own
            // overshoot supplies the gulp; returning >1 here would leave the orb
            // permanently wider.
            StartOrb(go: { start(false) })
                .scaleEffect(beat == .gone ? 1 : 0.9)
                .animation(.spring(response: 0.36, dampingFraction: 0.55), value: beat)
                .overlay { Scatter(beat: beat) }

            Spacer()

            // nothing kept yet means no bar: an empty shelf is worse than no shelf, and
            // the first shutter puts it there.
            if !studio.looks.isEmpty { bar.reveals(shown, by: 0.2, rise: 22) }
        }
    }

    private var bar: some View {
        HistoryCard { vault = true }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
    }
}

/// Everything you've kept, as one card wide enough to read as a place rather than a
/// status line. Lives on the floor of the home screen and again in the closet, because
/// both are somewhere you'd go looking for it.
struct HistoryCard: View {
    @Environment(Studio.self) private var studio
    let open: () -> Void

    var body: some View {
        Button { tap(); open() } label: {
            HStack(spacing: 15) {
                fan

                VStack(alignment: .leading, spacing: 3) {
                    Text("History").font(M.display(21)).foregroundStyle(M.ink)
                    Text("\(studio.looks.count) kept").tracked(8, 1.5).foregroundStyle(M.mute)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(M.rose)
            }
            .padding(.leading, 16)
            .padding(.trailing, 20)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white))
            .shadow(color: M.rouge.opacity(0.13), radius: 16, y: 7)
        }
        .buttonStyle(Squish())
        .accessibilityLabel("History, \(studio.looks.count) looks kept")
    }

    /// Three, tilted and overlapping, newest on top — a handful of photos dropped on a
    /// table. A straight row of three would just be three icons.
    private var fan: some View {
        HStack(spacing: -17) {
            ForEach(Array(studio.looks.prefix(3).enumerated()), id: \.element.id) { i, l in
                Snap(look: l)
                    .rotationEffect(.degrees([-10, 3, 13][i]))
                    .zIndex(Double(3 - i))
            }
        }
        // the tilt throws the corners past the layout frame; this keeps the label off them
        .padding(.trailing, 6)
    }
}

/// One kept look, small enough to fan. The shot if the session produced one, the piece
/// drawn on blush if it didn't — same recipe as LookCard, a third of the size.
struct Snap: View {
    let look: Look
    var side: CGFloat = 44

    var body: some View {
        ZStack {
            if let img = look.shot {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                M.blush
                GarmentLayer(garment: look.garment)
                    .frame(width: side * 0.48, height: side * 0.66)
            }
        }
        .frame(width: side, height: side * 4 / 3)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(.white, lineWidth: 2.5))
        .shadow(color: M.rouge.opacity(0.15), radius: 4, y: 2)
    }
}

/// Everything you kept, in its own window, because the home screen is one screen.
/// Filed by the piece rather than by the day: every shot and every clip of one garment
/// sits under that garment's own product photo, with the way back into it on the header.
struct LooksSheet: View {
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss
    /// Puts a piece back on. The whole reason a shelf of old photographs is worth
    /// opening — otherwise it is a scrapbook.
    let wear: (Garment) -> Void
    @State private var open: Look?

    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private var shelves: [(garment: Garment, looks: [Look])] { Wardrobe.shelves(studio.looks) }

    var body: some View {
        ZStack {
            M.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    VStack(spacing: 8) {
                        Text("History").font(M.display(30, .light)).foregroundStyle(M.ink)
                        Text("\(studio.looks.count) kept · \(shelves.count) pieces")
                            .tracked(9, 1.8).foregroundStyle(M.mute)
                    }
                    HStack {
                        Spacer()
                        Button { tap(); dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(M.ink)
                                .puck(34)
                        }
                        .accessibilityLabel("Close")
                    }
                    .padding(.trailing, 18)
                }
                .padding(.top, 26)
                .padding(.bottom, 22)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        ForEach(shelves, id: \.garment.id) { shelf($0.garment, $0.looks) }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 2)
                    .padding(.bottom, 40)
                }
            }
        }
        // one stop only. A medium detent underneath meant swiping down parked it
        // half-open and needed a second swipe to actually go — closing is one gesture.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // presented from in here, not from Home — a cover put up by the screen behind a
        // sheet lands behind the sheet
        .fullScreenCover(item: $open) { LookView(look: $0) }
    }

    /// One piece and everything you kept of it. The photograph of the garment is the
    /// heading, so a column of pictures of yourself is filed under what you were in.
    private func shelf(_ g: Garment, _ looks: [Look]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Color.white
                    GarmentLayer(garment: g).padding(g.shot == nil ? 11 : 4)
                }
                .frame(width: 48, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(M.shell, lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text(g.name).font(M.display(19)).foregroundStyle(M.ink)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(count(looks)).tracked(8, 1.5).foregroundStyle(M.mute)
                }

                Spacer(minLength: 6)

                // the call to action, and the only one on this screen: the shelf exists
                // so the piece can go back on, not so the photographs can be admired
                Button { tap(); wear(g) } label: {
                    Text("Wear").tracked(9, 1.8).foregroundStyle(M.onRose)
                        .padding(.horizontal, 17).padding(.vertical, 10)
                        .background(Capsule().fill(M.rose))
                }
                .buttonStyle(Squish())
                .accessibilityLabel("Wear \(g.name) again")
            }

            LazyVGrid(columns: cols, spacing: 12) {
                // the garment is named above, so the plate on each card says when
                ForEach(looks) { l in
                    LookCard(look: l, caption: l.date.formatted(.dateTime.day().month(.abbreviated)))
                        .onTapGesture { tap(); open = l }
                }
            }
        }
    }

    /// "3 photos · 1 clip", and neither half when there isn't one.
    private func count(_ looks: [Look]) -> String {
        let clips = looks.filter { $0.film != nil }.count
        let stills = looks.count - clips
        return [stills > 0 ? "\(stills) photo\(stills == 1 ? "" : "s")" : nil,
                clips > 0 ? "\(clips) clip\(clips == 1 ? "" : "s")" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// Present one sheet as another closes — SwiftUI drops the second otherwise.
func after(_ work: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
}

/// The intro belongs to the launch, not to the screen. HomeView is built again every time
/// you come back from the mirror, and a second and a half of stickers between you and the
/// camera the fourth time today is a toll, not a flourish.
enum Intro {
    static var played = false

    /// Reduce Motion gets the finished screen rather than a gentler intro. Asked here and
    /// not from the environment because this decides the *first* state — a frame later and
    /// the title has already flashed in from nothing.
    static var skip: Bool { played || UIAccessibility.isReduceMotionEnabled }
}

/// Under the orb, out on the page, or gone back under.
enum Beat { case cold, out, gone }

extension View {
    /// Reveal, not merely fade. An invisible button is still a button and still a stop on
    /// the VoiceOver rotor, so the hit test and the accessibility tree travel with the ink
    /// — the one thing three separate call sites would each have forgotten.
    func reveals(_ on: Bool, by delay: Double, rise: CGFloat = 12) -> some View {
        opacity(on ? 1 : 0)
            .offset(y: on ? 0 : rise)
            .allowsHitTesting(on)
            .accessibilityHidden(!on)
            .animation(.easeOut(duration: 0.36).delay(delay), value: on)
    }
}

/// One house piece as a die-cut sticker. The white edge is not drawn here — it is cut into
/// the Cut01…Cut10 art, following each garment's own outline the way a real sticker is
/// trimmed, because no shape SwiftUI can stroke follows a hem. All ten are narrower than
/// 3:4, so height is the dimension that binds and width comes out of the garment; sizing on
/// height is what keeps nine of these visually comparable.
///
/// The shadow reads the alpha, so it falls around the silhouette rather than round a box.
private struct Sticker: View {
    let art: String
    let h: CGFloat

    var body: some View {
        Image(art)
            .resizable().scaledToFit()
            .frame(height: h)
            .shadow(color: M.rouge.opacity(0.22), radius: 8, y: 5)
    }
}

/// Emptying the sticker bag. Nine cut-outs are flung onto the page around the orb, held
/// dead still for a tenth of a second, then pulled back in as the sphere swells to swallow
/// them. Hand-placed, never on a ring: nine things at even angles is a radial menu, and
/// this wants to read as a handful of stickers tipped out onto paper.
private struct Scatter: View {
    let beat: Beat

    /// Offsets are from the orb's own centre, so this never has to know where the orb landed
    /// on the screen. Two rules hold the table, and die-cutting changed which one bites.
    ///
    /// Horizontally: |x| plus the rotated half width — (w·cos t + h·sin t) / 2 — stays under
    /// 184, so nothing is shaved by the edge of the narrowest phone. `w` is now the garment's
    /// own width at this height rather than a fixed box, and it varies almost 2:1 across the
    /// set (Cut09 is 0.72 of its height, Cut01 only 0.36), so the same number here buys very
    /// different reach.
    ///
    /// Vertically is the tighter one now: a whole garment is far taller than the cropped band
    /// the old 3:4 window showed. With the orb centre ~362pt down, the top row's half-height
    /// is all that keeps Cut01 and Cut09 out of the Dynamic Island — which is why they sit at
    /// -218 and -230 rather than the -224/-240 the rectangles could afford.
    ///
    /// Sizes run 124 to 170, deliberately larger than a ring would allow, and the running
    /// order is scattered around the page rather than travelling around it: a bag empties in
    /// no order at all.
    private static let bag: [(art: String, x: CGFloat, y: CGFloat, h: CGFloat, tilt: Double)] = [
        ("Cut01", -128, -218, 158,  -9),   // 168.3 wide, 61.4 off the top — the tight one
        ("Cut05",  140,   34, 135,  10),   // 183.6 — grazes the sphere, right
        ("Cut02",  -16,  268, 147,  -8),   //  54.2
        ("Cut06",  108, -196, 135,  12),   // 154.3 — clears the settings puck
        ("Cut03", -140,  -18, 124, -12),   // 183.1 — grazes the sphere, left
        ("Cut04", -126,  196, 170,  10),   // 179.5 — the big one, low left
        ("Cut09",   26, -230, 124,  11),   //  81.3 — widest art, so it takes the centre lane
        ("Cut07",  122,  214, 135, -13),   // 163.4
        ("Cut08",   80,  152, 147,  -6),   // 117.7 — overlaps its neighbour, on purpose
    ]

    var body: some View {
        ZStack {
            ForEach(Array(Self.bag.enumerated()), id: \.offset) { i, s in
                Sticker(art: s.art, h: s.h)
                    // 26° short of the seat, so every scrap unwinds the same way into
                    // place — a flick of the wrist, not nine independent spins
                    .rotationEffect(.degrees(beat == .out ? s.tilt : s.tilt - 26))
                    .offset(x: place(s.x), y: place(s.y))
                    .scaleEffect(beat == .out ? 1 : (beat == .cold ? 0.34 : 0.18))
                    // this one sits ON the page, over the orb, so there is nothing to come
                    // out from behind: it has to fade-pop into being
                    .opacity(beat == .out ? 1 : 0)
                    .animation(curve(i), value: beat)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Out to the authored seat, and back to the orb's own centre on the way home.
    private func place(_ v: CGFloat) -> CGFloat {
        switch beat {
        case .cold: return v * 0.90   // tucked in, so the throw starts from near the sphere
        case .out:  return v
        case .gone: return 0
        }
    }

    /// Out on a loose spring — 0.58 damping is slack enough that each card overshoots its
    /// tilt and settles back, which is the whole difference between thrown and laid down.
    /// Home in the SAME order it arrived, not reversed: the bag is being sucked back in
    /// from the end you tipped first.
    private func curve(_ i: Int) -> Animation {
        switch beat {
        case .cold: return .linear(duration: 0)
        case .out:  return .spring(response: 0.42, dampingFraction: 0.58).delay(Double(i) * 0.045)
        case .gone: return .easeIn(duration: 0.24).delay(Double(i) * 0.022)
        }
    }
}


/// The whole home screen in one control: a candy sphere carrying the brand's camera,
/// lit along the crown, deeper at the foot, with the logo's gloss travelling across it —
/// and rings coming off it so it reads as live rather than as a picture of a button.
private struct StartOrb: View {
    var go: () -> Void
    @State private var sweep = false
    @State private var pulse = false

    private let d: CGFloat = 216

    var body: some View {
        ZStack {
            rings

            Button { tap(.medium); go() } label: {
                // the brand's own camera, pink on pink — the white glow is what lifts it
                // off the sphere without putting it on a plate
                Image("Camera")
                    .resizable().scaledToFit()
                    .frame(width: 80, height: 80)
                    .shadow(color: .white.opacity(0.9), radius: 4)
                    .shadow(color: M.rouge.opacity(0.4), radius: 6, y: 3)
                    .frame(width: d, height: d)
                    .background(bubble)
            }
            .buttonStyle(Squish())
            .accessibilityLabel("Try something on")
        }
        .task {
            pulse = true
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false).delay(0.8)) {
                sweep = true
            }
        }
    }

    /// Three, staggered a third of a cycle apart, so one is always leaving as another
    /// arrives. ponytail: no timer — each ring animates its own scale forever.
    private var rings: some View {
        ForEach(0..<3, id: \.self) { i in
            Circle()
                .strokeBorder(M.rose, lineWidth: 1.2)
                .frame(width: d, height: d)
                // 1.5x is as far as it can go and still be on a 393pt screen
                .scaleEffect(pulse ? 1.5 : 1)
                .opacity(pulse ? 0 : 0.6)
                .animation(.easeOut(duration: 3.6).repeatForever(autoreverses: false)
                    .delay(Double(i) * 1.2), value: pulse)
        }
        .allowsHitTesting(false)
    }

    private var bubble: some View {
        Circle()
            .fill(M.rose)
            .shadow(color: M.rouge.opacity(0.4), radius: 30, y: 14)
            .shadow(color: M.rose.opacity(0.5), radius: 8, y: 3)
            // round, not flat: the foot sits in its own shade
            .overlay {
                Circle().fill(
                    LinearGradient(colors: [.clear, M.rouge.opacity(0.34)],
                                   startPoint: .center, endPoint: .bottom))
            }
            // the wet highlight along the crown
            .overlay(alignment: .top) {
                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(0.72), .white.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 74)
                    .padding(.horizontal, 38)
                    .padding(.top, 9)
                    .blur(radius: 10)
            }
            .overlay { Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1) }
            .overlay { sheen }
            .clipShape(Circle())
    }

    /// Crosses about once every eight seconds — the rest of the cycle it is parked
    /// off the edge, which is the pause. One animation, no timer.
    private var sheen: some View {
        GeometryReader { geo in
            Capsule()
                .fill(.white.opacity(0.34))
                .frame(width: geo.size.width * 0.13, height: geo.size.height * 2)
                .rotationEffect(.degrees(22))
                .blur(radius: 9)
                .position(x: geo.size.width * (sweep ? 1.9 : -0.9), y: geo.size.height / 2)
        }
    }
}

/// Presses in like a real bubble. ponytail: the only button in the app that does.
struct Squish: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
