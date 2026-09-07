import Combine
import Foundation

private let pageSize = 20

/// A salesperson and their sales total for the selected day (leaderboard row).
struct StaffSales: Identifiable, Equatable {
    let salesperson: Salesperson
    let sales: Money
    var id: UUID { salesperson.id }
}

/// State for the add/edit expense sheet. `id == nil` → create.
///
/// The backend's expense record only stores ONE payment method (`cash` or
/// `upi` — there's no split field on it, unlike a bill). "Split" is
/// therefore only offered when creating a new expense: on save it becomes
/// TWO separate expense rows (a cash one and a UPI one) whose amounts add up
/// to what was entered — each still valid against the existing schema, and
/// the day summary's cash/UPI expense totals (which sum per-row) come out
/// correct either way. Editing an existing row is always single-method,
/// since it's always one of those two rows.
struct ExpenseEditor: Equatable {
    var id: UUID? = nil
    var amount: String = ""
    /// The chosen category. Required to save — the free-text reason it
    /// replaced is only still read for rows created before categories existed.
    var categoryId: UUID? = nil
    /// Optional remark stored alongside the category.
    var note: String = ""
    /// Legacy free-text reason, kept only so an old expense opened for edit
    /// can still show what it was.
    var reason: String = ""
    /// Inline "Add new category" field — managers only.
    var newCategoryName: String = ""
    var isAddingCategory = false
    /// "cash", "upi", or (create-only) "split".
    var paymentMethod: String = "cash"
    /// The cash portion when `paymentMethod == "split"`; the UPI portion is
    /// the remainder of `amount`.
    var splitCashText: String = ""
    var saving = false
    var error: String? = nil

    var amountMoney: Money { Money.parse(amount) }
    var splitCashMoney: Money { Money.parse(splitCashText) }
    var splitUpiMoney: Money {
        let remainder = amountMoney - splitCashMoney
        return remainder.isNegative ? .zero : remainder
    }

    var canSave: Bool {
        // A category is required to save (the spec's rule); amount must be
        // positive. The old "reason must be non-empty" check is gone with it.
        guard amountMoney.isPositive, categoryId != nil, !saving else {
            return false
        }
        if paymentMethod == "split" {
            return splitCashMoney.isPositive && splitCashMoney <= amountMoney
        }
        return true
    }
}

@MainActor
final class SalesViewModel: ObservableObject {
    enum SummaryState: Equatable {
        case loading
        case loaded(DaySummary)
        case error(String)

        static func == (lhs: SummaryState, rhs: SummaryState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading): return true
            case (.loaded(let a), .loaded(let b)): return a.date == b.date && a.totalSales == b.totalSales
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    let isManager: Bool

    @Published private(set) var selectedDate: Date = ShopCalendar.today()
    @Published private(set) var staff: [Salesperson] = []
    @Published private(set) var staffSales: [StaffSales] = []
    @Published private(set) var selectedStaffId: UUID?

    @Published private(set) var summaryState: SummaryState = .loading
    @Published private(set) var bills: [BillListEntry] = []
    @Published private(set) var billsLoading = true
    @Published private(set) var loadingMore = false
    @Published private(set) var hasMore = false

    @Published var expenseEditor: ExpenseEditor?
    @Published private(set) var expenseCategories: [ExpenseCategory] = []
    @Published var message: String?

    init(isManager: Bool) {
        self.isManager = isManager
    }

    var isToday: Bool { ShopCalendar.isToday(selectedDate) }
    var selectedStaffEmail: String? { staff.first { $0.id == selectedStaffId }?.email }

    func onAppear() async {
        if isManager && staff.isEmpty {
            await loadStaff()
        }
        await load()
    }

    private func loadStaff() async {
        do {
            staff = try await APIClient.shared.send(Endpoint(path: "shop/users"))
        } catch {
            staff = []
        }
    }

    /// Ranks salespeople by their sales for the selected day (fans out one
    /// day-summary request per staff member — small N).
    private func refreshLeaderboard() async {
        guard isManager, !staff.isEmpty else { return }
        let dateString = ShopCalendar.apiDateString(selectedDate)
        var rows: [StaffSales] = []
        for sp in staff {
            let query = [URLQueryItem(name: "date", value: dateString), URLQueryItem(name: "created_by", value: sp.id.uuidString)]
            if let summary: DaySummary = try? await APIClient.shared.send(Endpoint(path: "bills/summary/today", queryItems: query)) {
                rows.append(StaffSales(salesperson: sp, sales: summary.totalSalesMoney))
            }
        }
        staffSales = rows.filter { $0.sales.isPositive }.sorted { $0.sales > $1.sales }
    }

    func load() async {
        summaryState = .loading
        billsLoading = true

        let dateString = ShopCalendar.apiDateString(selectedDate)
        var mutableSummaryQuery = [URLQueryItem(name: "date", value: dateString)]
        if let selectedStaffId { mutableSummaryQuery.append(URLQueryItem(name: "created_by", value: selectedStaffId.uuidString)) }
        let summaryQuery = mutableSummaryQuery

        async let summaryTask: Void = loadSummary(query: summaryQuery)
        async let billsTask: Void = loadBills(dateString: dateString, reset: true)
        async let leaderboardTask: Void = refreshLeaderboard()
        _ = await (summaryTask, billsTask, leaderboardTask)
    }

    private func loadSummary(query: [URLQueryItem]) async {
        do {
            let summary: DaySummary = try await APIClient.shared.send(Endpoint(path: "bills/summary/today", queryItems: query))
            summaryState = .loaded(summary)
        } catch let error as APIError {
            summaryState = .error(error.userMessage)
        } catch {
            summaryState = .error(APIError.unknown.userMessage)
        }
    }

