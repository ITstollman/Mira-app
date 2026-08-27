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
