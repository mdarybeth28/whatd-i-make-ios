import SwiftUI

/// Videos: the website's Videos tab, native — every logged
/// video with its product, views, units sold and what it
/// earned (units × that product's commission per sale, the
/// server's own math, sent down as `earnings`).
struct VideosView: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var showingAdd = false
    @State private var editing: VideoItem?

    var body: some View {
        List {
            if let error = store.errorText {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.subheadline)
            }
            if store.videos.isEmpty {
                Text("No videos logged yet. Tap + when you post one, so you can see which videos actually sell.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.videos) { video in
                Button {
                    editing = video
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(video.productName ?? "No product linked")
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        Text(line(for: video))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    let video = store.videos[index]
                    Task { await store.deleteVideo(video) }
                }
            }
        }
        .navigationTitle("Videos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Log video", systemImage: "plus")
                }
            }
        }
        .task {
            await store.loadProducts()
            await store.loadVideos()
        }
        .refreshable {
            await store.loadVideos()
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                VideoFormView(video: nil)
            }
        }
        .sheet(item: $editing) { video in
            NavigationStack {
                VideoFormView(video: video)
            }
        }
    }

    private func line(for video: VideoItem) -> String {
        var parts: [String] = [video.datePosted]
        parts.append(String(video.views) + " views")
        parts.append(String(video.unitsSold) + " sold")
        if let earnings = video.earnings {
            parts.append(MoneyText.dollars(earnings) + " earned")
        }
        return parts.joined(separator: " · ")
    }
}

/// Log or edit one video — the website's video form fields.
struct VideoFormView: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss

    let video: VideoItem?

    @State private var productId: Int?
    @State private var date: Date
    @State private var viewsText: String
    @State private var unitsText: String
    @State private var url: String
    @State private var notes: String
    @State private var isSaving = false

    init(video: VideoItem?) {
        self.video = video
        _productId = State(initialValue: video?.productId)
        _date = State(initialValue: DateText.date(from: video?.datePosted))
        _viewsText = State(initialValue: video.map { String($0.views) } ?? "")
        _unitsText = State(initialValue: video.map { String($0.unitsSold) } ?? "")
        _url = State(initialValue: video?.url ?? "")
        _notes = State(initialValue: video?.notes ?? "")
    }

    var body: some View {
        Form {
            Section(header: Text("Video")) {
                Picker("Product", selection: $productId) {
                    Text("No product").tag(nil as Int?)
                    ForEach(store.products) { product in
                        Text(product.name).tag(product.id as Int?)
                    }
                }
                DatePicker("Date posted", selection: $date, displayedComponents: .date)
            }
            Section(header: Text("Numbers")) {
                HStack {
                    Text("Views")
                    Spacer()
                    TextField("0", text: $viewsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Units sold")
                    Spacer()
                    TextField("0", text: $unitsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            Section(header: Text("Links and notes")) {
                TextField("Video link", text: $url)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
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
                        await save()
                        isSaving = false
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving { ProgressView() }
                        Text(video == nil ? "Log video" : "Save changes")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle(video == nil ? "Log video" : "Edit video")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.products.isEmpty { await store.loadProducts() }
        }
    }

    private func save() async {
        let views = Int(viewsText) ?? 0
        let units = Int(unitsText) ?? 0
        if let existing = video {
            var edited = existing
            edited.productId = productId
            edited.datePosted = DateText.string(from: date)
            edited.views = views
            edited.unitsSold = units
            edited.url = url.isEmpty ? nil : url
            edited.notes = notes.isEmpty ? nil : notes
            if await store.updateVideo(edited) { dismiss() }
        } else {
            let ok = await store.createVideo(
                productId: productId,
                datePosted: DateText.string(from: date),
                views: views,
                unitsSold: units,
                url: url.isEmpty ? nil : url,
                notes: notes.isEmpty ? nil : notes
            )
            if ok { dismiss() }
        }
    }
}
