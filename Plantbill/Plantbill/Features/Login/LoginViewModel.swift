import Combine
import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published private(set) var isSubmitting: Bool = false
    @Published private(set) var errorMessage: String?

    var canSubmit: Bool {
        !isSubmitting
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    func submit(session: AuthSession) async {
        guard canSubmit else { return }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check the shape here rather than round-tripping to the server: a 422
        // comes back as Pydantic's own wording ("the part after the @-sign is a
        // special-use or reserved name…"), which is meaningless to a shop
        // owner and breaks the plain-language rule the rest of the app follows.
        guard Self.looksLikeEmail(trimmedEmail) else {
            errorMessage = "That email doesn't look right. Check it and try again."
            return
        }

        isSubmitting = true
        errorMessage = nil

        do {
            try await session.login(email: trimmedEmail, password: trimmedPassword)
        } catch let error as APIError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = APIError.unknown.userMessage
        }
        isSubmitting = false
    }

    /// Deliberately permissive — just enough to catch a typo before it becomes
    /// a server-worded 422. The server remains the authority on whether the
    /// account exists.
    private static func looksLikeEmail(_ value: String) -> Bool {
        guard !value.contains(" "), value.count >= 5 else { return false }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix(".") else { return false }
        return domain.split(separator: ".").allSatisfy { !$0.isEmpty }
    }
}
