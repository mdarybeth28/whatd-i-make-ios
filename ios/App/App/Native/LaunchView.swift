import SwiftUI

/// The app's front door: routes by the session state, nothing
/// else.
///
/// - restoring: a brief loading state while /auth/me answers.
/// - signedOut / working: the sign-in form (with the road to
///   sign-up). "working" keeps the same branch so the form —
///   and what the user typed — stays on screen during a
///   sign-in attempt.
/// - subscriptionRequired: the paywall (the server's gate said
///   signed in, no access) — now with the real Apple purchase
///   button (Phase 2).
/// - signedIn: HomeView — the tab bar with the data screens
///   (Phase 2), at website parity for the core flows.
///
/// COLOR PIN (Phase 2, the Pet build-3 lesson): the root view
/// is pinned to the light color scheme. Without it, semantic
/// colors flip in dark traits and text can render white on the
/// app's cream surfaces. The pin lives here, on the one root
/// view every branch passes through, so no screen can miss it.
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
                HomeView()
            } else if session.state == .subscriptionRequired {
                PaywallView()
            } else {
                NavigationStack {
                    SignInView()
                }
            }
        }
        .environmentObject(session)
        .preferredColorScheme(.light)
        .task {
            await session.restore()
        }
    }
}
