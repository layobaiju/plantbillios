import Foundation

/// Overridable API base URL, mirroring Android's AppPreferences/BaseUrlProvider
/// pattern. Exposed later in Settings; defaults to production.
enum BaseURLStore {
    private static let key = "base_url"

    /// Debug builds talk to a backend on the developer's own machine
    /// (`localhost` resolves to the host Mac from the simulator); Release
    /// always ships pointing at production. A value stored under `key` still
    /// wins over both, so this only changes the *default*.
    #if DEBUG
    static let defaultURL = "http://localhost:8000/"
    #else
    static let defaultURL = "https://api.plantbill.in/"
    #endif

    static var current: URL {
        let stored = UserDefaults.standard.string(forKey: key) ?? defaultURL
        return URL(string: stored) ?? URL(string: defaultURL)!
    }

    static func set(_ urlString: String) {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { trimmed = defaultURL }
        if !trimmed.hasSuffix("/") { trimmed += "/" }
        UserDefaults.standard.set(trimmed, forKey: key)
    }
}
