import SwiftUI

/// Paste a product link, get the piece. Two beats, because a listing is not one photo:
/// the server reads the page and hands back everything it is showing, and then the person
/// about to wear it says which of those photos is actually the garment. The lead shot on a
/// shop page is as often a campaign crop or a model in three other things, and whichever
/// one is chosen here is the reference the mirror copies.
struct LinkSheet: View {
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss

    @State private var link = ""
    @State private var working = false
    @State private var trouble: String?
    @State private var found: API.Scraped?
    @State private var shots: [String: Data] = [:]
    @State private var pick: String?
    @State private var pasteable = false
    @State private var height: PresentationDetent = .medium
    @FocusState private var typing: Bool

    var body: some View {
        ZStack {
            M.cream.ignoresSafeArea()
            if let found { chooser(found) } else { paste }
        }
        // large as well, because the chooser is a gallery and a gallery needs the room
        .presentationDetents([.medium, .large], selection: $height)
        .presentationDragIndicator(.visible)
        .onAppear { typing = true }
        // hasStrings is true for any copied text at all. hasURLs says "a link", costs no
        // paste prompt, and is why the chip only shows up when it would actually help.
        .onAppear { pasteable = UIPasteboard.general.hasURLs }
    }

    // MARK: - paste

    private var paste: some View {
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
                if pasteable {
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

            complaint

            Button { Task { await fetch() } } label: {
                HStack(spacing: 11) {
                    Text(working ? "Looking" : "Bring it in").tracked(11, 2.4)
                    if working { Dots(color: M.onRose) }
                }
                .foregroundStyle(M.onRose)
                .padding(.horizontal, 34)
                .padding(.vertical, 16)
                .background(Capsule().fill(ready ? M.rose : M.petal))
            }
            .buttonStyle(Squish())
            .animation(.easeInOut(duration: 0.22), value: working)
            .disabled(!ready || working)

            // ponytail: says what it does for them, not how we do it — how we do it is
            // the server's business and nobody standing in a fitting room cares.
            Text("Works on most shop pages. Paste the product page, not the search results.")
                .font(.system(size: 12))
                .foregroundStyle(M.mute)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer(minLength: 8)

            // "most shop pages" is a promise; these are the receipts. Same row the
            // closet and the onboarding show, so the claim is worded once.
            VStack(spacing: 12) {
                Text("Works with").tracked(8, 1.6).foregroundStyle(M.mute.opacity(0.7))
                BrandRow(tile: 40, columns: 6, gap: 7)
            }
            .padding(.bottom, 26)
        }
    }

    // MARK: - choose

