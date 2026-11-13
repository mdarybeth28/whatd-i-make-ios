import SwiftUI

/// Products: the website's Products tab, native. The list,
/// the add/edit form, and the per-product page where costs
/// and refunds live (on the web they hang off the product the
/// same way).
struct ProductsView: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var showingAdd = false

    var body: some View {
        List {
            if let error = store.errorText {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.subheadline)
            }
            if store.products.isEmpty {
                Text("No products yet. Tap + to add your first one — or scan a product screenshot from the Home tab.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.products) { product in
                NavigationLink {
                    ProductDetailView(product: product)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(product.name)
                            .fontWeight(.medium)
                        Text(subtitle(for: product))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    let product = store.products[index]
                    Task { await store.deleteProduct(product) }
                }
            }
        }
        .navigationTitle("Products")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add product", systemImage: "plus")
                }
            }
        }
        .task {
            await store.loadProducts()
            await store.loadSummary()
        }
        .refreshable {
            await store.loadProducts()
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                ProductFormView(product: nil)
            }
        }
    }

    private func subtitle(for product: Product) -> String {
        var parts: [String] = []
        if let price = product.price {
            parts.append(MoneyText.dollars(price))
        }
        if let perSale = product.commissionPerSale {
            parts.append(MoneyText.dollars(perSale) + " a sale")
        }
        if let source = product.source, !source.isEmpty {
            parts.append(source)
        }
        return parts.isEmpty ? "No price set" : parts.joined(separator: " · ")
    }
}

