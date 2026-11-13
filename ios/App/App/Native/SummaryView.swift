import SwiftUI

/// The home screen: the money summary, in the same plain
/// shape as the website's overview + true-profit view.
///
/// THE RULE (Mary's, and the server's): profit = commissions
/// + refunds that have actually landed − costs. A refund that
/// is still on its way is shown as "still coming" and never
/// counted. Every number here is the server's own /api/profit
/// answer (integer cents, exact) — nothing is added up on the
/// phone.
struct SummaryView: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var showingScan = false

    var body: some View {
        Form {
            if let error = store.errorText {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }

            moneySection
            countsSection
            upcomingSection

            Section {
                Button {
                    showingScan = true
                } label: {
                    Label("Scan a screenshot", systemImage: "camera.viewfinder")
                }
            }
        }
        .navigationTitle("What'd I Make?")
        .task {
            await store.loadSummary()
        }
        .refreshable {
            await store.loadSummary()
        }
        .sheet(isPresented: $showingScan) {
            NavigationStack {
                ScanView()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var moneySection: some View {
        Section(header: Text("Your money")) {
            if let profit = store.profit {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profit")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(MoneyText.cents(profit.totals.netCents))
                        .font(.largeTitle).fontWeight(.bold)
                        .foregroundStyle(profit.totals.netCents < 0 ? .red : .primary)
                    Text("Commissions + refunds that landed − costs.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                LabeledContent("Commissions", value: MoneyText.cents(profit.totals.commissionsCents))
                LabeledContent("Refunds received", value: MoneyText.cents(profit.totals.refundsReceivedCents))
                LabeledContent("Costs", value: MoneyText.cents(profit.totals.costsCents))
                if profit.totals.refundsPendingCents > 0 {
                    LabeledContent("Refunds still coming", value: MoneyText.cents(profit.totals.refundsPendingCents))
                    Text("Still-coming refunds count only when the money lands — that's why they're not in your profit yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let taskIncome = profit.totals.taskIncomeCents, taskIncome > 0 {
                    LabeledContent("Of which task rewards", value: MoneyText.cents(taskIncome))
                }
            } else if store.isLoading {
                HStack {
                    ProgressView()
                    Text("Adding it up…")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Your money summary will show here.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var countsSection: some View {
        if let overview = store.overview {
            Section(header: Text("Your shop so far")) {
                LabeledContent("Products", value: String(overview.products))
                LabeledContent("Videos logged", value: String(overview.videos))
                LabeledContent("Tasks", value: String(overview.tasks))
                LabeledContent("Sales logged", value: MoneyText.dollars(overview.totalEarnings))
            }
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        if let overview = store.overview, !overview.upcomingTasks.isEmpty {
            Section(header: Text("Coming up")) {
                ForEach(overview.upcomingTasks) { task in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.name)
                            .fontWeight(.medium)
                        Text(upcomingLine(for: task))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func upcomingLine(for task: TaskItem) -> String {
        var parts: [String] = []
        if let deadline = task.deadline, !deadline.isEmpty {
            parts.append("Due " + deadline)
        }
        if task.targetVideos > 0 {
            parts.append(String(task.videosDone) + " of " + String(task.targetVideos) + " videos")
        }
        return parts.joined(separator: " · ")
    }
}
