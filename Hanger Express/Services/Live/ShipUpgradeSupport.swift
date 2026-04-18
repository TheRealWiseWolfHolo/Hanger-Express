import Foundation

struct ShipUpgradePath: Hashable, Sendable {
    let sourceShipName: String
    let targetShipName: String
}

enum UpgradeTitleParser {
    static func parse(_ rawTitle: String) -> ShipUpgradePath? {
        let cleaned = sanitizeTitle(rawTitle)

        guard let separatorRange = cleaned.range(
            of: " to ",
            options: [.caseInsensitive, .diacriticInsensitive]
        ) else {
            return nil
        }

        let source = cleanShipSegment(String(cleaned[..<separatorRange.lowerBound]))
        let target = cleanShipSegment(String(cleaned[separatorRange.upperBound...]))

        guard !source.isEmpty, !target.isEmpty else {
            return nil
        }

        return ShipUpgradePath(sourceShipName: source, targetShipName: target)
    }

    static func normalizedShipKey(_ rawName: String) -> String {
        let lowercase = stripManufacturerPrefix(from: rawName)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let sanitizedScalars = lowercase.unicodeScalars.map { scalar -> String in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : " "
        }

        return sanitizedScalars
            .joined()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func stripManufacturerPrefix(from rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)

        for manufacturer in manufacturerPrefixes {
            if trimmed.range(of: manufacturer + " ", options: [.anchored, .caseInsensitive]) != nil {
                return String(trimmed.dropFirst(manufacturer.count + 1))
            }
        }

        return trimmed
    }

    private static func sanitizeTitle(_ rawTitle: String) -> String {
        rawTitle
            .replacingOccurrences(of: "→", with: " to ")
            .replacingOccurrences(of: "->", with: " to ")
            .replacingOccurrences(
                of: #"(?i)\b(ship\s+upgrade|upgrade|ccu)\b"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"^[\s\-\:\|]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanShipSegment(_ segment: String) -> String {
        segment
            .replacingOccurrences(of: #"^[\s\-\:\|]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\s\-\:\|]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let manufacturerPrefixes = [
        "Aegis",
        "Anvil",
        "ARGO",
        "Banu",
        "Consolidated Outland",
        "Crusader",
        "Drake",
        "Esperia",
        "Gatac",
        "Greycat",
        "Kruger",
        "MISC",
        "Mirai",
        "Origin",
        "RSI",
        "Tumbril"
    ]
}

struct RSIShipCatalog: Sendable {
    struct Ship: Hashable, Sendable {
        let id: Int
        let name: String
        let msrpUSD: Decimal?
        let imageURL: URL?
    }

    let ships: [Ship]

    private let shipsByKey: [String: Ship]

    init(ships: [Ship]) {
        self.ships = ships

        var keyedShips: [String: Ship] = [:]
        for ship in ships {
            let directKey = UpgradeTitleParser.normalizedShipKey(ship.name)
            keyedShips[directKey] = keyedShips[directKey] ?? ship

            let strippedKey = UpgradeTitleParser.normalizedShipKey(
                UpgradeTitleParser.stripManufacturerPrefix(from: ship.name)
            )
            keyedShips[strippedKey] = keyedShips[strippedKey] ?? ship
        }

        shipsByKey = keyedShips
    }

    func matchShip(named rawName: String) -> Ship? {
        let directKey = UpgradeTitleParser.normalizedShipKey(rawName)
        if let directMatch = shipsByKey[directKey] {
            return directMatch
        }

        let strippedKey = UpgradeTitleParser.normalizedShipKey(
            UpgradeTitleParser.stripManufacturerPrefix(from: rawName)
        )
        return shipsByKey[strippedKey]
    }
}
