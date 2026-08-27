import SwiftUI

/// Where you land. The mirror is a full-screen camera with three buttons on it, which
/// leaves nowhere to say hello, show you what you kept, or keep the settings — so this
/// holds all three and hands off to the mirror when you're ready.
struct HomeView: View {
    @Environment(Account.self) private var account
    @Environment(Studio.self) private var studio

    let start: () -> Void

    @State private var open: Look?
    @State private var profile = Dev.has("dev:profile")
    @State private var topup = Dev.has("dev:topup")
    @State private var paywall = Dev.has("dev:paywall")

    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            M.cream.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Hello, \(account.name)")
                        .font(M.display(34, .light))
                        .foregroundStyle(M.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.trailing, 56)   // the gear sits here
                        .padding(.top, 16)

                    Text(account.subscribed ? "\(account.sparks) sparks · Mira Pro" : "\(account.sparks) sparks")
                        .tracked(9, 1.8)
                        .foregroundStyle(M.mute)
                        .padding(.top, 8)

                    StartButton(go: start).padding(.top, 26)

                    Text(studio.looks.isEmpty ? "Your looks" : "Your looks · \(studio.looks.count)")
                        .tracked(9, 1.8)
                        .foregroundStyle(M.mute)
                        .padding(.top, 34)
                        .padding(.bottom, 14)

                    if studio.looks.isEmpty {
                        empty
                    } else {
                        LazyVGrid(columns: cols, spacing: 16) {
                            ForEach(studio.looks) { l in
                                LookCard(look: l).onTapGesture { tap(); open = l }
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
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
        }
        .fullScreenCover(item: $open) { LookView(look: $0) }
        .fullScreenCover(isPresented: $paywall) { PaywallView() }
        .sheet(isPresented: $topup) { TopupSheet() }
        .sheet(isPresented: $profile) {
            ProfileSheet(topup: { profile = false; after { topup = true } },
                         pro:   { profile = false; after { paywall = true } })
        }
    }

    /// Nothing kept yet: say what fills this, don't just leave a gap.
    private var empty: some View {
        VStack(spacing: 16) {
            Silhouette(cut: .slip)
                .stroke(M.rose.opacity(0.35), style: .init(lineWidth: 1.2, dash: [4, 5]))
                .frame(width: 92, height: 158)
            Text("Try something on, hit the shutter,\nand it lands here.")
                .multilineTextAlignment(.center)
                .font(.system(size: 13))
                .foregroundStyle(M.mute)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

/// Present one sheet as another closes — SwiftUI drops the second otherwise.
func after(_ work: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
}


/// The one thing on this screen worth pressing, so it gets the logo's treatment:
/// a candy bubble, lit along the crown, deeper at the foot, with the same gloss
/// travelling across it that the mark uses.
private struct StartButton: View {
    var go: () -> Void
    @State private var sweep = false

    var body: some View {
        Button { tap(.medium); go() } label: {
            HStack(spacing: 11) {
                Image(systemName: "sparkles").font(.system(size: 18, weight: .medium))
                Text("Try something on").tracked(13, 2.6)
            }
            .foregroundStyle(M.onRose)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 25)
            .background(bubble)
        }
        .buttonStyle(Squish())
        .task {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false).delay(0.8)) {
                sweep = true
            }
        }
        .accessibilityLabel("Try something on")
    }

    private var bubble: some View {
        Capsule()
            .fill(M.rose)
            .shadow(color: M.rouge.opacity(0.38), radius: 22, y: 11)
            .shadow(color: M.rose.opacity(0.45), radius: 5, y: 2)
            // round, not flat: the foot sits in its own shade
            .overlay {
                Capsule().fill(
                    LinearGradient(colors: [.clear, M.rouge.opacity(0.32)],
                                   startPoint: .center, endPoint: .bottom))
            }
            // the wet highlight along the crown
            .overlay(alignment: .top) {
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.66), .white.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 30)
                    .padding(.horizontal, 13)
                    .padding(.top, 4)
                    .blur(radius: 5)
            }
            .overlay { Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1) }
            .overlay { sheen }
            .clipShape(Capsule())
    }

    /// Crosses about once every eight seconds — the rest of the cycle it is parked
    /// off the edge, which is the pause. One animation, no timer.
    private var sheen: some View {
        GeometryReader { geo in
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: geo.size.width * 0.1, height: geo.size.height * 3)
                .rotationEffect(.degrees(22))
                .blur(radius: 7)
                .blendMode(.plusLighter)
                .position(x: geo.size.width * (sweep ? 2.2 : -1.2), y: geo.size.height / 2)
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
