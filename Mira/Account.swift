import FirebaseAuth
import FirebaseCore
import StoreKit
import SwiftUI

// MARK: - the unit
//
// One fitting = fifteen seconds in the mirror, or one photograph = $0.30 of COGS. The
// ledger and the wire still count seconds, because margin is only knowable per second
// and the refund route hands back the ones a session never used. The screen only ever
// says fittings, because that is the thing being sold — ``Spend.said`` is where the two
// meet, and a raw balance is never printed anywhere else.

enum Spend {
    /// What one fitting costs the wallet. A photograph costs the same and renders for a
    /// fifth of it; that margin is what pays for the mirror.
    static let perFitting = 15
    static let costPerSecond = 0.02
    /// Mirrors MAX_SESSION_SECONDS on the server, which is the real ceiling. Eight
    /// fittings back to back: long enough to stop feeling metered, short enough that a
    /// session left running can't empty a month.
    static let maxLiveSeconds = 120

    static func sparks(_ fittings: Int) -> Int { fittings * perFitting }
    static func fittings(_ sparks: Int) -> Int { sparks / perFitting }
    static func liveSeconds(forSparks n: Int) -> Int { n }

    /// A balance the way it is said out loud. Whole fittings only — a fraction of one
    /// buys nothing, so rounding down is the honest direction.
    static func said(_ n: Int) -> String { "\(fittings(n))" }

    /// The word that goes with ``said``.
    static func unit(_ n: Int) -> String { fittings(n) == 1 ? "fitting" : "fittings" }
}

enum Plan: String, CaseIterable, Identifiable {
    // yearly first: it is the one being sold, and CaseIterable sets the order on the paywall
    case yearly, monthly
    var id: String { rawValue }

    /// What the plan hands over, every month. Twelve fittings is $3.60 of compute
    /// against $10.62 of revenue on the yearly — the number the subscription is priced
    /// on, and the only one that decides whether it makes money.
    // ponytail: copy and grant both read this, so they cannot drift. App Store Connect and
    // `SOLD` in server/server.js have to be told separately.
    static let fittings = 12

    /// The App Store Connect product id, typed there by hand. Nothing about the price or
    /// the grant travels with it — the store owns the first and server.js owns the second.
    var productID: String {
        switch self {
        case .yearly:  "ai.mira.tryon.pro.yearly"
        case .monthly: "ai.mira.tryon.pro.monthly"
        }
    }

    /// How many months one purchase covers — what the /mo figure divides the price by.
    var months: Int {
        switch self {
        case .yearly:  12
        case .monthly: 1
        }
    }

    /// Which plan an entitlement is for, if it is for one at all.
    init?(product id: String) {
        guard let match = Plan.allCases.first(where: { $0.productID == id }) else { return nil }
        self = match
    }

    var price: String {
        switch self {
        case .yearly:  "$149.99"
        case .monthly: "$24.99"
        }
    }
    /// What it costs a month either way — the only number worth putting side by side.
    var perMonth: String {
        switch self {
        case .yearly:  "$12.50/mo"
        case .monthly: "$24.99/mo"
        }
    }
    var headline: String {
        switch self {
        case .yearly:  "Save 50%"
        case .monthly: "Monthly"
        }
    }
    /// The catch, spelled out under the headline. Nil when there isn't one. `price` is
    /// Apple's, in the currency the card is actually charged in — the strings above are
    /// dollars, and dollars under a euro price is the kind of thing App Review reads.
    func billed(_ price: String) -> String? {
        switch self {
        case .yearly:  "\(price) billed annually"
        case .monthly: nil
        }
    }
    var cadence: String {
        switch self {
        case .yearly:  "per year"
        case .monthly: "per month"
        }
    }
    /// The disclosure under the buy button, which has to name the real charge.
    func note(_ price: String) -> String {
        switch self {
        case .yearly:
            "\(Self.included) a month. \(price) billed annually and renews automatically unless canceled in the App Store."
        case .monthly:
            "\(Self.included) a month. \(price) per month. Renews automatically unless canceled in the App Store."
        }
    }
    var badge: String? {
        switch self {
        // ponytail: no free trial to shout about any more — a stranger gets one fitting
        // before the paywall, and the plan is paid for before it grants anything. Say
        // which row to pick instead of promising something that isn't given.
        case .yearly:  "BEST VALUE"
        case .monthly: nil
        }
    }
    /// Granted on subscribing, refreshed every month.
    var sparks: Int { Spend.sparks(Plan.fittings) }

    /// "12 fittings" — written once so the headline and the small print agree.
    static var included: String { "\(fittings) fittings" }
}

