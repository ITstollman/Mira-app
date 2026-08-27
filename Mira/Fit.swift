import SwiftUI

// MARK: - the measurement

/// What Mira knows about your body: how tall you are, what you reach for, and
/// whether you have told her yet.
struct Fit: Codable {
    var height = 168            // cm
    var size: Size = .s
    var done = false

    /// The whole point — a taller body wears a longer garment.
    /// 168 cm is the fit model; every cm off her is 0.4% of length, clamped both ways.
    // ponytail: one linear nudge off height. Torso/inseam ratios when there is a real body model.
    var scale: CGFloat { done ? min(1.12, max(0.90, 1 + CGFloat(height - 168) * 0.004)) : 1 }
}

// ponytail: UserDefaults + JSON, so the fit lives on one device. Move it onto the
// account (Account.swift) the day sizes should follow you across phones.
@Observable final class FitStore {
    var fit: Fit { didSet { save() } }
    private static let key = "mira.fit"

    init() {
        fit = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Fit.self, from: $0) } ?? Fit()
    }

    /// dev:fit jumps straight to the setup even if you have already done it.
    var needsSetup: Bool { Dev.has("dev:fit") || !fit.done }

    private func save() {
        if let d = try? JSONEncoder().encode(fit) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
}

// Size ships from Garment.swift as a plain raw-value enum — this is all Codable needs.
extension Size: Codable {}

// MARK: - three beats

struct FitSetup: View {
    @Environment(FitStore.self) private var fits
    var done: () -> Void

    @State private var beat = 0
    @State private var height: Double = 168
    @State private var size: Size = .s
    @State private var showing = false

    var body: some View {
        ZStack {
            M.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 30)

                MiraMark(size: 58).padding(.bottom, 22)

                Text(title)
                    .font(M.display(42, .light))
                    .kerning(2)
                    .foregroundStyle(M.ink)

                Text(sub)
                    .tracked(10, 1.6)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(M.mute)
                    .padding(.top, 10)
                    .padding(.horizontal, 34)

                Spacer(minLength: 24)

                control
                    .id(beat)
                    .transition(.asymmetric(
                        insertion: .offset(x: 44).combined(with: .opacity),
                        removal: .offset(x: -44).combined(with: .opacity)))

                Spacer(minLength: 24)

                dots.padding(.bottom, 20)

                Button { tap(.medium); next() } label: {
                    Text(beat == 2 ? "Start" : "Next")
                        .tracked(12, 2.6)
                        .foregroundStyle(M.onRose)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Capsule().fill(M.rose))
                }
                .padding(.horizontal, 30)

                Button { tap(); skip() } label: {
                    Text("Skip").tracked(9, 1.8).foregroundStyle(M.mute.opacity(0.7))
                }
                .padding(.top, 16)
                .padding(.bottom, 26)
            }
            .opacity(showing ? 1 : 0)
            .offset(y: showing ? 0 : 14)
        }
        .onAppear {
            height = Double(fits.fit.height)
            size = fits.fit.size
            withAnimation(.spring(response: 0.9, dampingFraction: 0.7)) { showing = true }
        }
    }

    // MARK: copy

    private var title: String {
        switch beat {
        case 0:  "How tall?"
        case 1:  "Your size"
        default: "That's you"
        }
    }

    private var sub: String {
        switch beat {
        case 0:  "So every hem lands where it should."
        case 1:  "The one you reach for. Change it any time."
        default: "Mira hangs each piece to your height and cuts it to your size."
        }
    }

    // MARK: the control

    @ViewBuilder private var control: some View {
        switch beat {
        case 0:
            VStack(spacing: 16) {
                HStack(alignment: .lastTextBaseline, spacing: 7) {
                    Text("\(Int(height))").font(M.display(64, .light)).foregroundStyle(M.ink)
                    Text("cm").tracked(11, 2.4).foregroundStyle(M.mute)
                }
                Slider(value: $height, in: 140...200, step: 1)
                    .tint(M.rose)
                    .onChange(of: Int(height)) { tap() }
                HStack {
                    Text("140").tracked(8, 1.4).foregroundStyle(M.mute.opacity(0.6))
                    Spacer()
                    Text("200").tracked(8, 1.4).foregroundStyle(M.mute.opacity(0.6))
                }
            }
            .padding(.horizontal, 34)

        case 1:
            // the same chips as the mirror's size row
            HStack(spacing: 8) {
                ForEach(Size.allCases) { s in
                    let on = size == s
                    Text(s.rawValue)
                        .font(.system(size: 12, weight: .bold))
                        .kerning(0.6)
                        .foregroundStyle(on ? M.onRose : M.ink.opacity(0.7))
                        .frame(width: 52, height: 38)
                        .background(Capsule().fill(on ? M.rose : M.blush))
                        .onTapGesture {
                            tap()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { size = s }
                        }
                }
            }

        default:
            VStack(spacing: 0) {
                row("Height", "\(Int(height)) cm")
                Rectangle().fill(M.shell).frame(height: 1)
                row("Usual size", size.rawValue)
            }
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(M.shell, lineWidth: 1))
            .padding(.horizontal, 34)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).tracked(9, 1.8).foregroundStyle(M.mute)
            Spacer()
            Text(value).font(M.display(24)).foregroundStyle(M.ink)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 17)
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i == beat ? M.rose : M.shell)
                    .frame(width: i == beat ? 20 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: beat)
    }

    // MARK: moves

    private func next() {
        guard beat == 2 else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { beat += 1 }
            return
        }
        fits.fit = Fit(height: Int(height), size: size, done: true)
        done()
    }

    // ponytail: skipping keeps the fit-model default (scale 1) rather than asking again.
    private func skip() {
        fits.fit.done = true
        done()
    }
}
