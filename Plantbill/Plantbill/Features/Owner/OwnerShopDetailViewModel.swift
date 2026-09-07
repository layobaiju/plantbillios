import Combine
import Foundation

struct NewStaffForm: Equatable {
    var email: String = ""
    var password: String = ""
    var role: String = "salesperson"
    var saving = false
    var error: String?

    var canSave: Bool { email.contains("@") && password.count >= 8 && !saving }
}

/// The shop's business identity — what prints on a bill and what a customer
/// pays into. Editable by the owner via `PATCH /owner/shops/{id}`.
struct BusinessDetailsForm: Equatable {
    var name = ""
    var address = ""
    var phone = ""
    var email = ""
    var upi = ""

    init() {}

    init(shop: OwnerShop) {
        name = shop.businessName ?? ""
        address = shop.businessAddress ?? ""
        phone = shop.businessPhone ?? ""
        email = shop.businessEmail ?? ""
        upi = shop.businessUpi ?? ""
    }

    /// Blank means "clear it", so empty strings are sent as nil rather than
    /// as an empty value the backend would have to interpret.
    var request: OwnerShopUpdateRequest {
        func trimmed(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return OwnerShopUpdateRequest(
            businessName: trimmed(name),
            businessAddress: trimmed(address),
            businessPhone: trimmed(phone),
            businessEmail: trimmed(email),
            businessUpi: trimmed(upi)
        )
    }
}

/// The bill whose full detail (items + totals) sheet is open.
struct OwnerBillDetailState {
    var loading = true
    var bill: BillDetail?
}

@MainActor
final class OwnerShopDetailViewModel: ObservableObject {
    let shopId: UUID

    @Published private(set) var report: DetailedReport?
    @Published private(set) var bills: [OwnerBillRow] = []
    @Published private(set) var billsLoading = false
    @Published private(set) var staff: [OwnerStaff] = []
    @Published private(set) var cashInHand: OwnerCashInHand?
    @Published var cashFull = true
    @Published private(set) var labourers: [Labourer] = []

    @Published var labourerDetail: WorkerDetail?
    @Published var billDetail: OwnerBillDetailState?
    @Published var newStaff = NewStaffForm()
    @Published var message: String?

    @Published private(set) var shopProfile: OwnerShop?
    @Published private(set) var savingProfile = false
    /// Set once the owner types, so a background refresh can't wipe an
    /// in-progress edit.
    @Published var profileEdited = false
    @Published var businessForm = BusinessDetailsForm()

    @Published var period: OwnerPeriod = .today {
        didSet {
            if oldValue != period {
                Task { await loadReport() }
                Task { await loadBills() }
                Task { await loadCashInHand() }
            }
        }
    }
    @Published var customFrom: Date = ShopCalendar.calendar.date(byAdding: .day, value: -6, to: ShopCalendar.today()) ?? ShopCalendar.today() {
        didSet {
            if period == .custom {
                Task { await loadReport() }
                Task { await loadBills() }
            }
        }
    }
    @Published var customTo: Date = ShopCalendar.today() {
        didSet {
            if period == .custom {
                Task { await loadReport() }
                Task { await loadBills() }
            }
        }
    }

    init(shopId: UUID) {
        self.shopId = shopId
    }

    func onAppear() async {
        async let reportTask: Void = loadReport()
        async let billsTask: Void = loadBills()
        async let staffTask: Void = loadStaff()
        async let cashTask: Void = loadCashInHand()
        async let labourTask: Void = loadLabourers()
        async let profileTask: Void = loadShopProfile()
        _ = await (reportTask, billsTask, staffTask, cashTask, labourTask, profileTask)
    }

    // MARK: Business details

    /// `GET /owner/shops` is the only route that returns the editable business
    /// fields — the overview rows carry takings, not the profile — so the
    /// shop is picked out of that list by id.
    func loadShopProfile() async {
        let shops: [OwnerShop]? = try? await APIClient.shared.send(Endpoint(path: "owner/shops"))
        guard let shop = shops?.first(where: { $0.id == shopId }) else { return }
        shopProfile = shop
        // Only seed the form the first time, so a refresh can't discard what
        // the owner is part-way through typing.
        if !profileEdited { businessForm = BusinessDetailsForm(shop: shop) }
    }

    func saveShopProfile() async {
        savingProfile = true
        defer { savingProfile = false }
        do {
            let body = try APIClient.shared.encode(businessForm.request)
            let updated: OwnerShop = try await APIClient.shared.send(
                Endpoint(path: "owner/shops/\(shopId)", method: .patch, body: body)
            )
            shopProfile = updated
            businessForm = BusinessDetailsForm(shop: updated)
            profileEdited = false
            message = "Business details saved."
        } catch let error as APIError {
            message = error.userMessage
        } catch {
            message = APIError.unknown.userMessage
        }
    }

