import SwiftUI

struct Garment: Identifiable, Hashable {
    let id: String
    let name: String
    let brand: String
    let price: Int
    let cut: Cut
    let tint: Color
    let category: Category
    /// What Decart is told to put on you. The whole try-on rides on this sentence.
    let prompt: String
    /// The real product shot, when there is one. Scraped garments have it; house pieces don't.
    var shot: Data? = nil
    var link: String? = nil

    enum Category: String, CaseIterable {
        case all = "All", dresses = "Dresses", tops = "Tops", sets = "Sets"
        case bottoms = "Bottoms", shoes = "Shoes", accessories = "Extras"
    }
    enum Cut { case slip, mini, corset, blazer, skirt, bodysuit }

    var isMine: Bool { link != nil }
}

// in an extension so the memberwise init survives — the catalog below leans on it
extension Garment {
    /// A piece off your camera roll. Same shape as a scraped one, minus the shop.
    init(photo: Data) {
        let id = UUID().uuidString
        self.init(id: id, name: "Your piece", brand: "From your photos", price: 0,
                  cut: .slip, tint: M.petal, category: .dresses,
                  prompt: "Substitute the outfit with the garment shown in the reference image, matching its cut, colour and fabric.",
                  shot: photo, link: "photos://\(id)")
    }

    init(scraped s: API.Scraped, shot: Data) {
        let category = Category(server: s.category)
        self.init(id: s.id,
                  name: s.name?.trimmed ?? "Untitled",
                  brand: s.brand?.trimmed ?? URL(string: s.source)?.host() ?? "The internet",
                  price: s.price ?? 0,
                  cut: category.cut,
                  tint: M.petal,
                  category: category,
                  prompt: s.prompt,
                  shot: shot,
                  link: s.source)
    }
}

extension Garment.Category {
    /// The server speaks lowercase slugs; `all` is a filter, never a garment.
    init(server: String) {
        switch server.lowercased() {
        case "dresses":     self = .dresses
        case "sets":        self = .sets
        case "bottoms":     self = .bottoms
        case "shoes":       self = .shoes
        case "accessories": self = .accessories
        // ponytail: an unrecognised slug lands on tops. Only the shelf it sits on is
        // wrong — the prompt still carries what the garment actually is.
        default:            self = .tops
        }
    }

    /// The placeholder outline for a garment with no photo of its own.
    var cut: Garment.Cut {
        switch self {
        case .dresses: .slip
        case .bottoms: .skirt
        case .sets:    .bodysuit
        default:       .corset
        }
    }
}

enum Size: String, CaseIterable, Identifiable {
    case xs = "XS", s = "S", m = "M", l = "L", xl = "XL"
    var id: String { rawValue }
    /// Fit preview scale — the silhouette breathes with the size you pick.
    var scale: CGFloat { [.xs: 0.90, .s: 0.96, .m: 1.0, .l: 1.06, .xl: 1.13][self] ?? 1 }
    /// How the size reads to the model. Mirrors `FIT` in server/server.js.
    var fit: String {
        switch self {
        case .xs: "a snug fit"
        case .s:  "a fitted cut"
        case .m:  "a true-to-size fit"
        case .l:  "a relaxed fit"
        case .xl: "an oversized fit"
        }
    }
}

