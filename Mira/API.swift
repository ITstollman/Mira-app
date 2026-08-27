import UIKit

/// The Mira server. The permanent Decart key never comes near the app — the server
/// mints a short-lived client token and we hand that straight to the SDK.
enum API {
    // ponytail: dev defaults, overridable from the scheme's environment variables so
    // there's no build config to maintain. Ship-time: bake into an xcconfig, and swap
    // the shared secret for a per-user token once accounts exist — anyone who pulls the
    // binary apart gets this one. The server's session cap and throttle bound the damage.
    static let base = URL(string: env("MIRA_API") ?? "http://127.0.0.1:8787")!
    private static let secret = env("MIRA_KEY") ?? "dev-secret"
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

    // ponytail: no receipt behind this — the server only honours it when MOCK_PURCHASE is
    // on, which production never is, so a "purchase" there fails and the balance snaps
    // back. StoreKit 2's signed transaction is what goes in the body instead.
    static func purchase(sparks: Int) async throws -> Int {
        let w: Wallet = try await send("/v1/account/credit", body: ["sparks": sparks])
        return w.sparks
    }

    /// Paste a product URL, get back something wearable. Two hops: parse, then fetch the shot.
    static func scrape(_ link: String) async throws -> Garment {
        let s: Scraped = try await send("/v1/garment/scrape", body: ["url": link])
        let shot = try await bytes("/v1/garment/image/\(s.id.replacingOccurrences(of: "scraped:", with: ""))")
        return Garment(scraped: s, shot: shot)
    }

    // MARK: - wire

    struct Scraped: Decodable {
        let id: String, prompt: String, category: String, source: String
        let name: String?, brand: String?, price: Int?
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

    private static func request(_ path: String, body: [String: Any]?) -> URLRequest {
        var r = URLRequest(url: base.appending(path: path))
        r.setValue(secret, forHTTPHeaderField: "x-mira-key")
        r.setValue(device, forHTTPHeaderField: "x-mira-device")
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
        let (data, response) = try await URLSession.shared.data(for: request(path, body: body))
        try check(data, response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func bytes(_ path: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request(path, body: nil))
        try check(data, response)
        return data
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
