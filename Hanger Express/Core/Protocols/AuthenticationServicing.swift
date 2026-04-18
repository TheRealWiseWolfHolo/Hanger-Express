import Foundation

protocol AuthenticationServicing: Sendable {
    func signIn(loginIdentifier: String, password: String, rememberMe: Bool) async throws -> SignInOutcome
    func submitTwoFactor(code: String, deviceName: String, trustDuration: TrustedDeviceDuration) async throws -> UserSession
    func cancelPendingAuthentication() async
}

enum SignInOutcome: Sendable {
    case authenticated(UserSession)
    case requiresTwoFactor
}

enum AuthenticationError: Error, LocalizedError, Sendable {
    case invalidInput(String)
    case signInFailed(String)
    case pendingVerificationExpired
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .invalidInput(message), let .signInFailed(message), let .unavailable(message):
            return message
        case .pendingVerificationExpired:
            return "The pending verification step expired. Start the sign-in flow again."
        }
    }
}
