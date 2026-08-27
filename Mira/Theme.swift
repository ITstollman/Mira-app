import SwiftUI

/// Straight off the mark. Flat fills only — no gradients anywhere in Mira.
enum M {
    static let rose  = Color(red: 0.984, green: 0.498, blue: 0.624)  // #FB7F9F  primary
    static let rouge = Color(red: 0.902, green: 0.200, blue: 0.373)  // #E6335F  pressed, shadows
    static let petal = Color(red: 0.906, green: 0.639, blue: 0.675)  // #E7A3AC  the frame
    static let blush = Color(red: 0.969, green: 0.902, blue: 0.914)  // #F7E6E9  soft fill
    static let shell = Color(red: 0.937, green: 0.847, blue: 0.863)  // #EFD8DC  hairlines
    static let cream = Color(red: 0.988, green: 0.961, blue: 0.965)  // #FCF5F6  paper
    static let ink   = Color(red: 0.227, green: 0.129, blue: 0.161)  // #3A2129  type
    /// What sits on top of a rose fill. Ink, not white: #FB7F9F is light enough that
    /// white type measures 2.43:1 on it and ink measures 6.04:1. Change it here, not
    /// at the sixteen call sites.
    static let onRose = ink

    /// The little rounded square the brand marks and their overflow tile share, so
    /// clip, border and fill can never drift apart.
    static let tile = RoundedRectangle(cornerRadius: 12, style: .continuous)

    static let mute  = Color(red: 0.541, green: 0.424, blue: 0.455)  // #8A6C74  subtype

    static func display(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: scaled(size), weight: weight, design: .serif)
    }

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: scaled(size), weight: weight)
    }

    /// Every point size in the app goes through here, so the whole thing moves
    /// with the system text-size setting. Clamped at AX2 in MiraApp.
    static func scaled(_ size: CGFloat) -> CGFloat {
        UIFontMetrics(forTextStyle: .body).scaledValue(for: size)
    }
}

extension View {
    func tracked(_ size: CGFloat = 11, _ kern: CGFloat = 2.4) -> some View {
        font(M.ui(size, .semibold))
            .textCase(.uppercase)
            .kerning(kern)
    }

    /// The only button chrome in the app: a flat puck, white unless it is the one thing
    /// on screen worth pressing.
    func puck(_ d: CGFloat = 44, fill: Color = .white) -> some View {
        frame(width: d, height: d)
            .background(Circle().fill(fill))
            .shadow(color: M.rouge.opacity(0.14), radius: 10, y: 4)
            .frame(width: max(d, 44), height: max(d, 44))   // hit area only; the visible puck stays at d
            .contentShape(Circle())
    }
}

/// The mark: an organic raspberry blob with a white m.
struct Blob: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        let base = min(r.width, r.height) / 2
        let steps = 96
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps) * .pi * 2
            let rad = base * (0.90 + 0.055 * sin(3 * t + 0.7) + 0.035 * cos(5 * t + 2.1))
            let pt = CGPoint(x: c.x + cos(t) * rad, y: c.y + sin(t) * rad)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}

// The logo is Logo.imageset — the candy-gloss M, its three sparkles, AND the soft
// pink-white plate they sit on, straight off Brand/top-left-sparkle.png. Only the
// screenshot's grey corners were cut, so what ships is the artwork the plate and
// all. The drawn blob+m below is the fallback if the asset ever goes missing — it
// is not dead code, it is what ships if the art does not.
// ponytail: the source art is 402x422, so this is a 1.6x Lanczos upscale. It holds
// because the art is smooth gloss with no texture. Re-render if we get the scene back.
struct MiraMark: View {
    var size: CGFloat = 88
    var sparkles = true

    private static let art = UIImage(named: "Logo") != nil

    var body: some View {
        ZStack {
            if sparkles && !Self.art {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i.isMultiple(of: 2) ? M.rose : M.petal)
                        .frame(width: size * 0.14, height: size * 0.058)
                        .rotationEffect(.degrees([-24.0, 18.0, 26.0, -12.0][i]))
                        .offset(x: [-0.54, 0.56, -0.48, 0.52][i] * size,
                                y: [-0.34, -0.42, 0.40, 0.36][i] * size)
                }
            }
            if Self.art {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Blob()
                    .fill(M.rose)
                    .shadow(color: M.rouge.opacity(0.22), radius: size * 0.12, y: size * 0.05)
                Text("m")
                    .font(.system(size: size * 0.56, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .offset(y: size * 0.02)
            }
        }
        .frame(width: size, height: size)
    }
}

func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

// ponytail: screenshot/dev switches, no effect unless launched with the flag.
enum Dev {
    static func has(_ flag: String) -> Bool { ProcessInfo.processInfo.arguments.contains(flag) }
}
