import CryptoKit
import Foundation

/// The last good copy of what the server sent for a screen, kept on the phone
/// so Sales and Customers still show something with no signal — "sales till
/// now" rather than an error.
///
/// Stored as the raw JSON the server returned, one file per request, so a
/// screen can opt in without its models having to be Encodable. The file's
/// modification date is when it was saved, which the screen shows ("saved at
/// 3:42 PM") so nobody takes an old total for a live one.
///
/// Scoped to the signed-in account and the server it came from, excluded from
/// backup, and wiped on sign-out: customer names and phone numbers are
/// personal data and must not outlive the session that was allowed to see them.
enum OfflineResponseCache {
    private static let directoryName = "OfflineCache/Responses"

    static func save(_ data: Data, for endpoint: Endpoint) {
        guard endpoint.method == .get, let url = fileURL(for: endpoint, create: true) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func load(for endpoint: Endpoint) -> (data: Data, savedAt: Date)? {
        guard endpoint.method == .get,
              let url = fileURL(for: endpoint, create: false),
              let data = try? Data(contentsOf: url) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let savedAt = attributes?[.modificationDate] as? Date ?? Date()
        return (data, savedAt)
    }

    /// Every saved copy, for every account — called on sign-out.
    static func clearAll() {
        guard let root = rootURL(create: false) else { return }
        try? FileManager.default.removeItem(at: root)
    }

    /// Path plus query, the query sorted so a request lands on the same file
    /// whatever order its parameters were built in.
    static func key(for endpoint: Endpoint) -> String {
        let query = endpoint.queryItems
            .map { "\($0.name)=\($0.value ?? "")" }
            .sorted()
            .joined(separator: "&")
        return "\(endpoint.path)?\(query)"
    }

    private static func rootURL(create: Bool) -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: create
        ) else { return nil }
        var root = base.appendingPathComponent(directoryName, isDirectory: true)
        if create, !FileManager.default.fileExists(atPath: root.path) {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? root.setResourceValues(values)
        }
        return root
    }

    private static func fileURL(for endpoint: Endpoint, create: Bool) -> URL? {
        guard let userId = BusinessProfile.shared.userId, let root = rootURL(create: create) else { return nil }
        // The server is part of the scope too, so a test build pointed at a
        // local backend can never surface its data under the live account.
        let scope = hash("\(BaseURLStore.current.absoluteString)|\(userId.uuidString)")
        let directory = root.appendingPathComponent(scope, isDirectory: true)
        if create, !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent(hash(key(for: endpoint)) + ".json")
    }

    private static func hash(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
