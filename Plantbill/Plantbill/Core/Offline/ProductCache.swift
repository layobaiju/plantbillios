import Foundation

/// The last product catalogue the server returned, kept on disk so the shop
/// can still bill with no signal.
///
/// This is the one thing worth caching for a nursery counter: with the
/// catalogue plus the held-bills store that already exists, a cashier can
/// browse plants, build a cart and park the bill, then save it when the
/// connection returns. Everything else (reports, dues, staff) is management
/// reading that can reasonably wait.
///
/// Deliberately NOT in the Keychain — it is shop data, not a secret, and the
/// catalogue can be large. Stored in Application Support, excluded from
/// backup, and scoped per shop so switching accounts can't show another
/// shop's plants.
enum ProductCache {
    private static let directoryName = "OfflineCache"

    private static func url(for shopId: UUID?) -> URL? {
        guard let shopId else { return nil }
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        var dir = base.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
        }
        return dir.appendingPathComponent("products-\(shopId.uuidString).json")
    }

    /// Only ever called with a full, unfiltered catalogue — caching a search
    /// result would leave the shop offline with a partial list.
    static func save(_ products: [Product], shopId: UUID?) {
        guard let url = url(for: shopId), let data = try? JSONEncoder().encode(products) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load(shopId: UUID?) -> [Product]? {
        guard let url = url(for: shopId),
              let data = try? Data(contentsOf: url),
              let products = try? JSONDecoder().decode([Product].self, from: data)
        else { return nil }
        return products
    }

    static func clear(shopId: UUID?) {
        guard let url = url(for: shopId) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
