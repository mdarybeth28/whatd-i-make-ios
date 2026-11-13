import SwiftUI

/// The signed-in app (Phase 2): a tab bar over the tracker's
/// core screens, mirroring the website's own sections —
/// Home (the money summary), Products, Videos, Money (the
/// sales log), and More (tasks, scoreboard, Etsy, account).
///
/// One TrackerStore lives here and is shared through the
/// environment, so a save on any tab is already true on the
/// others. If any call hears the server's gate (401/402), the
/// session re-checks itself and LaunchView routes accordingly
/// — this view never argues with the gate.
struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var store = TrackerStore()

    var body: some View {
        TabView {
            NavigationStack {
                SummaryView()
            }
            .tabItem { Label("Home", systemImage: "house") }

            NavigationStack {
                ProductsView()
            }
            .tabItem { Label("Products", systemImage: "tag") }

            NavigationStack {
                VideosView()
            }
            .tabItem { Label("Videos", systemImage: "play.rectangle") }

            NavigationStack {
                MoneyView()
            }
            .tabItem { Label("Money", systemImage: "dollarsign.circle") }

            NavigationStack {
                MoreView()
            }
            .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .environmentObject(store)
        .onChange(of: store.gateBlocked) { blocked in
            if blocked {
                Task {
                    await session.refreshAccess()
                    store.clearGateBlock()
                }
            }
        }
    }
}
