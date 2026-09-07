import Combine
import Foundation

/// Owner-only bill editing: change a line's price/quantity, add or remove
/// plants, adjust the discount and payment split. The server recomputes
/// every amount and marks the bill edited.
@MainActor
final class BillEditViewModel: ObservableObject {
    let billId: UUID

    @Published private(set) var isLoading = true
    @Published private(set) var loadError: String?
    @Published private(set) var products: [Product] = []
    @Published private(set) var lines: [CartLine] = []

    @Published var discountType: DiscountType = .flat
    @Published var discountValueText: String = ""
    @Published var paymentMode: PaymentMode = .cash
    @Published var cashPartText: String = ""
    @Published var dueAmountText: String = ""
    @Published var remarks: String = ""
    @Published private(set) var customerPhone: String?

    @Published var showingAddPicker = false
    @Published private(set) var isSaving = false
    @Published var saveError: String?
    @Published var saved = false

    init(billId: UUID) {
        self.billId = billId
    }

    var subtotal: Money { CartMath.subtotal(lines) }
    var discountValueMoney: Money { Money.parse(discountValueText) }
    var discountAmount: Money { CartMath.discountAmount(subtotal: subtotal, type: discountType, value: discountValueMoney) }
    var total: Money { CartMath.total(subtotal: subtotal, discount: discountAmount) }
    var isEmpty: Bool { lines.isEmpty }

    private var cashPartMoney: Money { Money.parse(cashPartText) }
    private var dueMoney: Money {
        let raw = Money.parse(dueAmountText)
        return raw > total ? total : raw
    }
    var cashAmount: Money {
        switch paymentMode {
        case .cash: return total - dueMoney
        case .upi: return .zero
        case .split: return min(cashPartMoney, total - dueMoney)
        }
    }
    var upiAmount: Money {
        let remainder = total - dueMoney - cashAmount
        return remainder.isNegative ? .zero : remainder
    }

    func load() async {
        isLoading = true
        loadError = nil
        async let detailTask: BillDetail? = try? APIClient.shared.send(Endpoint(path: "bills/\(billId)"))
        async let productsTask: [Product] = (try? APIClient.shared.send(Endpoint(path: "products", queryItems: [URLQueryItem(name: "active", value: "true")]))) ?? []
        let (detail, catalog) = await (detailTask, productsTask)
        products = catalog
        guard let detail else {
            isLoading = false
            loadError = "Couldn't load this bill."
            return
        }
        seed(from: detail, catalog: catalog)
        isLoading = false
    }

    private func seed(from detail: BillDetail, catalog: [Product]) {
        lines = detail.items.compactMap { item -> CartLine? in
            guard let productId = item.productId else { return nil }
            let name = catalog.first { $0.id == productId }?.name ?? item.productName
            // Editing an existing bill deliberately KEEPS its values — only new
            // bill creation starts blank (`info/iOS-UPDATES.md` §2).
            return CartLine(
                productId: productId,
                productName: name,
                qtyInput: "\(item.quantity)",
                priceInput: item.unitPriceMoney.toInput()
            )
        }
        discountType = DiscountType(rawValue: detail.discountType) ?? .flat
        let discountValue = Money.parse(detail.discountValue)
        discountValueText = discountValue.isPositive ? discountValue.toInput() : ""
        if detail.cashAmountMoney.isPositive && detail.upiAmountMoney.isPositive {
            paymentMode = .split
        } else if detail.upiAmountMoney.isPositive {
            paymentMode = .upi
        } else {
            paymentMode = .cash
        }
        cashPartText = detail.cashAmountMoney.isPositive ? detail.cashAmountMoney.toInput() : ""
        dueAmountText = detail.dueAmountMoney.isPositive ? detail.dueAmountMoney.toInput() : ""
        remarks = detail.remarks ?? ""
        customerPhone = detail.customerPhone
    }

    // MARK: Line editing

    func setQuantity(lineId: UUID, quantity: Int) {
        if quantity <= 0 {
            lines.removeAll { $0.id == lineId }
        } else if let index = lines.firstIndex(where: { $0.id == lineId }) {
            lines[index].qtyInput = "\(quantity)"
        }
    }

    func setUnitPrice(lineId: UUID, price: Money) {
        guard let index = lines.firstIndex(where: { $0.id == lineId }) else { return }
        lines[index].priceInput = price.toInput()
    }

    func removeLine(lineId: UUID) {
        lines.removeAll { $0.id == lineId }
    }

    func addProduct(_ product: Product) {
        // Same rule as seeding: the edit flow keeps prefilled values.
        lines.append(
            CartLine(
                productId: product.id,
                productName: product.name,
                qtyInput: "1",
                priceInput: product.price.toInput()
            )
        )
        showingAddPicker = false
    }

    // MARK: Save

    func save() async {
        guard !isEmpty, !isSaving else { return }
        let due = dueMoney
        if due.isPositive, (customerPhone?.filter(\.isNumber).count ?? 0) < 10 {
            saveError = "This bill has no phone on file — can't leave money due without one."
            return
        }
        isSaving = true
        saveError = nil
        do {
            let request = BillUpdateRequest(
                cashAmount: cashAmount.toWire(),
                upiAmount: upiAmount.toWire(),
                dueAmount: due.toWire(),
                remarks: remarks.trimmingCharacters(in: .whitespacesAndNewlines),
                items: lines.map { .init(productId: $0.productId, quantity: $0.quantity, unitPrice: $0.unitPrice.toWire()) },
                discountType: discountType.rawValue,
                discountValue: discountValueMoney.toWire()
            )
            let body = try APIClient.shared.encode(request)
            let _: BillDetail = try await APIClient.shared.send(Endpoint(path: "bills/\(billId)", method: .patch, body: body))
            isSaving = false
            saved = true
        } catch let error as APIError {
            isSaving = false
            saveError = error.userMessage
        } catch {
            isSaving = false
            saveError = APIError.unknown.userMessage
        }
    }
}
