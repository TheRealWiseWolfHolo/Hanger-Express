import Foundation
import WebKit

@MainActor
final class LiveHangarRepository: HangarRepository {
    private let browser = RSIAccountPageBrowser()
    private let previewRepository = PreviewHangarRepository()
    private let pledgePageSize = 50
    private let buybackPageSize = 100
    private let maxPages = 20

    func fetchSnapshot(
        for session: UserSession,
        progress: @escaping RefreshProgressHandler
    ) async throws -> HangarSnapshot {
        if session.authMode == .developerPreview {
            return try await previewRepository.fetchSnapshot(for: session, progress: progress)
        }

        guard !session.cookies.isEmpty else {
            throw LiveHangarRepositoryError.sessionUnavailable
        }

        progress(
            RefreshProgress(
                stage: .preparingSession,
                detail: "Restoring \(session.cookies.count) saved RSI cookies.",
                completedUnitCount: 1,
                totalUnitCount: 1
            )
        )

        var remotePledges: [RemotePledge] = []
        var pledgeTotalPages: Int?
        for page in 1 ... maxPages {
            progress(
                RefreshProgress(
                    stage: .pledges,
                    detail: pageDetail(
                        for: "pledges",
                        page: page,
                        totalPages: pledgeTotalPages,
                        loadedCount: remotePledges.count,
                        isLoading: true
                    ),
                    completedUnitCount: max(page - 1, 0),
                    totalUnitCount: pledgeTotalPages
                )
            )

            let result = try await browser.extractPledges(
                using: session.cookies,
                page: page,
                pageSize: pledgePageSize
            )

            if result.accessDenied {
                throw LiveHangarRepositoryError.sessionExpired
            }

            remotePledges.append(contentsOf: result.items)

            pledgeTotalPages = mergedTotalPages(
                known: pledgeTotalPages,
                discovered: inferredTotalPages(
                    reportedByPage: result.totalPages,
                    page: page,
                    pageItemCount: result.items.count,
                    pageSize: pledgePageSize
                )
            )

            progress(
                RefreshProgress(
                    stage: .pledges,
                    detail: pageDetail(
                        for: "pledges",
                        page: page,
                        totalPages: pledgeTotalPages,
                        loadedCount: remotePledges.count,
                        isLoading: false
                    ),
                    completedUnitCount: page,
                    totalUnitCount: pledgeTotalPages
                )
            )

            if shouldStopFetching(
                after: page,
                pageItemCount: result.items.count,
                knownTotalPages: pledgeTotalPages,
                pageSize: pledgePageSize
            ) {
                break
            }
        }

        var remoteBuyback: [RemoteBuybackPledge] = []
        var buybackTotalPages: Int?
        for page in 1 ... maxPages {
            progress(
                RefreshProgress(
                    stage: .buyback,
                    detail: pageDetail(
                        for: "buy-back items",
                        page: page,
                        totalPages: buybackTotalPages,
                        loadedCount: remoteBuyback.count,
                        isLoading: true
                    ),
                    completedUnitCount: max(page - 1, 0),
                    totalUnitCount: buybackTotalPages
                )
            )

            let result = try await browser.extractBuybackPledges(
                using: session.cookies,
                page: page,
                pageSize: buybackPageSize
            )

            if result.accessDenied {
                throw LiveHangarRepositoryError.sessionExpired
            }

            remoteBuyback.append(contentsOf: result.items)

            buybackTotalPages = mergedTotalPages(
                known: buybackTotalPages,
                discovered: inferredTotalPages(
                    reportedByPage: result.totalPages,
                    page: page,
                    pageItemCount: result.items.count,
                    pageSize: buybackPageSize
                )
            )

            progress(
                RefreshProgress(
                    stage: .buyback,
                    detail: pageDetail(
                        for: "buy-back items",
                        page: page,
                        totalPages: buybackTotalPages,
                        loadedCount: remoteBuyback.count,
                        isLoading: false
                    ),
                    completedUnitCount: page,
                    totalUnitCount: buybackTotalPages
                )
            )

            if shouldStopFetching(
                after: page,
                pageItemCount: result.items.count,
                knownTotalPages: buybackTotalPages,
                pageSize: buybackPageSize
            ) {
                break
            }
        }

        progress(
            RefreshProgress(
                stage: .finalizing,
                detail: "Loading RSI store ship MSRP and media data for upgrade valuation.",
                completedUnitCount: 0,
                totalUnitCount: 2
            )
        )

        let shipCatalog: RSIShipCatalog?
        do {
            shipCatalog = try await browser.fetchShipCatalog(using: session.cookies)
        } catch {
            shipCatalog = nil
        }

        progress(
            RefreshProgress(
                stage: .finalizing,
                detail: shipCatalog == nil
                    ? "RSI store valuation data was unavailable. Continuing with hangar media only."
                    : "Loaded \(shipCatalog?.ships.count ?? 0) RSI store ships for image and MSRP enrichment.",
                completedUnitCount: 1,
                totalUnitCount: 2
            )
        )

        let packages = remotePledges.map { normalize(package: $0, shipCatalog: shipCatalog) }
        let fleet = projectFleet(from: packages)
        let buyback = remoteBuyback.map(normalize(buyback:))

        progress(
            RefreshProgress(
                stage: .finalizing,
                detail: "Organized \(remotePledges.count) pledges and \(remoteBuyback.count) buy-back items.",
                completedUnitCount: 2,
                totalUnitCount: 2
            )
        )

        return HangarSnapshot(
            accountHandle: session.handle,
            lastSyncedAt: .now,
            packages: packages,
            fleet: fleet,
            buyback: buyback
        )
    }

