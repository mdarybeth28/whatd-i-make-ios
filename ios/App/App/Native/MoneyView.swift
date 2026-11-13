import SwiftUI

/// Money: the website's sales log, native — every commission
/// logged by hand (or by a scan, or by an Etsy sync), newest
/// first. This is one of the two doors money comes in through
/// (video earnings are the other); the profit view on Home
/// adds them up.
struct MoneyView: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var showingAdd = false
    @State private var editing: Sale?
    @State private var showingScan = false

    var body: some View {
        List {
            if let error = store.errorText {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.subheadline)
            }
            if store.sales.isEmpty {
                Text("No sales logged yet. When a commission lands, log it here — or scan the order screenshot and let the reader fill it in.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.sales) { sale in
                Button {
                    editing = sale
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sale.productName ?? "No product linked")
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text(line(for: sale))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(MoneyText.dollars(sale.commissionEarned))
                            .fontWeight(.semibold)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    let sale = store.sales[index]
                    Task { await store.deleteSale(sale) }
                }
            }
        }
        .navigationTitle("Money")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Log sale", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingScan = true
                } label: {
                    Label("Scan an order screenshot", systemImage: "camera.viewfinder")
                }
            }
        }
        .task {
            await store.loadProducts()
            await store.loadSales()
        }
        .refreshable {
            await store.loadSales()
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                SaleFormView(sale: nil)
            }
        }
        .sheet(item: $editing) { sale in
            NavigationStack {
                SaleFormView(sale: sale)
            }
        }
        .sheet(isPresented: $showingScan) {
            NavigationStack {
                ScanView()
            }
        }
    }

    private func line(for sale: Sale) -> String {
        var parts: [String] = [sale.date]
        if sale.units != 1 {
            parts.append(String(sale.units) + " units")
        }
        if let notes = sale.notes, !notes.isEmpty {
            parts.append(notes)
        }
        return parts.joined(separator: " · ")
    }
}

/// Log or edit one sale — the website's sale form fields.
struct SaleFormView: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss

    let sale: Sale?

    @State private var productId: Int?
    @State private var date: Date
    @State private var unitsText: String
    @State private var commissionText: String
    @State private var notes: String
    @State private var isSaving = false

    init(sale: Sale?) {
        self.sale = sale
        _productId = State(initialValue: sale?.productId)
        _date = State(initialValue: DateText.date(from: sale?.date))
        _unitsText = State(initialValue: sale.map { String($0.units) } ?? "1")
        _commissionText = State(initialValue: sale.map { String($0.commissionEarned) } ?? "")
        _notes = State(initialValue: sale?.notes ?? "")
    }

    var body: some View {
        Form {
            Section(header: Text("Sale")) {
                Picker("Product", selection: $productId) {
                    Text("No product").tag(nil as Int?)
                    ForEach(store.products) { product in
                        Text(product.name).tag(product.id as Int?)
                    }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            Section(header: Text("Numbers")) {
                HStack {
                    Text("Units")
                    Spacer()
                    TextField("1", text: $unitsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Commission earned")
                    Spacer()
                    TextField("0.00", text: $commissionText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            Section(header: Text("Notes")) {
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
                        Text(sale == nil ? "Log sale" : "Save changes")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(isSaving || MoneyText.parse(commissionText) == nil)
            }
        }
        .navigationTitle(sale == nil ? "Log sale" : "Edit sale")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.products.isEmpty { await store.loadProducts() }
        }
    }

    private func save() async {
        guard let commission = MoneyText.parse(commissionText) else { return }
        let units = Int(unitsText) ?? 1
        if let existing = sale {
            var edited = existing
            edited.productId = productId
            edited.date = DateText.string(from: date)
            edited.units = units
            edited.commissionEarned = commission
            edited.notes = notes.isEmpty ? nil : notes
            if await store.updateSale(edited) { dismiss() }
        } else {
            let ok = await store.createSale(
                productId: productId,
                date: DateText.string(from: date),
                units: units,
                commissionEarned: commission,
                notes: notes.isEmpty ? nil : notes
            )
            if ok { dismiss() }
        }
    }
}
