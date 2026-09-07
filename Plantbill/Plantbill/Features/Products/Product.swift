import Foundation

/// Mirrors backend `ProductOut` (app/schemas/product.py).
///
/// Encodable too, so the catalogue can be cached to disk — a shop with no
/// signal still needs to see its plants and prices to serve a customer.
struct Product: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let category: String?
    let retailPrice: String
    let lastWholesalePrice: String?
    let photoUrl: String?
    let isActive: Bool
    let createdAt: Date

    var price: Money { Money.parse(retailPrice) }
    var resolvedPhotoURL: URL? { MediaURL.resolve(photoUrl) }
}
