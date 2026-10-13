import Foundation

/// Buying Pro, through Lemon Squeezy. The checkout is tagged with your Talkie account, so the
/// payment lands on your board: Lemon Squeezy tells the lemon-webhook function, which turns Pro on,
/// and your profile changing is how the app hears about it.
enum Checkout {
    /// Off until the store is live. The links below are test mode, where Lemon Squeezy's test card
    /// would hand out Pro for nothing; Go Pro shows "payments open soon" meanwhile.
    static let isOpen = false

    /// Talkie Pro's two subscriptions in the switchtalkie store (product 1437273), each opening with
    /// its own variant picked. Test mode: these change when the store goes live.
    static var monthly: URL? { isOpen ? URL(string: "https://switchtalkie.lemonsqueezy.com/checkout/buy/7fe1762b-1474-4c5a-b069-80dba1a18587?enabled=2244194") : nil }
    static var yearly: URL? { isOpen ? URL(string: "https://switchtalkie.lemonsqueezy.com/checkout/buy/04b28ff2-47d0-464d-b9cc-0768b904251b?enabled=2244196") : nil }
    /// Where buyers sign in by email to see receipts, change card, switch or cancel.
    static var manage: URL? { isOpen ? URL(string: "https://app.lemonsqueezy.com/my-orders") : nil }

    /// A checkout link that carries your account (and code, to find you by if you write in).
    static func link(_ base: URL, account: UUID, code: String) -> URL {
        guard var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
        parts.queryItems = (parts.queryItems ?? []) + [
            URLQueryItem(name: "checkout[custom][user_id]", value: account.uuidString.lowercased()),
            URLQueryItem(name: "checkout[custom][code]", value: code)
        ]
        return parts.url ?? base
    }
}
