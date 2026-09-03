import SwiftUI

/// Say it and wear it. No shop, no photograph — lucy-vton-3.5 will take a written
/// garment, and Decart's enrichment fills in what a one-liner leaves out.
struct WordsSheet: View {
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss

    @State private var said = ""
    @FocusState private var typing: Bool

    /// Decart's guide asks for colour, fabric, cut and length. Nobody reads that as a
    /// rule, so it's three examples instead — tap one and it's in the box.
    private let examples = [
        "an oversized cream cable-knit sweater",
        "a black leather biker jacket, cropped, with silver zips",
        "a sage green linen midi dress with puff sleeves",
    ]

    var body: some View {
        ZStack {
            M.cream.ignoresSafeArea()

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("In your words").font(M.display(30, .light)).foregroundStyle(M.ink)
                    Text("Describe it and it goes on")
                        .tracked(9, 1.8).foregroundStyle(M.mute)
                }
                .padding(.top, 30)

                HStack(spacing: 10) {
                    Image(systemName: "text.bubble").font(.system(size: 14)).foregroundStyle(M.mute)
                    TextField("a red satin slip dress…", text: $said, axis: .vertical)
                        .font(.system(size: 15))
                        .foregroundStyle(M.ink)
                        .lineLimit(1...3)
                        .focused($typing)
                        .submitLabel(.go)
                        .onSubmit(wear)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(M.shell, lineWidth: 1))
                .padding(.horizontal, 22)

                VStack(spacing: 8) {
                    ForEach(examples, id: \.self) { line in
                        Button {
                            tap()
                            said = line
                        } label: {
                            Text(line)
                                .font(.system(size: 12))
                                .foregroundStyle(M.mute)
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Capsule().fill(M.blush))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button(action: wear) {
                    Text("Wear it")
                        .tracked(11, 2.4)
                        .foregroundStyle(M.onRose)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(ready ? M.rose : M.petal))
                }
                .disabled(!ready)

                // The one thing worth teaching: the model wants a garment, not a mood.
                Text("Colour, fabric and cut land best. \"Make me look expensive\" doesn't.")
                    .font(.system(size: 12))
                    .foregroundStyle(M.mute)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer(minLength: 0)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { typing = true }
    }

    private var ready: Bool { said.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 }

    private func wear() {
        guard ready else { return }
        tap(.medium)
        typing = false
        studio.add(Garment(described: said))
        dismiss()
    }
}
