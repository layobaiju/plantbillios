import Combine
import Foundation
import Network

/// Tracks whether the app can actually reach the backend, combining two
/// signals exactly as Android's `NetworkMonitor` does:
///
///  - device connectivity (`NWPathMonitor`) — catches "no internet";
///  - request outcomes reported by `APIClient` — catches "online, but the
///    server isn't answering", which a path check alone can't see.
///
/// The shop app is used on patchy rural connections, so this drives a visible
/// banner rather than failing silently mid-sale.
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    /// True when the device has a route AND the server last answered.
    @Published private(set) var isConnected = true
    @Published private(set) var isRechecking = false

    private var deviceOnline = true
    private var serverReachable = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.dofida.Plantbill.network")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.setDeviceOnline(online) }
        }
        monitor.start(queue: queue)
    }

    private func setDeviceOnline(_ online: Bool) {
        deviceOnline = online
        // Coming back onto a network clears a stale "server unreachable" flag,
        // so the banner doesn't stick after signal returns.
        if online { serverReachable = true }
        recompute()
    }

    /// Called by APIClient after every request.
    func reportSuccess() {
        serverReachable = true
        recompute()
    }

    func reportFailure() {
        serverReachable = false
        recompute()
    }

    private func recompute() {
        isConnected = deviceOnline && serverReachable
    }

    /// Actively re-check, behind the banner's "Try again". Hits the backend's
    /// own health endpoint rather than a generic host, since what matters is
    /// whether *this* server answers.
    func recheck() async {
        isRechecking = true
        defer { isRechecking = false }

        guard monitor.currentPath.status == .satisfied else {
            deviceOnline = false
            recompute()
            return
        }
        deviceOnline = true

        var request = URLRequest(url: BaseURLStore.current.appendingPathComponent("health"))
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let (_, response) = try? await URLSession.shared.data(for: request),
           let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
            serverReachable = true
        } else {
            serverReachable = false
        }
        recompute()
    }
}
