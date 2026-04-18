import Foundation

struct PreviewHangarRepository: HangarRepository {
    func fetchSnapshot(
        for session: UserSession,
        progress: @escaping RefreshProgressHandler
    ) async throws -> HangarSnapshot {
        await progress(
            RefreshProgress(
                stage: .preview,
                detail: "Loading the local sample hangar snapshot.",
                completedUnitCount: 0,
                totalUnitCount: 1
            )
        )

        let now = Date()
        let snapshot = HangarSnapshot(
            accountHandle: session.handle,
            lastSyncedAt: now,
            packages: Self.samplePackages,
            fleet: Self.sampleFleet,
            buyback: Self.sampleBuyback
        )

        await progress(
            RefreshProgress(
                stage: .preview,
                detail: "Preview hangar ready.",
                completedUnitCount: 1,
                totalUnitCount: 1
            )
        )

        return snapshot
    }

    static let sampleSnapshot = HangarSnapshot(
        accountHandle: UserSession.preview.handle,
        lastSyncedAt: referenceDate(year: 2026, month: 4, day: 17),
        packages: samplePackages,
        fleet: sampleFleet,
        buyback: sampleBuyback
    )

    private static let samplePackages: [HangarPackage] = [
        HangarPackage(
            id: 1001,
            title: "Polaris Expedition Pack",
            status: "Attributed",
            insurance: "LTI",
            acquiredAt: referenceDate(year: 2024, month: 11, day: 22),
            originalValueUSD: 750,
            currentValueUSD: 900,
            canGift: true,
            canReclaim: true,
            canUpgrade: false,
            contents: [
                PackageItem(id: "1001-1", title: "RSI Polaris", detail: "Capital ship", category: .ship, imageURL: sampleURL("polaris"), upgradePricing: nil),
                PackageItem(id: "1001-2", title: "Ursa Medivac", detail: "Ground vehicle", category: .vehicle, imageURL: sampleURL("ursa-medivac"), upgradePricing: nil),
                PackageItem(id: "1001-3", title: "Star Citizen Digital Download", detail: "Game access", category: .gamePackage, imageURL: nil, upgradePricing: nil),
                PackageItem(id: "1001-4", title: "Revelation Paint", detail: "Limited event skin", category: .flair, imageURL: nil, upgradePricing: nil)
            ]
        ),
        HangarPackage(
            id: 1002,
            title: "Vulture Foundation Token",
            status: "Hangar Ready",
            insurance: "LTI",
            acquiredAt: referenceDate(year: 2025, month: 2, day: 14),
            originalValueUSD: 150,
            currentValueUSD: 175,
            canGift: false,
            canReclaim: true,
            canUpgrade: true,
            contents: [
                PackageItem(id: "1002-1", title: "Drake Vulture", detail: "Salvage starter", category: .ship, imageURL: sampleURL("vulture"), upgradePricing: nil),
                PackageItem(id: "1002-2", title: "Self-Land Hangar", detail: "Legacy hangar flair", category: .flair, imageURL: nil, upgradePricing: nil)
            ]
        ),
        HangarPackage(
            id: 1003,
            title: "Zeus Mk II MR Patrol Build",
            status: "Hangar Ready",
            insurance: "120 months",
            acquiredAt: referenceDate(year: 2025, month: 9, day: 6),
            originalValueUSD: 170,
            currentValueUSD: 190,
            canGift: true,
            canReclaim: true,
            canUpgrade: true,
            contents: [
                PackageItem(id: "1003-1", title: "RSI Zeus Mk II MR", detail: "Pathfinder / patrol", category: .ship, imageURL: sampleURL("zeus-mk-ii-mr"), upgradePricing: nil),
                PackageItem(
                    id: "1003-2",
                    title: "Cutlass Black to Zeus Mk II MR",
                    detail: "Applied CCU history",
                    category: .upgrade,
                    imageURL: sampleURL("zeus-mk-ii-mr"),
                    upgradePricing: PackageItem.UpgradePricing(
                        sourceShipName: "Cutlass Black",
                        sourceShipMSRPUSD: 110,
                        targetShipName: "Zeus Mk II MR",
                        targetShipMSRPUSD: 190,
                        actualValueUSD: 80,
                        meltValueUSD: 20
                    )
                )
            ]
        ),
        HangarPackage(
            id: 1004,
            title: "Referral Pulse Reward",
            status: "Account Bound",
            insurance: "LTI",
            acquiredAt: referenceDate(year: 2026, month: 1, day: 19),
            originalValueUSD: 0,
            currentValueUSD: 30,
            canGift: false,
            canReclaim: false,
            canUpgrade: false,
            contents: [
                PackageItem(id: "1004-1", title: "Mirai Pulse", detail: "Referral reward", category: .vehicle, imageURL: sampleURL("mirai-pulse"), upgradePricing: nil),
                PackageItem(id: "1004-2", title: "Referral Bonus Token", detail: "Locked reward", category: .perk, imageURL: nil, upgradePricing: nil)
            ]
        )
    ]

    private static let sampleFleet: [FleetShip] = [
        FleetShip(
            id: 2001,
            displayName: "Polaris",
            manufacturer: "RSI",
            role: "Capital combat",
            insurance: "LTI",
            sourcePackageID: 1001,
            sourcePackageName: "Polaris Expedition Pack",
            meltValueUSD: 750,
            canGift: true,
            canReclaim: true
        ),
        FleetShip(
            id: 2002,
            displayName: "Ursa Medivac",
            manufacturer: "RSI",
            role: "Medical vehicle",
            insurance: "LTI",
            sourcePackageID: 1001,
            sourcePackageName: "Polaris Expedition Pack",
            meltValueUSD: 0,
            canGift: true,
            canReclaim: true
        ),
        FleetShip(
            id: 2003,
            displayName: "Vulture",
            manufacturer: "Drake",
            role: "Salvage",
            insurance: "LTI",
            sourcePackageID: 1002,
            sourcePackageName: "Vulture Foundation Token",
            meltValueUSD: 150,
            canGift: false,
            canReclaim: true
        ),
        FleetShip(
            id: 2004,
            displayName: "Zeus Mk II MR",
            manufacturer: "RSI",
            role: "Patrol / expedition",
            insurance: "120 months",
            sourcePackageID: 1003,
            sourcePackageName: "Zeus Mk II MR Patrol Build",
            meltValueUSD: 170,
            canGift: true,
            canReclaim: true
        )
    ]

    private static let sampleBuyback: [BuybackPledge] = [
        BuybackPledge(
            id: 3001,
            title: "Cutlass Black Starter Package",
            recoveredValueUSD: 115,
            addedToBuybackAt: referenceDate(year: 2025, month: 8, day: 2),
            notes: "Good base for future CCU chains."
        ),
        BuybackPledge(
            id: 3002,
            title: "Spirit C1 Warbond",
            recoveredValueUSD: 110,
            addedToBuybackAt: referenceDate(year: 2025, month: 10, day: 17),
            notes: "Watch sale windows before re-purchasing."
        ),
        BuybackPledge(
            id: 3003,
            title: "STV Referral Utility Pack",
            recoveredValueUSD: 35,
            addedToBuybackAt: referenceDate(year: 2026, month: 2, day: 7),
            notes: "Low-value item, but useful for fleet notes."
        )
    ]
}

private func referenceDate(year: Int, month: Int, day: Int) -> Date {
    let components = DateComponents(calendar: .current, year: year, month: month, day: day)
    return components.date ?? .now
}

private func sampleURL(_ slug: String) -> URL? {
    URL(string: "https://cdn.robertsspaceindustries.com/static/images/store/\(slug).jpg")
}
