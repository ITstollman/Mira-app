import SwiftUI

/// Two different questions wear the same word. "What have I got?" is a rail of clothes,
/// and it belongs in the closet. "What have I kept?" is a shelf of photographs, and it
/// belongs on the home screen. This is the first one, and the filing for the second.
// ponytail: derived, not stored. The Vault already keeps a piece for every kept look, so
// a second list on disk would only be somewhere for the two to disagree.
enum Wardrobe {
    /// Everything you can put back on: what you brought in this session, and the piece
    /// behind every look you kept. One row per piece however many times it was worn.
    static func pieces(_ studio: Studio) -> [Garment] {
        var seen = Set<String>()
        return (studio.mine + studio.looks.map(\.garment)).filter { seen.insert($0.id).inserted }
    }

    /// The kept looks, filed under the piece each one is of — newest piece first, newest
    /// look first inside it. Photographs and clips together: what you were wearing is
    /// what they have in common, not what kind of file they are.
    /// ponytail: `looks` arrives newest-first, so first-seen order is already date order.
    static func shelves(_ looks: [Look]) -> [(garment: Garment, looks: [Look])] {
        var order: [String] = []
        var by: [String: [Look]] = [:]
        for l in looks {
            if by[l.garment.id] == nil { order.append(l.garment.id) }
            by[l.garment.id, default: []].append(l)
        }
        return order.compactMap { id in
            guard let group = by[id], let g = group.first?.garment else { return nil }
            return (g, group)
        }
    }
}

/// One piece on its hanger: the product shot where we have one, the drawn silhouette
/// where we don't — the same recipe as everywhere else a garment stands in for itself.
struct PieceTile: View {
    let garment: Garment

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.white
                if garment.shot == nil {
                    // the outline is drawn to whatever frame it is handed, and this tile
                    // is wider than it is tall — padding alone gives a squat, wide dress
                    GarmentLayer(garment: garment).frame(width: 92, height: 130)
                } else {
                    // a product shot arrives cropped to the piece already
                    GarmentLayer(garment: garment).padding(12)
                }
            }
            .frame(height: 168)

            VStack(alignment: .leading, spacing: 3) {
                Text(garment.name).font(M.display(15)).foregroundStyle(M.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(garment.brand).tracked(7, 1.3).foregroundStyle(M.mute).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(M.shell, lineWidth: 1))
        .shadow(color: M.rouge.opacity(0.10), radius: 12, y: 6)
    }
}

/// The closet's fourth door: what you already own, one tap from being on you again.
/// Nothing you photographed is in here — the second time you wear something you are
/// looking for the thing, not the picture of it.
struct PiecesSheet: View {
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss
    /// Puts it on. The closet closes behind it, and this sheet goes with the closet.
    let wear: (Garment) -> Void

    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            M.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    VStack(spacing: 8) {
                        Text("Your pieces").font(M.display(30, .light)).foregroundStyle(M.ink)
                        Text("tap one to wear it again").tracked(9, 1.8).foregroundStyle(M.mute)
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
                    LazyVGrid(columns: cols, spacing: 16) {
                        ForEach(Wardrobe.pieces(studio)) { g in
                            Button { tap(); wear(g) } label: { PieceTile(garment: g) }
                                .buttonStyle(Squish())
                                .accessibilityLabel("Wear \(g.name) again")
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
                    .padding(.bottom, 40)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
