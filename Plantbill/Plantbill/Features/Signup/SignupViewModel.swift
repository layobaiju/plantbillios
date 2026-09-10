import Combine
import Foundation

@MainActor
final class SignupViewModel: ObservableObject {
    @Published var shopName: String = ""
    @Published var ownerName: String = ""
    @Published var ownerPhone: String = ""
    @Published var email: String = ""
    @Published var password: String = ""

    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?

    /// The server enforces this too; checking here is what lets the button
    /// stay disabled instead of letting the owner tap Start and be told no.
    static let minimumPasswordLength = 8

    var canSubmit: Bool {
        !isSubmitting
            && !shopName.trimmed.isEmpty
            && !email.trimmed.isEmpty
            && password.count >= Self.minimumPasswordLength
    }

    /// Shown under the password field as it's typed, so the requirement is
    /// visible before the button is reached rather than after it's pressed.
    var passwordHint: String? {
        guard !password.isEmpty, password.count < Self.minimumPasswordLength else { return nil }
        let needed = Self.minimumPasswordLength - password.count
        return needed == 1
            ? "1 more character needed."
            : "\(needed) more characters needed."
    }

    func submit(session: AuthSession) async {
        guard canSubmit else { return }

        let email = self.email.trimmed
        // Same reason as login: a 422 comes back in Pydantic's wording, which
        // means nothing to a shop owner.
        guard Self.looksLikeEmail(email) else {
            errorMessage = "That email doesn't look right. Check it and try again."
            return
        }

        let phone = ownerPhone.filter(\.isNumber)
        guard phone.isEmpty || phone.count >= 10 else {
            errorMessage = "That phone number looks too short. Enter all 10 digits."
            return
        }

        isSubmitting = true
        errorMessage = nil
        do {
            try await session.signUp(
                shopName: shopName.trimmed,
                email: email,
                password: password,
                ownerName: ownerName.trimmed.isEmpty ? nil : ownerName.trimmed,
                ownerPhone: phone.isEmpty ? nil : phone
            )
            // On success the session flips to .authenticated and RootView
            // replaces this screen, so there's nothing to reset here.
        } catch let error as APIError {
            errorMessage = error.userMessage
            isSubmitting = false
        } catch {
            errorMessage = APIError.unknown.userMessage
            isSubmitting = false
        }
    }

    private static func looksLikeEmail(_ value: String) -> Bool {
        guard !value.contains(" "), value.count >= 5 else { return false }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix(".") else { return false }
        return domain.split(separator: ".").allSatisfy { !$0.isEmpty }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
