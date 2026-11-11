import SwiftUI

/// The app's front door: routes by the session state, nothing
/// else. (Phase 1 has no tab bar yet — the data screens arrive
/// in a later phase, and this view grows the tabs then, the
/// way the Keeper apps' root views did.)
///
/// - restoring: a brief loading state while /auth/me answers.
/// - signedOut / working: the sign-in form (with the road to
///   sign-up). "working" keeps the same branch so the form —
///   and what the user typed — stays on screen during a
///   sign-in attempt.
/// - subscriptionRequired: the paywall (the server's gate said
///   signed in, no access).
/// - signedIn: the home placeholder, which proves the auth
///   round-trip end to end and nothing more.
struct LaunchView: View {
    @StateObject private var session = SessionStore()

    var body: some View {
        Group {
            if session.state == .restoring {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Opening What'd I Make?…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if session.state == .signedIn {
                HomePlaceholderView()
            } else if session.state == .subscriptionRequired {
                PaywallView()
            } else {
                NavigationStack {
                    SignInView()
                }
            }
        }
        .environmentObject(session)
        .task {
            await session.restore()
        }
    }
}
