import Foundation

/// A line in the in-progress cart. Client-generated id, never coalesced —
/// tapping the same product twice makes two lines (plants of the same kind
/// often sell at different prices by size), mirroring Android's CartLine.
///
/// Quantity and price are held as RAW TEXT because both start blank on a new
/// bill — no `0`, no qty 1, no saved-price prefill (see `info/iOS-UPDATES.md`
/// §2). Blank is a real state, distinct from zero: the line stays in the cart
/// while blank, and only the trash control removes it. The bill cannot be
/// saved until every line `isFilled`.
struct CartLine: Identifiable, Equatable {
    let id: UUID
    let productId: UUID
    var productName: String
    /// Raw quantity input; blank means "not filled in yet".
    var qtyInput: String
    /// Raw whole-rupee price input; blank means "not filled in yet".
    var priceInput: String

    var quantity: Int { Int(qtyInput.trimmingCharacters(in: .whitespaces)) ?? 0 }
    var unitPrice: Money {
        let trimmed = priceInput.trimmingCharacters(in: .whitespaces)
        return Money.parse(trimmed.isEmpty ? "0" : trimmed)
    }
    var lineTotal: Money { unitPrice * quantity }

    /// Ready to bill: a real quantity (≥ 1) and a non-blank price.
    var isFilled: Bool {
        quantity >= 1 && !priceInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init(id: UUID = UUID(), productId: UUID, productName: String, qtyInput: String = "", priceInput: String = "") {
        self.id = id
        self.productId = productId
        self.productName = productName
        self.qtyInput = qtyInput
        self.priceInput = priceInput
    }
}

enum DiscountType: String {
    case flat
    case percent
}

enum PaymentMode: String {
    case cash, upi, split
}

/// DISPLAY ONLY — mirrors the server's rules so the UI shows a live, correct
/// preview before submit, but the server recomputes and is authoritative on
/// every checkout.
enum CartMath {
    static func subtotal(_ lines: [CartLine]) -> Money {
        lines.reduce(Money.zero) { $0 + $1.lineTotal }
    }

    static func discountAmount(subtotal: Money, type: DiscountType, value: Money) -> Money {
        switch type {
        case .flat:
            return min(value, subtotal)
        case .percent:
            let clampedPercent = min(value.amount, 100)
            return Money(amount: subtotal.amount * clampedPercent / 100)
        }
    }

    static func total(subtotal: Money, discount: Money) -> Money {
        subtotal - discount
    }
}
