import Foundation

/// Overridable API base URL, mirroring Android's AppPreferences/BaseUrlProvider
/// pattern. Exposed later in Settings; defaults to production.
enum BaseURLStore {
    private static let key = "base_url"

    /// Debug builds talk to a backend on the developer's own machine; Release
    /// always ships pointing at production. A value stored under `key` still
    /// wins over both, so this only changes the *default*.
    ///
    /// The simulator shares the Mac's network stack, so `localhost` reaches it
    /// directly. A real device does not — there, `localhost` is the phone
    /// itself, so it needs the Mac's LAN address and both must be on the same
    /// Wi-Fi. Plain HTTP to that address is allowed by `NSAllowsLocalNetworking`
    /// in Info.plist.
    ///
    /// `devMachineHost` is the one line to change when the Mac's IP moves
    /// (`ipconfig getifaddr en0`).
    #if DEBUG
    private static let devMachineHost = "192.168.1.6"

    static var defaultURL: String {
        #if targetEnvironment(simulator)
        return "http://localhost:8000/"
        #else
        return "http://\(devMachineHost):8000/"
        #endif
    }
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
