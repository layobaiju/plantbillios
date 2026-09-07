import Foundation

/// Mirrors backend `CustomerOut` (app/schemas/customer.py).
struct Customer: Decodable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let phone: String?
    let whatsappEligible: Bool
    let createdAt: Date
}

/// Mirrors backend `CustomerLookupOut` — `GET /customers/lookup?phone=`.
/// `visitCount` is scoped to the signed-in shop by RLS, so a number seen only
/// at another shop comes back with `found == false`.
struct CustomerLookup: Decodable, Equatable {
    let found: Bool
    let name: String?
    let visitCount: Int
}
