import PhotosUI
import SwiftUI

struct ClosetSheet: View {
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss
    @State private var linking = false
    @State private var photo: PhotosPickerItem?
    /// Opens half-height: a live session bills by the second, and burying the reflection
    /// and its countdown under a full-screen browser is how someone loses minutes without
    /// seeing it happen. Drag up for the whole wardrobe.
    @State private var height: PresentationDetent = .medium

    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    /// Yours first, then the house. No filters, no size rail: this screen is two ways in
    /// and everything you have already brought through them.
    private var pieces: [Garment] { studio.mine + Catalog.all }

    var body: some View {
        ZStack {
            M.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    VStack(spacing: 8) {
                        Text("The Closet").font(M.display(30, .light)).foregroundStyle(M.ink)
                        Text("\(pieces.count) pieces ready to wear")
                            .tracked(9, 1.8).foregroundStyle(M.mute)
                    }
                    // the way out that isn't picking something. The swipe works too, but the
                    // meter may be running behind this and a gesture is a bad only-option.
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
                        PhotosPicker(selection: $photo, matching: .images) {
                            WayCard(icon: "photo.on.rectangle.angled",
                                    action: "Your photos", from: "off your camera roll")
                        }
                        .buttonStyle(.plain)

                        WayCard(icon: "link", action: "Paste a link", from: "from any shop", shops: true)
                            .onTapGesture { tap(); linking = true }

                        ForEach(pieces) { g in
                            GarmentCard(garment: g, on: studio.wearing?.id == g.id)
                                .onTapGesture {
                                    studio.wear(g)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { dismiss() }
                                }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $height)
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        // a piece off the roll goes straight on, same as a pasted one
        .onChange(of: photo) { _, item in Task { await load(item) } }
        // pasted piece goes straight on, so get out of the way and let them see it
        .sheet(isPresented: $linking, onDismiss: { if studio.wearing?.isMine == true { dismiss() } }) {
            LinkSheet()
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        studio.add(Garment(photo: data))
        photo = nil
        dismiss()
    }
}

/// The two ways a piece gets in here. Same card, different door.
struct WayCard: View {
    let icon: String
    let action: String
    let from: String
    /// Names the shops instead of leaving "any shop" to be taken on faith.
    var shops = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(M.blush)
            VStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 24, weight: .light)).foregroundStyle(M.rose)
                Text(action).tracked(10, 1.6).foregroundStyle(M.ink)
                Text(from).tracked(8, 1.2).foregroundStyle(M.mute)
                    .multilineTextAlignment(.center)
                if shops { BrandRow(tile: 36, columns: 3, gap: 6).padding(.top, 4) }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 208)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(M.petal, style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(action)
        .accessibilityAddTraits(.isButton)
    }
}

struct GarmentCard: View {
    @Environment(Studio.self) private var studio
    let garment: Garment
    let on: Bool

    private var isLoved: Bool { studio.loved.contains(garment.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white)
                GarmentLayer(garment: garment)
                    .frame(width: 94, height: 148)

                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isLoved ? "heart.fill" : "heart")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isLoved ? M.rose : M.mute.opacity(0.55))
                            .padding(9)
                            .background(Circle().fill(M.blush))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .onTapGesture { studio.love(garment) }
                            .accessibilityLabel(isLoved ? "Unsave" : "Save")
                    }
                    Spacer()
                }
                .padding(4)
            }
            .frame(height: 208)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(on ? M.rose : M.shell, lineWidth: on ? 1.8 : 1)
            )
            .shadow(color: M.rouge.opacity(0.10), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(garment.name).font(M.display(16)).foregroundStyle(M.ink).lineLimit(1)
                Text("\(garment.brand)  ·  $\(garment.price)").tracked(8, 1.2).foregroundStyle(M.mute)
            }
            .padding(.top, 10)
            .padding(.horizontal, 4)
        }
    }
}