// ponytail: hardcoded catalog, and the prompts are a second copy of the ones in
// server/catalog.json — the live mirror sends them straight to Decart from here,
// /v1/look reads them there. One feed replaces both when the catalog is real.
enum Catalog {
    static let all: [Garment] = [
        .init(id: "g1", name: "Aphrodite Slip", brand: "Mira Atelier", price: 189, cut: .slip,
              tint: Color(red: 0.886, green: 0.337, blue: 0.431), category: .dresses,
              prompt: "Substitute the outfit with a raspberry pink silk-satin slip dress, bias cut, midi length, with thin spaghetti straps, a straight neckline and a fluid drape."),
        .init(id: "g2", name: "Champagne Hour", brand: "Lune", price: 240, cut: .slip,
              tint: Color(red: 0.910, green: 0.835, blue: 0.737), category: .dresses,
              prompt: "Substitute the outfit with a champagne beige satin slip dress, bias cut, ankle length, with delicate thin straps, a cowl neckline and a soft liquid sheen."),
        .init(id: "g3", name: "Sugar Mini", brand: "Saint Rose", price: 145, cut: .mini,
              tint: Color(red: 0.949, green: 0.663, blue: 0.737), category: .dresses,
              prompt: "Substitute the outfit with a soft pink mini dress, fitted through the bodice with a slight A-line skirt, thin straps and a straight neckline."),
        .init(id: "g4", name: "Cherry Corset", brand: "Velvet Hour", price: 165, cut: .corset,
              tint: Color(red: 0.753, green: 0.161, blue: 0.247), category: .tops,
              prompt: "Substitute the upper body garment with a deep cherry red structured corset top, strapless, with visible boning seams, a sweetheart neckline and a cropped hem."),
        .init(id: "g5", name: "Milk Corset", brand: "Mira Atelier", price: 158, cut: .corset,
              tint: Color(red: 0.969, green: 0.945, blue: 0.941), category: .tops,
              prompt: "Substitute the upper body garment with an off-white milky corset top, strapless, with vertical boning seams, a straight neckline and a cropped fitted hem."),
        .init(id: "g6", name: "Noir Blazer", brand: "Lune", price: 320, cut: .blazer,
              tint: Color(red: 0.169, green: 0.145, blue: 0.161), category: .sets,
              prompt: "Substitute the upper body garment with a black tailored wool blazer worn open, with notch lapels, structured shoulders, long sleeves and two front flap pockets."),
        .init(id: "g7", name: "Rose Rouge", brand: "Saint Rose", price: 132, cut: .skirt,
              tint: Color(red: 0.851, green: 0.310, blue: 0.447), category: .bottoms,
              prompt: "Substitute the lower body garment with a rose pink A-line midi skirt, high waisted, in a soft matte fabric with a smooth flared drape."),
        .init(id: "g8", name: "Halo Bodysuit", brand: "Velvet Hour", price: 118, cut: .bodysuit,
              tint: Color(red: 0.788, green: 0.655, blue: 0.863), category: .tops,
              prompt: "Substitute the upper body garment with a pale lilac fitted bodysuit in a smooth stretch knit, with thin straps, a scoop neckline and a sleek second-skin fit."),
        .init(id: "g9", name: "Ballet Slip", brand: "Lune", price: 210, cut: .slip,
              tint: Color(red: 0.953, green: 0.780, blue: 0.812), category: .dresses,
              prompt: "Substitute the outfit with a ballet pink silk slip dress, bias cut, midi length, with thin straps, a soft V neckline and a delicate lace trim at the bust."),
        .init(id: "g10", name: "Midnight Mini", brand: "Mira Atelier", price: 199, cut: .mini,
              tint: Color(red: 0.231, green: 0.165, blue: 0.333), category: .dresses,
              prompt: "Substitute the outfit with a deep midnight purple mini dress, fitted through the body, with thin straps, a square neckline and a short straight hem."),
        .init(id: "g11", name: "Peach Set", brand: "Saint Rose", price: 176, cut: .bodysuit,
              tint: Color(red: 0.941, green: 0.631, blue: 0.518), category: .sets,
              prompt: "Substitute the outfit with a peach orange matching two piece set, a fitted cropped top with thin straps and a high waisted skirt in the same ribbed knit fabric."),
        .init(id: "g12", name: "Silk Pencil", brand: "Velvet Hour", price: 154, cut: .skirt,
              tint: Color(red: 0.663, green: 0.635, blue: 0.808), category: .bottoms,
              prompt: "Substitute the lower body garment with a periwinkle blue silk pencil skirt, high waisted, knee length, with a straight narrow silhouette and a back slit."),
    ]
}

private extension String {
    var trimmed: String? {
        let s = trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}

/// One parametric garment outline. Same builder, six specs.
struct Silhouette: Shape {
    var cut: Garment.Cut

    struct Spec { var top, hem, bust, waist, flare, dip, hemCurve: CGFloat; var straps: Bool }

