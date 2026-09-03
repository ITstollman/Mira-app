import PhotosUI
import SwiftUI

struct ClosetSheet: View {
    /// The trial's ten on the house. Only the first fifteen seconds get them — after
    /// that the closet is yours, and a shelf of house pieces is somebody else's shop.
    let starter: Bool
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss
    @State private var linking = Dev.has("dev:link")
    @State private var photo: PhotosPickerItem?
    @State private var shooting = false
    @State private var history = Dev.has("dev:history")
    /// Everything you already own, deduped. The closet's fourth door opens onto this.
    private var pieces: [Garment] { Wardrobe.pieces(studio) }
    /// Opens just under two-thirds: a live session bills by the second, and burying the
    /// reflection and its countdown under a full-screen browser is how someone loses
    /// minutes without seeing it happen. Not .medium, though — three doors and the history
    /// don't fit in half a screen, and half of a card showing is worse than a shorter
    /// mirror. Drag up for the whole wardrobe.
    @State private var height: PresentationDetent
    private static let open: PresentationDetent = .fraction(0.58)
    /// The rail costs about a fifth of a screen, and a rail you have to drag up to see
    /// is not a one-tap start.
    private static let withRail: PresentationDetent = .fraction(0.72)

    init(starter: Bool = false) {
        self.starter = starter
        _height = State(initialValue: starter ? Self.withRail : Self.open)
    }

    var body: some View {
        ZStack {
            M.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    VStack(spacing: 8) {
                        Text("The Closet").font(M.display(30, .light)).foregroundStyle(M.ink)
                        // what is in here is clothes; the photographs are the home
                        // screen's, and counting them under this title read as a promise
                        // this sheet doesn't keep
                        Text(pieces.isEmpty ? "nothing of yours yet"
                                            : "\(pieces.count) ready to wear")
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
                .padding(.top, 20)
                .padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 16) {
                        // first, because it is the only door a stranger can walk through
                        // without going and finding something to put behind it
                        if starter {
                            StarterRail { g in
                                studio.wear(g)
                                dismiss()
                            }
                        }

                        // three ways in and one way back, one to a row and all the same
                        // card. Side by side they were half-empty boxes; stacked and
                        // uniform they read as a list of somewheres to go.
                        VStack(spacing: 12) {
                            // a piece you're holding never made it to the camera roll, and
                            // making someone shoot it in Camera and come back is two apps
                            // to do one thing. ponytail: hidden where there's no camera —
                            // Dev.jumping keeps it on screen for the screenshots.
                            if UIImagePickerController.isSourceTypeAvailable(.camera) || Dev.jumping {
                                WayCard(icon: "camera", action: "Take a photo",
                                        from: "shoot the piece itself")
                                    .onTapGesture {
                                        tap()
                                        shooting = UIImagePickerController.isSourceTypeAvailable(.camera)
                                    }
                            }

                            PhotosPicker(selection: $photo, matching: .images) {
                                WayCard(icon: "photo.on.rectangle.angled",
                                        action: "Your photos", from: "off your camera roll")
                            }
                            .buttonStyle(.plain)

                            WayCard(icon: "link", action: "Paste a link", from: "from any shop", shops: true)
                                .onTapGesture { tap(); linking = true }

                            // the fourth row, and the same row: three doors in and one
                            // back to what you already own. Clothes, not photographs —
                            // standing in front of a mirror you are looking for the thing
                            // to put on, and the pictures of yourself live on the home
                            // screen where there is room to look at them.
                            if !pieces.isEmpty {
                                WayCard(icon: "hanger", action: "Your pieces",
                                        from: "\(pieces.count) worn before")
                                    .onTapGesture { tap(); history = true }
                            }
                        }

                        // day one there is nothing kept, and a card reading "0 kept" is a
                        // dead end where a line saying what fills it isn't
                        if pieces.isEmpty && !starter {
                            Text("Anything you bring in stays here, ready to go back on.")
                                .font(.system(size: 13))
                                .foregroundStyle(M.mute)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 34)
                                .padding(.top, 14)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)               // room for the cards' own shadows
                    .padding(.bottom, 24)
                }
                // ponytail: anchored here, not beside the link sheet below — a view honours
                // one sheet, and two isPresented sheets on the same one drops the second.
                .sheet(isPresented: $history) {
                    // dismissing the closet takes this with it, so one call does both
                    PiecesSheet { g in studio.wear(g); dismiss() }
                }
            }
        }
        .presentationDetents([starter ? Self.withRail : Self.open, .large], selection: $height)
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        // a piece off the roll goes straight on, same as a pasted one
        .onChange(of: photo) { _, item in Task { await load(item) } }
        // pasted piece goes straight on, so get out of the way and let them see it
        .sheet(isPresented: $linking, onDismiss: { if studio.wearing?.isMine == true { dismiss() } }) {
            LinkSheet()
        }
        .fullScreenCover(isPresented: $shooting) {
            Shoot { data in
                shooting = false
                guard let data else { return }
                studio.add(Garment(photo: data))
                dismiss()
            }
            .ignoresSafeArea()
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        studio.add(Garment(photo: data))
        photo = nil
        dismiss()
    }
}

/// The ways a piece gets in here. Same card, different door — and the same white card
/// the history below it wears, because all three are somewhere to go. The dashed outline
/// this used to have read as an empty drop zone in an app with no other dashed edge.
struct WayCard: View {
    let icon: String
    let action: String
    let from: String
    /// Names the shops instead of leaving "any shop" to be taken on faith.
    var shops = false

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(M.rose)
                .frame(width: 42, height: 42)
                .background(Circle().fill(M.blush))

            VStack(alignment: .leading, spacing: 3) {
                Text(action).font(M.display(21)).foregroundStyle(M.ink)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text(from).tracked(8, 1.5).foregroundStyle(M.mute)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }

            Spacer(minLength: 6)

            // the logos where the chevron would be: on this row they are the arrow,
            // and they say where it points better than a chevron does
            if shops {
                BrandRow(tile: 21, columns: 3, gap: 4)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(M.rose)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 18)
        // fixed, not padded: the shop marks are taller than the icon discs, so padding
        // alone makes one card in four stand a few points proud of the others
        .frame(height: M.scaled(68))
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white))
        .shadow(color: M.rouge.opacity(0.13), radius: 16, y: 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(action)
        .accessibilityAddTraits(.isButton)
    }
}


/// The camera, for a piece that is in your hands rather than on your roll.
/// ponytail: UIImagePickerController is capture, retake and use-photo for twenty lines.
/// AVFoundation would be a hundred and fifty to arrive at the same three buttons — and
/// Camera.swift's session belongs to the mirror, which is running behind this sheet.
private struct Shoot: UIViewControllerRepresentable {
    /// nil means they backed out.
    let done: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.cameraDevice = .rear          // the garment is in front of you, not behind
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ p: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (Data?) -> Void
        init(done: @escaping (Data?) -> Void) { self.done = done }

        func imagePickerController(_ p: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // 0.9, same as the roll: this is the reference the mirror copies and a
            // soft jpeg of a print is a soft print in the reflection
            done((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.9))
        }

        func imagePickerControllerDidCancel(_ p: UIImagePickerController) { done(nil) }
    }
}
