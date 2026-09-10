import Combine
import Foundation

@MainActor
final class CustomerDetailViewModel: ObservableObject {
    let customerId: UUID

    @Published private(set) var isLoading = true
    @Published private(set) var loadError: String?
    /// The customer's name, taken from the first bill that recorded one —
    /// nil when no bill has it (UI shows a fallback).
    @Published private(set) var name: String?
    @Published private(set) var bills: [BillListEntry] = []
    /// Set when these bills are the copy saved on this phone.
    @Published private(set) var savedAt: Date?

    init(customerId: UUID) {
        self.customerId = customerId
    }

    var totalSpent: Money { bills.reduce(Money.zero) { $0 + $1.totalMoney } }
    var creditBillCount: Int { bills.filter { $0.paymentMethod == .due }.count }

    func load() async {
        isLoading = bills.isEmpty
        loadError = nil
        do {
            let query = [
                URLQueryItem(name: "customer_id", value: customerId.uuidString),
                URLQueryItem(name: "limit", value: "100"),
            ]
            let result: Cached<BillListPage> = try await APIClient.shared.sendCached(Endpoint(path: "bills", queryItems: query))
            bills = result.value.items
            name = result.value.items.first { $0.customerName?.isEmpty == false }?.customerName
            savedAt = result.savedAt
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            loadError = error.userMessage
        } catch {
            isLoading = false
            loadError = APIError.unknown.userMessage
        }
    }
}
