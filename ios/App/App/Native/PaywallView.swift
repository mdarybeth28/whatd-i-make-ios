import SwiftUI

/// The paywall — shown when the server's gate says this account
/// is signed in but has no access (the free week ended, or a
/// subscription lapsed). It carries the web gate's own plain
/// facts: What'd I Make? is $12/month, and access is decided by
/// the server, never by this screen.
///
/// PHASE 1 SHAPE: there is deliberately NO purchase button
/// yet. The Apple product does not exist until it is created
/// in App Store Connect (after the Paid Apps paperwork
/// clears), and the server's IAP bridge is a later phase too.
/// What ships now is the honest screen around that future
/// button: the explanation, the account it applies to, a
/// "Restore / check again" that re-asks the server, and
/// sign-out.
struct PaywallView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var isChecking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let email = session.currentEmail {
                    Text("Signed in as " + email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                statusSection
                checkAgainRow
                signOutRow
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your free week has ended")
                .font(.title2).fontWeight(.bold)
            Text("What'd I Make? is " + StoreConfig.priceDisplay + " after the free week. Keep your products, videos and money numbers all in one place — subscribe and you are right back in.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let status = session.subscriptionStatus, !status.isEmpty {
            Text("Subscription state: " + status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        if let ends = session.trialEndsAt, !ends.isEmpty {
            Text("Free week ended: " + ends)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        // FUTURE PURCHASE BUTTON SPOT (Phase 3): the "Subscribe —
        // $12/month" button goes here. It will present Apple's
        // StoreKit purchase for StoreConfig.monthlyProductID and
        // then confirm through the server's IAP bridge, which
        // writes subscription_status the way the Stripe webhook
        // does today. Until the App Store Connect product and
        // the bridge exist, no button is shown — a button that
        // cannot finish would be a lie on the screen.
    }

    private var checkAgainRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isChecking = true
                Task {
                    await session.refreshAccess()
                    isChecking = false
                }
            } label: {
                HStack {
                    if isChecking { ProgressView() }
                    Text("Restore / check again")
                        .fontWeight(.semibold)
                }
            }
            Text("Just paid, or renewed on the website? Tap this and the app asks the server again — if your account has access now, you go straight in.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var signOutRow: some View {
        Button(role: .destructive) {
            Task { await session.signOut() }
        } label: {
            Text("Sign out")
        }
    }
}
