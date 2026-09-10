import Combine
import Foundation

/// A short confirmation shown over the bill screen — Android's Snackbar
/// messages. An enum rather than a String so the view can render each one as
/// localized text.
enum BillToast: Equatable {
    case addedToCart(String)
    case added(String)
    case billHeld
    case voiceNeedsProducts
    case voiceUnavailable
}

@MainActor
final class BillingViewModel: ObservableObject {
    enum CatalogState: Equatable {
        case loading
        case loaded
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

    // MARK: Catalogue

    /// Loaded once and filtered on the phone, like Android's
    /// `filteredProducts`. Typing a letter or tapping a category never goes
    /// back to the server, so the grid doesn't blank to a spinner in the
    /// middle of a search and the category chips don't collapse to the one
    /// that was picked.
    @Published private(set) var catalogState: CatalogState = .loading
    @Published private(set) var products: [Product] = []
    @Published var searchText: String = ""
    @Published var selectedCategory: String?
    /// True when the catalogue came from this phone because the server
    /// couldn't be reached.
    @Published private(set) var isShowingCachedProducts = false

    var categories: [String] {
        let names = products.compactMap { product -> String? in
            guard let category = product.category,
                  !category.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return category
        }
        return Array(Set(names)).sorted()
    }

    var filteredProducts: [Product] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return products.filter { product in
            if let selectedCategory, product.category != selectedCategory { return false }
            if !needle.isEmpty, product.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) == nil {
                return false
            }
            return true
        }
    }

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
            let digits = String(Self.asciiDigits(customerPhone).prefix(10))
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
    private var lookupTask: Task<Void, Never>?
    @Published var remarks: String = ""
    /// Reused across retries of the same cart so a double tap never saves the
    /// bill twice; replaced once the cart is cleared or saved.
    private(set) var idempotencyKey = UUID().uuidString

    // MARK: Held bills

    @Published private(set) var heldBills: [HeldBill] = HeldBillStore.load()

    // MARK: Checkout

    @Published private(set) var checkoutState: CheckoutState = .idle
    @Published private(set) var toast: BillToast?
    private var toastTask: Task<Void, Never>?

    // MARK: Computed (display-only preview — the server is authoritative)

    var subtotal: Money { CartMath.subtotal(cartLines) }
    var discountValueMoney: Money { Money.parse(discountValueText) }
    var discountAmount: Money { CartMath.discountAmount(subtotal: subtotal, type: discountType, value: discountValueMoney) }
    var total: Money { CartMath.total(subtotal: subtotal, discount: discountAmount) }
    var dueAmount: Money { Money.parse(dueAmountText) }
    /// The due actually sent: never more than the bill itself. Android clamps
    /// the same way, so an over-typed due can't make cash + UPI + due miss the
    /// total and have the server refuse the bill.
    var effectiveDue: Money { min(dueAmount, total) }
    private var payment: (cash: Money, upi: Money) {
        CartMath.paymentSplit(total: total, mode: paymentMode, cashEntered: Money.parse(cashPartText), due: dueAmount)
    }
    var cashAmount: Money { payment.cash }
    var upiAmount: Money { payment.upi }
    /// The customer labels switch to "required" as soon as any due is typed.
    var requiresCustomerPhone: Bool { dueAmount.isPositive }
    /// The cart button's badge — Android's `itemCount`, the sum of quantities.
    var itemCount: Int { cartLines.reduce(0) { $0 + $1.quantity } }

    /// Every line needs a quantity ≥ 1 and a price before the bill can be
    /// saved. Mirrors Android's `allLinesFilled`.
    var allLinesFilled: Bool { !cartLines.isEmpty && cartLines.allSatisfy(\.isFilled) }

    /// Shown under the disabled Save button while any line is still blank.
    var showsIncompleteLinesHint: Bool { !cartLines.isEmpty && !allLinesFilled }

    /// For the scan-to-pay QR: the shop's UPI ID, and the name the customer's
    /// UPI app shows as the payee — the shop's, never the app's.
    var businessUpi: String? { BusinessProfile.shared.upi }
    var businessName: String { BusinessProfile.shared.businessName ?? BusinessProfile.shared.shopName ?? "" }

    // MARK: Product loading

    func loadProducts() async {
        if products.isEmpty { catalogState = .loading }
        do {
            let list: [Product] = try await APIClient.shared.send(
                Endpoint(path: "products", queryItems: [URLQueryItem(name: "active", value: "true")])
            )
            products = list
            isShowingCachedProducts = false
            catalogState = .loaded
            ProductCache.save(list, shopId: BusinessProfile.shared.shopId)
        } catch {
            // With no signal, serve the last known catalogue rather than an
            // error — the cashier can still browse plants, build a cart and
            // hold the bill.
            if let cached = ProductCache.load(shopId: BusinessProfile.shared.shopId)?.filter(\.isActive),
               !cached.isEmpty {
                products = cached
                isShowingCachedProducts = true
                catalogState = .loaded
            } else if products.isEmpty {
                catalogState = .error((error as? APIError)?.userMessage ?? APIError.unknown.userMessage)
            }
        }
    }

    // MARK: Cart line editing

    /// Always appends a NEW line — tapping a plant that's already in the cart
    /// does not bump the existing line, because the same plant in a different
    /// size is a different price. Quantity starts blank; the price pre-fills
    /// from the saved price and is left blank only when there is none (₹0),
    /// which forces a deliberate entry. The search box is cleared so the next
    /// plant is searched from empty. Android's `addLine`.
    func addToCart(_ product: Product) {
        cartLines.append(
            CartLine(
                productId: product.id,
                productName: product.name,
                priceInput: product.price.isPositive ? product.price.toInput() : ""
            )
        )
        searchText = ""
    }

    /// Raw text straight from the quantity box. Clearing it returns the line
    /// to blank and KEEPS the line — only the remove control removes a line.
    func updateQuantityText(lineId: UUID, text: String) {
        guard let index = cartLines.firstIndex(where: { $0.id == lineId }) else { return }
        cartLines[index].qtyInput = String(Self.asciiDigits(text).prefix(7))
    }

    /// Blank stays blank — it is never coerced to 0.
    func updatePriceText(lineId: UUID, text: String) {
        guard let index = cartLines.firstIndex(where: { $0.id == lineId }) else { return }
        cartLines[index].priceInput = Self.sanitizedAmount(text)
    }

    /// Stepper `+`: from blank this gives 1, matching Android's QuantityStepper.
    func incrementQuantity(lineId: UUID) {
        guard let index = cartLines.firstIndex(where: { $0.id == lineId }) else { return }
        cartLines[index].qtyInput = "\(max(1, cartLines[index].quantity + 1))"
    }

    /// Stepper `−`: floors at 1 so it can never reach 0 (removing is the
    /// remove control's job, not the stepper's).
    func decrementQuantity(lineId: UUID) {
        guard let index = cartLines.firstIndex(where: { $0.id == lineId }) else { return }
        cartLines[index].qtyInput = "\(max(1, cartLines[index].quantity - 1))"
    }

    func removeLine(lineId: UUID) {
        cartLines.removeAll { $0.id == lineId }
    }

    /// Empty the cart and reset every bill input, keeping the loaded catalogue.
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

    // MARK: Voice search

    /// Every alternative the recogniser heard is scored against the catalogue
    /// and the best-scoring product is added straight to the cart. The mic is
    /// deliberately restricted to the shop's own products: whatever is spoken
    /// snaps to a real product name rather than leaking stray words into a
    /// text search. Mirrors Android's `onVoiceTranscript`.
    func onVoiceTranscript(_ alternatives: [String]) {
        guard !products.isEmpty else {
            showToast(.voiceNeedsProducts)
            return
        }
        let names = products.map(\.name)
        var best: PhoneticMatcher.Match?
        for alt in alternatives {
            if let m = PhoneticMatcher.findClosest(transcript: alt, candidates: names),
               best == nil || m.score > best!.score {
                best = m
            }
        }
        let product = best.flatMap { m in products.first { $0.name == m.candidate } } ?? products[0]
        addToCart(product)
        showToast(.addedToCart(product.name))
    }

    func showVoiceUnavailable() {
        showToast(.voiceUnavailable)
    }

    private func showToast(_ message: BillToast) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
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

    /// Creates a "Quick Add" product, then carts it with the typed price and
    /// count. Returns nil on success, or the message to show under the form.
    /// Android's `saveQuickAdd`.
    func quickAdd(name: String, price: Money, quantity: Int) async -> String? {
        do {
            let body = try APIClient.shared.encode(
                ProductCreateRequest(name: name, category: "Quick Add", retailPrice: price.toWire(), lastWholesalePrice: nil)
            )
            let product: Product = try await APIClient.shared.send(Endpoint(path: "products", method: .post, body: body))
            products.insert(product, at: 0)
            // Quick add is the one flow that seeds explicit values — the
            // operator has just typed the price and count, so the line arrives
            // filled.
            cartLines.append(
                CartLine(
                    productId: product.id,
                    productName: product.name,
                    qtyInput: "\(max(1, quantity))",
                    priceInput: price.toInput()
                )
            )
            searchText = ""
            showToast(.added(product.name))
            return nil
        } catch let error as APIError {
            if case .network = error { return error.userMessage }
            if case .badRequest(let detail) = error { return detail }
            return "Couldn't add the item."
        } catch {
            return "Couldn't add the item."
        }
    }

    // MARK: Held bills

    /// Park the current cart so a ready customer can be billed first. Saves a
    /// device-local snapshot of the whole bill, then empties the cart. Resume
    /// it later from "Held bills".
    func holdCurrentBill() {
        guard !cartLines.isEmpty else { return }
        HeldBillStore.add(snapshotCurrentBill())
        heldBills = HeldBillStore.load()
        clearCart()
        showToast(.billHeld)
    }

    /// If a cart is already in progress it is parked first — never silently
    /// discarded — then the chosen held bill is restored and removed from the
    /// held list.
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
            remarks: remarks,
            itemCount: itemCount,
            totalWire: total.toWire()
        )
    }

    // MARK: Checkout

    func checkout() async {
        guard !cartLines.isEmpty, checkoutState != .submitting else { return }
        // The server enforces quantity ≥ 1 / unit_price ≥ 0; the client's job is
        // simply never to submit an incomplete line.
        guard allLinesFilled else {
            checkoutState = .error("Enter a quantity and price for every item before saving.")
            return
        }
        let due = effectiveDue
        // A due means money owed later — the shop must be able to reach the
        // customer, so their phone number is compulsory whenever any amount is
        // left unpaid.
        if due.isPositive && customerPhone.count < 10 {
            checkoutState = .error("Enter the customer's phone number — it's required when there's a due (money owed).")
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
            dueAmount: due.toWire(),
            remarks: trimmedRemarks.isEmpty ? nil : trimmedRemarks,
            // Same rule as Android's BillRepository: the customer travels only
            // with a name; the phone rides along with it.
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

    // MARK: Input helpers

    /// Keeps digits only, normalised to ASCII — a Hindi or Tamil keypad can
    /// type its own numerals, which `Int`/`Decimal` parsing wouldn't read.
    private static func asciiDigits(_ text: String) -> String {
        String(text.compactMap { ch -> Character? in
            guard let value = ch.wholeNumberValue, (0...9).contains(value) else { return nil }
            return Character(String(value))
        })
    }

    /// Digits plus at most one decimal point, so a pre-filled price like
    /// "150.5" survives being edited.
    private static func sanitizedAmount(_ text: String) -> String {
        var result = ""
        var seenPoint = false
        for ch in text {
            if let value = ch.wholeNumberValue, (0...9).contains(value) {
                result.append(String(value))
            } else if ch == ".", !seenPoint {
                seenPoint = true
                result.append(ch)
            }
        }
        return result
    }
}