    private func loadBills(dateString: String, reset: Bool) async {
        do {
            var query = [
                URLQueryItem(name: "date_from", value: dateString),
                URLQueryItem(name: "date_to", value: dateString),
                URLQueryItem(name: "limit", value: "\(pageSize)"),
                URLQueryItem(name: "offset", value: "\(reset ? 0 : bills.count)"),
            ]
            if let selectedStaffId { query.append(URLQueryItem(name: "created_by", value: selectedStaffId.uuidString)) }
            let page: BillListPage = try await APIClient.shared.send(Endpoint(path: "bills", queryItems: query))
            bills = reset ? page.items : bills + page.items
            hasMore = page.hasMore
            billsLoading = false
            loadingMore = false
        } catch let error as APIError {
            billsLoading = false
            loadingMore = false
            message = error.userMessage
        } catch {
            billsLoading = false
            loadingMore = false
        }
    }

    func loadMore() async {
        guard !loadingMore, hasMore else { return }
        loadingMore = true
        await loadBills(dateString: ShopCalendar.apiDateString(selectedDate), reset: false)
    }

    func changeDate(_ date: Date) {
        selectedDate = ShopCalendar.calendar.startOfDay(for: date)
        Task { await load() }
    }

    func goToPreviousDay() {
        changeDate(ShopCalendar.calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate)
    }

    func goToNextDay() {
        let next = ShopCalendar.calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        if next <= ShopCalendar.today() { changeDate(next) }
    }

    func selectStaff(_ id: UUID?) {
        selectedStaffId = id
        Task { await load() }
    }

    // MARK: Expense editor

    func openCreateExpense() {
        expenseEditor = ExpenseEditor()
        Task { await loadExpenseCategories() }
    }

    func openEditExpense(_ expense: Expense) {
        expenseEditor = ExpenseEditor(
            id: expense.id,
            amount: expense.amount,
            categoryId: expense.categoryId,
            note: expense.note ?? "",
            reason: expense.reason,
            paymentMethod: expense.paymentMethod
        )
        Task { await loadExpenseCategories() }
    }

    func closeExpenseEditor() { expenseEditor = nil }

    /// The picker's options. Any shop staff can read them; only a manager can
    /// add one.
    func loadExpenseCategories() async {
        guard let list: [ExpenseCategory] = try? await APIClient.shared.send(
            Endpoint(path: "expense-categories")
        ) else { return }
        expenseCategories = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Manager-only "Add new": creates the category, then selects it so the
    /// expense being written can use it immediately.
    func createExpenseCategory() async {
        guard isManager, var editor = expenseEditor else { return }
        let name = editor.newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let body = try APIClient.shared.encode(ExpenseCategoryRequest(name: name))
            let created: ExpenseCategory = try await APIClient.shared.send(
                Endpoint(path: "expense-categories", method: .post, body: body)
            )
            await loadExpenseCategories()
            editor.categoryId = created.id
            editor.newCategoryName = ""
            editor.isAddingCategory = false
            editor.error = nil
            expenseEditor = editor
        } catch let error as APIError {
            // 409 on a duplicate name — surface it rather than failing silently.
            editor.error = error.userMessage
            expenseEditor = editor
        } catch {
            editor.error = APIError.unknown.userMessage
            expenseEditor = editor
        }
    }

    func saveExpense() async {
        guard var editor = expenseEditor, editor.canSave else { return }
        editor.saving = true
        expenseEditor = editor
        let categoryId = editor.categoryId
        let trimmedNote = editor.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let note: String? = trimmedNote.isEmpty ? nil : trimmedNote
        do {
            if editor.id == nil, editor.paymentMethod == "split" {
                // No split field on the backend's expense model — post the
                // cash and UPI portions as two separate rows instead.
                if editor.splitCashMoney.isPositive {
                    let body = try APIClient.shared.encode(ExpenseRequest(amount: editor.splitCashMoney.toWire(), categoryId: categoryId, note: note, paymentMethod: "cash"))
                    let _: Expense = try await APIClient.shared.send(Endpoint(path: "expenses", method: .post, body: body))
                }
                if editor.splitUpiMoney.isPositive {
                    let body = try APIClient.shared.encode(ExpenseRequest(amount: editor.splitUpiMoney.toWire(), categoryId: categoryId, note: note, paymentMethod: "upi"))
                    let _: Expense = try await APIClient.shared.send(Endpoint(path: "expenses", method: .post, body: body))
                }
            } else {
                let body = try APIClient.shared.encode(ExpenseRequest(amount: editor.amountMoney.toWire(), categoryId: categoryId, note: note, paymentMethod: editor.paymentMethod))
                if let id = editor.id {
                    let _: Expense = try await APIClient.shared.send(Endpoint(path: "expenses/\(id)", method: .patch, body: body))
                } else {
                    let _: Expense = try await APIClient.shared.send(Endpoint(path: "expenses", method: .post, body: body))
                }
            }
            expenseEditor = nil
            await load()
        } catch let error as APIError {
            editor.saving = false
            editor.error = error.userMessage
            expenseEditor = editor
        } catch {
            editor.saving = false
            editor.error = APIError.unknown.userMessage
            expenseEditor = editor
        }
    }

    func deleteExpense(_ id: UUID) async {
        do {
            try await APIClient.shared.sendNoContent(Endpoint(path: "expenses/\(id)", method: .delete))
            await load()
        } catch let error as APIError {
            message = error.userMessage
        } catch {
            message = APIError.unknown.userMessage
        }
    }

    func dismissMessage() { message = nil }
}