    private var currentRange: (Date, Date) { period.range(customFrom: customFrom, customTo: customTo) }

    func loadReport() async {
        let (from, to) = currentRange
        let query = [
            URLQueryItem(name: "date_from", value: ShopCalendar.apiDateString(from)),
            URLQueryItem(name: "date_to", value: ShopCalendar.apiDateString(to)),
        ]
        report = try? await APIClient.shared.send(Endpoint(path: "owner/shops/\(shopId)/report", queryItems: query))
    }

    func loadBills() async {
        let (from, to) = currentRange
        billsLoading = true
        let query = [
            URLQueryItem(name: "date_from", value: ShopCalendar.apiDateString(from)),
            URLQueryItem(name: "date_to", value: ShopCalendar.apiDateString(to)),
        ]
        if let page: OwnerBillList = try? await APIClient.shared.send(Endpoint(path: "owner/shops/\(shopId)/bills", queryItems: query)) {
            bills = page.items
        }
        billsLoading = false
    }

    func loadStaff() async {
        staff = (try? await APIClient.shared.send(Endpoint(path: "owner/shops/\(shopId)/staff"))) ?? []
    }

    func loadCashInHand() async {
        let (_, to) = currentRange
        let query = [URLQueryItem(name: "date", value: ShopCalendar.apiDateString(to))]
        cashInHand = try? await APIClient.shared.send(Endpoint(path: "owner/shops/\(shopId)/cash-in-hand", queryItems: query))
    }

    func loadLabourers() async {
        labourers = (try? await APIClient.shared.send(Endpoint(path: "owner/shops/\(shopId)/labourers"))) ?? []
    }

    // MARK: Labourer detail

    func openLabourer(_ l: Labourer) {
        labourerDetail = WorkerDetail(labourer: l, loading: true)
        Task {
            do {
                let payments: [LabourPayment] = try await APIClient.shared.send(Endpoint(path: "owner/shops/\(shopId)/labourers/\(l.id)/payments"))
                labourerDetail?.loading = false
                labourerDetail?.payments = payments
            } catch {
                labourerDetail?.loading = false
            }
        }
    }
    func closeLabourer() { labourerDetail = nil }

    // MARK: Bill detail

    func openBill(_ id: UUID) {
        billDetail = OwnerBillDetailState(loading: true)
        Task {
            do {
                let bill: BillDetail = try await APIClient.shared.send(Endpoint(path: "owner/shops/\(shopId)/bills/\(id)"))
                billDetail = OwnerBillDetailState(loading: false, bill: bill)
            } catch let error as APIError {
                billDetail = nil
                message = error.userMessage
            } catch {
                billDetail = nil
                message = APIError.unknown.userMessage
            }
        }
    }
    func closeBill() { billDetail = nil }

    // MARK: Staff

    func addStaff() async {
        guard newStaff.canSave else { return }
        newStaff.saving = true
        do {
            let request = OwnerStaffCreateRequest(email: newStaff.email.trimmingCharacters(in: .whitespacesAndNewlines), password: newStaff.password, role: newStaff.role)
            let body = try APIClient.shared.encode(request)
            let _: OwnerStaff = try await APIClient.shared.send(Endpoint(path: "owner/shops/\(shopId)/staff", method: .post, body: body))
            newStaff = NewStaffForm()
            message = "Staff added."
            await loadStaff()
        } catch let error as APIError {
            newStaff.saving = false
            newStaff.error = error.userMessage
        } catch {
            newStaff.saving = false
            newStaff.error = APIError.unknown.userMessage
        }
    }

    func deleteStaff(_ s: OwnerStaff) async {
        do {
            try await APIClient.shared.sendNoContent(Endpoint(path: "owner/shops/\(shopId)/staff/\(s.id)", method: .delete))
            message = "\(s.email) removed."
            await loadStaff()
        } catch let error as APIError {
            message = error.userMessage
        } catch {
            message = APIError.unknown.userMessage
        }
    }

    // Deliberately not implemented, to stay at parity rather than ahead of it:
    // the backend also exposes PATCH /owner/shops/{id} and
    // POST /owner/shops/{id}/staff/{id}/reset-password, and Android wraps both
    // in OwnerRepository — but nothing in Android's UI calls either, so they
    // are dead plumbing there rather than features an owner can reach.

    func dismissMessage() { message = nil }
}