    private func inferredTotalPages(
        reportedByPage: Int?,
        page: Int,
        pageItemCount: Int,
        pageSize: Int
    ) -> Int? {
        if let reportedByPage, reportedByPage > 0 {
            return reportedByPage
        }

        if pageItemCount < pageSize {
            return page
        }

        return nil
    }

    private func mergedTotalPages(known: Int?, discovered: Int?) -> Int? {
        switch (known, discovered) {
        case let (known?, discovered?):
            return max(known, discovered)
        case let (known?, nil):
            return known
        case let (nil, discovered?):
            return discovered
        case (nil, nil):
            return nil
        }
    }

    private func shouldStopFetching(
        after page: Int,
        pageItemCount: Int,
        knownTotalPages: Int?,
        pageSize: Int
    ) -> Bool {
        if let knownTotalPages, page >= knownTotalPages {
            return true
        }

        return pageItemCount < pageSize
    }

    private func pageDetail(
        for itemLabel: String,
        page: Int,
        totalPages: Int?,
        loadedCount: Int,
        isLoading: Bool
    ) -> String {
        let pageLabel: String
        if let totalPages, totalPages > 0 {
            pageLabel = "page \(page) of \(totalPages)"
        } else {
            pageLabel = "page \(page)"
        }

        let countLabel = loadedCount == 1 ? "1 \(itemLabel.dropLast())" : "\(loadedCount) \(itemLabel)"

        if isLoading {
            if loadedCount > 0 {
                return "Loading \(pageLabel). \(countLabel) already synced."
            }

            return "Loading \(pageLabel)."
        }

        return "Finished \(pageLabel). \(countLabel) synced so far."
    }

    private func normalize(package remote: RemotePledge, shipCatalog: RSIShipCatalog?) -> HangarPackage {
        let containsSummary = remote.containsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let packageValueUSD = parseMoney(remote.valueText)
        let contents = normalizeContents(
            for: remote,
            containsSummary: containsSummary,
            packageValueUSD: packageValueUSD,
            shipCatalog: shipCatalog
        )

        return HangarPackage(
            id: remote.id ?? stableNumericID(from: remote.title),
            title: normalizePackageTitle(remote.title),
            status: remote.statusText.nilIfEmpty ?? "Unknown",
            insurance: inferInsurance(from: remote.alsoContains, containsSummary: containsSummary),
            acquiredAt: parseRSIDate(remote.dateText) ?? .now,
            originalValueUSD: packageValueUSD,
            currentValueUSD: packageValueUSD,
            canGift: remote.canGift,
            canReclaim: remote.canReclaim,
            canUpgrade: remote.canUpgrade,
            contents: contents
        )
    }

