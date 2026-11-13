import Foundation

/// Everything about the Tracker app's server and its (future)
/// Apple payment door, in one place.
///
/// THE SERVER: unlike the Keeper apps (Supabase), "What'd I Make?"
/// runs on Mary's own Node server at whatdimake.com — email +
/// password sign-in with express-session cookies, a SQLite store,
/// and a server-side subscription gate. The native layer talks to
/// that same server's JSON API; the account, the trial, and the
/// gate are the server's, identical to the website's.
///
/// THE PRICE is settled and does not change here: $12/month on
/// every door (web Stripe, Apple IAP). Mary's call, 2026-11-10 —
/// same price both places, and the app sells through Apple
/// in-app purchase (Face ID, done inside the app) rather than
/// sending people out to the website to pay.
///
/// APPLE IAP DOOR: ONE auto-renewable subscription product in
/// App Store Connect with EXACTLY this ID, at $12/month:
///   - com.marybethsfinds.whatdimake.monthly
/// (Created 2026-11-13, with the "What'd I Make? Premium"
/// group — see TRACKER-IOS-STATUS.md.)
///
/// IAP BRIDGE (PHASE 2 — built): the gate reads only the
/// users.subscription_status / trial fields in the server's
/// SQLite DB. The bridge (src/routes/apple-iap.js on the
/// server) verifies Apple's signed transaction itself and
/// writes subscription_status the way the Stripe webhook
/// does; App Store Server Notifications land on its second
/// endpoint for renewals, failures, expiries and revokes.
/// The app's part is small: StoreKit runs the purchase, the
/// signed transaction is POSTed to /billing/apple/verify,
/// and /auth/me is re-asked. Access is never granted locally.
enum StoreConfig {
    // MARK: Server

    /// The one and only server this app talks to. It is an API
    /// base URL for native URLSession calls — never a page the
    /// app loads in a web view.
    static let baseURL = URL(string: "https://whatdimake.com")!

    // MARK: Apple IAP product ID (create in App Store Connect later)

    static let monthlyProductID = "com.marybethsfinds.whatdimake.monthly"
    static let allProductIDs = [monthlyProductID]

    // MARK: Price display (settled — matches the web price)

    static let priceDisplay = "$12/month"
}
