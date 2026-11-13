import SwiftUI
import PhotosUI
import UIKit

/// Scan a screenshot — the website's reader, native. Pick a
/// screenshot, the server's vision door reads it (the same
/// POST /api/vision/scan the web uses, same 60-reads-a-day
/// cap), and what comes back is a DRAFT held on this screen
/// for review. Nothing is saved until Save is tapped, and
/// saving sends exactly what the website's review screen
/// sends:
///
/// - Product page → a new product (name + price prefilled).
/// - Etsy order → a sale for the order total.
/// - Printify order → a COST for the total charge (a
///   Printify amount is always a cost, never income).
/// - TikTok sample order → a cost for the total paid, plus
///   the promised sample refund as a PENDING refund — it
///   counts only when it lands and "Refund received" is
///   tapped on the product page.
///
/// If a product-page read turns out to be an order page, the
/// read is re-run as an order, like the web does.
struct ScanView: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var kindIndex = 0 // 0 = product page, 1 = order page
    @State private var isReading = false
    @State private var savedMessage: String?

    // Product review fields
    @State private var productName = ""
    @State private var productPriceText = ""
    @State private var showProductReview = false

    // Order review fields
    @State private var showOrderReview = false
    @State private var orderKind = "tiktok" // tiktok | printify | etsy
    @State private var orderProductId: Int?
    @State private var orderNewName = ""
    @State private var orderDate = Date()
    @State private var totalText = ""
    @State private var productionText = ""
    @State private var shippingText = ""
    @State private var subtotalText = ""
    @State private var taxesText = ""
    @State private var refundText = ""
    @State private var isSaving = false

    var body: some View {
        Form {
            Section(header: Text("Screenshot")) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(imageData == nil ? "Choose a screenshot" : "Choose a different one",
                          systemImage: "photo.on.rectangle")
                }
                Picker("What is it?", selection: $kindIndex) {
                    Text("Product page").tag(0)
                    Text("Order page").tag(1)
                }
                .pickerStyle(.segmented)
                Button {
                    isReading = true
                    Task {
                        await read()
                        isReading = false
                    }
                } label: {
                    HStack {
                        if isReading { ProgressView() }
                        Text("Read screenshot")
                            .fontWeight(.semibold)
                    }
                }
                .disabled(imageData == nil || isReading)
                Text("Reads count toward the same 60-a-day the website uses. The read is a draft — you check it before anything saves.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = store.errorText {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }

            if let savedMessage {
                Section {
                    Text(savedMessage)
                        .foregroundStyle(.green)
                }
            }

            if showProductReview {
                productReviewSection
            }
            if showOrderReview {
                orderReviewSection
            }
        }
        .navigationTitle("Scan a screenshot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .onChange(of: pickerItem) { item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    imageData = prepareJPEG(from: data) ?? data
                    showProductReview = false
                    showOrderReview = false
                    savedMessage = nil
                }
            }
        }
        .task {
            if store.products.isEmpty { await store.loadProducts() }
        }
    }

    // MARK: - Reading

    private func read() async {
        guard let imageData else { return }
        savedMessage = nil
        if kindIndex == 0 {
            guard let parsed = await store.scanProduct(imageData: imageData) else { return }
            if parsed.screen == "order" {
                // The web routes an order page into the order
                // flow — same here: re-read it as an order.
                await readOrder(imageData: imageData)
                return
            }
            productName = parsed.name
            productPriceText = parsed.price.map { String($0) } ?? ""
            showProductReview = true
            showOrderReview = false
        } else {
            await readOrder(imageData: imageData)
        }
    }

    private func readOrder(imageData: Data) async {
        guard let parsed = await store.scanOrder(imageData: imageData) else { return }
        orderKind = ["tiktok", "printify", "etsy"].contains(parsed.kind) ? parsed.kind : "printify"
        orderProductId = matchProduct(named: parsed.name)?.id
        orderNewName = parsed.name
        orderDate = Date()
        totalText = dollarsText(parsed.totalCents)
        productionText = dollarsText(parsed.productionCents)
        shippingText = dollarsText(parsed.shippingCents)
        subtotalText = dollarsText(parsed.subtotalCents)
        taxesText = dollarsText(parsed.taxesCents)
        refundText = dollarsText(parsed.refundCents)
        if orderKind == "etsy" {
            totalText = dollarsText(parsed.orderTotalCents ?? parsed.totalCents)
        }
        showOrderReview = true
        showProductReview = false
    }

    private func dollarsText(_ centsValue: Int?) -> String {
        guard let centsValue else { return "" }
        return String(format: "%.2f", Double(centsValue) / 100)
    }

    /// The web's product matching, simplified to the same
    /// spirit: a product whose name contains the read name,
    /// or is contained in it, or shares its first long word.
    private func matchProduct(named name: String) -> Product? {
        let target = name.lowercased()
        if target.isEmpty { return nil }
        for product in store.products {
            let candidate = product.name.lowercased()
            if candidate.contains(target) || target.contains(candidate) {
                return product
            }
        }
        let firstWord = target.split(separator: " ").first.map { String($0) } ?? ""
        if firstWord.count >= 4 {
            return store.products.first { $0.name.lowercased().contains(firstWord) }
        }
        return nil
    }

    // MARK: - Product review

    private var productReviewSection: some View {
        Section(header: Text("Check it, then save")) {
            TextField("Product name", text: $productName)
            HStack {
                Text("Price")
                Spacer()
                TextField("0.00", text: $productPriceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            Button {
                isSaving = true
                Task {
                    let created = await store.createProduct(
                        name: productName.trimmingCharacters(in: .whitespaces),
                        price: MoneyText.parse(productPriceText),
                        commissionPerSale: nil, commissionPct: nil,
                        shopLink: nil, notes: nil, source: nil
                    )
                    isSaving = false
                    if created != nil {
                        showProductReview = false
                        savedMessage = "Product saved! 🎉"
                    }
                }
            } label: {
                HStack {
                    if isSaving { ProgressView() }
                    Text("Save product")
                        .fontWeight(.semibold)
                }
            }
            .disabled(isSaving || productName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Order review

    private var orderReviewSection: some View {
        Section(header: Text("Check it, then save")) {
            Picker("This order is", selection: $orderKind) {
                Text("TikTok sample").tag("tiktok")
                Text("Printify").tag("printify")
                Text("Etsy").tag("etsy")
            }
            Picker("Product", selection: $orderProductId) {
                Text("New product…").tag(nil as Int?)
                ForEach(store.products) { product in
                    Text(product.name).tag(product.id as Int?)
                }
            }
            if orderProductId == nil {
                TextField("New product name", text: $orderNewName)
            }
            DatePicker("Date", selection: $orderDate, displayedComponents: .date)

            if orderKind == "etsy" {
                HStack {
                    Text("Order total — becomes the sale")
                    Spacer()
                    TextField("0.00", text: $totalText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            } else if orderKind == "printify" {
                HStack {
                    Text("Production cost")
                    Spacer()
                    TextField("0.00", text: $productionText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Shipping")
                    Spacer()
                    TextField("0.00", text: $shippingText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Total charge — becomes the cost")
                    Spacer()
                    TextField("0.00", text: $totalText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            } else {
                HStack {
                    Text("Item subtotal")
                    Spacer()
                    TextField("0.00", text: $subtotalText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Taxes")
                    Spacer()
                    TextField("0.00", text: $taxesText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Total paid — becomes the cost")
                    Spacer()
                    TextField("0.00", text: $totalText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Sample refund expected")
                    Spacer()
                    TextField("0.00", text: $refundText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Button {
                isSaving = true
                Task {
                    await saveOrder()
                    isSaving = false
                }
            } label: {
                HStack {
                    if isSaving { ProgressView() }
                    Text(orderKind == "etsy" ? "Save sale" : orderKind == "printify" ? "Save cost" : "Save cost + refund")
                        .fontWeight(.semibold)
                }
            }
            .disabled(isSaving)
            Text("Saving works the same as the website: Printify and TikTok totals save as costs, an Etsy total saves as a sale, and a sample refund waits as pending until it lands.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func saveOrder() async {
        // The product first — an existing pick, or a new one
        // created with the source the web assigns per kind.
        var productId = orderProductId
        if productId == nil {
            let name = orderNewName.trimmingCharacters(in: .whitespaces)
            if name.isEmpty {
                store.errorText = "Give the product a name first."
                return
            }
            let source = orderKind == "etsy" ? "Etsy" : orderKind == "printify" ? "Other" : "TikTok Shop"
            let created = await store.createProduct(
                name: name, price: nil, commissionPerSale: nil, commissionPct: nil,
                shopLink: nil, notes: nil, source: source
            )
            productId = created?.id
        }
        guard let productId else { return }
        let date = DateText.string(from: orderDate)

        if orderKind == "etsy" {
            guard let total = MoneyText.parse(totalText), total > 0 else {
                store.errorText = "Enter the order total first."
                return
            }
            if await store.createSale(productId: productId, date: date, units: 1,
                                      commissionEarned: total,
                                      notes: "Etsy order — scanned from order screenshot") {
                showOrderReview = false
                savedMessage = "Sale saved! 🎉"
            }
        } else if orderKind == "printify" {
            var total = MoneyText.parse(totalText) ?? 0
            if total <= 0 {
                let production = MoneyText.parse(productionText) ?? 0
                let shipping = MoneyText.parse(shippingText) ?? 0
                total = ((production + shipping) * 100).rounded() / 100
            }
            guard total > 0 else {
                store.errorText = "Enter the total charge first."
                return
            }
            if await store.addCost(productId: productId, amount: total,
                                   note: "Printify order — scanned from order screenshot",
                                   date: date) {
                showOrderReview = false
                savedMessage = "Cost saved! 🎉"
            }
        } else {
            let total = MoneyText.parse(totalText) ?? 0
            let refund = MoneyText.parse(refundText) ?? 0
            var savedAny = false
            if total > 0 {
                let costSaved = await store.addCost(productId: productId, amount: total,
                                                    note: "TikTok sample order — scanned from order screenshot",
                                                    date: date)
                if costSaved { savedAny = true }
            }
            if refund > 0 {
                let refundSaved = await store.addRefund(productId: productId, expectedAmount: refund,
                                                         note: "Sample refund — from order screenshot")
                if refundSaved { savedAny = true }
            }
            if savedAny {
                showOrderReview = false
                savedMessage = "Saved! The refund sits as pending until it lands. 🎉"
            } else {
                store.errorText = "Enter the total paid or the expected refund first."
            }
        }
    }

    // MARK: - Image prep (the web downscales before sending, too)

    private func prepareJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1568
        let longest = max(image.size.width, image.size.height)
        if longest <= maxSide {
            return image.jpegData(compressionQuality: 0.85)
        }
        let scale = maxSide / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}
