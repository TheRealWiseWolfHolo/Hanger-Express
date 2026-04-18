import Foundation

actor PreviewAuthenticationService: AuthenticationServicing {
    private var pendingLoginIdentifier: String?
    private var pendingPassword: String?

    func signIn(loginIdentifier: String, password: String, rememberMe: Bool) async throws -> SignInOutcome {
        let trimmedLoginIdentifier = loginIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedLoginIdentifier.isEmpty, !password.isEmpty else {
            throw AuthenticationError.invalidInput("Enter your RSI email or Login ID and password to continue.")
        }

        pendingLoginIdentifier = trimmedLoginIdentifier
        pendingPassword = password
        return .requiresTwoFactor
    }

    func submitTwoFactor(code: String, deviceName: String, trustDuration: TrustedDeviceDuration) async throws -> UserSession {
        guard let pendingLoginIdentifier, let pendingPassword else {
            throw AuthenticationError.pendingVerificationExpired
        }

        let handle = pendingLoginIdentifier.split(separator: "@").first.map(String.init) ?? pendingLoginIdentifier
        self.pendingLoginIdentifier = nil
        self.pendingPassword = nil

        return UserSession(
            handle: handle,
            displayName: handle,
            email: pendingLoginIdentifier,
            authMode: .developerPreview,
            notes: "Preview authentication completed without contacting RSI.",
            credentials: AccountCredentials(loginIdentifier: pendingLoginIdentifier, password: pendingPassword),
            cookies: [],
            createdAt: .now
        )
    }

    func cancelPendingAuthentication() async {
        pendingLoginIdentifier = nil
        pendingPassword = nil
    }
}
