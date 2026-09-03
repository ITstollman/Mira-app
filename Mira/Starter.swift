import SwiftUI

/// Ten pieces on the house, for the one screen where somebody has nothing of their own
/// yet: the first fifteen seconds. Shooting a garment or pasting a link before you have
/// seen the thing work is a lot to ask of a stranger — this is one tap instead.
///
// ponytail: bundled art, not the server's catalog. They exist to make the trial
// one-tap; if the real catalog ever ships to the app, this file goes away.
enum Starter {
    /// The reference the mirror copies, straight out of the asset catalog.
    /// ponytail: re-encoded on pick, not held — one piece is worn at a time and the
    /// alternative is 800KB of JPEG resident for a screen most people see once.
    static func wearable(_ g: Garment) -> Garment {
        var piece = g
        piece.shot = UIImage(named: g.id)?.jpegData(compressionQuality: 0.9)
        return piece
    }

    /// `id` doubles as the asset name — one string, so a rename can't half-happen.
    static let all: [Garment] = [
        .init(id: "Outfit01", name: "Cream Suit", brand: "Mira", price: 0, cut: .blazer,
              tint: Color(red: 0.945, green: 0.925, blue: 0.878), category: .sets,
              prompt: "Substitute the outfit with a cream double-breasted trouser suit: a structured ivory blazer over a matching camisole, with high-waisted wide-leg trousers in a smooth crepe."),
        .init(id: "Outfit02", name: "Leather Edge", brand: "Mira", price: 0, cut: .blazer,
              tint: Color(red: 0.145, green: 0.137, blue: 0.145), category: .sets,
              prompt: "Substitute the outfit with a black moto look: a cropped distressed leather biker jacket over a graphic tee, with ripped black skinny jeans and chunky black lace-up boots."),
        .init(id: "Outfit03", name: "Liquid Silver", brand: "Mira", price: 0, cut: .skirt,
              tint: Color(red: 0.788, green: 0.804, blue: 0.831), category: .sets,
              prompt: "Substitute the outfit with a liquid-silver sculptural look: a metallic foil trench coat with exaggerated shoulders over a pleated silver midi skirt, with silver knee boots."),
        .init(id: "Outfit04", name: "Terracotta", brand: "Mira", price: 0, cut: .slip,
              tint: Color(red: 0.729, green: 0.322, blue: 0.180), category: .dresses,
              prompt: "Substitute the outfit with a terracotta bohemian maxi dress in crinkled rust cotton, with wide bell sleeves, tiered broderie panels, a braided leather belt and suede ankle boots."),
        .init(id: "Outfit05", name: "Y2K Chrome", brand: "Mira", price: 0, cut: .mini,
              tint: Color(red: 0.867, green: 0.780, blue: 0.882), category: .sets,
              prompt: "Substitute the outfit with a holographic Y2K set: an iridescent pastel cropped puffer jacket over a pleated baby-pink mini skirt, with white platform boots."),
        .init(id: "Outfit06", name: "Emerald Satin", brand: "Mira", price: 0, cut: .slip,
              tint: Color(red: 0.043, green: 0.353, blue: 0.259), category: .dresses,
              prompt: "Substitute the outfit with an emerald green silk-satin cowl-neck slip dress worn under a long ivory wool coat, with strappy nude heels."),
        .init(id: "Outfit07", name: "Cyber Suit", brand: "Mira", price: 0, cut: .bodysuit,
              tint: Color(red: 0.788, green: 0.937, blue: 0.169), category: .sets,
              prompt: "Substitute the outfit with a neon lime technical jumpsuit with reflective taped panels, utility buckles and cargo pockets, worn with black combat boots."),
        .init(id: "Outfit08", name: "Sand Street", brand: "Mira", price: 0, cut: .blazer,
              tint: Color(red: 0.831, green: 0.769, blue: 0.671), category: .sets,
              prompt: "Substitute the outfit with beige streetwear: an oversized sand hoodie with baggy cargo trousers, a small crossbody sling bag and cream chunky sneakers."),
        .init(id: "Outfit09", name: "Red Carpet", brand: "Mira", price: 0, cut: .slip,
              tint: Color(red: 0.780, green: 0.098, blue: 0.129), category: .dresses,
              prompt: "Substitute the outfit with a scarlet avant-garde gown: one-shouldered, in heavy silk taffeta, with a sculpted draped bodice and a long cascading ruffled train."),
        .init(id: "Outfit10", name: "Cottage Cool", brand: "Mira", price: 0, cut: .corset,
              tint: Color(red: 0.784, green: 0.639, blue: 0.443), category: .sets,
              prompt: "Substitute the outfit with a cottagecore look: a white puff-sleeve blouse under an embroidered tan corset, with tailored camel shorts, white knee socks and flat shoes."),
    ]
}

/// The rail of them. Lives at the top of the closet during the trial, above the three
/// doors — for somebody with an empty closet it is the only one that opens in one tap.
struct StarterRail: View {
    let wear: (Garment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tap one to try it on").tracked(9, 1.8).foregroundStyle(M.mute)
                .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Starter.all) { g in
                        Button { wear(Starter.wearable(g)) } label: {
                            Image(g.id)
                                .resizable().scaledToFit()
                                .frame(width: 88, height: 132)
                                .background(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .shadow(color: M.rouge.opacity(0.13), radius: 12, y: 5)
                        }
                        .buttonStyle(Squish())
                        .accessibilityLabel(g.name)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)      // room for the cards' own shadows
            }
        }
    }
}
