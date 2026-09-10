import Combine
import Foundation

enum AuthState: Equatable {
    case loading
    case unauthenticated
    /// Role is admin or otherwise not supported by this app (parity with
    /// Android's UnsupportedRoleScreen — admin uses the web app instead).
    case unsupportedRole
    case authenticated(CurrentUser)
}

/// Root session/auth state for the app. Mirrors Android's SessionRepository:
/// bootstraps from a stored token on launch, and a 401 from anywhere forces
/// a global logout back to the login screen.
@MainActor
final class AuthSession: ObservableObject {
    @Published private(set) var state: AuthState = .loading

    private let apiClient = APIClient.shared

    init() {
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .apiUnauthorized) {
                self?.logout()
            }
        }
    }

    /// Opening the app must work with no network. Only a token the server
    /// actively rejects ends the session — an unreachable server does not,
    /// or a shop with patchy signal would be locked out of its own till and
    /// unable to sign back in. Mirrors Android's SessionRepository, which
    /// restores optimistically from the cached identity for the same reason.
    func bootstrap() async {
        guard await KeychainStore.loadToken() != nil else {
            state = .unauthenticated
            return
        }
        do {
            let user: CurrentUser = try await apiClient.send(Endpoint(path: "auth/me"))
            await KeychainStore.saveUser(user)
            state = resolvedState(for: user)
        } catch APIError.sessionExpired {
            // The token really is dead — this is the one case that signs out.
            await KeychainStore.clear()
            state = .unauthenticated
        } catch {
            // Offline, 5xx, timeout: keep the session and route from the last
            // known identity so the app stays usable.
            if let cached = await KeychainStore.loadUser() {
                state = resolvedState(for: cached)
            } else {
                // Token but no cached identity (upgraded from an older build):
                // nothing to route from, so ask for a sign-in.
                state = .unauthenticated
            }
        }
    }

    /// Creates a shop and signs straight into it — no "now go and log in"
    /// step, because the server hands back a token with the 201 and asking a
    /// shop owner to re-type the password they just chose is a place to lose
    /// them.
    func signUp(
        shopName: String,
        email: String,
        password: String,
        ownerName: String?,
        ownerPhone: String?
    ) async throws {
        let body = try apiClient.encode(
            SignupRequest(
                shopName: shopName,
                email: email,
                password: password,
                ownerName: ownerName,
                ownerPhone: ownerPhone
            )
        )
        let token: TokenResponse = try await apiClient.send(
            Endpoint(path: "auth/signup", method: .post, body: body, requiresAuth: false)
        )
        await KeychainStore.saveToken(token.accessToken)

        let user: CurrentUser = try await apiClient.send(Endpoint(path: "auth/me"))
        await KeychainStore.saveUser(user)
        state = resolvedState(for: user)
    }

    /// In-app account deletion, required by App Store guideline 5.1.1(v) once
    /// an app lets people create an account. Deletes the workspace and
    /// everything in it, server-side, then drops the session.
    ///
    /// The server refuses this (403) for a shop the admin set up, so the UI
    /// only offers it where it will actually work.
    func deleteAccount() async throws {
        try await apiClient.sendNoContent(
            Endpoint(path: "auth/me", method: .delete)
        )
        logout()
    }

    func login(email: String, password: String) async throws {
        let body = try apiClient.encode(LoginRequest(email: email, password: password))
        let token: TokenResponse = try await apiClient.send(
            Endpoint(path: "auth/login", method: .post, body: body, requiresAuth: false)
        )
        await KeychainStore.saveToken(token.accessToken)

        let user: CurrentUser = try await apiClient.send(Endpoint(path: "auth/me"))
        await KeychainStore.saveUser(user)
        state = resolvedState(for: user)
    }

    /// Synchronous on purpose — flips the UI back to the login screen
    /// instantly, without waiting on the Keychain delete, which happens in
    /// the background.
    func logout() {
        state = .unauthenticated
        BusinessProfile.shared.clear()
        TrialStore.shared.clear()
        // Clears the cached identity too, so a signed-out device can't be
        // routed back in from a stale one.
        Task { await KeychainStore.clear() }
    }

    private func resolvedState(for user: CurrentUser) -> AuthState {
        guard user.isActive, user.role.usesMainShell || user.role.usesOwnerShell else {
            return .unsupportedRole
        }
        BusinessProfile.shared.update(from: user)
        TrialStore.shared.update(from: user)
        return .authenticated(user)
    }
}
