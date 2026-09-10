import Foundation

/// A fully self-contained cart snapshot — doesn't depend on the live
/// product catalog still containing the item. Device-local only, never
/// synced to the server until final checkout. Mirrors Android's
/// `HeldBillStore` (DataStore JSON) using UserDefaults instead.
struct HeldBill: Identifiable, Codable, Equatable {
    struct Line: Codable, Equatable {
        let id: UUID
        let productId: UUID
        let productName: String
        let unitPriceWire: String
        let quantity: Int
    }

    let id: UUID
    let savedAt: Date
    let idempotencyKey: String
    var lines: [Line]
    var discountType: String
    var discountValueText: String
    var paymentMode: String
    var cashAmountText: String
    var upiAmountText: String
    var dueAmountText: String
    var customerName: String
    var customerPhone: String
    var remarks: String
    /// Captured when the bill is held, as Android does, so the list shows the
    /// real count (sum of quantities) and the total after discount. Optional
    /// so bills held by an older build still load.
    var itemCount: Int?
    var totalWire: String?

    /// Falls back to the lines for a bill held before these were recorded.
    var displayItemCount: Int {
        itemCount ?? lines.reduce(0) { $0 + $1.quantity }
    }

    var displayTotal: Money {
        if let totalWire { return Money.parse(totalWire) }
        return lines.reduce(Money.zero) { $0 + Money.parse($1.unitPriceWire) * $1.quantity }
    }
}

enum HeldBillStore {
    private static let key = "held_bills"

    static func load() -> [HeldBill] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([HeldBill].self, from: data)) ?? []
    }

    static func save(_ bills: [HeldBill]) {
        guard let data = try? JSONEncoder().encode(bills) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func add(_ bill: HeldBill) {
        var bills = load()
        bills.insert(bill, at: 0)
        save(bills)
    }

    static func remove(id: UUID) {
        save(load().filter { $0.id != id })
    }
}
