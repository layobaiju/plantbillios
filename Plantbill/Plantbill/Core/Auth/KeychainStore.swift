import Foundation
import Security

/// JWT storage in the iOS Keychain. The Security framework's SecItem* calls
/// are synchronous — every call here is routed through `Task.detached` so
/// it never runs on the caller's actor (almost always @MainActor, since
/// APIClient is driven from MainActor view models). Skipping that would
/// block the main thread on every single network call while it reads the
/// token, which is exactly the ANR-style bug Android hit with its Keystore
/// access before its "lazy Keystore" fix — same failure mode, different
/// platform API.
enum KeychainStore {
    private nonisolated static let service = "com.dofida.Plantbill"
    private nonisolated static let account = "jwt"
    /// The signed-in user, cached beside the token so the app can open and
    /// route itself with no network. Mirrors Android's `SavedAccount`. No
    /// password is ever stored — only the bearer token and the identity.
    private nonisolated static let userAccount = "current_user"

    static func saveToken(_ token: String) async {
        await Task.detached(priority: .userInitiated) { save(Data(token.utf8), account) }.value
    }

    static func loadToken() async -> String? {
        await Task.detached(priority: .userInitiated) {
            load(account).flatMap { String(data: $0, encoding: .utf8) }
        }.value
    }

    static func deleteToken() async {
        await Task.detached(priority: .userInitiated) { delete(account) }.value
    }

    static func saveUser(_ user: CurrentUser) async {
        guard let data = try? JSONEncoder().encode(user) else { return }
        await Task.detached(priority: .userInitiated) { save(data, userAccount) }.value
    }

    /// The last known identity, for opening the app offline.
    static func loadUser() async -> CurrentUser? {
        await Task.detached(priority: .userInitiated) {
            load(userAccount).flatMap { try? JSONDecoder().decode(CurrentUser.self, from: $0) }
        }.value
    }

    /// Full sign-out: token and cached identity together, so a logged-out
    /// device can't be routed from a stale identity.
    static func clear() async {
        await Task.detached(priority: .userInitiated) {
            delete(account)
            delete(userAccount)
        }.value
    }

    // Explicitly `nonisolated` — the project defaults every declaration to
    // @MainActor, which would otherwise pin these back onto the main actor
    // and defeat the whole point of running them inside `Task.detached`.
    private nonisolated static func save(_ data: Data, _ account: String) {
        var query = baseQuery(account)
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let attributesToUpdate = [kSecValueData as String: data]
            SecItemUpdate(baseQuery(account) as CFDictionary, attributesToUpdate as CFDictionary)
        }
    }

    private nonisolated static func load(_ account: String) -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private nonisolated static func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private nonisolated static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
