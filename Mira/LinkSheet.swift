import SwiftUI

/// Paste a product link, get the piece. The server does the scraping (and the proxy
/// rotation); this just asks and waits.
struct LinkSheet: View {
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss

    @State private var link = ""
    @State private var working = false
    @State private var trouble: String?
    @FocusState private var typing: Bool

    var body: some View {
        ZStack {
            M.cream.ignoresSafeArea()

            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    Text("From anywhere").font(M.display(30, .light)).foregroundStyle(M.ink)
                    Text("Paste a product link and try it on")
                        .tracked(9, 1.8).foregroundStyle(M.mute)
                }
                .padding(.top, 30)

                HStack(spacing: 10) {
                    Image(systemName: "link").font(.system(size: 14)).foregroundStyle(M.mute)
                    TextField("https://", text: $link)
                        .font(.system(size: 15))
                        .foregroundStyle(M.ink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .submitLabel(.go)
                        .focused($typing)
                        .onSubmit { Task { await fetch() } }
                    // hasStrings doesn't read the board, so no banner until they ask for one
                    if UIPasteboard.general.hasStrings {
                        Button {
                            tap()
                            link = UIPasteboard.general.string ?? link
                        } label: {
                            Text("Paste").tracked(9, 1.4).foregroundStyle(M.rose)
                        }
                        .accessibilityLabel("Paste the copied link")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(Capsule().fill(.white))
                .overlay(Capsule().strokeBorder(M.shell, lineWidth: 1))
                .padding(.horizontal, 22)

                if let trouble {
                    Text(trouble)
                        .font(.system(size: 13))
                        .foregroundStyle(M.rouge)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 34)
                        .transition(.opacity)
                }

                Button { Task { await fetch() } } label: {
                    ZStack {
                        Text(working ? "Looking" : "Bring it in")
                            .tracked(11, 2.4)
                            .foregroundStyle(M.onRose)
                            .opacity(working ? 0.45 : 1)
                        if working { ProgressView().tint(M.onRose).offset(x: 62) }
                    }
                    .padding(.horizontal, 34)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(ready ? M.rose : M.petal))
                }
                .disabled(!ready || working)

                Text("Works on most shop pages. Some stores block us — that's what the proxies are for.")
                    .font(.system(size: 12))
                    .foregroundStyle(M.mute)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer()
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { typing = true }
    }

    private var ready: Bool { link.trimmingCharacters(in: .whitespaces).hasPrefix("http") }

    private func fetch() async {
        guard ready, !working else { return }
        typing = false
        working = true
        withAnimation { trouble = nil }
        do {
            let garment = try await API.scrape(link.trimmingCharacters(in: .whitespaces))
            tap(.medium)
            studio.add(garment)
            dismiss()
        } catch {
            tap(.heavy)
            withAnimation { trouble = error.localizedDescription }
        }
        working = false
    }
}
