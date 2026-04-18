import Foundation

struct AppEnvironment {
    let sessionStore: any SessionStore
    let hangarRepository: any HangarRepository
    let authService: any AuthenticationServicing
    let recaptchaBroker: RecaptchaBroker

    static var preview: AppEnvironment {
        let broker = RecaptchaBroker()
        return AppEnvironment(
            sessionStore: PreviewSessionStore(),
            hangarRepository: PreviewHangarRepository(),
            authService: PreviewAuthenticationService(),
            recaptchaBroker: broker
        )
    }

    static var live: AppEnvironment {
        let broker = RecaptchaBroker()
        return AppEnvironment(
            sessionStore: KeychainSessionStore(),
            hangarRepository: LiveHangarRepository(),
            authService: RSIAuthService(recaptchaBroker: broker),
            recaptchaBroker: broker
        )
    }
}
