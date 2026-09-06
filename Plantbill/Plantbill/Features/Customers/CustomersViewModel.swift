import Combine
import Foundation

@MainActor
final class CustomersViewModel: ObservableObject {
    enum State {
        case loading
        case loaded([Customer])
        case error(String)
    }

    @Published private(set) var state: State = .loading
    @Published var query: String = ""

    var visible: [Customer] {
        guard case .loaded(let customers) = state else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return customers }
        return customers.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) || ($0.phone?.contains(trimmed) ?? false)
        }
    }

    func load() async {
        state = .loading
        do {
            let customers: [Customer] = try await APIClient.shared.send(Endpoint(path: "customers"))
            state = .loaded(customers)
        } catch let error as APIError {
            state = .error(error.userMessage)
        } catch {
            state = .error(APIError.unknown.userMessage)
        }
    }
}