    private func normalizeContents(
        for remote: RemotePledge,
        containsSummary: String,
        packageValueUSD: Decimal,
        shipCatalog: RSIShipCatalog?
    ) -> [PackageItem] {
        let upgradeMeltValueUSD = inferredUpgradeMeltValue(
            package: remote,
            packageValueUSD: packageValueUSD
        )

        let liveItems = remote.items.enumerated().map { offset, item in
            let itemCategory = category(for: item.kind, title: item.title, detail: item.detail)
            let upgradePath = itemCategory == .upgrade ? UpgradeTitleParser.parse(item.title) : nil
            let sourceShip = upgradePath.flatMap { shipCatalog?.matchShip(named: $0.sourceShipName) }
            let targetShip = upgradePath.flatMap { shipCatalog?.matchShip(named: $0.targetShipName) }

            return PackageItem(
                id: "\(remote.id ?? stableNumericID(from: remote.title))-\(offset)",
                title: item.title.nilIfEmpty ?? "Untitled Item",
                detail: item.detail.nilIfEmpty ?? item.kind.nilIfEmpty ?? "Unknown",
                category: itemCategory,
                imageURL: itemImageURL(
                    for: item,
                    category: itemCategory,
                    shipCatalog: shipCatalog,
                    targetShip: targetShip
                ),
                upgradePricing: upgradePricing(
                    path: upgradePath,
                    sourceShip: sourceShip,
                    targetShip: targetShip,
                    meltValueUSD: upgradeMeltValueUSD
                )
            )
        }

        if !liveItems.isEmpty {
            return liveItems
        }

        guard !containsSummary.isEmpty else {
            return []
        }

        return [
            PackageItem(
                id: "\(remote.id ?? stableNumericID(from: remote.title))-0",
                title: containsSummary,
                detail: "Extracted from the RSI pledge summary",
                category: .perk,
                imageURL: nil,
                upgradePricing: nil
            )
        ]
    }

    private func itemImageURL(
        for item: RemotePledgeItem,
        category: PackageItem.Category,
        shipCatalog: RSIShipCatalog?,
        targetShip: RSIShipCatalog.Ship?
    ) -> URL? {
        if let directURL = item.imageURL.flatMap(URL.init(string:)) {
            return directURL
        }

        switch category {
        case .upgrade:
            return targetShip?.imageURL
        case .ship, .vehicle:
            return shipCatalog?.matchShip(named: item.title)?.imageURL
        case .gamePackage, .flair, .perk:
            return nil
        }
    }

    private func upgradePricing(
        path: ShipUpgradePath?,
        sourceShip: RSIShipCatalog.Ship?,
        targetShip: RSIShipCatalog.Ship?,
        meltValueUSD: Decimal?
    ) -> PackageItem.UpgradePricing? {
        guard let path else {
            return nil
        }

        let actualValueUSD: Decimal?
        if let sourceMSRP = sourceShip?.msrpUSD, let targetMSRP = targetShip?.msrpUSD {
            actualValueUSD = targetMSRP - sourceMSRP
        } else {
            actualValueUSD = nil
        }

        return PackageItem.UpgradePricing(
            sourceShipName: path.sourceShipName,
            sourceShipMSRPUSD: sourceShip?.msrpUSD,
            targetShipName: path.targetShipName,
            targetShipMSRPUSD: targetShip?.msrpUSD,
            actualValueUSD: actualValueUSD,
            meltValueUSD: meltValueUSD
        )
    }

    private func inferredUpgradeMeltValue(package remote: RemotePledge, packageValueUSD: Decimal) -> Decimal? {
        guard packageValueUSD > 0 else {
            return nil
        }

        let upgradeItems = remote.items.filter {
            category(for: $0.kind, title: $0.title, detail: $0.detail) == .upgrade
        }

        guard !upgradeItems.isEmpty else {
            return nil
        }

        let nonUpgradeCategories = remote.items
            .map { category(for: $0.kind, title: $0.title, detail: $0.detail) }
            .filter { $0 != .upgrade && $0 != .perk && $0 != .flair }

        return nonUpgradeCategories.isEmpty ? packageValueUSD : nil
    }

    private func normalize(buyback remote: RemoteBuybackPledge) -> BuybackPledge {
        let title = remote.title.nilIfEmpty ?? "Untitled Buy Back"
        let notes = remote.containsText.nilIfEmpty ?? "Recovered from the RSI buy-back page."

        return BuybackPledge(
            id: remote.id ?? stableNumericID(from: title),
            title: title,
            recoveredValueUSD: parseMoney(remote.valueText),
            addedToBuybackAt: parseRSIDate(remote.dateText) ?? .now,
            notes: notes
        )
    }