/// Add or edit one product — the same fields the website's
/// product form carries.
struct ProductFormView: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss

    let product: Product?

    @State private var name: String
    @State private var priceText: String
    @State private var perSaleText: String
    @State private var pctText: String
    @State private var shopLink: String
    @State private var notes: String
    @State private var source: String
    @State private var isSaving = false

    private static let sources = ["", "TikTok Shop", "Etsy", "Amazon", "Other"]

    init(product: Product?) {
        self.product = product
        _name = State(initialValue: product?.name ?? "")
        _priceText = State(initialValue: product?.price.map { String($0) } ?? "")
        _perSaleText = State(initialValue: product?.commissionPerSale.map { String($0) } ?? "")
        _pctText = State(initialValue: product?.commissionPct.map { String($0) } ?? "")
        _shopLink = State(initialValue: product?.shopLink ?? "")
        _notes = State(initialValue: product?.notes ?? "")
        _source = State(initialValue: product?.source ?? "")
    }

    var body: some View {
        Form {
            Section(header: Text("Product")) {
                TextField("Name", text: $name)
                Picker("Where you sell it", selection: $source) {
                    ForEach(Self.sources, id: \.self) { option in
                        Text(option.isEmpty ? "Not set" : option).tag(option)
                    }
                }
            }
            Section(header: Text("Money")) {
                HStack {
                    Text("Price")
                    Spacer()
                    TextField("0.00", text: $priceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Commission per sale")
                    Spacer()
                    TextField("0.00", text: $perSaleText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Commission %")
                    Spacer()
                    TextField("0", text: $pctText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            Section(header: Text("Links and notes")) {
                TextField("Shop link", text: $shopLink)
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
                        Text(product == nil ? "Add product" : "Save changes")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle(product == nil ? "Add product" : "Edit product")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let existing = product {
            var edited = existing
            edited.name = trimmedName
            edited.price = MoneyText.parse(priceText)
            edited.commissionPerSale = MoneyText.parse(perSaleText)
            edited.commissionPct = MoneyText.parse(pctText)
            edited.shopLink = shopLink.isEmpty ? nil : shopLink
            edited.notes = notes.isEmpty ? nil : notes
            edited.source = source.isEmpty ? nil : source
            if await store.updateProduct(edited) { dismiss() }
        } else {
            let created = await store.createProduct(
                name: trimmedName,
                price: MoneyText.parse(priceText),
                commissionPerSale: MoneyText.parse(perSaleText),
                commissionPct: MoneyText.parse(pctText),
                shopLink: shopLink.isEmpty ? nil : shopLink,
                notes: notes.isEmpty ? nil : notes,
                source: source.isEmpty ? nil : source
            )
            if created != nil { dismiss() }
        }
    }
}

/// One product's page: its details, its money (from the
/// server's profit view), its costs and its refunds. Costs
/// and refunds are added here exactly as on the web — and a
/// refund only starts counting when "Refund received" is
/// tapped, because that's when the money actually lands.
struct ProductDetailView: View {
    @EnvironmentObject private var store: TrackerStore
    let product: Product

    @State private var showingEdit = false
    @State private var costAmountText = ""
    @State private var costNote = ""
    @State private var costDate = Date()
    @State private var refundAmountText = ""
    @State private var refundNote = ""

    private var current: Product {
        store.products.first { $0.id == product.id } ?? product
    }

    var body: some View {
        Form {
            Section(header: Text("Details")) {
                if let price = current.price {
                    LabeledContent("Price", value: MoneyText.dollars(price))
                }
                if let perSale = current.commissionPerSale {
                    LabeledContent("Commission per sale", value: MoneyText.dollars(perSale))
                }
                if let pct = current.commissionPct {
                    LabeledContent("Commission %", value: String(pct) + "%")
                }
                if let source = current.source, !source.isEmpty {
                    LabeledContent("Sold on", value: source)
                }
                if let notes = current.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button("Edit product") { showingEdit = true }
            }

            moneySection
            costsSection
            refundsSection
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadDetail(for: product.id)
            await store.loadSummary()
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                ProductFormView(product: current)
            }
        }
    }

    // MARK: - Money for this product

    @ViewBuilder
    private var moneySection: some View {
        if let row = store.profitRow(for: product.id) {
            Section(header: Text("Money for this product")) {
                LabeledContent("Commissions", value: MoneyText.cents(row.commissionsCents))
                LabeledContent("Refunds received", value: MoneyText.cents(row.refundsReceivedCents))
                LabeledContent("Costs", value: MoneyText.cents(row.costsCents))
                LabeledContent("Profit", value: MoneyText.cents(row.netCents))
                if row.belowBreakEven {
                    Text("This one is under water so far — costs are ahead of what it has brought in.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if row.refundsPendingCents > 0 {
                    Text(MoneyText.cents(row.refundsPendingCents) + " in refunds still coming — not counted yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Costs

    private var costsSection: some View {
        Section(header: Text("Costs")) {
            ForEach(store.detailCosts) { cost in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MoneyText.dollars(cost.amount))
                            .fontWeight(.medium)
                        if let note = cost.note, !note.isEmpty {
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let date = cost.date, !date.isEmpty {
                        Text(date)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    let cost = store.detailCosts[index]
                    Task { await store.deleteCost(cost) }
                }
            }
            HStack {
                TextField("Amount", text: $costAmountText)
                    .keyboardType(.decimalPad)
                TextField("What for", text: $costNote)
            }
            DatePicker("Date", selection: $costDate, displayedComponents: .date)
            Button("Add cost") {
                guard let amount = MoneyText.parse(costAmountText) else { return }
                Task {
                    if await store.addCost(productId: product.id, amount: amount,
                                           note: costNote.isEmpty ? nil : costNote,
                                           date: DateText.string(from: costDate)) {
                        costAmountText = ""
                        costNote = ""
                    }
                }
            }
            .disabled(MoneyText.parse(costAmountText) == nil)
        }
    }

    // MARK: - Refunds

    private var refundsSection: some View {
        Section(header: Text("Refunds")) {
            ForEach(store.detailRefunds) { refund in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(MoneyText.dollars(refund.isReceived ? (refund.receivedAmount ?? refund.expectedAmount) : refund.expectedAmount))
                            .fontWeight(.medium)
                        Spacer()
                        Text(refund.isReceived ? "Received" : "Still coming")
                            .font(.footnote)
                            .foregroundStyle(refund.isReceived ? .green : .orange)
                    }
                    if let note = refund.note, !note.isEmpty {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !refund.isReceived {
                        Button("Refund received") {
                            Task { await store.receiveRefund(refund) }
                        }
                        .font(.subheadline)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    let refund = store.detailRefunds[index]
                    Task { await store.deleteRefund(refund) }
                }
            }
            HStack {
                TextField("Expected amount", text: $refundAmountText)
                    .keyboardType(.decimalPad)
                TextField("What for", text: $refundNote)
            }
            Button("Add refund (still coming)") {
                guard let amount = MoneyText.parse(refundAmountText) else { return }
                Task {
                    if await store.addRefund(productId: product.id, expectedAmount: amount,
                                              note: refundNote.isEmpty ? nil : refundNote) {
                        refundAmountText = ""
                        refundNote = ""
                    }
                }
            }
            .disabled(MoneyText.parse(refundAmountText) == nil)
            Text("A refund joins your profit only when you tap “Refund received” — when the money is really in your hands.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
