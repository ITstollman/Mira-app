import StoreKit

/// StoreKit 2. Apple takes the money and hands back a signed transaction; the server is
/// the only thing that reads it, because an app allowed to say what it just bought is the
/// mocked purchase this replaced.
///
/// The rule that makes every path here safe to retry: a transaction is *finished* only
/// after the server has credited it. Anything that goes wrong in between — no signal, a
/// crash, the app killed mid-sheet — leaves it unfinished, StoreKit hands it straight back
/// on the next launch, and the ledger pays out per transaction id exactly once.
@Observable @MainActor final class Shop {
    /// Every id the app can ask for. Typed into App Store Connect by hand and into
    /// `SOLD` in server/server.js by hand, so all three drift independently — Checks.swift
    /// covers the shape of this one and the server's tests cover its own.
    static var ids: Set<String> { Set(Plan.allCases.map(\.productID) + Pack.all.map(\.id)) }

    /// Apple's row for each id, which is where the price the user will actually be charged
    /// lives — the strings in Account.swift are USD, and a fallback. Empty until the store
    /// answers, and empty forever in a build with nothing configured behind it.
    private(set) var products: [String: Product] = [:]
    /// What is being bought this second, so the row that was tapped is the one that spins.
    private(set) var buying: String?
    /// Worth putting in front of someone. Cancelling is not a fault and never sets this.
    var fault: String?

    private unowned let account: Account

    init(_ account: Account) { self.account = account }

    /// Once, after the account exists. The listener runs for the life of the app: a
    /// renewal, an Ask-to-Buy finally approved, or a purchase made on another phone all
    /// arrive there rather than through `buy`.
    func start() {
        Task { [weak self] in
            for await _ in Transaction.updates { await self?.settle() }
        }
        Task { await load(); await settle() }
    }

    func load() async {
        let found = (try? await Product.products(for: Shop.ids)) ?? []
        products = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Apple's price, in the viewer's own currency. Nil until the store has answered,
    /// which is every caller's cue to fall back to the hardcoded dollars.
    func price(_ id: String) -> String? { products[id]?.displayPrice }

    /// That price cut into `n` and set in the same currency — "$12.50" under the yearly
    /// plan, "$2.00" under a ten-pack. Nil for the same reason `price` is.
    func split(_ id: String, by n: Int) -> String? {
        guard n > 0, let p = products[id] else { return nil }
        return (p.price / Decimal(n)).formatted(p.priceFormatStyle)
    }

    /// Buy one thing. True only once Apple has taken the money *and* the server has
    /// credited it — which is the only moment a sheet is allowed to close over a purchase.
    func buy(_ id: String) async -> Bool {
        guard buying == nil else { return false }
        if products[id] == nil { await load() }      // a fast tap can beat the store's answer
        guard let product = products[id] else {
            fault = "That isn't on sale right now — try again in a moment."
            return false
        }

        buying = id
        defer { buying = nil }
        do {
            switch try await product.purchase() {
            case .success(let signed):
                guard case .verified = signed else {
                    fault = "The App Store couldn't verify that purchase."
                    return false
                }
                // Deliberately not reading any further into `signed`: settle() asks Apple
                // what is owned rather than trusting the object in hand, and this is in it.
                return await settle()

            case .pending:
                // Ask to Buy, or a bank that wants a word first. Transaction.updates has it.
                fault = "That needs approval first. Your fittings land the moment it goes through."
                return false

            case .userCancelled:
                return false

            @unknown default:
                return false
            }
        } catch {
            fault = error.localizedDescription
            return false
        }
    }

    /// Apple requires a working Restore on any screen that sells something. `sync` is the
    /// part that re-authenticates and replays what this Apple ID owns; `settle` is the
    /// part that turns it back into fittings.
    func restore() async {
        try? await AppStore.sync()
        await load()
        await settle()
    }

    /// Hand the server everything Apple currently says is owned, and take back the balance
    /// it lands on.
    ///
    /// A subscription lives in `currentEntitlements`, where a renewal turns up as a new
    /// transaction id — that, and nothing else, is what refills the month. Miss three
    /// months and Apple still offers one entitlement, so three months away is one grant
    /// rather than three: fittings do not stockpile, which is the whole margin.
    ///
    /// A consumable never appears there at all, so those come from `unfinished` — which is
    /// exactly where a purchase whose credit never landed has been waiting.
    @discardableResult
    func settle() async -> Bool {
        // Signed out there is no account to credit, and the server says so with a 401.
        // Sign-in calls this again, which is where a purchase made in the gap lands.
        guard account.signedIn else { return false }

        var owned: Plan?
        var receipts: [String: Transaction] = [:]

        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result else { continue }
            receipts[result.jwsRepresentation] = t
            if let plan = Plan(product: t.productID) { owned = plan }
        }
        for await result in Transaction.unfinished {
            guard case .verified(let t) = result else { continue }
            receipts[result.jwsRepresentation] = t
        }
        account.entitled(owned)

        guard !receipts.isEmpty else { return true }
        guard let sparks = try? await API.purchase(receipts: Array(receipts.keys)) else { return false }
        account.adopt(sparks)
        // Only now. An unfinished transaction is the one thing that survives a crash
        // between Apple taking the money and us handing over the fittings.
        for t in receipts.values { await t.finish() }
        return true
    }
}
