import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable {
        case hangar
        case fleet
        case buyback
        case settings
    }

    enum LoadState {
        case idle
        case loading
        case loaded(HangarSnapshot)
        case failed(String)
    }

    var selectedTab: Tab = .hangar
    var session: UserSession?
    var loadState: LoadState = .idle
    var lastRefreshAt: Date?
    var refreshProgress: RefreshProgress?

    let authService: any AuthenticationServicing
    let recaptchaBroker: RecaptchaBroker

    private let sessionStore: any SessionStore
    private let hangarRepository: any HangarRepository
    private var hasBootstrapped = false

    init(environment: AppEnvironment) {
        sessionStore = environment.sessionStore
        hangarRepository = environment.hangarRepository
        authService = environment.authService
        recaptchaBroker = environment.recaptchaBroker
    }

    var snapshot: HangarSnapshot? {
        guard case let .loaded(snapshot) = loadState else {
            return nil
        }

        return snapshot
    }

    var isRefreshing: Bool {
        refreshProgress != nil
    }

    func bootstrap() async {
        guard !hasBootstrapped else {
            return
        }

        hasBootstrapped = true
        session = await sessionStore.loadSession()

        if session != nil {
            await refresh()
        }
    }

    func enablePreviewSession() async {
        let preview = UserSession.preview
        await sessionStore.save(preview)
        session = preview
        await refresh()
    }

    func completeAuthentication(_ session: UserSession) async {
        await sessionStore.save(session)
        self.session = session
        await refresh()
    }

    func clearSession() async {
        await authService.cancelPendingAuthentication()
        await sessionStore.clear()
        session = nil
        lastRefreshAt = nil
        loadState = .idle
        selectedTab = .hangar
    }

    func refresh() async {
        guard let session else {
            loadState = .idle
            return
        }

        guard !isRefreshing else {
            return
        }

        let existingSnapshot = snapshot
        if existingSnapshot == nil {
            loadState = .loading
        }

        refreshProgress = initialProgress(for: session)

        do {
            let snapshot = try await hangarRepository.fetchSnapshot(for: session) { [weak self] progress in
                self?.refreshProgress = progress
            }
            lastRefreshAt = snapshot.lastSyncedAt
            loadState = .loaded(snapshot)
        } catch {
            loadState = .failed("Unable to refresh the hangar snapshot. \(error.localizedDescription)")
        }

        refreshProgress = nil
    }

    private func initialProgress(for session: UserSession) -> RefreshProgress {
        if session.authMode == .developerPreview {
            return RefreshProgress(
                stage: .preview,
                detail: "Loading the local sample hangar snapshot.",
                completedUnitCount: 0,
                totalUnitCount: 1
            )
        }

        return RefreshProgress(
            stage: .preparingSession,
            detail: "Preparing your saved RSI cookies for a live refresh.",
            completedUnitCount: 0,
            totalUnitCount: 1
        )
    }
}
