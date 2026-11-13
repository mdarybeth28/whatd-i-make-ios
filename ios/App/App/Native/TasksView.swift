import SwiftUI

/// Tasks: the website's reward trackers, native — post X
/// videos by a deadline, maybe for a cash reward. Progress is
/// bumped here; a reward becomes income only when "Reward
/// received" is tapped and the money has actually landed
/// (the server posts it as a sale at that tap — the same
/// rule as refunds).
struct TasksView: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var showingAdd = false

    var body: some View {
        List {
            if let error = store.errorText {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.subheadline)
            }
            if store.tasks.isEmpty {
                Text("No tasks yet. When a shop offers you a deal — post some videos by a date, maybe for a reward — track it here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.tasks) { task in
                VStack(alignment: .leading, spacing: 6) {
                    Text(task.name)
                        .fontWeight(.medium)
                    Text(line(for: task))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Button("+1 video done") {
                            var edited = task
                            edited.videosDone += 1
                            Task { await store.updateTask(edited) }
                        }
                        .font(.subheadline)
                        if task.videosDone > 0 {
                            Button("−1") {
                                var edited = task
                                edited.videosDone -= 1
                                Task { await store.updateTask(edited) }
                            }
                            .font(.subheadline)
                        }
                        if let reward = task.rewardAmount, reward > 0, task.rewardStatus != "received" {
                            Button("Reward received") {
                                Task { await store.taskRewardReceived(task) }
                            }
                            .font(.subheadline)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .onDelete { offsets in
                for index in offsets {
                    let task = store.tasks[index]
                    Task { await store.deleteTask(task) }
                }
            }
        }
        .navigationTitle("Tasks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add task", systemImage: "plus")
                }
            }
        }
        .task {
            await store.loadTasks()
        }
        .refreshable {
            await store.loadTasks()
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                TaskFormView()
            }
        }
    }

    private func line(for task: TaskItem) -> String {
        var parts: [String] = []
        if task.targetVideos > 0 {
            parts.append(String(task.videosDone) + " of " + String(task.targetVideos) + " videos")
        }
        if let deadline = task.deadline, !deadline.isEmpty {
            parts.append("Due " + deadline)
        }
        if let reward = task.rewardAmount, reward > 0 {
            if task.rewardStatus == "received" {
                parts.append(MoneyText.dollars(reward) + " reward — received")
            } else {
                parts.append(MoneyText.dollars(reward) + " reward if you finish")
            }
        }
        return parts.joined(separator: " · ")
    }
}

/// Add one task — the website's task form fields.
struct TaskFormView: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var targetText = ""
    @State private var hasDeadline = false
    @State private var deadline = Date()
    @State private var rewardText = ""
    @State private var notes = ""
    @State private var isSaving = false

    var body: some View {
        Form {
            Section(header: Text("Task")) {
                TextField("What is the task?", text: $name)
                HStack {
                    Text("Videos to post")
                    Spacer()
                    TextField("0", text: $targetText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            Section(header: Text("Deadline and reward")) {
                Toggle("Has a deadline", isOn: $hasDeadline)
                if hasDeadline {
                    DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
                }
                HStack {
                    Text("Reward ($)")
                    Spacer()
                    TextField("0.00", text: $rewardText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                TextField("Notes", text: $notes, axis: .vertical)
            }
            if let error = store.errorText {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
            Section {
                Button {
                    isSaving = true
                    Task {
                        let ok = await store.createTask(
                            name: name.trimmingCharacters(in: .whitespaces),
                            targetVideos: Int(targetText) ?? 0,
                            deadline: hasDeadline ? DateText.string(from: deadline) : nil,
                            rewardAmount: MoneyText.parse(rewardText),
                            notes: notes.isEmpty ? nil : notes
                        )
                        isSaving = false
                        if ok { dismiss() }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving { ProgressView() }
                        Text("Add task")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("Add task")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Scoreboard: which products actually convert — the
/// website's ranking, from /api/scoreboard.
struct ScoreboardView: View {
    @EnvironmentObject private var store: TrackerStore

    var body: some View {
        List {
            if store.scoreboard.isEmpty {
                Text("Nothing ranked yet — as sales and videos come in, your products line up here by what they earned.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.scoreboard) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.name)
                            .fontWeight(.medium)
                        Text(String(row.totalUnits) + " sold · " + String(row.videoCount) + " videos")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(MoneyText.dollars(row.totalEarnings))
                        .fontWeight(.semibold)
                }
            }
        }
        .navigationTitle("Scoreboard")
        .task {
            await store.loadScoreboard()
        }
        .refreshable {
            await store.loadScoreboard()
        }
    }
}
