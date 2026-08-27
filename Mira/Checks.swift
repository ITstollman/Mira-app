#if DEBUG
import DecartSDK
import Foundation

/// One self-check for the parts that would cost money or lie about a garment if they
/// drifted. Runs at launch in DEBUG only.
// ponytail: asserts, not XCTest — there's no test target and this doesn't need one.
enum Checks {
    static func run() {
        // sparks in, sparks out: a session that never used a second costs nothing
        for seconds in [10, 33, 60, 90, 120] {
            let charged = Spend.sparks(forLiveSeconds: seconds)
            assert(charged > 0, "a live session must cost something")
            assert(charged >= seconds * Spend.livePerMinute / 60, "never undercharge — round up")
            assert(Spend.sparks(forLiveSeconds: seconds) - Spend.sparks(forLiveSeconds: seconds) == 0)
        }
        // what the wallet can afford must be affordable
        for wallet in [0, 9, 15, 120, 600] {
            let seconds = min(Spend.maxLiveSeconds, Spend.liveSeconds(forSparks: wallet))
            assert(Spend.sparks(forLiveSeconds: seconds) <= wallet, "quoted \(seconds)s on \(wallet) sparks")
        }
        assert(Spend.liveSeconds(forSparks: 9) < 10, "9 sparks must not buy a session")

        // the paywall makes two arithmetic claims out loud — that the yearly plan is
        // $12.50 *a month*, and that this is half the monthly one. Both have to be true.
        func dollars(_ s: String) -> Double { Double(s.filter { $0.isNumber || $0 == "." }) ?? 0 }
        let yearly = dollars(Plan.yearly.price), monthly = dollars(Plan.monthly.price)
        assert(abs(dollars(Plan.yearly.perMonth) - yearly / 12) < 0.01,
               "the yearly /mo figure isn't \(Plan.yearly.price) split twelve ways")
        assert(abs(dollars(Plan.monthly.perMonth) - monthly) < 0.01)
        assert(yearly / 12 <= monthly / 2 + 0.01, "'save 50%' has to survive the arithmetic")
        assert(Plan.yearly.badge?.contains("3 MINUTES") == true, "the badge lost the offer")
        assert(Plan.yearly.note.hasPrefix(Plan.trialCopy), "small print drifted from the badge")
        assert(Plan.allCases.first == .yearly, "the paywall sells the top row first")

        // every slug the scraper can emit lands somewhere real
        for slug in ["dresses", "tops", "sets", "bottoms", "shoes", "accessories", "nonsense"] {
            assert(Garment.Category(server: slug) != .all, "\(slug) resolved to the All filter")
        }
        assert(Garment.Category(server: "Shoes") == .shoes, "slug match must be case-insensitive")

        // every garment has something to say to Decart
        for g in Catalog.all {
            assert(g.prompt.hasPrefix("Substitute the"), "\(g.id) isn't phrased as a substitution")
            assert(g.prompt.hasSuffix("."), "\(g.id) prompt runs on")
            assert(!g.isMine, "house pieces have no link")
        }
        assert(Set(Catalog.all.map(\.id)).count == Catalog.all.count, "duplicate garment id")
        assert(Size.allCases.allSatisfy { !$0.fit.isEmpty })

        // The server whitelists this exact string when it mints a token, and the SDK puts
        // it on the wire as ?model=. If a vendored-SDK bump moves it, every live session
        // gets refused at connect — so it fails here first, where someone can read it.
        assert(Models.realtime(.lucyVton3_5).name == "lucy-vton-3.5",
               "the model id moved — VTON_MODEL in server/server.js has to move with it")

        NSLog("✓ Mira checks passed")
    }
}
#endif
