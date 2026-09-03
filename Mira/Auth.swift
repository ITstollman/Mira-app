import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import SwiftUI

struct AuthView: View {
    @Environment(Account.self) private var account
    @State private var email = ""
    @State private var password = ""
    @State private var mailing = Dev.has("dev:mail")
    @State private var busy = false
    @State private var trouble: String?
    /// The raw half of the nonce Apple was given the hash of. Set when the sheet is
    /// asked for, read when it answers — Firebase needs the raw one to prove they match.
    @State private var raw = ""
    @State private var legal: Legal?
    @FocusState private var typing: Field?

    private enum Field { case email, password }

    /// Firebase's own minimum is six characters, and refusing on the phone reads better
    /// than a round trip that comes back "weak password".
    private var valid: Bool { email.contains("@") && email.contains(".") && password.count >= 6 }

    /// ponytail: measured off the screen, not off the layout, so the keyboard coming
    /// up cannot resize the reel. UIScreen.main is fine while the app is portrait,
    /// phone-only and single-window.
    /// The pitch sits inside the band now, so the band gets the height the headline
    /// used to take — and gives it back once a keyboard needs the room.
    private var banner: CGFloat { UIScreen.main.bounds.height * (mailing ? 0.32 : 0.52) }
    private var wide: CGFloat { UIScreen.main.bounds.width }
    /// The strip behind the status bar. The band runs up under it — square top corners
    /// with rounded bottom ones is the shape of something that bleeds off the top edge,
    /// and stopping at the safe area left a bar of cream above her head.
    /// ponytail: same portrait, single-window assumption as `wide`.
    private var top: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .keyWindow?.safeAreaInsets.top ?? 0
    }

    var body: some View {
        ZStack {
            M.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                // the same reel the onboarding runs: a stranger deciding whether to hand
                // over an email wants to see the thing working, not our monogram.
                // 9:16 footage in a wide band, so it renders at its own shape and gets
                // cropped — biased high, or the band lands on her chin.
                Reel(name: "cool-tryon-video", loop: true) { DemoPlaceholder() }
                    .frame(width: wide, height: wide * 16 / 9)
                    // ponytail: a fraction of the footage, not of the overflow, so the
                    // window stays on her face when the band shrinks for the keyboard.
                    // 0.13 tuned to cool-tryon-video.mp4: low enough to spend the band
                    // on the outfit rather than on the ceiling, high enough that the
                    // push-in around ten seconds still keeps her hair off the top edge.
                    // + top, so growing the band upward spends the new strip on the
                    // footage above her rather than sliding her whole face up the screen
                    .offset(y: -(wide * 16 / 9) * 0.13 + top)
                    .frame(width: wide, height: banner + top, alignment: .top)
                    .overlay(alignment: .bottom) { pitch }
                    .clipShape(.rect(bottomLeadingRadius: 34, bottomTrailingRadius: 34,
                                     style: .continuous))
                    .shadow(color: M.rouge.opacity(0.16), radius: 22, y: 12)
                    .ignoresSafeArea(edges: .top)

                Spacer(minLength: 16)

                if let trouble {
                    // Sign-in can now fail in a dozen ways, and a button that does nothing
                    // is the worst of them. Tap it away.
                    Text(trouble)
                        .font(.system(size: 13))
                        .foregroundStyle(M.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(M.blush))
                        .padding(.horizontal, 30)
                        .padding(.bottom, 10)
                        .transition(.opacity)
                        .onTapGesture { withAnimation { self.trouble = nil } }
                }

                if mailing { mail } else { providers }

                Spacer(minLength: 24)

                // The two nouns are the sentence. A custom scheme so SwiftUI's own markdown
                // links open the bundled page instead of throwing somebody into Safari
                // halfway through creating an account.
                Text("By continuing you agree to the [Terms](mira:terms) and [Privacy Policy](mira:privacy).")
                    .tracked(8, 1.2)
                    .tint(M.rose)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(M.mute.opacity(0.6))
                    .padding(.horizontal, 44)
                    .padding(.bottom, 22)
                    .environment(\.openURL, OpenURLAction { url in
                        tap()
                        legal = Legal(rawValue: String(url.absoluteString.dropFirst(5)))
                        return .handled
                    })
            }
            // Nothing here dismisses itself — the auth-state listener in Account does,
            // by way of the root view. Until then the screen has to look busy.
            .opacity(busy ? 0.55 : 1)
            .allowsHitTesting(!busy)
        }
        .sheet(item: $legal) { LegalSheet(page: $0) }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: mailing)
        .animation(.easeInOut(duration: 0.2), value: trouble)
        .task { if mailing { typing = .email } }
        .onTapGesture { typing = nil }
    }

    /// The pitch, on the footage instead of under it. A scrim, not a shadow: the clip
    /// ends on a pale tulle gown and white type alone would disappear into it.
    private var pitch: some View {
        Text("Wear it before\nyou buy it.")
            .font(M.display(30, .light))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
            .padding(.bottom, 26)
            .background(
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.62)],
                               startPoint: .top, endPoint: .bottom)
            )
    }

    /// Three ways in, all the same weight. Email is a button like the rest —
    /// it opens the field instead of parking a keyboard target on the screen.
    private var providers: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.signIn) { request in
                raw = Nonce.make()
                request.requestedScopes = [.email, .fullName]
                request.nonce = Nonce.hashed(raw)
            } onCompletion: { result in
                switch result {
                case .failure(let error):
                    // Backing out of the sheet is an answer, not a fault.
                    if (error as? ASAuthorizationError)?.code != .canceled { say(error) }
                case .success(let auth):
                    guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                          let token = cred.identityToken.flatMap({ String(data: $0, encoding: .utf8) })
                    else { return trouble = "Apple didn't hand over an identity token" }
                    go {
                        try await Auth.auth().signIn(with: OAuthProvider.appleCredential(
                            withIDToken: token, rawNonce: raw, fullName: cred.fullName))
                    }
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 54)
            .clipShape(Capsule())

            // ponytail: the row is a promise the plist has to be able to keep. `clientID`
            // is nil until Google is switched on in the console and GoogleService-Info.plist
            // is downloaded again — until then the button could only apologise, so it isn't
            // drawn. Nothing to undo afterwards: the new plist brings the row back.
            if FirebaseApp.app()?.options.clientID != nil {
                Provider(label: "Continue with Google") { GoogleG(size: 19) } action: { google() }
            }

            Provider(label: "Continue with email") {
                Image(systemName: "envelope").font(.system(size: 16, weight: .regular)).foregroundStyle(M.rose)
            } action: {
                tap(.medium)
                withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) { mailing = true }
                typing = .email
            }
        }
        .padding(.horizontal, 30)
        .transition(.opacity)
    }

    private var mail: some View {
        VStack(spacing: 12) {
            TextField("", text: $email, prompt: Text("your email").foregroundStyle(M.mute.opacity(0.6)))
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .submitLabel(.next)
                .onSubmit { typing = .password }
                .focused($typing, equals: .email)
                .modifier(Bar(lit: typing == .email))

            // One field, both doors: an address nobody has used yet becomes an account.
            SecureField("", text: $password, prompt: Text("a password").foregroundStyle(M.mute.opacity(0.6)))
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit(mailIn)
                .focused($typing, equals: .password)
                .modifier(Bar(lit: typing == .password))

            Button(action: mailIn) {
                Text("Continue")
                    .tracked(12, 2.6)
                    .foregroundStyle(M.onRose)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Capsule().fill(valid ? M.rose : M.petal))
            }
            .disabled(!valid)

            Button {
                tap()
                typing = nil
                withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) { mailing = false }
            } label: {
                Text("Use another way")
                    .tracked(10, 1.8)
                    .foregroundStyle(M.mute)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
        }
        .padding(.horizontal, 30)
        .transition(.opacity)
    }

    // MARK: - the three doors

    private func google() {
        // Set by FirebaseApp.configure() from GoogleService-Info.plist — and absent from
        // that file until Google is switched on as a provider in the console.
        guard let id = FirebaseApp.app()?.options.clientID, let host = Presenter.top() else {
            return trouble = "Google sign-in isn't switched on yet"
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: id)
        go {
            let out = try await GIDSignIn.sharedInstance.signIn(withPresenting: host)
            guard let token = out.user.idToken?.tokenString else {
                throw API.Fault("Google didn't hand over an identity token")
            }
            try await Auth.auth().signIn(with: GoogleAuthProvider.credential(
                withIDToken: token, accessToken: out.user.accessToken.tokenString))
        }
    }

    private func mailIn() {
        guard valid else { return }
        tap(.medium)
        typing = nil
        go {
            do { try await Auth.auth().signIn(withEmail: email, password: password) }
            catch {
                // Email-enumeration protection is on by default, so Firebase will not say
                // "no such user" — it says the credential is bad either way. Trying to
                // *create* the address is what tells the two apart: if it comes back
                // taken, the account exists and the password was simply wrong.
                do { try await Auth.auth().createUser(withEmail: email, password: password) }
                catch let second as NSError where second.code == AuthErrorCode.emailAlreadyInUse.rawValue {
                    throw API.Fault("That password doesn't match this email")
                }
            }
        }
    }

    /// Runs a sign-in and shows whatever went wrong. There is no success branch on
    /// purpose: Account's listener notices, and the root view swaps this screen out.
    private func go(_ work: @escaping () async throws -> Void) {
        busy = true
        trouble = nil
        Task {
            do { try await work() } catch { say(error) }
            busy = false
        }
    }

    private func say(_ error: Error) {
        // Google's own cancel arrives as a thrown error rather than a result.
        if (error as NSError).domain == kGIDSignInErrorDomain,
           (error as NSError).code == GIDSignInError.canceled.rawValue { return }
        trouble = error.localizedDescription
    }
}

