import Foundation

actor PreviewSessionStore: SessionStore {
    private var session: UserSession?

    func loadSession() async -> UserSession? {
        session
    }

    func save(_ session: UserSession) async {
        self.session = session
    }

    func clear() async {
        session = nil
    }
}