    private func projectFleet(from packages: [HangarPackage]) -> [FleetShip] {
        packages.flatMap { package in
            let sourceItems = package.contents.filter { item in
                item.category == .ship || item.category == .vehicle
            }

            return sourceItems.enumerated().map { offset, item in
                let meltValue = sourceItems.count == 1 ? package.originalValueUSD : .zero

                return FleetShip(
                    id: package.id * 100 + offset,
                    displayName: item.title,
                    manufacturer: inferManufacturer(from: item),
                    role: inferRole(from: item),
                    insurance: package.insurance,
                    sourcePackageID: package.id,
                    sourcePackageName: package.title,
                    meltValueUSD: meltValue,
                    canGift: package.canGift,
                    canReclaim: package.canReclaim
                )
            }
        }
    }

    private func normalizePackageTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.localizedCaseInsensitiveContains("contains"),
           trimmed.localizedCaseInsensitiveContains("nameable ship"),
           let prefix = trimmed.components(separatedBy: " Contains ").first {
            return prefix
        }

        return trimmed.isEmpty ? "Untitled Pledge" : trimmed
    }

    private func category(for kind: String, title: String, detail: String) -> PackageItem.Category {
        let haystack = [kind, title, detail]
            .joined(separator: " ")
            .localizedLowercase

        if haystack.contains("upgrade") || title.contains(" to ") {
            return .upgrade
        }

        if haystack.contains("game package") || haystack.contains("digital download") {
            return .gamePackage
        }

        if haystack.contains("vehicle") || haystack.contains("ground vehicle") || haystack.contains("bike") {
            return .vehicle
        }

        if haystack.contains("ship") || haystack.contains("gunboat") || haystack.contains("fighter") || haystack.contains("freighter") {
            return .ship
        }

        if haystack.contains("paint") || haystack.contains("skin") || haystack.contains("hangar") || haystack.contains("flair") {
            return .flair
        }

        if haystack.contains("perk") || haystack.contains("reward") || haystack.contains("token") || haystack.contains("coin") {
            return .perk
        }

        return .perk
    }

    private func inferInsurance(from alsoContains: [String], containsSummary: String) -> String {
        let candidates = alsoContains + containsSummary.components(separatedBy: "#")

        for rawValue in candidates {
            let value = rawValue
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard value.localizedCaseInsensitiveContains("insurance") else {
                continue
            }

            if value.localizedCaseInsensitiveContains("lifetime") {
                return "LTI"
            }

            let lowercased = value.localizedLowercase
            if let months = firstMatch(in: lowercased, pattern: #"(\d+)\s*(month|months|mo)\b"#) {
                return "\(months) months"
            }

            if let years = firstMatch(in: lowercased, pattern: #"(\d+)\s*(year|years|yr)\b"#) {
                return "\(years * 12) months"
            }
        }

        return "Unknown"
    }

    private func inferManufacturer(from item: PackageItem) -> String {
        let candidates = [item.detail, item.title]
        let manufacturers = [
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

        for manufacturer in manufacturers {
            if candidates.contains(where: { $0.localizedCaseInsensitiveContains(manufacturer) }) {
                return manufacturer
            }
        }

        return "Unknown"
    }

    private func inferRole(from item: PackageItem) -> String {
        let detail = item.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty, detail.caseInsensitiveCompare(item.category.rawValue) != .orderedSame {
            return detail
        }

        return item.category.rawValue
    }

    private func parseMoney(_ value: String) -> Decimal {
        let normalized = value
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty, !normalized.localizedCaseInsensitiveContains("uec") else {
            return .zero
        }

        if let direct = Decimal(string: normalized.filter { $0.isNumber || $0 == "." || $0 == "-" }) {
            return direct
        }

        return .zero
    }

    private func parseRSIDate(_ value: String) -> Date? {
        let normalized = value
            .replacingOccurrences(of: "Created:", with: "")
            .replacingOccurrences(of: "Date:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return nil
        }

        for formatter in Self.dateFormatters {
            if let date = formatter.date(from: normalized) {
                return date
            }
        }

        return nil
    }

    private func firstMatch(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return Int(text[captureRange])
    }

    private func stableNumericID(from text: String) -> Int {
        var value = 0
        for scalar in text.unicodeScalars {
            value = (value &* 31 &+ Int(scalar.value)) & 0x7fffffff
        }
        return max(value, 1)
    }

    private static let dateFormatters: [DateFormatter] = {
        let formats = [
            "MMM d, yyyy",
            "MMM dd, yyyy",
            "MMMM d, yyyy",
            "MMMM dd, yyyy",
            "yyyy-MM-dd"
        ]

        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }()
}

