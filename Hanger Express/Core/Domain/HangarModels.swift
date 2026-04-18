import Foundation

nonisolated struct UserSession: Hashable, Sendable, Codable {
    enum AuthMode: String, Hashable, Sendable, Codable {
        case rsiNativeLogin = "RSI GraphQL login"
        case importedCookies = "Imported cookies"
        case developerPreview = "Preview data"

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)

            self = AuthMode(rawValue: rawValue) ?? .rsiNativeLogin
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    let handle: String
    let displayName: String
    let email: String
    let authMode: AuthMode
    let notes: String
    let credentials: AccountCredentials?
    let cookies: [SessionCookie]
    let createdAt: Date

    var hasStoredCredentials: Bool {
        credentials != nil
    }

    static let preview = UserSession(
        handle: "WiseWolfHolo",
        displayName: "WiseWolfHolo",
        email: "preview@hangerexpress.invalid",
        authMode: .developerPreview,
        notes: "Uses local sample data while the live RSI integration is being built.",
        credentials: nil,
        cookies: [],
        createdAt: .now
    )

    init(
        handle: String,
        displayName: String,
        email: String,
        authMode: AuthMode,
        notes: String,
        credentials: AccountCredentials?,
        cookies: [SessionCookie],
        createdAt: Date
    ) {
        self.handle = handle
        self.displayName = displayName
        self.email = email
        self.authMode = authMode
        self.notes = notes
        self.credentials = credentials
        self.cookies = cookies
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case handle
        case displayName
        case email
        case authMode
        case notes
        case credentials
        case cookies
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        handle = try container.decode(String.self, forKey: .handle)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? handle
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        authMode = try container.decodeIfPresent(AuthMode.self, forKey: .authMode) ?? .rsiNativeLogin
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        credentials = try container.decodeIfPresent(AccountCredentials.self, forKey: .credentials)
        cookies = try container.decodeIfPresent([SessionCookie].self, forKey: .cookies) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }
}

nonisolated struct AccountCredentials: Hashable, Sendable, Codable {
    let loginIdentifier: String
    let password: String

    private enum CodingKeys: String, CodingKey {
        case loginIdentifier
        case password
    }

    init(loginIdentifier: String, password: String) {
        self.loginIdentifier = loginIdentifier
        self.password = password
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        loginIdentifier = try container.decode(String.self, forKey: .loginIdentifier)
        password = try container.decode(String.self, forKey: .password)
    }
}

nonisolated struct SessionCookie: Hashable, Sendable, Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresAt: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool
    let version: Int

    init(_ cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expiresAt = cookie.expiresDate
        isSecure = cookie.isSecure
        isHTTPOnly = cookie.isHTTPOnly
        version = cookie.version
    }

    var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path
        ]

        if let expiresAt {
            properties[.expires] = expiresAt
        }

        if isSecure {
            properties[.secure] = "TRUE"
        }

        if isHTTPOnly {
            properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        }

        properties[.version] = version
        return HTTPCookie(properties: properties)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case value
        case domain
        case path
        case expiresAt
        case isSecure
        case isHTTPOnly
        case version
    }

    init(
        name: String,
        value: String,
        domain: String,
        path: String,
        expiresAt: Date?,
        isSecure: Bool,
        isHTTPOnly: Bool,
        version: Int
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expiresAt = expiresAt
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
        self.version = version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        name = try container.decode(String.self, forKey: .name)
        value = try container.decode(String.self, forKey: .value)
        domain = try container.decode(String.self, forKey: .domain)
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? "/"
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        isSecure = try container.decodeIfPresent(Bool.self, forKey: .isSecure) ?? true
        isHTTPOnly = try container.decodeIfPresent(Bool.self, forKey: .isHTTPOnly) ?? true
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
    }
}

enum TrustedDeviceDuration: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case session
    case day
    case week
    case month
    case year

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .session:
            return "This session"
        case .day:
            return "1 day"
        case .week:
            return "1 week"
        case .month:
            return "1 month"
        case .year:
            return "1 year"
        }
    }
}

struct HangarSnapshot: Hashable, Sendable {
    let accountHandle: String
    let lastSyncedAt: Date
    let packages: [HangarPackage]
    let fleet: [FleetShip]
    let buyback: [BuybackPledge]

    var metrics: HangarMetrics {
        HangarMetrics(
            packageCount: packages.count,
            shipCount: fleet.count,
            giftableCount: packages.filter(\.canGift).count,
            reclaimableCount: packages.filter(\.canReclaim).count,
            totalOriginalValue: packages.reduce(into: Decimal.zero) { partialResult, package in
                partialResult += package.originalValueUSD
            },
            totalCurrentValue: packages.reduce(into: Decimal.zero) { partialResult, package in
                partialResult += package.currentValueUSD
            }
        )
    }
}

struct HangarMetrics: Hashable, Sendable {
    let packageCount: Int
    let shipCount: Int
    let giftableCount: Int
    let reclaimableCount: Int
    let totalOriginalValue: Decimal
    let totalCurrentValue: Decimal
}

struct HangarPackage: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let status: String
    let insurance: String
    let acquiredAt: Date
    let originalValueUSD: Decimal
    let currentValueUSD: Decimal
    let canGift: Bool
    let canReclaim: Bool
    let canUpgrade: Bool
    let contents: [PackageItem]

    var thumbnailURL: URL? {
        contents.compactMap(\.imageURL).first
    }
}

struct PackageItem: Identifiable, Hashable, Sendable {
    enum Category: String, Hashable, Sendable {
        case ship = "Ship"
        case vehicle = "Vehicle"
        case gamePackage = "Game Package"
        case flair = "Flair"
        case upgrade = "Upgrade"
        case perk = "Perk"
    }

    struct UpgradePricing: Hashable, Sendable {
        let sourceShipName: String
        let sourceShipMSRPUSD: Decimal?
        let targetShipName: String
        let targetShipMSRPUSD: Decimal?
        let actualValueUSD: Decimal?
        let meltValueUSD: Decimal?
    }

    let id: String
    let title: String
    let detail: String
    let category: Category
    let imageURL: URL?
    let upgradePricing: UpgradePricing?
}

struct FleetShip: Identifiable, Hashable, Sendable {
    let id: Int
    let displayName: String
    let manufacturer: String
    let role: String
    let insurance: String
    let sourcePackageID: Int
    let sourcePackageName: String
    let meltValueUSD: Decimal
    let canGift: Bool
    let canReclaim: Bool
}

struct BuybackPledge: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let recoveredValueUSD: Decimal
    let addedToBuybackAt: Date
    let notes: String
}
