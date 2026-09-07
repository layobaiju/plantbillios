import Combine
import Foundation

@MainActor
final class BillingViewModel: ObservableObject {
    enum ProductLoadState {
        case loading
        case loaded([Product])
        case empty
        case error(String)
    }

    enum CheckoutState: Equatable {
        case idle
        case submitting
        case success(BillOut)
        case error(String)

        static func == (lhs: CheckoutState, rhs: CheckoutState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.submitting, .submitting): return true
            case (.success(let a), .success(let b)): return a.id == b.id
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    // MARK: Product browsing

    @Published private(set) var productState: ProductLoadState = .loading
    @Published var searchText: String = "" { didSet { scheduleReload() } }
    @Published var selectedCategory: String? = nil { didSet { Task { await loadProducts() } } }
    @Published private(set) var categories: [String] = []
    @Published private var searchDebounceTask: Task<Void, Never>?

    // MARK: Cart

    @Published private(set) var cartLines: [CartLine] = []
    @Published var discountType: DiscountType = .flat
    @Published var discountValueText: String = ""
    @Published var paymentMode: PaymentMode = .cash
    @Published var cashPartText: String = ""
    @Published var dueAmountText: String = ""
    @Published var customerName: String = ""
    /// Digits only, capped at 10 — the server rejects a non-10-digit
    /// `new_customer.phone` with 422, so it is enforced here on the way in.
    /// Setting it (re)schedules the returning-customer lookup.
    @Published var customerPhone: String = "" {
        didSet {
            let digits = String(customerPhone.filter(\.isNumber).prefix(10))
            if digits != customerPhone {
                customerPhone = digits
                return // the re-entrant set below handles the rest
            }
            if digits.count < 10 { returningCustomer = nil }
            scheduleCustomerLookup(digits)
        }
    }
    /// Non-nil only when the backend reported a match for the current 10-digit
    /// number. Never gates or delays saving the bill.
    @Published private(set) var returningCustomer: CustomerLookup?
    @Published private var lookupTask: Task<Void, Never>?
    @Published var remarks: String = ""
    @Published private(set) var idempotencyKey = UUID().uuidString

    // MARK: Held bills

    @Published private(set) var heldBills: [HeldBill] = HeldBillStore.load()

    // MARK: Checkout

    @Published private(set) var checkoutState: CheckoutState = .idle

    // MARK: Computed (display-only preview — server is authoritative)

    var subtotal: Money { CartMath.subtotal(cartLines) }
    var discountValueMoney: Money { Money.parse(discountValueText) }
    var discountAmount: Money { CartMath.discountAmount(subtotal: subtotal, type: discountType, value: discountValueMoney) }
    var total: Money { CartMath.total(subtotal: subtotal, discount: discountAmount) }
    var dueAmount: Money { Money.parse(dueAmountText) }
    var amountToCollect: Money {
        let remainder = total - dueAmount
        return remainder.isNegative ? .zero : remainder
    }
    var cashAmount: Money {
        switch paymentMode {
        case .cash: return amountToCollect
        case .upi: return .zero
        case .split: return min(Money.parse(cashPartText), amountToCollect)
        }
    }
    var upiAmount: Money {
        switch paymentMode {
        case .cash: return .zero
        case .upi: return amountToCollect
        case .split: return amountToCollect - cashAmount
        }
    }
    var requiresCustomerPhone: Bool { dueAmount.isPositive }

    /// Every line needs a quantity ≥ 1 and a price before the bill can be
    /// saved. Mirrors Android's `allLinesFilled`.
    var allLinesFilled: Bool { !cartLines.isEmpty && cartLines.allSatisfy(\.isFilled) }

    /// Shown under the disabled Save button while any line is still blank.
    var showsIncompleteLinesHint: Bool { !cartLines.isEmpty && !allLinesFilled }

    // MARK: Product loading

