import SwiftUI

/// The paywall — shown when the server's gate says this
/// account is signed in but has no access (the free week
/// ended, or a subscription lapsed).
///
/// PHASE 2: the purchase button is real. It runs Apple's
/// StoreKit purchase for the $12/month product (the settled
/// price — the same on web and in the app, Mary's call), and
/// a verified purchase is confirmed with the server's Apple
/// bridge (POST /billing/apple/verify), which writes
/// subscription_status the way the Stripe webhook does. The
/// gate is then re-asked. This screen never grants access by
/// itself: if the server doesn't say yes, nobody gets in —
/// the same rule as the website's Stripe door.
struct PaywallView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var subs = SubscriptionStore()
    @State private var isConfirming = false
    @State private var note: String?

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
                subscribeSection
                checkAgainRow
                signOutRow
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            subs.onVerifiedTransaction = { jws in
                await confirmWithServer(jws)
            }
            subs.start()
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
    }

    private var subscribeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task {
                    if let jws = await subs.purchase() {
                        await confirmWithServer(jws)
                    }
                }
            } label: {
                HStack {
                    Spacer()
                    if subs.isBusy || isConfirming { ProgressView() }
                    Text("Subscribe — " + (subs.product?.displayPrice ?? "$12") + "/month")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(subs.isBusy || isConfirming)

            Button {
                Task {
                    if let jws = await subs.restore() {
                        await confirmWithServer(jws)
                    } else if subs.phase == .idle {
                        note = "Apple didn't find a subscription to restore for this account."
                    }
                }
            } label: {
                Text("Restore purchases")
                    .fontWeight(.semibold)
            }
            .disabled(subs.isBusy || isConfirming)

            if case .failed(let message) = subs.phase {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            if let note {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Payment goes through Apple with Face ID — no card typed here. Cancel anytime in your Apple subscriptions. Subscribing on the website instead works too; it's the same account and the same price.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var checkAgainRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await session.refreshAccess() }
            } label: {
                Text("Check again")
                    .fontWeight(.semibold)
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

    // MARK: - Server confirmation

    /// Sends one verified transaction to the server bridge,
    /// then re-asks the gate. The bridge verifies Apple's
    /// signature itself — the app only carries the message.
    private func confirmWithServer(_ jws: String) async {
        isConfirming = true
        note = nil
        do {
            let response = try await APIClient.shared.post("/billing/apple/verify", json: ["signedTransaction": jws])
            if response.status == 200 {
                await session.refreshAccess()
                if session.state == .subscriptionRequired {
                    note = "Apple confirmed the purchase, but the server hasn't opened the door yet. Give it a moment and tap Check again."
                }
            } else {
                note = response.serverMessage ?? "The server couldn't confirm that purchase yet. Tap Check again in a moment — if it keeps happening, tell Mary."
            }
        } catch {
            note = "Could not reach the server to confirm the purchase. Check your connection and tap Check again."
        }
        isConfirming = false
    }
}
