import SwiftUI
import UIKit

/// More: everything that isn't a main tab — Tasks and the
/// Scoreboard, Etsy (status + sync), the Shortcut share key,
/// and the account itself. Same doors as the website's app
/// page, grouped the way the phone wants them.
struct MoreView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var store: TrackerStore
    @State private var shareKey: String?
    @State private var keyCopied = false

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    TasksView()
                } label: {
                    Label("Tasks", systemImage: "checklist")
                }
                NavigationLink {
                    ScoreboardView()
                } label: {
                    Label("Scoreboard", systemImage: "trophy")
                }
            }

            etsySection
            shareSection
            accountSection
        }
        .navigationTitle("More")
        .task {
            await store.loadEtsyStatus()
            if shareKey == nil {
                shareKey = await store.loadShareKey()
            }
        }
    }

    // MARK: - Etsy

    private var etsySection: some View {
        Section(header: Text("Etsy")) {
            if store.etsyConnected {
                LabeledContent("Status", value: "Connected")
                if let shop = store.etsyShopId, !shop.isEmpty {
                    LabeledContent("Shop", value: shop)
                }
                Button("Sync Etsy products") {
                    Task { await store.etsySyncProducts() }
                }
                Button("Sync Etsy sales") {
                    Task { await store.etsySyncSales() }
                }
            } else {
                LabeledContent("Status", value: "Not connected")
                Text("Connecting Etsy starts on the website — it takes you to Etsy's own sign-in and back. Once it's connected there, this page shows it and the sync buttons work here too.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Link("Connect Etsy on whatdimake.com", destination: URL(string: "https://whatdimake.com/oauth/etsy")!)
            }
            if let message = store.etsyMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Shortcut share key

    private var shareSection: some View {
        Section(header: Text("Phone Shortcut")) {
            if let shareKey {
                Text(shareKey)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                Button(keyCopied ? "Copied!" : "Copy key") {
                    UIPasteboard.general.string = shareKey
                    keyCopied = true
                }
                Text("This key is how your iPhone Shortcut adds products and videos without signing in each time. Treat it like a password — anyone with it can act as you.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Your Shortcut key loads with your account.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section(header: Text("Your account")) {
            if let email = session.currentEmail {
                LabeledContent("Email", value: email)
            }
            LabeledContent("Access", value: accessSummary)
            if let status = session.subscriptionStatus, !status.isEmpty {
                LabeledContent("Subscription", value: status)
            }
            if session.trialActive {
                if let ends = session.trialEndsAt, !ends.isEmpty {
                    LabeledContent("Free week ends", value: ends)
                } else {
                    LabeledContent("Free week", value: "Running")
                }
            }
            Button(role: .destructive) {
                Task { await session.signOut() }
            } label: {
                Text("Sign out")
            }
        }
    }

    private var accessSummary: String {
        if session.subscriptionStatus == "active" || session.subscriptionStatus == "trialing" {
            return "Subscribed"
        }
        if session.trialActive {
            return "Free week"
        }
        return "Allowed in"
    }
}
