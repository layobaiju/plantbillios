import Foundation

/// POST /auth/login response.
struct TokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
}

/// GET /auth/me response.
///
/// Encodable as well as Decodable so it can be cached next to the token: the
/// app has to be able to open and route itself with no network, exactly like
/// Android's `SavedAccount` in TokenStore.
struct CurrentUser: Codable, Equatable {
    let id: UUID
    let email: String
    let role: Role
    let shopId: UUID?
    let isActive: Bool
    let shopName: String?
    let businessName: String?
    let businessUpi: String?

    static func == (lhs: CurrentUser, rhs: CurrentUser) -> Bool {
        lhs.id == rhs.id && lhs.role == rhs.role
    }
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}
