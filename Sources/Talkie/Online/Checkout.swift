import Foundation

/// Buying Pro, through Lemon Squeezy. The checkout is tagged with your Talkie account, so the
/// payment lands on your board: Lemon Squeezy tells the lemon-webhook function, which turns Pro on,
/// and your profile changing is how the app hears about it.
enum Checkout {
    /// Talkie Pro's two subscriptions. Nil until the store is set up; Go Pro shows the pricing then.
    static let monthly: URL? = nil
    static let yearly: URL? = nil
    /// The store's customer portal: receipts, changing card, switching or cancelling.
    static let manage: URL? = nil

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
