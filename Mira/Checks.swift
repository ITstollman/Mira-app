#if DEBUG
import DecartSDK
import FirebaseCore
import Foundation
import UIKit

/// One self-check for the parts that would cost money or lie about a garment if they
/// drifted. Runs at launch in DEBUG only.
// ponytail: asserts, not XCTest — there's no test target and this doesn't need one.
enum Checks {
    @MainActor static func run() {
        // fittings in, fittings out — the wallet is only ever spoken in whole ones
        assert(Spend.fittings(Spend.sparks(12)) == 12, "a fitting doesn't survive the round trip")
        assert(Spend.fittings(Spend.perFitting - 1) == 0, "part of a fitting is not a fitting")
        // what the wallet can afford must be affordable, and worth starting
        for wallet in [0, 14, 15, 180, 1125] {
            let seconds = min(Spend.maxLiveSeconds, Spend.liveSeconds(forSparks: wallet))
            assert(seconds <= wallet, "quoted \(seconds)s on a \(wallet)-second wallet")
            assert(wallet < Spend.perFitting || seconds >= Spend.perFitting,
                   "\(wallet) affords a fitting but only \(seconds)s was quoted")
        }

        assert(Spend.said(Spend.sparks(12)) == "12" && Spend.unit(Spend.sparks(12)) == "fittings")
        assert(Spend.said(Spend.perFitting) == "1" && Spend.unit(Spend.perFitting) == "fitting")
        assert(Spend.said(0) == "0" && Spend.unit(0) == "fittings")
        assert(Spend.said(Spend.perFitting - 1) == "0", "an unaffordable balance reads as none")
        for pack in Pack.all { assert(pack.sparks % Spend.perFitting == 0, "\(pack.id) isn't whole fittings") }
        // a bigger pack has to be better value, or the badge on it is a lie
        let each = Pack.all.map { (Double($0.price.dropFirst()) ?? 0) / Double(Spend.fittings($0.sparks)) }
        assert(zip(each, each.dropFirst()).allSatisfy { $0 > $1 + 0.001 },
               "the topup ladder doesn't get cheaper: \(each)")
        // and every one of them dearer than subscribing, or nobody subscribes
        let planEach = 12.50 / Double(Plan.fittings)
        assert(each.allSatisfy { $0 > planEach }, "a topup undercuts Mira Pro")
        // and every one of them clears what a fitting costs us, twice over
        let cost = Double(Spend.perFitting) * Spend.costPerSecond
        assert(each.allSatisfy { $0 > cost * 2 },
               "a topup sells a fitting for under 2x compute: \(each) vs \(cost)")
        // and the plan itself clears it, which is the whole reason the grant is 12
        assert(planEach > cost, "Mira Pro sells a fitting below what it costs to run")

        // the paywall makes two arithmetic claims out loud — that the yearly plan is
        // $12.50 *a month*, and that this is half the monthly one. Both have to be true.
        func dollars(_ s: String) -> Double { Double(s.filter { $0.isNumber || $0 == "." }) ?? 0 }
        let yearly = dollars(Plan.yearly.price), monthly = dollars(Plan.monthly.price)
        assert(abs(dollars(Plan.yearly.perMonth) - yearly / 12) < 0.01,
               "the yearly /mo figure isn't \(Plan.yearly.price) split twelve ways")
        assert(abs(dollars(Plan.monthly.perMonth) - monthly) < 0.01)
        assert(yearly / 12 <= monthly / 2 + 0.01, "'save 50%' has to survive the arithmetic")
        // what the plan hands over is written in three places and they have to agree
        assert(Spend.fittings(Plan.monthly.sparks) == Plan.fittings, "the grant drifted from the copy")
        assert(Plan.allCases.allSatisfy { $0.note($0.price).contains(Plan.included) },
               "small print doesn't say what the plan actually gives you")
        assert(Plan.allCases.first == .yearly, "the paywall sells the top row first")

        // The ids are typed by hand into App Store Connect and again into SOLD in
        // server/server.js. A typo here is a product that never loads and a purchase the
        // server won't pay out, so at least hold the shape still.
        let sold = Plan.allCases.map(\.productID) + Pack.all.map(\.id)
        assert(Set(sold).count == sold.count, "two products share an id")
        assert(sold.allSatisfy { $0.hasPrefix("ai.mira.tryon.") }, "a product id isn't ours: \(sold)")
        assert(Shop.ids.count == sold.count, "Shop asks the store for the wrong set")
        assert(Plan.allCases.allSatisfy { Plan(product: $0.productID) == $0 },
               "an entitlement wouldn't resolve back to its plan")

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
        // a starter outfit that shadowed a catalog id would come back as the wrong
        // garment on relaunch — the Vault looks the catalog up first
        assert(Starter.all.allSatisfy { !Catalog.ids.contains($0.id) }, "a starter outfit shadows a catalog id")
        assert(Set(Starter.all.map(\.id)).count == Starter.all.count, "duplicate starter id")

        // history files a look under the piece it is of. Every look lands exactly once,
        // a piece worn twice is one shelf and not two, and the order kept is the order shown.
        let a = Catalog.all[0], b = Catalog.all[1]
        let kept = [Look(garment: a, size: .s, shot: nil),
                    Look(garment: b, size: .m, shot: nil),
                    Look(garment: a, size: .l, shot: nil)]
        let shelves = Wardrobe.shelves(kept)
        assert(shelves.count == 2, "history made \(shelves.count) shelves out of 2 pieces")
        assert(shelves.map(\.looks.count).reduce(0, +) == kept.count, "history dropped a look")
        assert(shelves[0].garment.id == a.id && shelves[0].looks.count == 2,
               "history lost the order it was kept in")
        assert(Wardrobe.shelves([]).isEmpty, "an empty history is an empty shelf")
        assert(Size.allCases.allSatisfy { !$0.fit.isEmpty })

        // The server whitelists this exact string when it mints a token, and the SDK puts
        // it on the wire as ?model=. If a vendored-SDK bump moves it, every live session
        // gets refused at connect — so it fails here first, where someone can read it.
        assert(Models.realtime(.lucyVton3_5).name == "lucy-vton-3.5",
               "the model id moved — VTON_MODEL in server/server.js has to move with it")

        // The plist in the bundle has to name the project the server verifies tokens
        // against, or every signed-in call comes back "bad token" with nothing on either
        // side saying why.
        assert(FirebaseApp.app()?.options.projectID == "mira-live-virtual-try-on",
               "GoogleService-Info.plist is for a different Firebase project")

        // Google's callback comes back as a url, and it only reaches the app if the
        // reversed client id is registered as a scheme. The two live in different files,
        // so they drift the moment GoogleService-Info.plist is downloaded again. Silent
        // until Google is switched on in the console and the plist grows the key.
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let reversed = NSDictionary(contentsOfFile: path)?["REVERSED_CLIENT_ID"] as? String {
            let urls = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
            assert(urls.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }.contains(reversed),
                   "add \(reversed) to CFBundleURLTypes in Mira-Info.plist or Google sign-in never returns")
        }

        NSLog("✓ Mira checks passed")
    }
}
#endif