struct Pack: Identifiable {
    let id: String
    let sparks: Int
    let price: String
    let note: String?

    /// The size the way it is said out loud.
    var said: String { "\(Spend.said(sparks)) \(Spend.unit(sparks))" }
    /// What one works out to: the pack equivalent of the plan's /mo figure, and the only
    /// thing that makes the ladder legible at a glance. Checks enforces that it falls as
    /// the packs get bigger — otherwise the badge on the middle one is a lie.
    var each: String {
        let d = Double(price.dropFirst()) ?? 0
        return String(format: "$%.2f each", d / Double(Spend.fittings(sparks)))
    }
    /// How many fittings the price is divided by to get that figure.
    var fittings: Int { Spend.fittings(sparks) }

    // Each step down the ladder buys a cheaper fitting — $2.00, $1.67, $1.33 — against
    // $0.30 of compute, so the thinnest of them still clears 4x. All of them dearer than
    // the plan's $1.04, which is the point: a topup is what you buy when you did not
    // want to subscribe.
    // `id` is the App Store Connect product id; `price` is the fallback shown until the
    // store answers with what this actually costs where the user is standing.
    static let all = [
        Pack(id: "ai.mira.tryon.fittings.10", sparks: Spend.sparks(10), price: "$19.99", note: nil),
        Pack(id: "ai.mira.tryon.fittings.30", sparks: Spend.sparks(30), price: "$49.99", note: "MOST POPULAR"),
        Pack(id: "ai.mira.tryon.fittings.75", sparks: Spend.sparks(75), price: "$99.99", note: nil),
    ]
}

// The balance lives on the server — this is a cache of what it last said, kept locally so
// the number is on screen before a round trip finishes. Anything that actually moves
// money comes back with the new balance and `adopt` takes it.
//
// Identity is Firebase's. `uid` and `email` are written by the auth-state listener and by
// nothing else — signing in happens in AuthView, which hands Firebase a credential; this
// class only ever notices. That is also what restores a session off the Keychain, which
// is why it survives a reinstall where the old device-keyed wallet did not.
//
// `plan` is Apple's answer, not ours: Shop reads it out of `Transaction.currentEntitlements`
// and writes it here through `entitled`. The UserDefaults copy is a cache for the cold
// launch, the same way `sparks` is a cache of the ledger.
@Observable @MainActor final class Account {
    /// True until Firebase has said who is signed in. The root view holds still for it
    /// rather than flashing the sign-in screen at somebody whose session is coming back.
    private(set) var restoring = true
    private(set) var uid: String?
    private(set) var email: String?
    private(set) var plan: Plan?
    var sparks: Int

    /// StoreKit. Held here because every screen that sells something already has the
    /// account in the environment, and the two only ever move together. Ignored by
    /// Observation — the reference never changes, and Shop publishes its own insides.
    @ObservationIgnored private(set) lazy var shop = Shop(self)

    var signedIn: Bool { uid != nil }
    /// What to call you on the home screen. Apple hands back an address only on the very
    /// first authorization, and a relay one at that, so this falls through often.
    var name: String {
        guard let first = email?.prefix(while: { $0.isLetter }), !first.isEmpty else { return "there" }
        return first.prefix(1).uppercased() + first.dropFirst()
    }
    var subscribed: Bool { plan != nil }
    var fittingsLeft: Int { Spend.fittings(sparks) }
    var liveSeconds: Int { sparks }

    private let d = UserDefaults.standard
    /// Dev flags fake a session, so the jump-to-screen launch arguments still land on a
    /// phone that has never signed in. `dev:auth` and `dev:mail` are the exceptions —
    /// they ask for the real sign-in screen, so they must not be faked past.
    private let faking = Dev.jumping && !Dev.has("dev:auth") && !Dev.has("dev:mail")
    /// A launch argument said what the plan is, so the App Store doesn't get a vote.
    private let pinned = Dev.has("dev:pro") || Dev.has("dev:broke")

