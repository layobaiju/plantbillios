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
    /// Set when the list is the copy saved on this phone (no internet, or the
    /// server failing) rather than a fresh one.
    @Published private(set) var savedAt: Date?

    var visible: [Customer] {
        guard case .loaded(let customers) = state else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return customers }
        return customers.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) || ($0.phone?.contains(trimmed) ?? false)
        }
    }

    func load() async {
        // A refresh keeps the current list on screen instead of blanking it.
        if case .loaded = state {} else { state = .loading }
        do {
            let result: Cached<[Customer]> = try await APIClient.shared.sendCached(Endpoint(path: "customers"))
            state = .loaded(result.value)
            savedAt = result.savedAt
        } catch let error as APIError {
            state = .error(error.userMessage)
        } catch {
            state = .error(APIError.unknown.userMessage)
        }
    }
}
