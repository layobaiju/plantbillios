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

    // --- Free trial ---------------------------------------------------------
    // Only a shop created through in-app signup has these. Every shop the
    // admin set up reports trialEndsAt = nil / isTrialLocked = false, which is
    // the behaviour the app had before trials existed. Defaulted rather than
    // required so a build of this app still decodes a response from a server
    // that predates the trial fields.
    let trialEndsAt: Date?
    let trialDaysLeft: Int?
    let isTrialLocked: Bool
    let isSubscribed: Bool
    let isSelfSignup: Bool

    init(
        id: UUID,
        email: String,
        role: Role,
        shopId: UUID?,
        isActive: Bool,
        shopName: String?,
        businessName: String?,
        businessUpi: String?,
        trialEndsAt: Date? = nil,
        trialDaysLeft: Int? = nil,
        isTrialLocked: Bool = false,
        isSubscribed: Bool = false,
        isSelfSignup: Bool = false
    ) {
        self.id = id
        self.email = email
        self.role = role
        self.shopId = shopId
        self.isActive = isActive
        self.shopName = shopName
        self.businessName = businessName
        self.businessUpi = businessUpi
        self.trialEndsAt = trialEndsAt
        self.trialDaysLeft = trialDaysLeft
        self.isTrialLocked = isTrialLocked
        self.isSubscribed = isSubscribed
        self.isSelfSignup = isSelfSignup
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        email = try c.decode(String.self, forKey: .email)
        role = try c.decode(Role.self, forKey: .role)
        shopId = try c.decodeIfPresent(UUID.self, forKey: .shopId)
        isActive = try c.decode(Bool.self, forKey: .isActive)
        shopName = try c.decodeIfPresent(String.self, forKey: .shopName)
        businessName = try c.decodeIfPresent(String.self, forKey: .businessName)
        businessUpi = try c.decodeIfPresent(String.self, forKey: .businessUpi)
        trialEndsAt = try c.decodeIfPresent(Date.self, forKey: .trialEndsAt)
        trialDaysLeft = try c.decodeIfPresent(Int.self, forKey: .trialDaysLeft)
        isTrialLocked = try c.decodeIfPresent(Bool.self, forKey: .isTrialLocked) ?? false
        isSubscribed = try c.decodeIfPresent(Bool.self, forKey: .isSubscribed) ?? false
        isSelfSignup = try c.decodeIfPresent(Bool.self, forKey: .isSelfSignup) ?? false
    }

    static func == (lhs: CurrentUser, rhs: CurrentUser) -> Bool {
        lhs.id == rhs.id && lhs.role == rhs.role
    }
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

/// POST /auth/signup — creates the shop and its first user together.
struct SignupRequest: Encodable {
    let shopName: String
    let email: String
    let password: String
    let ownerName: String?
    let ownerPhone: String?
}