    private func chooser(_ p: API.Scraped) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button { tap(); back() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(M.ink)
                        .puck(34)
                }
                .accessibilityLabel("Back to the link")

                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name ?? "That piece")
                        .font(M.display(19)).foregroundStyle(M.ink).lineLimit(1)
                    Text(p.brand ?? "").tracked(8, 1.5).foregroundStyle(M.mute).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            stage

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(p.images.enumerated()), id: \.element) { i, id in
                        thumb(id, at: i)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 3)   // the selected ring is 2pt and would clip
            }
            .frame(height: 90)

            Text("Pick the photo that shows the piece on its own — that's the one the mirror copies.")
                .font(.system(size: 12))
                .foregroundStyle(M.mute)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            complaint

            Button { wear(p) } label: {
                HStack(spacing: 11) {
                    Text(working ? "Putting it on" : "Wear it").tracked(11, 2.4)
                    if working { Dots(color: M.onRose) }
                }
                .foregroundStyle(M.onRose)
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
                .background(Capsule().fill(chosen == nil ? M.petal : M.rose))
            }
            .buttonStyle(Squish())
            .animation(.easeInOut(duration: 0.22), value: working)
            .disabled(chosen == nil || working)

            Spacer(minLength: 10)
        }
        // the photos are already on the server; this just walks them down, all at once,
        // so the row fills in rather than arriving in order
        .task(id: p.source) { await load(p.images) }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    /// The choice, big enough to make. A flat-lay and a campaign shot are indistinguishable
    /// at thumbnail size, which is the whole failure this screen exists to prevent.
    private var stage: some View {
        ZStack {
            if let img = chosen {
                Image(uiImage: img).resizable().scaledToFit().padding(12)
            } else {
                Dots(d: 7)
            }
        }
        // grows into whatever the detent gives it rather than leaving the foot of a large
        // sheet empty; at .medium it shrinks back to about a postcard
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 180)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(M.shell, lineWidth: 1))
        .padding(.horizontal, 20)
    }

    private func thumb(_ id: String, at i: Int) -> some View {
        let on = pick == id
        return ZStack {
            M.blush
            if let d = shots[id], let img = UIImage(data: d) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Dots(d: 4)
            }
        }
        .frame(width: 64, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(on ? M.rose : M.shell, lineWidth: on ? 2 : 1))
        .scaleEffect(on ? 1.05 : 1)
        .onTapGesture {
            tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { pick = id }
        }
        .accessibilityLabel("Photo \(i + 1) of \(found?.images.count ?? 0)")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private var complaint: some View {
        Group {
            if let trouble {
                Text(trouble)
                    .font(.system(size: 13))
                    .foregroundStyle(M.rouge)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - doing it

    /// A shared link arrives wrapped in a sentence more often than not — "omg look at this
    /// https://…". Take the url out of it rather than making them edit it down.
    private var url: String? {
        link.split(whereSeparator: \.isWhitespace)
            .first { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
            .map(String.init)
    }

    private var ready: Bool { url != nil }
    private var chosen: UIImage? { pick.flatMap { shots[$0] }.flatMap(UIImage.init(data:)) }

    private func fetch() async {
        guard let url, !working else { return }
        typing = false
        working = true
        withAnimation { trouble = nil }
        do {
            let p = try await API.find(url)
            tap(.medium)
            // one photo is not a choice, and a screen offering one option is an insult
            if p.images.count == 1 {
                try await put(p, p.images[0])
            } else {
                pick = p.images.first
                withAnimation(.easeInOut(duration: 0.25)) { found = p; height = .large }
            }
        } catch {
            tap(.heavy)
            withAnimation { trouble = error.localizedDescription }
        }
        working = false
    }

    private func wear(_ p: API.Scraped) {
        guard let id = pick, !working else { return }
        tap(.medium)
        Task {
            working = true
            do { try await put(p, id) }
            catch {
                tap(.heavy)
                withAnimation { trouble = error.localizedDescription }
            }
            working = false
        }
    }

    private func put(_ p: API.Scraped, _ id: String) async throws {
        let data = if let have = shots[id] { have } else { try await API.shot(id) }
        studio.add(Garment(scraped: p, pick: id, shot: data))
        dismiss()
    }

    /// All of them at once. ponytail: full-size bytes, no thumbnail endpoint — six product
    /// shots is a couple of megabytes and they are the same bytes the chosen one needs
    /// anyway, so picking is instant. Add a resize on the server if it bites on cellular.
    @MainActor private func load(_ ids: [String]) async {
        await withTaskGroup(of: (String, Data?).self) { group in
            for id in ids where shots[id] == nil {
                group.addTask { (id, try? await API.shot(id)) }
            }
            for await (id, data) in group {
                guard let data else { continue }
                withAnimation(.easeOut(duration: 0.2)) { shots[id] = data }
            }
        }
        // the lead shot is the default, but not if it was the one that failed to arrive
        if pick.map({ shots[$0] == nil }) ?? true {
            withAnimation { pick = ids.first { shots[$0] != nil } }
        }
    }

    private func back() {
        withAnimation(.easeInOut(duration: 0.2)) {
            found = nil
            height = .medium
            trouble = nil
        }
        shots = [:]
        pick = nil
        typing = true
    }
}
