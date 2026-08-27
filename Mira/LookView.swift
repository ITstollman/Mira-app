import SwiftUI

/// The moment after the shutter: you, wearing it.
struct LookView: View {
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss
    let look: Look
    @State private var kept = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if let img = look.shot {
                Image(uiImage: img).resizable().scaledToFill().ignoresSafeArea()
            } else {
                MirrorFallback()
            }

            GeometryReader { g in
                let feed = g.size.height - 230
                GarmentLayer(garment: look.garment, scale: look.size.scale)
                    .frame(width: g.size.width * 0.60, height: feed * 0.78)
                    .position(x: g.size.width / 2, y: feed * 0.60)
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button { tap(); dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(M.ink).puck(40)
                    }
                    .accessibilityLabel("Close")
                    Spacer()
                    Text("Your look").tracked(9, 2.4).foregroundStyle(M.ink)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(.white))
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                Spacer()
            }

            VStack(spacing: 14) {
                VStack(spacing: 5) {
                    Text(look.garment.name).font(M.display(28, .light)).foregroundStyle(M.ink)
                    Text("\(look.garment.brand)  ·  $\(look.garment.price)  ·  Size \(look.size.rawValue)")
                        .tracked(9, 1.8).foregroundStyle(M.mute)
                }

                Button {
                    guard !kept else { return }
                    studio.keep(look)
                    withAnimation(.spring) { kept = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { dismiss() }
                } label: {
                    HStack(spacing: 8) {
                        if kept { Image(systemName: "heart.fill").font(.system(size: 13)) }
                        Text(kept ? "Kept" : "Keep this look").tracked(11, 2.4)
                    }
                    .foregroundStyle(M.onRose)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Capsule().fill(M.rose))
                }

                HStack(spacing: 10) {
                    Button { tap(); dismiss() } label: {
                        Text("Discard").tracked(10, 2)
                            .foregroundStyle(M.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Capsule().fill(M.blush))
                    }
                    if let img = look.shot {
                        ShareLink(item: Image(uiImage: img),
                                  preview: SharePreview(look.garment.name, image: Image(uiImage: img))) {
                            Text("Share").tracked(10, 2)
                                .foregroundStyle(M.ink)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Capsule().fill(M.blush))
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34, style: .continuous)
                    .fill(M.cream)
                    .shadow(color: M.rouge.opacity(0.18), radius: 24, y: -8)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .background(M.cream)
    }
}

struct LookbookView: View {
    @Environment(Studio.self) private var studio
    @State private var open: Look?
    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            M.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("Lookbook").font(M.display(30, .light)).foregroundStyle(M.ink)
                    Text(studio.looks.isEmpty ? "Nothing kept yet" : "\(studio.looks.count) looks")
                        .tracked(9, 1.8).foregroundStyle(M.mute)
                }
                .padding(.top, 26)
                .padding(.bottom, 22)

                if studio.looks.isEmpty {
                    Spacer()
                    VStack(spacing: 18) {
                        Silhouette(cut: .slip)
                            .stroke(M.rose.opacity(0.35), style: .init(lineWidth: 1.2, dash: [4, 5]))
                            .frame(width: 110, height: 190)
                        Text("Try something on, hit the shutter,\nand it lands here.")
                            .multilineTextAlignment(.center)
                            .font(.system(size: 13))
                            .foregroundStyle(M.mute)
                    }
                    Spacer()
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: cols, spacing: 16) {
                            ForEach(studio.looks) { l in
                                LookCard(look: l).onTapGesture { tap(); open = l }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .fullScreenCover(item: $open) { LookView(look: $0) }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }
}

struct LookCard: View {
    let look: Look

    var body: some View {
        ZStack {
            if let img = look.shot {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                M.blush
            }
            GeometryReader { g in
                GarmentLayer(garment: look.garment, scale: look.size.scale)
                    .frame(width: g.size.width * 0.58, height: g.size.height * 0.62)
                    .position(x: g.size.width / 2, y: g.size.height * 0.42)
            }
            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(look.garment.name).font(M.display(14)).foregroundStyle(M.ink)
                        Text("Size \(look.size.rawValue)").tracked(8, 1.2).foregroundStyle(M.mute)
                    }
                    Spacer()
                }
                .padding(12)
                .background(.white.opacity(0.92))
            }
        }
        .frame(height: 238)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(M.shell, lineWidth: 1))
        .shadow(color: M.rouge.opacity(0.10), radius: 12, y: 6)
    }
}
