import Foundation

/// The tracker server's data shapes, as the website's own API
/// returns them (src/routes/api.js on the server). Field names
/// on the wire are snake_case; the CodingKeys below map them
/// once, here, so the views can use plain Swift names.
///
/// Every amount the server stores is a dollar number (REAL);
/// the /api/profit endpoint is the one exception — it answers
/// in integer cents, exactly so its totals are exact, and the
/// views format those with MoneyText.cents.
struct Product: Codable, Identifiable {
    let id: Int
    var name: String
    var price: Double?
    var commissionPerSale: Double?
    var commissionPct: Double?
    var shopLink: String?
    var notes: String?
    var source: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, price, notes, source
        case commissionPerSale = "commission_per_sale"
        case commissionPct = "commission_pct"
        case shopLink = "shop_link"
        case createdAt = "created_at"
    }
}

struct VideoItem: Codable, Identifiable {
    let id: Int
    var productId: Int?
    var datePosted: String
    var views: Int
    var unitsSold: Int
    var notes: String?
    var url: String?
    var productName: String?
    var commissionPerSale: Double?
    var earnings: Double?

    enum CodingKeys: String, CodingKey {
        case id, views, notes, url, earnings
        case productId = "product_id"
        case datePosted = "date_posted"
        case unitsSold = "units_sold"
        case productName = "product_name"
        case commissionPerSale = "commission_per_sale"
    }
}

struct Sale: Codable, Identifiable {
    let id: Int
    var productId: Int?
    var date: String
    var units: Int
    var commissionEarned: Double
    var notes: String?
    var productName: String?

    enum CodingKeys: String, CodingKey {
        case id, date, units, notes
        case productId = "product_id"
        case commissionEarned = "commission_earned"
        case productName = "product_name"
    }
}

struct TaskItem: Codable, Identifiable {
    let id: Int
    var name: String
    var targetVideos: Int
    var videosDone: Int
    var deadline: String?
    var rewardAmount: Double?
    var notes: String?
    var rewardStatus: String?

    enum CodingKeys: String, CodingKey {
        case id, name, deadline, notes
        case targetVideos = "target_videos"
        case videosDone = "videos_done"
        case rewardAmount = "reward_amount"
        case rewardStatus = "reward_status"
    }
}

struct CostItem: Codable, Identifiable {
    let id: Int
    var productId: Int
    var amount: Double
    var note: String?
    var date: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, amount, note, date
        case productId = "product_id"
        case createdAt = "created_at"
    }
}

struct RefundItem: Codable, Identifiable {
    let id: Int
    var productId: Int
    var expectedAmount: Double
    var receivedAmount: Double?
    var status: String
    var note: String?
    var receivedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, note
        case productId = "product_id"
        case expectedAmount = "expected_amount"
        case receivedAmount = "received_amount"
        case receivedAt = "received_at"
    }

    var isReceived: Bool { status == "received" }
}

struct Overview: Codable {
    var products: Int
    var videos: Int
    var tasks: Int
    var totalEarnings: Double
    var upcomingTasks: [TaskItem]

    enum CodingKeys: String, CodingKey {
        case products, videos, tasks
        case totalEarnings = "totalEarnings"
        case upcomingTasks
    }
}

/// /api/profit — the money truth of the whole app, in cents.
/// The rule it embodies (Mary's, and the server's):
///   profit = commissions + refunds RECEIVED − costs.
/// A refund that is still pending is reported separately and
/// never counted; a Printify amount is always a cost.
struct ProfitTotals: Codable {
    var commissionsCents: Int
    var costsCents: Int
    var refundsReceivedCents: Int
    var refundsPendingCents: Int
    var netCents: Int
    var taskIncomeCents: Int?

    enum CodingKeys: String, CodingKey {
        case commissionsCents = "commissions_cents"
        case costsCents = "costs_cents"
        case refundsReceivedCents = "refunds_received_cents"
        case refundsPendingCents = "refunds_pending_cents"
        case netCents = "net_cents"
        case taskIncomeCents = "task_income_cents"
    }
}

struct ProfitProductRow: Codable, Identifiable {
    var productId: Int
    var name: String
    var commissionsCents: Int
    var costsCents: Int
    var refundsReceivedCents: Int
    var refundsPendingCents: Int
    var netCents: Int
    var belowBreakEven: Bool

    var id: Int { productId }

    enum CodingKeys: String, CodingKey {
        case name
        case productId = "product_id"
        case commissionsCents = "commissions_cents"
        case costsCents = "costs_cents"
        case refundsReceivedCents = "refunds_received_cents"
        case refundsPendingCents = "refunds_pending_cents"
        case netCents = "net_cents"
        case belowBreakEven = "below_break_even"
    }
}

struct ProfitResponse: Codable {
    var totals: ProfitTotals
    var products: [ProfitProductRow]
}

struct ScoreRow: Codable, Identifiable {
    let id: Int
    var name: String
    var price: Double?
    var commissionPerSale: Double?
    var totalUnits: Int
    var totalEarnings: Double
    var videoCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, price
        case commissionPerSale = "commission_per_sale"
        case totalUnits = "total_units"
        case totalEarnings = "total_earnings"
        case videoCount = "video_count"
    }
}

/// The vision reader's answers (POST /api/vision/scan). The
/// server returns the same shapes its web review screens use:
/// a product read, or an order read whose money arrives in
/// cents.
struct ScanProductParsed: Codable {
    var name: String
    var price: Double?
    var screen: String
}

struct ScanOrderParsed: Codable {
    var kind: String
    var name: String
    var subtotalCents: Int?
    var taxesCents: Int?
    var totalCents: Int?
    var refundCents: Int?
    var productionCents: Int?
    var shippingCents: Int?
    var orderTotalCents: Int?

    enum CodingKeys: String, CodingKey {
        case kind, name
        case subtotalCents = "subtotal_cents"
        case taxesCents = "taxes_cents"
        case totalCents = "total_cents"
        case refundCents = "refund_cents"
        case productionCents = "production_cents"
        case shippingCents = "shipping_cents"
        case orderTotalCents = "order_total_cents"
    }
}

/// Money words for the screens. Built by concatenation on
/// purpose — this project's Swift avoids the string
/// interpolation token throughout (see the Phase 1 notes).
enum MoneyText {
    static func dollars(_ value: Double) -> String {
        "$" + String(format: "%.2f", value)
    }

    static func cents(_ value: Int) -> String {
        let sign = value < 0 ? "-" : ""
        let absolute = abs(value)
        let whole = absolute / 100
        let part = absolute % 100
        let partText = part < 10 ? "0" + String(part) : String(part)
        return sign + "$" + String(whole) + "." + partText
    }

    /// What the user typed into a money field, as a number —
    /// nil when the field is empty or not a number.
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        return Double(trimmed)
    }
}

/// The server's dates are "yyyy-MM-dd" strings. These helpers
/// move between those strings and DatePicker dates.
enum DateText {
    private static var formatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    static func today() -> String {
        formatter.string(from: Date())
    }

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from text: String?) -> Date {
        if let text, let parsed = formatter.date(from: text) {
            return parsed
        }
        return Date()
    }
}