private enum LiveHangarRepositoryError: Error, LocalizedError {
    case sessionUnavailable
    case sessionExpired
    case unexpectedMarkup(String)

    var errorDescription: String? {
        switch self {
        case .sessionUnavailable:
            return "No saved RSI session cookies were available for a live hangar refresh."
        case .sessionExpired:
            return "The saved RSI session expired. Sign in again to refresh the live hangar."
        case let .unexpectedMarkup(message):
            return message
        }
    }
}

@MainActor
private final class RSIAccountPageBrowser: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var loadContinuation: CheckedContinuation<Void, Error>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func extractPledges(
        using cookies: [SessionCookie],
        page: Int,
        pageSize: Int
    ) async throws -> RemotePledgePage {
        let url = try pageURL(path: "/en/account/pledges", page: page, pageSize: pageSize)
        try await prepareWebView(with: cookies)
        try await load(url: url)
        return try await evaluate(script: Self.pledgesExtractionScript, as: RemotePledgePage.self)
    }

    func extractBuybackPledges(
        using cookies: [SessionCookie],
        page: Int,
        pageSize: Int
    ) async throws -> RemoteBuybackPage {
        let url = try pageURL(path: "/en/account/buy-back-pledges", page: page, pageSize: pageSize)
        try await prepareWebView(with: cookies)
        try await load(url: url)
        return try await evaluate(script: Self.buybackExtractionScript, as: RemoteBuybackPage.self)
    }

    func fetchShipCatalog(using cookies: [SessionCookie]) async throws -> RSIShipCatalog {
        let url = try storefrontURL(path: "/pledge-store/ship-upgrades")
        try await prepareWebView(with: cookies)
        try await load(url: url)

        let payload = try await evaluate(script: Self.shipCatalogExtractionScript, as: RemoteShipCatalogPayload.self)

        if payload.accessDenied {
            throw LiveHangarRepositoryError.sessionExpired
        }

        guard payload.status == "ok" else {
            throw LiveHangarRepositoryError.unexpectedMarkup(
                payload.failureMessage ?? "RSI store valuation data could not be loaded."
            )
        }

        guard (200 ..< 300).contains(payload.graphQLStatus) else {
            throw LiveHangarRepositoryError.unexpectedMarkup(
                "RSI store catalog returned HTTP \(payload.graphQLStatus)."
            )
        }

        guard payload.errors.isEmpty else {
            throw LiveHangarRepositoryError.unexpectedMarkup(
                "RSI store catalog returned GraphQL errors: \(payload.errors.joined(separator: ", "))."
            )
        }

        return RSIShipCatalog(
            ships: payload.ships.map { ship in
                RSIShipCatalog.Ship(
                    id: ship.id,
                    name: ship.name,
                    msrpUSD: ship.msrpUSD,
                    imageURL: ship.imageURL.flatMap(URL.init(string:))
                )
            }
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    private func prepareWebView(with cookies: [SessionCookie]) async throws {
        try await replaceCookies(cookies)
    }

    private func replaceCookies(_ cookies: [SessionCookie]) async throws {
        let store = webView.configuration.websiteDataStore.httpCookieStore

        let existingCookies = await allCookies(from: store)
        for cookie in existingCookies where cookie.domain.contains("robertsspaceindustries.com") {
            await withCheckedContinuation { continuation in
                store.delete(cookie) {
                    continuation.resume()
                }
            }
        }

        for cookie in cookies {
            guard let httpCookie = cookie.httpCookie else {
                continue
            }

            await withCheckedContinuation { continuation in
                store.setCookie(httpCookie) {
                    continuation.resume()
                }
            }
        }
    }

    private func allCookies(from store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func load(url: URL) async throws {
        if loadContinuation != nil {
            throw LiveHangarRepositoryError.unexpectedMarkup("The RSI page loader is already busy.")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            webView.load(URLRequest(url: url))
        }
    }

    private func evaluate<Value: Decodable>(script: String, as type: Value.Type) async throws -> Value {
        let result = try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )

        guard let result else {
            throw LiveHangarRepositoryError.unexpectedMarkup("RSI returned an empty page payload.")
        }

        let data = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    private func pageURL(path: String, page: Int, pageSize: Int) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "robertsspaceindustries.com"
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pagesize", value: String(pageSize))
        ]

        guard let url = components.url else {
            throw LiveHangarRepositoryError.unexpectedMarkup("Unable to build the RSI page URL.")
        }

        return url
    }

    private func storefrontURL(path: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "robertsspaceindustries.com"
        components.path = path

        guard let url = components.url else {
            throw LiveHangarRepositoryError.unexpectedMarkup("Unable to build the RSI storefront URL.")
        }

        return url
    }

    private static let pledgesExtractionScript = """
    await new Promise(resolve => setTimeout(resolve, 150));

    const firstText = (node, selectors) => {
      for (const selector of selectors) {
        const found = node.querySelector(selector);
        const value = found?.textContent?.trim();
        if (value) {
          return value;
        }
      }
      return "";
    };

    const firstImageURL = (node) => {
      const candidates = [];
      const image = node.querySelector('img, picture img');
      if (image) {
        candidates.push(
          image.currentSrc,
          image.getAttribute('src'),
          image.getAttribute('data-src'),
          image.getAttribute('data-original'),
          image.getAttribute('data-lazy'),
          image.getAttribute('srcset')?.split(',')[0]?.trim()?.split(' ')[0]
        );
      }

      const styledNode = node.querySelector('[style*="background-image"]');
      if (styledNode) {
        const style = styledNode.getAttribute('style') || '';
        const match = style.match(/url\\((['"]?)(.*?)\\1\\)/i);
        if (match?.[2]) {
          candidates.push(match[2]);
        }
      }

      for (const candidate of candidates) {
        if (!candidate) {
          continue;
        }

        try {
          return new URL(candidate, window.location.href).toString();
        } catch {
          continue;
        }
      }

      return "";
    };

    const firstValue = (node, selectors) => {
      for (const selector of selectors) {
        const found = node.querySelector(selector);
        const value = found?.value?.trim() || found?.getAttribute?.('value')?.trim() || found?.getAttribute?.('content')?.trim();
        if (value) {
          return value;
        }
      }
      return "";
    };

    const pageNumbers = Array.from(document.querySelectorAll('a[href*="page="], button[data-page], [data-page]'))
      .map((node) => {
        const candidates = [
          node.getAttribute?.('data-page'),
          node.textContent,
          (() => {
            const href = node.getAttribute?.('href');
            if (!href) {
              return null;
            }
            try {
              return new URL(href, window.location.href).searchParams.get('page');
            } catch {
              return null;
            }
          })()
        ];

        for (const candidate of candidates) {
          const match = String(candidate || '').match(/\\b(\\d+)\\b/);
          if (!match) {
            continue;
          }

          const parsed = Number.parseInt(match[1], 10);
          if (Number.isFinite(parsed) && parsed > 0) {
            return parsed;
          }
        }

        return null;
      })
      .filter((value) => Number.isFinite(value));

    const accessDenied = document.title.toLowerCase().includes('access denied') || document.body.innerText.includes('Access denied');
    const rows = Array.from(document.querySelectorAll('.list-items .row'));

    return {
      accessDenied,
      title: document.title,
      totalPages: pageNumbers.length ? Math.max(...pageNumbers) : null,
      items: rows.map((row) => {
        const titles = Array.from(row.querySelectorAll('.title'))
          .map((node) => node.textContent.trim())
          .filter(Boolean);
        const items = Array.from(row.querySelectorAll('.with-images .item')).map((item) => ({
          title: firstText(item, ['.title']),
          kind: firstText(item, ['.kind']),
          detail: firstText(item, ['.liner', '.subtitle']),
          imageURL: firstImageURL(item)
        }));

        return {
          id: (() => {
            const value = Number.parseInt(firstValue(row, ['.js-pledge-id']), 10);
            return Number.isFinite(value) ? value : null;
          })(),
          title: firstValue(row, ['.js-pledge-name']) || firstText(row, ['h1', 'h2', '.title']),
          statusText: firstText(row, ['.availability', '.status']),
          dateText: firstText(row, ['.date-col', '.date']),
          valueText: firstValue(row, ['.js-pledge-value']) || firstText(row, ['.value', '.price']),
          containsText: firstText(row, ['.items-col', '.contains']),
          alsoContains: titles,
          canGift: row.querySelector('.shadow-button.js-gift, .js-gift') !== null,
          canReclaim: row.querySelector('.shadow-button.js-reclaim, .js-reclaim') !== null,
          canUpgrade: row.querySelector('.shadow-button.js-apply-upgrade, .js-apply-upgrade') !== null,
          items
        };
      })
    };
    """

    private static let shipCatalogExtractionScript = """
    await new Promise(resolve => setTimeout(resolve, 300));

    const hasAccessDeniedMarkup = document.title.toLowerCase().includes('access denied') || document.body.innerText.includes('Access denied');
    if (hasAccessDeniedMarkup) {
      return {
        accessDenied: true,
        status: 'access-denied',
        graphQLStatus: 0,
        errors: [],
        failureMessage: 'The RSI storefront rejected the current session.',
        ships: []
      };
    }

    const cookieValue = (name) => {
      const pattern = new RegExp('(?:^|; )' + name.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&') + '=([^;]*)');
      const match = document.cookie.match(pattern);
      return match ? decodeURIComponent(match[1]) : '';
    };

    const tokenCookieName = (() => {
      const host = window.location.host;
      const parts = host.split('.');
      const subdomain = parts.length > 2 ? parts.slice(0, -2).join('.') : '';
      if (subdomain && !host.includes('local')) {
        return subdomain.includes('.') ? `rsi-review-${subdomain.split('.')[0]}-token` : `rsi-${subdomain}-token`;
      }
      return 'rsi-token';
    })();

    const tokenValue = cookieValue(tokenCookieName);
    if (!tokenValue) {
      return {
        accessDenied: false,
        status: 'token-missing',
        graphQLStatus: 0,
        errors: [],
        failureMessage: `RSI storefront token cookie (${tokenCookieName}) was not available.`,
        ships: []
      };
    }

    const baseHeaders = {
      'Content-Type': 'application/json;charset=UTF-8',
      'Accept': 'application/json',
      ['x-' + tokenCookieName]: tokenValue
    };

    const authResponse = await fetch('/api/account/v2/setAuthToken', {
      method: 'POST',
      credentials: 'include',
      headers: baseHeaders,
      body: JSON.stringify({})
    });

    const contextResponse = await fetch('/api/ship-upgrades/setContextToken', {
      method: 'POST',
      credentials: 'include',
      headers: baseHeaders,
      body: JSON.stringify({
        fromShipId: null,
        toShipId: null,
        toSkuId: null,
        pledgeId: null
      })
    });

    if (!authResponse.ok || !contextResponse.ok) {
      return {
        accessDenied: false,
        status: 'token-renewal-failed',
        graphQLStatus: 0,
        errors: [],
        failureMessage: `RSI storefront token renewal failed (auth ${authResponse.status}, context ${contextResponse.status}).`,
        ships: []
      };
    }

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '';
    const language = document.documentElement.getAttribute('lang') || 'en';
    const query = `query initShipUpgrade {
      ships {
        id
        name
        msrp
        medias {
          productThumbMediumAndSmall
          slideShow
        }
      }
    }`;

    const graphQLResponse = await fetch('/pledge-store/api/graphql', {
      method: 'POST',
      credentials: 'include',
      headers: {
        'Content-Type': 'application/json;charset=UTF-8',
        'Accept': 'application/json',
        'X-CSRF-TOKEN': csrfToken,
        'Accept-Language': language
      },
      body: JSON.stringify([
        {
          operationName: 'initShipUpgrade',
          query,
          variables: {}
        }
      ])
    });

    const rawBody = await graphQLResponse.text();
    let parsedBody = null;
    try {
      parsedBody = JSON.parse(rawBody);
    } catch {}

    const payload = Array.isArray(parsedBody) ? parsedBody[0] : parsedBody;
    const responseErrors = Array.isArray(payload?.errors)
      ? payload.errors.map((entry) => entry?.message || 'Unknown GraphQL error')
      : [];

    const normalizeImageURL = (value) => {
      if (!value) {
        return '';
      }

      const candidate = Array.isArray(value) ? value[0] : value;
      if (!candidate) {
        return '';
      }

      try {
        return new URL(candidate, window.location.origin).toString();
      } catch {
        return '';
      }
    };

    const normalizeMSRP = (value) => {
      if (typeof value === 'number' && Number.isFinite(value)) {
        return Math.abs(value) >= 1000 ? value / 100 : value;
      }

      if (typeof value === 'string' && value.trim()) {
        const parsed = Number.parseFloat(value);
        return Number.isFinite(parsed) ? (Math.abs(parsed) >= 1000 ? parsed / 100 : parsed) : null;
      }

      return null;
    };

    const ships = Array.isArray(payload?.data?.ships)
      ? payload.data.ships.map((ship) => ({
          id: Number.parseInt(String(ship?.id ?? ''), 10),
          name: ship?.name || '',
          msrpUSD: normalizeMSRP(ship?.msrp),
          imageURL: normalizeImageURL(
            ship?.medias?.productThumbMediumAndSmall || ship?.medias?.slideShow
          )
        }))
        .filter((ship) => Number.isFinite(ship.id) && ship.id > 0 && ship.name)
      : [];

    return {
      accessDenied: false,
      status: 'ok',
      graphQLStatus: graphQLResponse.status,
      errors: responseErrors,
      failureMessage: responseErrors.length ? rawBody.slice(0, 500) : '',
      ships
    };
    """

    private static let buybackExtractionScript = """
    await new Promise(resolve => setTimeout(resolve, 150));

    const firstText = (node, selectors) => {
      for (const selector of selectors) {
        const found = node.querySelector(selector);
        const value = found?.textContent?.trim();
        if (value) {
          return value;
        }
      }
      return "";
    };

    const pageNumbers = Array.from(document.querySelectorAll('a[href*="page="], button[data-page], [data-page]'))
      .map((node) => {
        const candidates = [
          node.getAttribute?.('data-page'),
          node.textContent,
          (() => {
            const href = node.getAttribute?.('href');
            if (!href) {
              return null;
            }
            try {
              return new URL(href, window.location.href).searchParams.get('page');
            } catch {
              return null;
            }
          })()
        ];

        for (const candidate of candidates) {
          const match = String(candidate || '').match(/\\b(\\d+)\\b/);
          if (!match) {
            continue;
          }

          const parsed = Number.parseInt(match[1], 10);
          if (Number.isFinite(parsed) && parsed > 0) {
            return parsed;
          }
        }

        return null;
      })
      .filter((value) => Number.isFinite(value));

    const accessDenied = document.title.toLowerCase().includes('access denied') || document.body.innerText.includes('Access denied');
    const articles = Array.from(document.querySelectorAll('article.pledge'));

    return {
      accessDenied,
      title: document.title,
      totalPages: pageNumbers.length ? Math.max(...pageNumbers) : null,
      items: articles.map((article) => {
        const button = article.querySelector('.holosmallbtn, a[href*="/pledge/buyback/"]');
        const href = button?.getAttribute('href') || '';
        const hrefId = Number(href.split('/').filter(Boolean).pop());
        const dataId = Number(button?.getAttribute('data-pledgeid'));
        const definitionValues = Array.from(article.querySelectorAll('dl dd'))
          .map((node) => node.textContent.trim())
          .filter(Boolean);

        return {
          id: Number.isFinite(hrefId) && hrefId > 0 ? hrefId : (Number.isFinite(dataId) && dataId > 0 ? dataId : null),
          title: firstText(article, ['.information h1', 'h1', 'h2']),
          dateText: definitionValues[0] || '',
          containsText: definitionValues[2] || firstText(article, ['.information .contains']),
          valueText: firstText(article, ['.price', '.value', '.cost'])
        };
      })
    };
    """
}

