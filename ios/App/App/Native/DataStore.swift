import Foundation

/// The data layer for the Phase 2 screens: every call the
/// website's own pages make to the tracker's API, over the
/// same session cookie the sign-in set (APIClient). Nothing
/// here invents data — every list on screen is a server answer,
/// and every save is the same POST/PUT the website sends,
/// field for field (see src/routes/api.js on the server).
///
/// THE GATE STILL BELONGS TO THE SERVER: if a call comes back
/// 401 or 402 mid-session (signed out elsewhere, subscription
/// lapsed), the store flags `gateBlocked` and the root view
/// sends the user back through the session's own check — the
/// same answer the website would give.
@MainActor
final class TrackerStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var videos: [VideoItem] = []
    @Published private(set) var sales: [Sale] = []
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var scoreboard: [ScoreRow] = []
    @Published private(set) var overview: Overview?
    @Published private(set) var profit: ProfitResponse?

    @Published private(set) var detailCosts: [CostItem] = []
    @Published private(set) var detailRefunds: [RefundItem] = []

    @Published private(set) var etsyConnected = false
    @Published private(set) var etsyShopId: String?
    @Published private(set) var etsyMessage: String?

    @Published var errorText: String?
    @Published private(set) var gateBlocked = false
    @Published private(set) var isLoading = false

    private let client = APIClient.shared
    private let decoder = JSONDecoder()

    // MARK: - Plumbing

    /// Runs one API call and decodes its JSON answer. A 401 or
    /// 402 raises the gate flag instead of an error message —
    /// the session store owns what happens next.
    private func call<T: Decodable>(_ type: T.Type, _ make: () async throws -> APIResponse) async -> T? {
        do {
            let response = try await make()
            if response.status == 401 || response.status == 402 {
                gateBlocked = true
                return nil
            }
            guard response.status == 200 else {
                errorText = response.serverMessage ?? ("Something went wrong (HTTP " + String(response.status) + ").")
                return nil
            }
            return try decoder.decode(type, from: response.data)
        } catch {
            errorText = "Could not reach the server. Check your connection and try again."
            return nil
        }
    }

    /// A call whose answer we don't need to decode (deletes,
    /// one-tap actions). Returns true on success.
    private func callOK(_ make: () async throws -> APIResponse) async -> Bool {
        do {
            let response = try await make()
            if response.status == 401 || response.status == 402 {
                gateBlocked = true
                return false
            }
            guard response.status == 200 else {
                errorText = response.serverMessage ?? ("Something went wrong (HTTP " + String(response.status) + ").")
                return false
            }
            return true
        } catch {
            errorText = "Could not reach the server. Check your connection and try again."
            return false
        }
    }

    /// Dictionary value for an optional field being PUT: the
    /// value itself, or JSON null when the field is cleared
    /// (the server turns null/'' into NULL on update).
    private func orNull<T>(_ value: T?) -> Any {
        if let value { return value }
        return NSNull()
    }

    func clearGateBlock() {
        gateBlocked = false
    }

    // MARK: - Loads

    func loadSummary() async {
        isLoading = true
        if let loaded: Overview = await call(Overview.self, { try await self.client.get("/api/overview") }) {
            overview = loaded
        }
        if let loaded: ProfitResponse = await call(ProfitResponse.self, { try await self.client.get("/api/profit") }) {
            profit = loaded
        }
        isLoading = false
    }

    func loadProducts() async {
        if let loaded: [Product] = await call([Product].self, { try await self.client.get("/api/products") }) {
            products = loaded
        }
    }

    func loadVideos() async {
        if let loaded: [VideoItem] = await call([VideoItem].self, { try await self.client.get("/api/videos") }) {
            videos = loaded
        }
    }

    func loadSales() async {
        if let loaded: [Sale] = await call([Sale].self, { try await self.client.get("/api/sales") }) {
            sales = loaded
        }
    }

    func loadTasks() async {
        if let loaded: [TaskItem] = await call([TaskItem].self, { try await self.client.get("/api/tasks") }) {
            tasks = loaded
        }
    }

    func loadScoreboard() async {
        if let loaded: [ScoreRow] = await call([ScoreRow].self, { try await self.client.get("/api/scoreboard") }) {
            scoreboard = loaded
        }
    }

    func productName(for id: Int?) -> String? {
        guard let id else { return nil }
        return products.first { $0.id == id }?.name
    }

    func profitRow(for productId: Int) -> ProfitProductRow? {
        profit?.products.first { $0.productId == productId }
    }

    // MARK: - Products

    func createProduct(name: String, price: Double?, commissionPerSale: Double?,
                       commissionPct: Double?, shopLink: String?, notes: String?,
                       source: String?) async -> Product? {
        var body: [String: Any] = ["name": name]
        if let price { body["price"] = price }
        if let commissionPerSale { body["commission_per_sale"] = commissionPerSale }
        if let commissionPct { body["commission_pct"] = commissionPct }
        if let shopLink, !shopLink.isEmpty { body["shop_link"] = shopLink }
        if let notes, !notes.isEmpty { body["notes"] = notes }
        if let source, !source.isEmpty { body["source"] = source }
        let created: Product? = await call(Product.self, { try await self.client.post("/api/products", json: body) })
        if created != nil { await loadProducts() }
        return created
    }

    func updateProduct(_ product: Product) async -> Bool {
        var body: [String: Any] = ["name": product.name]
        body["price"] = orNull(product.price)
        body["commission_per_sale"] = orNull(product.commissionPerSale)
        body["commission_pct"] = orNull(product.commissionPct)
        body["shop_link"] = orNull(product.shopLink)
        body["notes"] = orNull(product.notes)
        body["source"] = orNull(product.source)
        let path = "/api/products/" + String(product.id)
        let ok = await callOK { try await self.client.put(path, json: body) }
        if ok { await loadProducts() }
        return ok
    }

    func deleteProduct(_ product: Product) async {
        let path = "/api/products/" + String(product.id)
        if await callOK({ try await self.client.delete(path) }) {
            await loadProducts()
        }
    }

    // MARK: - Videos

    func createVideo(productId: Int?, datePosted: String, views: Int, unitsSold: Int,
                     url: String?, notes: String?) async -> Bool {
        var body: [String: Any] = ["date_posted": datePosted, "views": views, "units_sold": unitsSold]
        if let productId { body["product_id"] = productId }
        if let url, !url.isEmpty { body["url"] = url }
        if let notes, !notes.isEmpty { body["notes"] = notes }
        let created: VideoItem? = await call(VideoItem.self, { try await self.client.post("/api/videos", json: body) })
        if created != nil { await loadVideos() }
        return created != nil
    }

    func updateVideo(_ video: VideoItem) async -> Bool {
        var body: [String: Any] = [
            "date_posted": video.datePosted,
            "views": video.views,
            "units_sold": video.unitsSold,
        ]
        body["product_id"] = orNull(video.productId)
        body["url"] = orNull(video.url)
        body["notes"] = orNull(video.notes)
        let path = "/api/videos/" + String(video.id)
        let ok = await callOK { try await self.client.put(path, json: body) }
        if ok { await loadVideos() }
        return ok
    }

    func deleteVideo(_ video: VideoItem) async {
        let path = "/api/videos/" + String(video.id)
        if await callOK({ try await self.client.delete(path) }) {
            await loadVideos()
        }
    }

    // MARK: - Sales (the money log)

    func createSale(productId: Int?, date: String, units: Int, commissionEarned: Double,
                    notes: String?) async -> Bool {
        var body: [String: Any] = ["date": date, "units": units, "commission_earned": commissionEarned]
        if let productId { body["product_id"] = productId }
        if let notes, !notes.isEmpty { body["notes"] = notes }
        let created: Sale? = await call(Sale.self, { try await self.client.post("/api/sales", json: body) })
        if created != nil {
            await loadSales()
            await loadSummary()
        }
        return created != nil
    }

    func updateSale(_ sale: Sale) async -> Bool {
        var body: [String: Any] = [
            "date": sale.date,
            "units": sale.units,
            "commission_earned": sale.commissionEarned,
        ]
        body["product_id"] = orNull(sale.productId)
        body["notes"] = orNull(sale.notes)
        let path = "/api/sales/" + String(sale.id)
        let ok = await callOK { try await self.client.put(path, json: body) }
        if ok {
            await loadSales()
            await loadSummary()
        }
        return ok
    }

    func deleteSale(_ sale: Sale) async {
        let path = "/api/sales/" + String(sale.id)
        if await callOK({ try await self.client.delete(path) }) {
            await loadSales()
            await loadSummary()
        }
    }

    // MARK: - Costs and refunds (per product)

    func loadDetail(for productId: Int) async {
        let costsPath = "/api/products/" + String(productId) + "/costs"
        if let loaded: [CostItem] = await call([CostItem].self, { try await self.client.get(costsPath) }) {
            detailCosts = loaded
        }
        let refundsPath = "/api/products/" + String(productId) + "/refunds"
        if let loaded: [RefundItem] = await call([RefundItem].self, { try await self.client.get(refundsPath) }) {
            detailRefunds = loaded
        }
    }

    func addCost(productId: Int, amount: Double, note: String?, date: String?) async -> Bool {
        var body: [String: Any] = ["product_id": productId, "amount": amount]
        if let note, !note.isEmpty { body["note"] = note }
        if let date, !date.isEmpty { body["date"] = date }
        let created: CostItem? = await call(CostItem.self, { try await self.client.post("/api/costs", json: body) })
        if created != nil {
            await loadDetail(for: productId)
            await loadSummary()
        }
        return created != nil
    }

    func deleteCost(_ cost: CostItem) async {
        let path = "/api/costs/" + String(cost.id)
        if await callOK({ try await self.client.delete(path) }) {
            await loadDetail(for: cost.productId)
            await loadSummary()
        }
    }

    func addRefund(productId: Int, expectedAmount: Double, note: String?) async -> Bool {
        var body: [String: Any] = ["product_id": productId, "expected_amount": expectedAmount]
        if let note, !note.isEmpty { body["note"] = note }
        let created: RefundItem? = await call(RefundItem.self, { try await self.client.post("/api/refunds", json: body) })
        if created != nil {
            await loadDetail(for: productId)
            await loadSummary()
        }
        return created != nil
    }

    /// The one tap that makes a refund count: the money
    /// actually arrived. Until this is tapped the refund stays
    /// pending and stays OUT of the profit number — the
    /// server's rule, mirrored here by simply never counting
    /// it locally either.
    func receiveRefund(_ refund: RefundItem) async {
        let path = "/api/refunds/" + String(refund.id) + "/receive"
        if await callOK({ try await self.client.post(path, json: [:]) }) {
            await loadDetail(for: refund.productId)
            await loadSummary()
        }
    }

    func deleteRefund(_ refund: RefundItem) async {
        let path = "/api/refunds/" + String(refund.id)
        if await callOK({ try await self.client.delete(path) }) {
            await loadDetail(for: refund.productId)
            await loadSummary()
        }
    }

    // MARK: - Tasks

    func createTask(name: String, targetVideos: Int, deadline: String?,
                    rewardAmount: Double?, notes: String?) async -> Bool {
        var body: [String: Any] = ["name": name, "target_videos": targetVideos, "videos_done": 0]
        if let deadline, !deadline.isEmpty { body["deadline"] = deadline }
        if let rewardAmount { body["reward_amount"] = rewardAmount }
        if let notes, !notes.isEmpty { body["notes"] = notes }
        let created: TaskItem? = await call(TaskItem.self, { try await self.client.post("/api/tasks", json: body) })
        if created != nil { await loadTasks() }
        return created != nil
    }

    func updateTask(_ task: TaskItem) async -> Bool {
        var body: [String: Any] = [
            "name": task.name,
            "target_videos": task.targetVideos,
            "videos_done": task.videosDone,
        ]
        body["deadline"] = orNull(task.deadline)
        body["reward_amount"] = orNull(task.rewardAmount)
        body["notes"] = orNull(task.notes)
        let path = "/api/tasks/" + String(task.id)
        let ok = await callOK { try await self.client.put(path, json: body) }
        if ok { await loadTasks() }
        return ok
    }

    func deleteTask(_ task: TaskItem) async {
        let path = "/api/tasks/" + String(task.id)
        if await callOK({ try await self.client.delete(path) }) {
            await loadTasks()
        }
    }

    /// A finished task's cash reward becomes income only when
    /// it lands — the server posts it as a sale at this tap,
    /// the same rule as refunds.
    func taskRewardReceived(_ task: TaskItem) async {
        let path = "/api/tasks/" + String(task.id) + "/reward-received"
        if await callOK({ try await self.client.post(path, json: [:]) }) {
            await loadTasks()
            await loadSummary()
        }
    }

    // MARK: - Etsy

    func loadEtsyStatus() async {
        do {
            let response = try await client.get("/api/etsy/status")
            if response.status == 401 || response.status == 402 {
                gateBlocked = true
                return
            }
            if let json = response.jsonObject {
                etsyConnected = (json["connected"] as? Bool) ?? false
                if let shop = json["shop_id"] as? String {
                    etsyShopId = shop
                } else if let shopNumber = json["shop_id"] as? NSNumber {
                    etsyShopId = shopNumber.stringValue
                } else {
                    etsyShopId = nil
                }
            }
        } catch {
            // Status is a quiet extra; a failed read just leaves
            // the last known state on screen.
        }
    }

    func etsySyncProducts() async {
        etsyMessage = nil
        if await callOK({ try await self.client.post("/api/etsy/sync", json: [:]) }) {
            etsyMessage = "Etsy products synced."
            await loadProducts()
        } else {
            etsyMessage = errorText
        }
    }

    func etsySyncSales() async {
        etsyMessage = nil
        if await callOK({ try await self.client.post("/api/etsy/sync-sales", json: [:]) }) {
            etsyMessage = "Etsy sales synced."
            await loadSales()
            await loadSummary()
        } else {
            etsyMessage = errorText
        }
    }

    // MARK: - Share key (the iPhone Shortcut door)

    func loadShareKey() async -> String? {
        do {
            let response = try await client.get("/api/share-key")
            if response.status == 200, let json = response.jsonObject {
                return json["key"] as? String
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - Vision scan

    /// Sends one screenshot to the server's reader
    /// (POST /api/vision/scan?kind=product) — the same door
    /// the website uses, with the same daily cap (60 reads a
    /// day). The answer is a DRAFT: nothing is saved until the
    /// review screen's Save button sends the normal POSTs.
    func scanProduct(imageData: Data) async -> ScanProductParsed? {
        await scan(path: "/api/vision/scan?kind=product", imageData: imageData, as: ScanProductParsed.self)
    }

    func scanOrder(imageData: Data) async -> ScanOrderParsed? {
        await scan(path: "/api/vision/scan?kind=order", imageData: imageData, as: ScanOrderParsed.self)
    }

    private func scan<T: Decodable>(path: String, imageData: Data, as type: T.Type) async -> T? {
        do {
            let response = try await client.postRaw(path, data: imageData, contentType: "image/jpeg")
            if response.status == 401 || response.status == 402 {
                gateBlocked = true
                return nil
            }
            if response.status == 429 {
                errorText = "That's today's 60 reads used up — the reader resets tomorrow."
                return nil
            }
            guard response.status == 200 else {
                errorText = "The reader couldn't read that one. Try a clearer screenshot."
                return nil
            }
            guard let json = response.jsonObject,
                  let parsed = json["parsed"] as? [String: Any],
                  let parsedData = try? JSONSerialization.data(withJSONObject: parsed) else {
                errorText = "The reader couldn't read that one. Try a clearer screenshot."
                return nil
            }
            return try decoder.decode(type, from: parsedData)
        } catch {
            errorText = "Could not reach the server. Check your connection and try again."
            return nil
        }
    }
}
