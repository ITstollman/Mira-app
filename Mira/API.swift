import FirebaseAuth
import FirebaseCore
import UIKit

/// The Mira server. The permanent Decart key never comes near the app — the server
/// mints a short-lived client token and we hand that straight to the SDK.
enum API {
    // The fallbacks are what the app actually runs on. ProcessInfo carries the scheme's
    // variables *only* while Xcode owns the process — tap the icon on the phone and they
    // are gone, so a localhost default had the iPhone dialling itself: "could not connect
    // to the server". The env vars remain the override for pointing at a local server.
    // ponytail: the shared secret is a doorman, not a lock — anyone who pulls the binary
    // apart gets this one, and it only keeps scanners off the free routes. Identity is the
    // Firebase ID token below; the server keys the wallet off that when it is there.
    static let base = URL(string: env("MIRA_API") ?? "https://mira-server-production-550f.up.railway.app")!
    // The doorman never appears in this repo. Secrets.xcconfig (gitignored) puts it
    // in Info.plist at build time, so the shipped binary has it and git does not.
    // An unfilled Secrets.xcconfig leaves it empty, which the server refuses loudly.
    private static let secret = env("MIRA_KEY")
        ?? (Bundle.main.object(forInfoDictionaryKey: "MIRAKey") as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
        ?? "dev-secret"
    // Who we are before anyone signs in. The server still opens a wallet on it, and
    // hands that wallet over on first sign-in.
    // ponytail: delete this the day the app can be forced to update — see the matching
    // comment in server/ledger.js.
    private static let device = UIDevice.current.identifierForVendor?.uuidString ?? "sim"

    struct Token {
        let value: String, model: String, grant: String
        let seconds: Int
        /// What the wallet had left after the server charged for this session.
        let sparks: Int
    }

    /// A client token good for one live-mirror session, capped server-side at `seconds`.
    /// The sparks are gone by the time this returns — `refund` gives back what goes unused.
    static func mirrorToken(seconds: Int) async throws -> Token {
        let wire: TokenWire = try await send("/v1/mirror/token", body: ["seconds": seconds])
        guard let value = wire.value else { throw Fault("the server minted an empty token") }
        return Token(value: value, model: wire.model, grant: wire.grant,
                     seconds: wire.seconds, sparks: wire.sparks)
    }

    /// What the wallet holds, according to the only copy that counts.
    static func balance() async throws -> Int {
        let w: Wallet = try await send("/v1/account", body: nil)
        return w.sparks
    }

    /// Hand back the seconds a live session never used. The server won't return more
    /// than it charged, and won't honour the same grant twice.
    static func refund(grant: String, seconds: Int) async throws -> Int {
        let w: Wallet = try await send("/v1/mirror/refund", body: ["grant": grant, "seconds": seconds])
        return w.sparks
    }

    /// The signed transactions Apple handed over. The server verifies each against Apple's
    /// root certificate and pays out per transaction id exactly once, so resending is free
    /// — which is what makes it safe to keep handing over everything StoreKit still holds.
    static func purchase(receipts: [String]) async throws -> Int {
        let w: Wallet = try await send("/v1/account/credit", body: ["receipts": receipts])
        return w.sparks
    }

    /// Paste a product URL, get back what the page is selling — including every photo it
    /// offers. Which of them is the garment rather than the mood is the user's call, so
    /// this stops at handing over the list.
    static func find(_ link: String) async throws -> Scraped {
        try await send("/v1/garment/scrape", body: ["url": link])
    }

    /// One of those photos, by the id `find` handed back. They expire in half an hour.
    static func shot(_ id: String) async throws -> Data {
        try await bytes("/v1/garment/image/\(id.replacingOccurrences(of: "scraped:", with: ""))")
    }

    // MARK: - wire

    struct Scraped: Decodable {
        let id: String, prompt: String, category: String, source: String
        let name: String?, brand: String?, price: Int?
        /// The listing's photos, the page's own lead shot first.
        let images: [String]
    }

    private struct Wallet: Decodable { let sparks: Int }

    /// `apiKey` is Decart's own spelling — their OpenAPI schema, their guide and both
    /// their SDKs agree, and the value is prefixed `ek_`. The rest is ours.
    private struct TokenWire: Decodable {
        let apiKey: String
        let model: String, grant: String
        let seconds: Int, sparks: Int
        var value: String? { apiKey.isEmpty ? nil : apiKey }
    }

    struct Fault: LocalizedError {
        let message: String
        init(_ m: String) { message = m }
        var errorDescription: String? { message }
    }

    /// Asked for per request, never cached in a `static let`: Firebase hands back the one
    /// it already has until the hour is nearly up, so this is a memory read almost always,
    /// and a refresh exactly when it needs to be. A `static let` would freeze whatever was
    /// true at type-init, which on a cold launch is nobody.
    private static func idToken() async -> String? {
        guard FirebaseApp.app() != nil, let user = Auth.auth().currentUser else { return nil }
        return try? await user.getIDToken()
    }

    private static func request(_ path: String, body: [String: Any]?) async -> URLRequest {
        var r = URLRequest(url: base.appending(path: path))
        r.setValue(secret, forHTTPHeaderField: "x-mira-key")
        r.setValue(device, forHTTPHeaderField: "x-mira-device")
        if let token = await idToken() { r.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
        r.timeoutInterval = 30
        if let body {
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "content-type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return r
    }

    /// A nil body means GET.
    private static func send<T: Decodable>(_ path: String, body: [String: Any]?) async throws -> T {
        let (data, response) = try await fetch(await request(path, body: body))
        try check(data, response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func bytes(_ path: String) async throws -> Data {
        let (data, response) = try await fetch(await request(path, body: nil))
        try check(data, response)
        return data
    }

    /// Names the host in the banner. "Could not connect to the server" on its own cannot
    /// tell a stale build still dialling localhost from a server that is genuinely down,
    /// and that ambiguity cost an evening.
    private static func fetch(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await URLSession.shared.data(for: req) }
        catch let e as URLError { throw Fault("\(e.localizedDescription) — \(base.host() ?? "?")") }
    }

    /// Surface the server's own wording — it writes the sentence the user should read.
    private static func check(_ data: Data, _ response: URLResponse) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard !(200..<300).contains(code) else { return }
        let said = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
        throw Fault(said ?? "the server said \(code)")
    }

    private static func env(_ k: String) -> String? {
        ProcessInfo.processInfo.environment[k].flatMap { $0.isEmpty ? nil : $0 }
    }
}