    static func spec(_ c: Garment.Cut) -> Spec {
        switch c {
        case .slip:     return .init(top: 0.18, hem: 0.97, bust: 0.200, waist: 0.175, flare: 0.300, dip: 0.045, hemCurve:  0.030, straps: true)
        case .mini:     return .init(top: 0.17, hem: 0.62, bust: 0.210, waist: 0.180, flare: 0.285, dip: 0.040, hemCurve:  0.028, straps: true)
        case .corset:   return .init(top: 0.20, hem: 0.54, bust: 0.245, waist: 0.160, flare: 0.185, dip: 0.055, hemCurve:  0.022, straps: false)
        case .blazer:   return .init(top: 0.10, hem: 0.68, bust: 0.270, waist: 0.215, flare: 0.245, dip: 0.150, hemCurve:  0.020, straps: false)
        case .skirt:    return .init(top: 0.36, hem: 0.82, bust: 0.185, waist: 0.185, flare: 0.320, dip: 0.000, hemCurve:  0.030, straps: false)
        case .bodysuit: return .init(top: 0.17, hem: 0.60, bust: 0.210, waist: 0.175, flare: 0.180, dip: 0.052, hemCurve: -0.075, straps: true)
        }
    }

    func path(in r: CGRect) -> Path {
        let s = Silhouette.spec(cut)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
        }
        let top = s.top, hem = s.hem
        let waistY = top + (hem - top) * 0.42
        let upper = waistY - top, lower = hem - waistY

        var p = Path()
        p.move(to: pt(0.5 - s.bust, top))
        p.addQuadCurve(to: pt(0.5 + s.bust, top), control: pt(0.5, top + s.dip * 2))
        p.addCurve(to: pt(0.5 + s.waist, waistY),
                   control1: pt(0.5 + s.bust + 0.012, top + upper * 0.40),
                   control2: pt(0.5 + s.waist, waistY - upper * 0.35))
        p.addCurve(to: pt(0.5 + s.flare, hem),
                   control1: pt(0.5 + s.waist + 0.006, waistY + lower * 0.30),
                   control2: pt(0.5 + s.flare * 0.92, hem - lower * 0.25))
        p.addQuadCurve(to: pt(0.5 - s.flare, hem), control: pt(0.5, hem + s.hemCurve))
        p.addCurve(to: pt(0.5 - s.waist, waistY),
                   control1: pt(0.5 - s.flare * 0.92, hem - lower * 0.25),
                   control2: pt(0.5 - s.waist - 0.006, waistY + lower * 0.30))
        p.addCurve(to: pt(0.5 - s.bust, top),
                   control1: pt(0.5 - s.waist, waistY - upper * 0.35),
                   control2: pt(0.5 - s.bust - 0.012, top + upper * 0.40))
        p.closeSubpath()

        if s.straps {
            for sign in [CGFloat(-1), CGFloat(1)] {
                var st = Path()
                st.move(to: pt(0.5 + sign * (s.bust - 0.060), 0))
                st.addQuadCurve(to: pt(0.5 + sign * (s.bust - 0.010), top),
                                control: pt(0.5 + sign * (s.bust - 0.050), top * 0.55))
                st.addLine(to: pt(0.5 + sign * (s.bust + 0.018), top))
                st.addQuadCurve(to: pt(0.5 + sign * (s.bust - 0.032), 0),
                                control: pt(0.5 + sign * (s.bust - 0.022), top * 0.55))
                st.closeSubpath()
                p.addPath(st)
            }
        }
        return p
    }
}

/// The garment as it hangs on you. Flat fill, white hairline, soft separation shadow.

/// The garment as it hangs on you: the real product shot when we scraped one,
/// otherwise the parametric outline — flat fill, white hairline, soft separation shadow.
struct GarmentLayer: View {
    let garment: Garment
    var scale: CGFloat = 1

    var body: some View {
        Group {
            if let shot = garment.shot, let img = UIImage(data: shot) {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                Silhouette(cut: garment.cut)
                    .fill(garment.tint)
                    .overlay {
                        Silhouette(cut: garment.cut).stroke(.white.opacity(0.85), lineWidth: 1.4)
                    }
            }
        }
        .compositingGroup()
        .shadow(color: M.rouge.opacity(0.22), radius: 16, y: 9)
        .scaleEffect(scale)
    }
}
