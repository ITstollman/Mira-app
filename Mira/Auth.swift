import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @Environment(Account.self) private var account
    @State private var email = ""
    @State private var mailing = false
    @FocusState private var typing: Bool

    private var valid: Bool { email.contains("@") && email.contains(".") }

    var body: some View {
        ZStack {
            M.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 30)

                MiraMark(size: 58).padding(.bottom, 22)

                Text("Come in")
                    .font(M.display(42, .light))
                    .kerning(2)
                    .foregroundStyle(M.ink)

                Text("Your looks, your sizes, on every device.")
                    .tracked(10, 1.6)
                    .foregroundStyle(M.mute)
                    .padding(.top, 10)

                Spacer(minLength: 24)

                if mailing { mail } else { providers }

                Spacer(minLength: 40)

                Text("By continuing you agree to the Terms and Privacy Policy.")
                    .tracked(8, 1.2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(M.mute.opacity(0.6))
                    .padding(.horizontal, 44)
                    .padding(.bottom, 22)
            }
        }
        .onTapGesture { typing = false }
    }

    /// Three ways in, all the same weight. Email is a button like the rest —
    /// it opens the field instead of parking a keyboard target on the screen.
    private var providers: some View {
        VStack(spacing: 12) {
            // ponytail: no Sign in with Apple capability on this target yet, so a
            // failed authorization still lets you in. Delete the failure branch
            // once the entitlement and a real backend exist.
            SignInWithAppleButton(.signIn) { $0.requestedScopes = [.email] } onCompletion: { result in
                if case .success(let auth) = result,
                   let cred = auth.credential as? ASAuthorizationAppleIDCredential {
                    account.signIn(cred.email ?? "you@privaterelay.appleid.com")
                } else {
                    account.signIn("you@privaterelay.appleid.com")
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 54)
            .clipShape(Capsule())

            // ponytail: mocked. GoogleSignIn is not in the project and there is no
            // GoogleService-Info.plist for ai.mira.tryon yet — this signs you in the
            // same way Apple's failure branch does. Swap the body for
            // GIDSignIn.sharedInstance.signIn(withPresenting:) once both land.
            Provider(label: "Continue with Google") { GoogleG(size: 19) } action: {
                account.signIn("you@gmail.com")
            }

            Provider(label: "Continue with email") {
                Image(systemName: "envelope.fill").font(.system(size: 15)).foregroundStyle(M.rose)
            } action: {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) { mailing = true }
                typing = true
            }
        }
        .padding(.horizontal, 30)
        .transition(.opacity)
    }

    private var mail: some View {
        VStack(spacing: 12) {
            TextField("", text: $email, prompt: Text("your email").foregroundStyle(M.mute.opacity(0.6)))
                .font(.system(size: 16))
                .foregroundStyle(M.ink)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { if valid { account.signIn(email) } }
                .focused($typing)
                .padding(.horizontal, 22)
                .frame(height: 54)
                .background(Capsule().fill(.white))
                .overlay(Capsule().stroke(typing ? M.petal : M.shell, lineWidth: 1.2))

            Button {
                typing = false
                account.signIn(email)
            } label: {
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
                typing = false
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
}

/// One provider row. Same chrome for every third-party way in, so no single
/// option looks like the house favourite.
private struct Provider<Icon: View>: View {
    let label: String
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void

    var body: some View {
        Button {
            tap(.medium)
            action()
        } label: {
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