    init() {
        // Firebase has to be up before Auth.auth() is touched, and a SwiftUI App's stored
        // property defaults are evaluated *before* its init body — so configuring in
        // MiraApp.init would already be too late for this line. Idempotent on purpose.
        if FirebaseApp.app() == nil { FirebaseApp.configure() }

        plan   = d.string(forKey: "plan").flatMap(Plan.init(rawValue:))
        sparks = d.object(forKey: "sparks") as? Int ?? Spend.perFitting   // one fitting on the house

        if Dev.has("dev:pro") { plan = .monthly; sparks = Spend.sparks(Plan.fittings) }
        if Dev.has("dev:broke") { plan = nil; sparks = 0 }
        if faking {
            uid = "dev"; email = "you@mira.ai"; restoring = false
            return                                          // no listener: it would undo all of that
        }

        // Fires once with whatever the Keychain had, then on every sign-in and sign-out.
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            MainActor.assumeIsolated { self?.became(user) }
        }
        // Everything Apple already owes this phone, asked for at launch: a renewal that
        // happened while the app was shut, a purchase made on another device, and any
        // transaction whose credit never landed the first time.
        shop.start()
    }

    /// Firebase changed its mind about who this is.
    private func became(_ user: User?) {
        restoring = false
        guard user?.uid != uid else { email = user?.email; return }
        let first = uid == nil                              // signing in, rather than switching
        uid = user?.uid
        email = user?.email
        // Each account's balance is remembered under its own key, so the next person to
        // hold the phone never sees the last one's number. Signing in for the first time
        // carries the device wallet's over, because the server moves those same sparks.
        sparks = d.object(forKey: purse) as? Int ?? (first ? sparks : 0)
        // A receipt credits an account, so nothing Apple owes could be handed over until
        // there was one. Whatever this Apple ID owns lands on the wallet now.
        Task { await sync(); await shop.settle() }
    }

    /// Where this account's cached balance is written down. Signed out, that is the
    /// device wallet the server still opens for a caller with no token.
    private var purse: String { uid.map { "sparks:\($0)" } ?? "sparks" }

    /// Take the server's number. It is the only one that can actually be spent.
    func adopt(_ n: Int) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { sparks = max(0, n) }
        d.set(sparks, forKey: purse)
    }

    /// Ask what we really have. Quiet on failure — a stale number beats an error banner
    /// over a mirror, and the next spend gets refused by the server anyway.
    func sync() async {
        if let n = try? await API.balance() { adopt(n) }
    }

    func signOut() {
        try? Auth.auth().signOut()                          // the listener does the rest
        plan = nil
        d.removeObject(forKey: "plan")
        // The subscription belongs to the Apple ID, not to this Mira account, so it is
        // still bought and paid for — `settle` holds off while signed out and hands it
        // back on the next sign-in, which is the only place a receipt can be credited.
        // ponytail: the lookbook stays. It never leaves the phone, so signing out is not
        // the moment to delete somebody's photographs — and signing back in would find
        // them gone. Clear the Vault here the day looks live on the account.
    }

    /// Apple requires account deletion wherever there is account creation. The auth
    /// record goes first — if Firebase wants a fresher sign-in it refuses before
    /// anything is lost — then the wallet, on a token minted while the user still
    /// existed. Returns the sentence to show, or nil once the account is gone.
    func deleteAccount() async -> String? {
        guard let user = Auth.auth().currentUser else { return nil }
        let uid = user.uid
        let token = try? await user.getIDToken()
        do { try await user.delete() }
        catch let e as NSError where e.code == AuthErrorCode.requiresRecentLogin.rawValue {
            // A stale session may not delete an account. Signing out is the honest move:
            // the next screen is the sign-in Firebase wants, and nothing is lost yet.
            signOut()
            return "To confirm it's you, sign in again and then delete your account."
        }
        catch { return error.localizedDescription }
        // Best-effort: if this call is lost, what's orphaned is one integer under a
        // hashed key that no longer has an owner to name.
        try? await API.closeWallet(token: token)
        plan = nil
        d.removeObject(forKey: "plan")
        d.removeObject(forKey: "sparks:\(uid)")     // the listener has already moved on
        return nil
    }

    /// False if the purchase didn't happen, in which case the sheet stays where it is and
    /// `shop.fault` has the sentence to show. Dismissing over a failed payment is how you
    /// get the support mail that opens "you charged me".
    func subscribe(_ p: Plan) async -> Bool {
        tap(.medium)
        return await shop.buy(p.productID)
    }

    func topup(_ pack: Pack) async -> Bool {
        tap(.medium)
        return await shop.buy(pack.id)
    }

    /// Apple requires a working Restore on any screen that sells something.
    func restore() async {
        tap(.medium)
        await shop.restore()
    }

    /// What Apple says this Apple ID owns, straight from `Transaction.currentEntitlements`.
    /// Cached so a cold launch isn't a paywall in a subscriber's face while StoreKit wakes
    /// up, then overwritten the moment it answers — including to nil, which is what makes
    /// a cancelled subscription actually lapse.
    func entitled(_ p: Plan?) {
        guard !pinned else { return }               // a dev flag outranks the store
        plan = p
        if let p { d.set(p.rawValue, forKey: "plan") } else { d.removeObject(forKey: "plan") }
    }
}
