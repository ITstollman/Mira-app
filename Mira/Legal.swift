import SwiftUI
import WebKit

/// Support, Terms and Privacy — the same page the site serves, bundled rather than linked.
/// A legal link that 404s is a rejection, and a link to a domain nobody has pointed
/// anywhere yet is a 404 with extra steps. This one works on a plane.
// ponytail: Mira/legal.html is a copy of landing/legal.html. Edit that one and
// `cp landing/legal.html Mira/`. A copy build phase isn't worth hand-editing the pbxproj.
enum Legal: String, Identifiable {
    case support, terms, privacy
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct LegalSheet: View {
    let page: Legal
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(page.title).font(M.display(20)).foregroundStyle(M.ink)
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
                .padding(.trailing, 16)
            }
            .padding(.top, 18)
            .padding(.bottom, 10)

            Paper(anchor: page.rawValue)
        }
        .background(M.cream.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// The bundled page, opened at one of its three sections.
private struct Paper: UIViewRepresentable {
    let anchor: String

    func makeUIView(context: Context) -> WKWebView {
        // the page is written for a website: it opens with a mark and a nav that only
        // mean anything next to index.html, which is not in here. Take those out, then
        // jump to the section they actually asked for.
        let strip = WKUserScript(source: """
            document.querySelector('.top')?.remove();
            document.querySelectorAll('a[href$="index.html"]')
                .forEach(a => a.replaceWith(a.textContent));
            document.getElementById('\(anchor)')?.scrollIntoView();
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)

        let cfg = WKWebViewConfiguration()
        cfg.userContentController.addUserScript(strip)

        let web = WKWebView(frame: .zero, configuration: cfg)
        web.isOpaque = false                       // else it flashes white over the cream
        web.backgroundColor = UIColor(M.cream)
        web.scrollView.backgroundColor = UIColor(M.cream)
        if let file = Bundle.main.url(forResource: "legal", withExtension: "html") {
            web.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}
}

/// The line every screen that sells has to carry, written once. Apple rejects a paywall
/// whose Terms and Privacy are decoration, and three copies of it is three chances for
/// one of them to go stale.
struct FinePrint: View {
    @Environment(Account.self) private var account
    @State private var page: Legal?
    @State private var restoring = false

    var body: some View {
        HStack(spacing: 20) {
            word("Terms") { page = .terms }
            word("Privacy") { page = .privacy }
            if restoring {
                Dots(color: M.mute.opacity(0.6), d: 4)
            } else {
                word("Restore") {
                    restoring = true
                    Task { await account.restore(); restoring = false }
                }
            }
        }
        .sheet(item: $page) { LegalSheet(page: $0) }
    }

    private func word(_ what: String, _ go: @escaping () -> Void) -> some View {
        Button { tap(); go() } label: {
            Text(what).tracked(8, 1.2).foregroundStyle(M.mute.opacity(0.6))
        }
    }
}
