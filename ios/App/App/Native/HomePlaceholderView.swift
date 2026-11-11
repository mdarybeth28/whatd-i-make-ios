import SwiftUI

/// The signed-in landing for Phase 1. Its whole job is to prove
/// the auth round-trip end to end — the app signed in against
/// the real server, the gate said this account has access, and
/// here is the account it belongs to. No data screens and NO
/// fake data: products, videos, sales and the profit view are
/// the next phase, built on this same API client.
struct HomePlaceholderView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("You're in. 🎉")
                        .font(.title3).fontWeight(.bold)
                    Text("Data screens come next.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
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
            }
            Section {
                Button(role: .destructive) {
                    Task { await session.signOut() }
                } label: {
                    Text("Sign out")
                }
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
