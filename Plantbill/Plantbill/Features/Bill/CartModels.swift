import Foundation

/// A line in the in-progress cart. Client-generated id, never coalesced —
/// tapping the same product twice makes two lines (plants of the same kind
/// often sell at different prices by size), mirroring Android's CartLine.
///
/// Quantity and price are held as RAW TEXT. Quantity starts blank on every
/// tap; the price pre-fills from the product's saved price and is blank only
/// when the product has none (₹0) — Android's `addLine`. Blank is a real
/// state, distinct from zero: the line stays in the cart while blank, and only
/// the remove control takes it out. The bill can't be saved until every line
/// `isFilled`.
struct CartLine: Identifiable, Equatable {
    let id: UUID
    let productId: UUID
    var productName: String
    /// Raw quantity input; blank means "not filled in yet".
    var qtyInput: String
    /// Raw price input; blank means "not filled in yet".
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

/// DISPLAY ONLY — mirrors the server's rules (and Android's `CartMath`) so the
/// UI shows a live, correct preview before submit, but the server recomputes
/// and is authoritative on every checkout.
enum CartMath {
    static func subtotal(_ lines: [CartLine]) -> Money {
        lines.reduce(Money.zero) { $0 + $1.lineTotal }
    }

    /// Flat is capped at the subtotal; percent at 100%, rounded half-up to the
    /// paisa like the server.
    static func discountAmount(subtotal: Money, type: DiscountType, value: Money) -> Money {
        guard subtotal.isPositive, value.isPositive else { return .zero }
        switch type {
        case .flat:
            return min(value, subtotal)
        case .percent:
            let percent = min(value.amount, 100)
            var raw = subtotal.amount * percent / 100
            var rounded = Decimal()
            NSDecimalRound(&rounded, &raw, 2, .plain)
            return Money(amount: rounded)
        }
    }

    static func total(subtotal: Money, discount: Money) -> Money {
        subtotal - discount
    }

    /// Splits what's payable now into (cash, upi). `due` is the part deferred,
    /// so payable now = total − due. Guarantees cash + upi + due == total — the
    /// server's hard rule — with Split auto-filling UPI as the remainder.
    /// Android's `paymentSplit`.
    static func paymentSplit(total: Money, mode: PaymentMode, cashEntered: Money, due: Money) -> (cash: Money, upi: Money) {
        let safeDue = min(due, total)
        let payableNow = total - safeDue
        switch mode {
        case .cash:
            return (payableNow, .zero)
        case .upi:
            return (.zero, payableNow)
        case .split:
            let cash: Money
            if payableNow < cashEntered {
                cash = payableNow
            } else if cashEntered.isNegative {
                cash = .zero
            } else {
                cash = cashEntered
            }
            return (cash, payableNow - cash)
        }
    }
}
