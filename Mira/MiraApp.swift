import GoogleSignIn
import SwiftUI

@main
struct MiraApp: App {
    @State private var studio = Studio()
    @State private var account = Account()

    init() {
        #if DEBUG
        Checks.run()
        #endif
        // SwiftUI's .tint only reaches the filled half; the rest of the track and its
        // shadow ship system grey, which is the one true neutral in a pink app.
        UISlider.appearance().maximumTrackTintColor = UIColor(M.shell)
        // ponytail: FirebaseApp.configure() is in Account.init, not here. A SwiftUI App's
        // stored properties are built *before* its init body runs, so `account` above has
        // already reached for Auth.auth() by the time this line would have configured it.
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(studio)
                .environment(account)
                .preferredColorScheme(.light)
                .tint(M.rose)
                // Google's sheet hands the sign-in back as a url. Without this the
                // browser closes and nothing ever happens.
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        }
    }
}

struct RootView: View {
    @Environment(Account.self) private var account
    // ponytail: dev-only jump-to-screen flags (dev:mirror, dev:closet, dev:look,
    // dev:seed, dev:auth, dev:paywall, dev:topup, dev:profile, dev:pro,
    // dev:broke, dev:onboard, dev:looks, dev:history, dev:link)
    @State private var onboarded = Onboard.done
    /// Home unless you asked for the mirror — everything scoped to the mirror screen
    /// (the closet, a captured look) implies it.
    @State private var mirroring = ["mirror", "closet", "look", "link"].contains { Dev.has("dev:\($0)") }
    /// Set by the home screen when it sends you in wearing something already.
    @State private var straight = false

    var body: some View {
        ZStack {
            if !onboarded {
                OnboardingView {
                    Onboard.finish()
                    withAnimation(.easeInOut(duration: 0.5)) { onboarded = true }
                }
                .transition(.opacity)
            } else if account.restoring {
                // Firebase is still reading the keychain. A held breath beats flashing the
                // sign-in screen at somebody whose session is one runloop away from coming
                // back — and it is over before the first frame on almost every launch.
                Color.clear
            } else if account.signedIn && !Dev.has("dev:auth") {
                // signed in is all the way in. There used to be a height-and-size
                // questionnaire here; nothing downstream ever read the answer, and a form
                // between the sign-in and the mirror is a page nobody came for.
                if mirroring {
                    MirrorView(straight: straight,
                               back: { withAnimation(.easeInOut(duration: 0.3)) { mirroring = false } })
                        .transition(.opacity)
                } else {
                    HomeView(start: { picked in
                        straight = picked
                        withAnimation(.easeInOut(duration: 0.3)) { mirroring = true }
                    })
                    .transition(.opacity)
                }
            } else {
                AuthView()
                    .transition(.opacity)
                    // dev:auth asks for the sign-in screen. A live session would just
                    // re-authorize the same uid and every button would look broken.
                    .task { if Dev.has("dev:auth"), account.signedIn { account.signOut() } }
            }
        }
        .background(M.cream)
        // ponytail: type scales with the system text-size setting, clamped at AX2 —
        // MirrorView's camera overlay is fixed-geometry and blows out past that.
        // Upgrade path: relayout the overlay for AX3+ and drop the clamp.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

/// Seen the reel once, never again.
/// ponytail: UserDefaults, so deleting the app replays it. Launch with dev:onboard to
/// force it back; any other dev: flag skips it so the jump-to-screen flags still land.
enum Onboard {
    private static let key = "onboarded"

    static var done: Bool {
        if ["onboard", "reveal", "hero", "trial"].contains(where: { Dev.has("dev:\($0)") }) { return false }
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("dev:") }) { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func finish() { UserDefaults.standard.set(true, forKey: key) }

    /// The onboarding already made the offer this launch, so the mirror must not make it
    /// again thirty seconds later. Resets on relaunch, which is when asking is fair again.
    static var pitched = false
}
