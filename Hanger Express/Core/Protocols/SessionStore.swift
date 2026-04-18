import Foundation

protocol SessionStore: Sendable {
    func loadSession() async -> UserSession?
    func save(_ session: UserSession) async
    func clear() async
}
