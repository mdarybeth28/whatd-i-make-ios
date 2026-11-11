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
/// APPLE IAP DOOR: the product ID below is PROPOSED — a named
/// constant, not an App Store Connect fact yet. When the Paid
/// Apps paperwork clears, ONE auto-renewable subscription
/// product must be created in App Store Connect with EXACTLY
/// this ID, at $12/month:
///   - com.marybethsfinds.whatdimake.monthly
/// The bundle id (com.marybethsfinds.whatdimake) is likewise
/// PROPOSED — it locks only at first submission.
///
/// IAP BRIDGE (LATER PHASE — not in this build): the server gate
/// reads only the users.subscription_status / trial fields in
/// its SQLite DB, which today are written by the Stripe webhook.
/// Apple purchases will need a small server endpoint (the "IAP
/// bridge") that verifies the App Store receipt and writes
/// subscription_status the same way, plus App Store Server
/// Notifications for renewals/cancellations. No StoreKit code
/// ships in Phase 1 at all.
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
