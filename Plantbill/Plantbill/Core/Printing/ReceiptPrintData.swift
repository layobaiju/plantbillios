import Foundation
import UIKit

/// Everything needed to render a printable receipt — a common shape both
/// `BillOut` (right after checkout) and `BillDetail` (viewing/reprinting
/// later) can map to, so the print layout only needs to be built once.
struct ReceiptPrintData {
    struct Item {
        let name: String
        let quantity: Int
        let unitPrice: Money
        let lineTotal: Money
    }

    /// "0001", or the first 8 characters of the id for a bill saved before
    /// bill numbers existed — Android's fallback.
    let billNumber: String
    let businessName: String
    let businessAddress: String?
    let businessPhone: String?
    let createdAt: Date
    let staffEmail: String?
    let customerName: String?
    let customerPhone: String?
    let remarks: String?
    let items: [Item]
    let subtotal: Money
    /// "Discount", or "Discount (10.00%)" for a percentage discount.
    let discountLabel: String
    let discountAmount: Money
    let total: Money
    let cashAmount: Money
    let upiAmount: Money
    let dueAmount: Money
    /// The shop's logo, when it has one switched on. Fetched just before
    /// printing and never required.
    var logo: UIImage? = nil

    static func billNumber(_ billNo: String?, id: UUID) -> String {
        billNo ?? String(id.uuidString.prefix(8)).uppercased()
    }

    static func discountLabel(type: String, value: String) -> String {
        type == "percent" ? "Discount (\(Money.parse(value).toWire())%)" : "Discount"
    }
}

extension BillDetail {
    var receiptData: ReceiptPrintData {
        ReceiptPrintData(
            billNumber: ReceiptPrintData.billNumber(billNo, id: id),
            businessName: businessName ?? shopName ?? "NURSERY RECEIPT",
            businessAddress: businessAddress,
            businessPhone: businessPhone,
            createdAt: createdAt,
            staffEmail: salespersonEmail,
            customerName: customerName,
            customerPhone: customerPhone,
            remarks: remarks,
            items: items.map { .init(name: $0.productName, quantity: $0.quantity, unitPrice: $0.unitPriceMoney, lineTotal: $0.lineTotalMoney) },
            subtotal: subtotalMoney,
            discountLabel: ReceiptPrintData.discountLabel(type: discountType, value: discountValue),
            discountAmount: discountAmountMoney,
            total: totalMoney,
            cashAmount: cashAmountMoney,
            upiAmount: upiAmountMoney,
            dueAmount: dueAmountMoney
        )
    }
}

extension BillOut {
    /// What the app holds without a round trip. Used only when the full bill
    /// can't be fetched (no signal), so the receipt still prints — just
    /// without the shop's address, phone and logo.
    var receiptData: ReceiptPrintData {
        ReceiptPrintData(
            billNumber: ReceiptPrintData.billNumber(billNo, id: id),
            businessName: BusinessProfile.shared.businessName ?? BusinessProfile.shared.shopName ?? "NURSERY RECEIPT",
            businessAddress: nil,
            businessPhone: nil,
            createdAt: createdAt,
            staffEmail: salespersonEmail,
            customerName: customerName,
            customerPhone: nil,
            remarks: remarks,
            items: items.map { .init(name: $0.productName, quantity: $0.quantity, unitPrice: Money.parse($0.unitPrice), lineTotal: Money.parse($0.lineTotal)) },
            subtotal: Money.parse(subtotal),
            discountLabel: ReceiptPrintData.discountLabel(type: discountType, value: discountValue),
            discountAmount: Money.parse(discountAmount),
            total: Money.parse(total),
            cashAmount: Money.parse(cashAmount),
            upiAmount: Money.parse(upiAmount),
            dueAmount: Money.parse(dueAmount)
        )
    }
}
