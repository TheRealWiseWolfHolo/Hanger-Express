import Foundation

nonisolated enum RefreshStage: Hashable, Sendable {
    case preview
    case preparingSession
    case pledges
    case buyback
    case finalizing

    var title: String {
        switch self {
        case .preview:
            return "Loading preview hangar"
        case .preparingSession:
            return "Restoring RSI session"
        case .pledges:
            return "Refreshing hangar pledges"
        case .buyback:
            return "Refreshing buy-back pledges"
        case .finalizing:
            return "Organizing your inventory"
        }
    }

    var stepNumber: Int {
        switch self {
        case .preview:
            return 1
        case .preparingSession:
            return 1
        case .pledges:
            return 2
        case .buyback:
            return 3
        case .finalizing:
            return 4
        }
    }

    var stepCount: Int {
        switch self {
        case .preview:
            return 1
        case .preparingSession, .pledges, .buyback, .finalizing:
            return 4
        }
    }
}

nonisolated struct RefreshProgress: Hashable, Sendable {
    let stage: RefreshStage
    let detail: String
    let completedUnitCount: Int
    let totalUnitCount: Int?

    var fractionCompleted: Double? {
        guard let totalUnitCount, totalUnitCount > 0 else {
            return nil
        }

        let boundedCompletedUnits = min(max(completedUnitCount, 0), totalUnitCount)
        return Double(boundedCompletedUnits) / Double(totalUnitCount)
    }

    var stepLabel: String {
        "Step \(stage.stepNumber) of \(stage.stepCount)"
    }
}

typealias RefreshProgressHandler = @MainActor @Sendable (RefreshProgress) -> Void

protocol HangarRepository: Sendable {
    func fetchSnapshot(
        for session: UserSession,
        progress: @escaping RefreshProgressHandler
    ) async throws -> HangarSnapshot
}