private nonisolated struct RemotePledgePage: Decodable {
    let accessDenied: Bool
    let title: String
    let totalPages: Int?
    let items: [RemotePledge]
}

private nonisolated struct RemotePledge: Decodable {
    let id: Int?
    let title: String
    let statusText: String
    let dateText: String
    let valueText: String
    let containsText: String
    let alsoContains: [String]
    let canGift: Bool
    let canReclaim: Bool
    let canUpgrade: Bool
    let items: [RemotePledgeItem]
}

private nonisolated struct RemotePledgeItem: Decodable {
    let title: String
    let kind: String
    let detail: String
    let imageURL: String?
}

private nonisolated struct RemoteShipCatalogPayload: Decodable {
    let accessDenied: Bool
    let status: String
    let graphQLStatus: Int
    let errors: [String]
    let failureMessage: String?
    let ships: [RemoteStoreShip]
}

private nonisolated struct RemoteStoreShip: Decodable {
    let id: Int
    let name: String
    let msrpUSD: Decimal?
    let imageURL: String?
}

private nonisolated struct RemoteBuybackPage: Decodable {
    let accessDenied: Bool
    let title: String
    let totalPages: Int?
    let items: [RemoteBuybackPledge]
}

private nonisolated struct RemoteBuybackPledge: Decodable {
    let id: Int?
    let title: String
    let dateText: String
    let containsText: String
    let valueText: String
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
