import Photos
import SwiftUI

/// One look from the lookbook, full bleed. Nothing here asks whether to save it — the
/// shutter already did that — so the whole footer is what you do with it afterwards.
struct LookView: View {
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss
    let look: Look

    /// The footer folds away, because a clip of yourself is the point of the screen and
    /// a third of it was a card with four buttons on it.
    @State private var open = true
    @State private var saving = false
    @State private var saved = false
    @State private var refused = false

    private var loved: Bool { studio.loved.contains(look.garment.id) }
    /// Nothing to put in the roll or the share sheet when the mirror never rendered one.
    private var has: Bool { look.film != nil || look.shot != nil }

    private var preview: SharePreview<Image, Never> {
        SharePreview(look.garment.name, image: Image(uiImage: look.shot ?? UIImage()))
    }

    private var share: some View {
        Text("Share").tracked(11, 2.4)
            .foregroundStyle(M.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Capsule().fill(M.blush))
    }

    private var keepLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: saved ? "checkmark" : "arrow.down.to.line")
                .font(.system(size: 13, weight: .semibold))
            Text(saved ? "Saved" : "Save").tracked(11, 2.4)
        }
        .foregroundStyle(M.onRose)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 17)
        .background(Capsule().fill(M.rose))
        .opacity(saving ? 0.55 : 1)
    }

    /// One tap to the camera roll — the share sheet's "Save Video" was three.
    private func keep() {
        guard !saving, !saved else { return }
        tap()
        saving = true
        Task {
            let ok = await Album.add(look)
            saving = false
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { saved = ok }
            refused = !ok
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // The photograph already has the garment on you — the mirror rendered it there.
            // Drawing the reference over the top of that covered the wearer with a flat
            // dress, so the silhouette is what stands in when there is no photograph, and
            // nothing else.
            if let film = look.film {
                Player(url: film).ignoresSafeArea()
            } else if let img = look.shot {
                // clamped, then clipped: scaledToFill reports the overflowing size, and a
                // ZStack sizes to its biggest child — so an unclamped photograph pushed the
                // name and the three buttons out past both edges of the phone
                Color.clear
                    .overlay { Image(uiImage: img).resizable().scaledToFill() }
                    .clipped()
                    .ignoresSafeArea()
            } else {
                MirrorFallback()
                GeometryReader { g in
                    let feed = g.size.height - 230
                    GarmentLayer(garment: look.garment, scale: look.size.scale)
                        .frame(width: g.size.width * 0.60, height: feed * 0.78)
                        .position(x: g.size.width / 2, y: feed * 0.60)
                }
                .ignoresSafeArea()
            }

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

            if !open {
                Button { tap(); fold(true) } label: {
                    Image(systemName: "chevron.up").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(M.ink).puck(40)
                }
                .accessibilityLabel("Show the buttons")
                .padding(.bottom, 18)
                .transition(.scale.combined(with: .opacity))
            }

            if open {
            VStack(spacing: 14) {
                Button { tap(); fold(false) } label: {
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(M.mute)
                        .frame(maxWidth: .infinity)          // the whole strip is the target
                        .contentShape(.rect)
                }
                .accessibilityLabel("Hide the buttons")

                // Just the name. The price under it was $0 on everything but the twelve
                // demo pieces — your own photographs and the starter outfits have no
                // price — and a size on a picture of yourself reads like a receipt.
                Text(look.garment.name).font(M.display(28, .light)).foregroundStyle(M.ink)

                // A clip shared as its poster frame is a photograph, which is not what
                // anybody meant by sharing it. The file goes; the frame is the preview.
                if has {
                    HStack(spacing: 10) {
                        Button { keep() } label: { keepLabel }
                            .accessibilityLabel(saved ? "Saved to your photos" : "Save to your photos")
                        if let film = look.film {
                            ShareLink(item: film, preview: preview) { share }
                        } else if let img = look.shot {
                            ShareLink(item: Image(uiImage: img), preview: preview) { share }
                        }
                    }
                }

                HStack(spacing: 10) {
                    // the heart is on the piece, not the photograph — Profile counts
                    // pieces loved, and this is the only place that can still add one
                    Button { studio.love(look.garment) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: loved ? "heart.fill" : "heart").font(.system(size: 13))
                            Text(loved ? "Loved" : "Love").tracked(10, 2)
                        }
                        .foregroundStyle(loved ? M.rouge : M.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Capsule().fill(M.blush))
                    }
                    .accessibilityLabel(loved ? "Unlove \(look.garment.name)" : "Love \(look.garment.name)")

                    Button { studio.drop(look); dismiss() } label: {
                        Text("Delete").tracked(10, 2)
                            .foregroundStyle(M.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Capsule().fill(M.blush))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34, style: .continuous)
                    .fill(M.cream)
                    .shadow(color: M.rouge.opacity(0.18), radius: 24, y: -8)
                    .ignoresSafeArea(edges: .bottom)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(M.cream)
        .alert("Couldn't save that", isPresented: $refused) {
            Button("Open Settings") {
                URL(string: UIApplication.openSettingsURLString).map { UIApplication.shared.open($0) }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Mira needs permission to add to your photo library.")
        }
    }

    private func fold(_ show: Bool) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { open = show }
    }
}

/// One tap to the camera roll. Add-only, so iOS asks for the narrow permission and Mira
/// never gets to see the rest of somebody's library.
// ponytail: no album of our own. Photos already groups by day, and a "Mira" album is a
// second thing to keep in sync with the lookbook.
enum Album {
    static func add(_ look: Look) async -> Bool {
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized,
              look.film != nil || look.shot != nil else { return false }
        return await withCheckedContinuation { done in
            PHPhotoLibrary.shared().performChanges {
                // The clip, if there is one — saving its poster frame instead would hand
                // somebody a photograph when they asked for the video.
                if let film = look.film {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: film)
                } else if let shot = look.shot {
                    PHAssetChangeRequest.creationRequestForAsset(from: shot)
                }
            } completionHandler: { ok, _ in done.resume(returning: ok) }
        }
    }
}

struct LookCard: View {
    let look: Look
    /// What the plate at the foot says. The garment's name on its own; the date when
    /// the shelf above has already named the garment.
    var caption: String? = nil

    var body: some View {
        ZStack {
            if let img = look.shot {
                Color.clear
                    .overlay { Image(uiImage: img).resizable().scaledToFill() }
                    .clipped()
            } else {
                M.blush
                GeometryReader { g in
                    GarmentLayer(garment: look.garment, scale: look.size.scale)
                        .frame(width: g.size.width * 0.58, height: g.size.height * 0.62)
                        .position(x: g.size.width / 2, y: g.size.height * 0.42)
                }
            }
            if look.film != nil { PlayBadge(side: 34) }
            VStack {
                Spacer()
                HStack {
                    Text(caption ?? look.garment.name).font(M.display(14)).foregroundStyle(M.ink)
                    Spacer()
                }
                .padding(12)
                // opaque: at 92% the shot bleeds through and every caption plate
                // ends up a different colour
                .background(.white)
            }
        }
        .frame(height: 238)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(M.shell, lineWidth: 1))
        .shadow(color: M.rouge.opacity(0.10), radius: 12, y: 6)
    }
}
