import SwiftUI

// MARK: - the unit
//
// One spark = one second of Mira compute = $0.02 of COGS.
// Everything the app can do is priced in sparks so margin is knowable per tap.

enum Spend {
    static let look = 3          // a still try-on render  ~$0.06
    static let livePerMinute = 60 // the mirror running    ~$1.20
    static let costPerSpark = 0.02
    /// Mirrors MAX_SESSION_SECONDS on the server, which is the real ceiling.
    static let maxLiveSeconds = 120

    static func sparks(forLiveSeconds s: Int) -> Int { (s * livePerMinute + 59) / 60 }
    static func liveSeconds(forSparks n: Int) -> Int { n * 60 / livePerMinute }
}

enum Plan: String, CaseIterable, Identifiable {
    // yearly first: it is the one being sold, and CaseIterable sets the order on the paywall
    case yearly, monthly
    var id: String { rawValue }

    /// The intro offer, in seconds of live mirror. Three minutes is $3.60 of compute —
    /// the most expensive pitch we run and the only one that has ever worked, because
    /// nobody buys a mirror they have not stood in front of.
    // ponytail: copy and grant both read this, so they cannot drift. StoreKit has to be
    // told separately when the real introductory offer is configured.
    static let trialSeconds = 180

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
        case .yearly:  "Start free & save 50%"
        case .monthly: "Monthly"
        }
    }
    /// The catch, spelled out under the headline. Nil when there isn't one.
    var billed: String? {
        switch self {
        case .yearly:  "$149.99 billed annually"
        case .monthly: nil
        }
    }
    var cadence: String {
        switch self {
        case .yearly:  "per year"
        case .monthly: "per month"
        }
    }
    var note: String {
        switch self {
        case .yearly:
            "\(Self.trialCopy) free, then $149.99 per year. Billed annually and renews automatically unless canceled in the App Store."
        case .monthly:
            "$24.99 per month. Renews automatically unless canceled in the App Store."
        }
    }
    var badge: String? {
        switch self {
        case .yearly:  "\(Self.trialCopy.uppercased()) FREE"
        case .monthly: nil
        }
    }
    /// Sparks granted, refreshed every month.
    var sparks: Int { 600 }

    /// "3 minutes" — written once so the badge, the headline and the small print agree.
    static var trialCopy: String { "\(trialSeconds / 60) minutes" }

    var grant: String { "600 sparks a month" }
}

struct Pack: Identifiable {
    let id: String
    let sparks: Int
    let price: String
    let note: String?

    // ponytail: hardcoded. StoreKit products replace this when there's an App Store Connect entry.
    static let all = [
        Pack(id: "spark.150", sparks: 150, price: "$9.99",  note: nil),
        Pack(id: "spark.350", sparks: 350, price: "$19.99", note: "MOST POPULAR"),
        Pack(id: "spark.800", sparks: 800, price: "$39.99", note: nil),
    ]
}

// The sparks live on the server — this is a cache of what it last said, kept locally so
// the number is on screen before a round trip finishes. Anything that actually moves
// money comes back with the new balance and `adopt` takes it.
//
// ponytail: plan and email are still UserDefaults with a mocked purchase. StoreKit 2 and
// a receipt-verifying server slot in behind subscribe/topup without moving anything else.
@Observable final class Account {
    var email: String?
    var plan: Plan?
    var sparks: Int

    var signedIn: Bool { email != nil }
    /// What to call you on the home screen. The address is all Google hands over until
    /// we ask for a profile scope we don't need yet.
    var name: String {
        guard let first = email?.prefix(while: { $0.isLetter }), !first.isEmpty else { return "there" }
        return first.prefix(1).uppercased() + first.dropFirst()
    }
    var subscribed: Bool { plan != nil }
    var looksLeft: Int { sparks / Spend.look }
    var liveSeconds: Int { sparks }

    private let d = UserDefaults.standard

    init() {
        email  = d.string(forKey: "email")
        plan   = d.string(forKey: "plan").flatMap(Plan.init)
        sparks = d.object(forKey: "sparks") as? Int ?? 15   // 5 looks on the house

        if Dev.has("dev:pro") { email = "you@mira.ai"; plan = .monthly; sparks = 600 }
        if Dev.has("dev:broke") { email = "you@mira.ai"; plan = nil; sparks = 0 }
    }

    /// Take the server's number. It is the only one that can actually be spent.
    func adopt(_ n: Int) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { sparks = max(0, n) }
        d.set(sparks, forKey: "sparks")
    }

    /// Ask what we really have. Quiet on failure — a stale number beats an error banner
    /// over a mirror, and the next spend gets refused by the server anyway.
    func sync() async {
        if let n = try? await API.balance() { adopt(n) }
    }

    func signIn(_ address: String) {
        tap(.medium)
        email = address
        d.set(address, forKey: "email")
    }

    func signOut() {
        email = nil; plan = nil
        d.removeObject(forKey: "email"); d.removeObject(forKey: "plan")
    }

    func subscribe(_ p: Plan) {
        tap(.medium)
        // ponytail: mocked purchase, so the grant lands once ever. StoreKit's verified
        // transaction id replaces this, and a renewal is what refills.
        let first = plan == nil
        plan = p
        d.set(p.rawValue, forKey: "plan")
        if first { buy(p.sparks) }
    }

    func topup(_ pack: Pack) {
        tap(.medium)
        buy(pack.sparks)
    }

    /// Show the sparks landing, then let the server say whether they really did. When it
    /// refuses — which it does in production, there being no receipt — the number snaps
    /// back rather than promising compute nobody paid for.
    private func buy(_ n: Int) {
        credit(n)
        Task {
            if let settled = try? await API.purchase(sparks: n) { adopt(settled) } else { await sync() }
        }
    }

    private func credit(_ n: Int) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { sparks = max(0, sparks + n) }
        d.set(sparks, forKey: "sparks")
    }
}