/// The capsule every field on this screen sits in.
private struct Bar: ViewModifier {
    let lit: Bool
    func body(content: Content) -> some View {
        content
            .font(.system(size: 16))
            .foregroundStyle(M.ink)
            .autocorrectionDisabled()
            .padding(.horizontal, 22)
            .frame(height: 54)
            .background(Capsule().fill(.white))
            .overlay(Capsule().stroke(lit ? M.petal : M.shell, lineWidth: 1.2))
    }
}

/// A one-shot nonce: Apple is given the hash, Firebase is given the raw string, and the
/// pair is what stops an identity token captured from one sign-in being replayed into
/// somebody else's account.
enum Nonce {
    static func make() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        // SecRandom rather than Int.random: this is the thing standing between an
        // intercepted Apple token and an account.
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return hex(bytes)
    }

    static func hashed(_ raw: String) -> String { hex(SHA256.hash(data: Data(raw.utf8))) }

    private static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// Google's sheet needs a UIKit parent, which SwiftUI does not hand out.
// ponytail: the front window's root controller. Correct while the app is one scene and
// presents nothing full-screen over this view; revisit if either changes.
enum Presenter {
    static func top() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?.rootViewController
    }
}

/// One provider row. Same chrome for every third-party way in, so no single
/// option looks like the house favourite.
private struct Provider<Icon: View>: View {
    let label: String
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon()
                Text(label)
                    .font(M.ui(16, .medium))
                    .foregroundStyle(M.ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Capsule().fill(.white))
            .overlay(Capsule().stroke(M.shell, lineWidth: 1.2))
        }
        .accessibilityLabel(label)
    }
}

/// Google's own G, straight off their brand artwork — the four official paths as a
/// vector asset, so it stays sharp at any size and is the mark they require on a
/// "Continue with Google" button.
struct GoogleG: View {
    var size: CGFloat = 19
    var body: some View {
        Image("GoogleG").resizable().scaledToFit().frame(width: size, height: size)
    }
}
