import SwiftUI
import FirebaseCore

@main
struct MiraApp: App {
    @State private var studio = Studio()
    @State private var account = Account()
    @State private var fits = FitStore()

    init() {
        #if DEBUG
        Checks.run()
        #endif
        // ponytail: configure only when the plist is actually in the bundle, so the app
        // still runs before Firebase is wired. FirebaseApp.configure() traps without it.
        // Drop the guard once GoogleService-Info.plist ships for real.
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(studio)
                .environment(account)
                .environment(fits)
                .preferredColorScheme(.light)
                .tint(M.rose)
        }
    }
}

struct RootView: View {
    @Environment(Account.self) private var account
    @Environment(FitStore.self) private var fits
    // ponytail: dev-only jump-to-screen flags (dev:mirror, dev:closet, dev:lookbook,
    // dev:look, dev:seed, dev:auth, dev:paywall, dev:topup, dev:profile, dev:fit,
    // dev:pro, dev:broke, dev:onboard)
    @State private var onboarded = Onboard.done
    // dev:mirror means "jump to the mirror" — only dev:fit asks for the tape measure
    @State private var measured = Dev.has("dev:mirror") && !Dev.has("dev:fit")

    var body: some View {
        ZStack {
            if !onboarded {
                OnboardingView {
                    Onboard.finish()
                    withAnimation(.easeInOut(duration: 0.5)) { onboarded = true }
                }
                .transition(.opacity)
            } else if account.signedIn && !Dev.has("dev:auth") {
                if fits.needsSetup && !measured {
                    FitSetup { withAnimation(.easeInOut(duration: 0.4)) { measured = true } }
                        .transition(.opacity)
                } else {
                    MirrorView().transition(.opacity)
                }
            } else {
                AuthView().transition(.opacity)
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
        if ["onboard", "reveal", "hero", "pick", "trial"].contains(where: { Dev.has("dev:\($0)") }) { return false }
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("dev:") }) { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func finish() { UserDefaults.standard.set(true, forKey: key) }

    /// The onboarding already made the offer this launch, so the mirror must not make it
    /// again thirty seconds later. Resets on relaunch, which is when asking is fair again.
    static var pitched = false
}