    private func scheduleReload() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await loadProducts()
        }
    }

    func loadProducts() async {
        productState = .loading
        do {
            var query: [URLQueryItem] = [URLQueryItem(name: "active", value: "true")]
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { query.append(URLQueryItem(name: "q", value: trimmed)) }
            if let selectedCategory { query.append(URLQueryItem(name: "category", value: selectedCategory)) }

            let products: [Product] = try await APIClient.shared.send(Endpoint(path: "products", queryItems: query))
            categories = Array(Set(products.compactMap { $0.category?.isEmpty == false ? $0.category : nil })).sorted()
            productState = products.isEmpty ? .empty : .loaded(products)
        } catch let error as APIError {
            productState = .error(error.userMessage)
        } catch {
            productState = .error(APIError.unknown.userMessage)
        }
    }

    // MARK: Cart line editing

    /// Manual tap-to-add starts BLANK — no quantity, no price prefill from the
    /// product's saved price. The operator enters the size-based price and the
    /// count for every line (`info/iOS-UPDATES.md` §2).
    func addToCart(_ product: Product) {
        cartLines.append(CartLine(productId: product.id, productName: product.name))
    }

    /// Raw text straight from the quantity box. Clearing it returns the line to
    /// blank and KEEPS the line — blank is not "removed"; only the trash
    /// control removes a line.
    func updateQuantityText(lineId: UUID, text: String) {
        guard let index = cartLines.firstIndex(where: { $0.id == lineId }) else { return }
        cartLines[index].qtyInput = text.filter(\.isNumber)
    }

    func updatePriceText(lineId: UUID, text: String) {
        guard let index = cartLines.firstIndex(where: { $0.id == lineId }) else { return }
        cartLines[index].priceInput = text.filter(\.isNumber)
    }

    /// Stepper `+`: from blank this gives 1, matching Android's QuantityStepper.
    func incrementQuantity(lineId: UUID) {
        guard let index = cartLines.firstIndex(where: { $0.id == lineId }) else { return }
        let next = max(1, cartLines[index].quantity + 1)
        cartLines[index].qtyInput = "\(next)"
    }

    /// Stepper `−`: floors at 1 so it can never reach 0 (removing is the trash
    /// control's job, not the stepper's). From blank it also lands on 1.
    func decrementQuantity(lineId: UUID) {
        guard let index = cartLines.firstIndex(where: { $0.id == lineId }) else { return }
        let next = max(1, cartLines[index].quantity - 1)
        cartLines[index].qtyInput = "\(next)"
    }

    func removeLine(lineId: UUID) {
        cartLines.removeAll { $0.id == lineId }
    }

    func clearCart() {
        cartLines = []
        discountType = .flat
        discountValueText = ""
        paymentMode = .cash
        cashPartText = ""
        dueAmountText = ""
        customerName = ""
        customerPhone = ""
        lookupTask?.cancel()
        returningCustomer = nil
        remarks = ""
        idempotencyKey = UUID().uuidString
        checkoutState = .idle
    }

    // MARK: Returning-customer lookup

    /// Debounced ~350ms once the field reaches 10 digits. Fire-and-forget: a
    /// failure leaves the hint empty and never surfaces an error, because this
    /// must never block or delay saving a bill. RLS scopes the visit count to
    /// this shop, so a number only ever seen at another shop returns found=false.
    private func scheduleCustomerLookup(_ digits: String) {
        lookupTask?.cancel()
        guard digits.count == 10 else { return }
        lookupTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let result: CustomerLookup? = try? await APIClient.shared.send(
                Endpoint(path: "customers/lookup", queryItems: [URLQueryItem(name: "phone", value: digits)])
            )
            guard let self, !Task.isCancelled else { return }
            // Ignore a late response if the field changed while it was in flight.
            guard self.customerPhone == digits else { return }
            self.returningCustomer = (result?.found == true) ? result : nil
        }
    }

    // MARK: Quick add

    func quickAdd(name: String, price: Money, quantity: Int) async -> Bool {
        do {
            let body = try APIClient.shared.encode(
                ProductCreateRequest(name: name, category: "Quick Add", retailPrice: price.toWire(), lastWholesalePrice: nil)
            )
            let product: Product = try await APIClient.shared.send(Endpoint(path: "products", method: .post, body: body))
            // Quick add is the one flow that seeds explicit values — the operator
            // has just typed the price and count, so the line arrives filled.
            cartLines.append(
                CartLine(
                    productId: product.id,
                    productName: product.name,
                    qtyInput: "\(max(1, quantity))",
                    priceInput: price.toInput()
                )
            )
            return true
        } catch {
            return false
        }
    }

    // MARK: Held bills

    func holdCurrentBill() {
        guard !cartLines.isEmpty else { return }
        HeldBillStore.add(snapshotCurrentBill())
        heldBills = HeldBillStore.load()
        clearCart()
    }

    func resume(_ held: HeldBill) {
        if !cartLines.isEmpty {
            HeldBillStore.add(snapshotCurrentBill())
        }
        // A held bill was filled in before it was parked, so it comes back with
        // its values intact rather than blank.
        cartLines = held.lines.map {
            CartLine(
                id: $0.id,
                productId: $0.productId,
                productName: $0.productName,
                qtyInput: $0.quantity >= 1 ? "\($0.quantity)" : "",
                priceInput: Money.parse($0.unitPriceWire).toInput()
            )
        }
        discountType = DiscountType(rawValue: held.discountType) ?? .flat
        discountValueText = held.discountValueText
        paymentMode = PaymentMode(rawValue: held.paymentMode) ?? .cash
        cashPartText = held.cashAmountText
        dueAmountText = held.dueAmountText
        customerName = held.customerName
        customerPhone = held.customerPhone
        remarks = held.remarks
        idempotencyKey = held.idempotencyKey
        checkoutState = .idle

        HeldBillStore.remove(id: held.id)
        heldBills = HeldBillStore.load()
    }

    func discardHeld(_ held: HeldBill) {
        HeldBillStore.remove(id: held.id)
        heldBills = HeldBillStore.load()
    }

    private func snapshotCurrentBill() -> HeldBill {
        HeldBill(
            id: UUID(),
            savedAt: Date(),
            idempotencyKey: idempotencyKey,
            lines: cartLines.map {
                HeldBill.Line(id: $0.id, productId: $0.productId, productName: $0.productName, unitPriceWire: $0.unitPrice.toWire(), quantity: $0.quantity)
            },
            discountType: discountType.rawValue,
            discountValueText: discountValueText,
            paymentMode: paymentMode.rawValue,
            cashAmountText: cashPartText,
            upiAmountText: "",
            dueAmountText: dueAmountText,
            customerName: customerName,
            customerPhone: customerPhone,
            remarks: remarks
        )
    }

    // MARK: Checkout

    func checkout() async {
        guard !cartLines.isEmpty else { return }
        // The server enforces quantity ≥ 1 / unit_price ≥ 0; the client's job is
        // simply never to submit an incomplete line.
        guard allLinesFilled else {
            checkoutState = .error("Enter a quantity and price for every item.")
            return
        }
        if requiresCustomerPhone && !isValidPhone(customerPhone) {
            checkoutState = .error("Enter a valid 10-digit phone number since money is owed on this bill.")
            return
        }

        checkoutState = .submitting

        let trimmedName = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = customerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRemarks = remarks.trimmingCharacters(in: .whitespacesAndNewlines)

        let request = BillCreateRequest(
            idempotencyKey: idempotencyKey,
            items: cartLines.map { .init(productId: $0.productId, quantity: $0.quantity, unitPrice: $0.unitPrice.toWire()) },
            discountType: discountType.rawValue,
            discountValue: discountValueMoney.toWire(),
            cashAmount: cashAmount.toWire(),
            upiAmount: upiAmount.toWire(),
            dueAmount: dueAmount.toWire(),
            remarks: trimmedRemarks.isEmpty ? nil : trimmedRemarks,
            newCustomer: trimmedName.isEmpty ? nil : .init(name: trimmedName, phone: trimmedPhone.isEmpty ? nil : trimmedPhone)
        )

        do {
            let body = try APIClient.shared.encode(request)
            let bill: BillOut = try await APIClient.shared.send(Endpoint(path: "bills", method: .post, body: body))
            checkoutState = .success(bill)
        } catch let error as APIError {
            checkoutState = .error(error.userMessage)
        } catch {
            checkoutState = .error(APIError.unknown.userMessage)
        }
    }

    func startNewBill() {
        clearCart()
    }

    private func isValidPhone(_ phone: String) -> Bool {
        let digits = phone.filter(\.isNumber)
        return digits.count == 10
    }
}
