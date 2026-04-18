import Foundation
import SwiftUI
import WebKit

enum RecaptchaAction: String, Sendable {
    case login = "Login"
}

struct BrowserGraphQLResponse: Sendable {
    let statusCode: Int
    let body: String
}

protocol AuthenticationWebSessionProviding: AnyObject, Sendable {
    @MainActor func resetAuthenticationSession() async throws
    @MainActor func signIn(loginIdentifier: String, password: String, rememberMe: Bool, query: String) async throws -> BrowserGraphQLResponse
    @MainActor func submitTwoFactor(code: String, deviceName: String, trustDuration: TrustedDeviceDuration, query: String) async throws -> BrowserGraphQLResponse
    @MainActor func currentRSICookies() async throws -> [SessionCookie]
}

final class RecaptchaBroker: NSObject, @unchecked Sendable, AuthenticationWebSessionProviding {
    // RSI's auth flow couples reCAPTCHA, CSRF, and cookies to the same browser session,
    // so the login mutations must run inside the web view instead of a separate URLSession.
    static let helperURL = URL(string: "https://robertsspaceindustries.com/en/")!
    static let siteKey = "6LerBOgUAAAAAKPg6vsAFPTN66Woz-jBClxdQU-o"

    @MainActor private weak var webView: WKWebView?
    @MainActor private var isReady = false
    @MainActor private var readyError: Error?
    @MainActor private var readyContinuations: [CheckedContinuation<Void, Error>] = []

    @MainActor
    func attach(webView: WKWebView) {
        self.webView = webView
        isReady = false
        readyError = nil
    }

    @MainActor
    func detach(webView: WKWebView) {
        guard self.webView === webView else {
            return
        }

        self.webView = nil
        failReadyWaiters(with: AuthenticationError.unavailable("The RSI verification helper was released before it finished loading."))
    }

    @MainActor
    func markReady() {
        isReady = true
        readyError = nil

        let continuations = readyContinuations
        readyContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    @MainActor
    func markFailed(_ error: Error) {
        failReadyWaiters(with: error)
    }

    @MainActor
    func resetAuthenticationSession() async throws {
        try await awaitReady()
        try await clearRSICookies()
        try await reloadHelperPage()
    }

    @MainActor
    func signIn(loginIdentifier: String, password: String, rememberMe: Bool, query: String) async throws -> BrowserGraphQLResponse {
        try await awaitReady()

        guard let webView else {
            throw AuthenticationError.unavailable("The RSI verification helper is not ready yet.")
        }

        let result = try await webView.callAsyncJavaScript(
            """
            const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
            if (!csrfToken) {
              throw new Error("The RSI page did not expose a CSRF token.");
            }

            const markMatch = document.documentElement.innerHTML.match(/window\\.Mark = new Turbulent\\.Mark\\(\\{ 'name' : 'Rsi-XSRF', 'token' : '([^']+)'/);
            const mark = markMatch ? markMatch[1] : null;

            const captchaToken = await new Promise((resolve, reject) => {
              if (!window.grecaptcha || !window.grecaptcha.enterprise) {
                reject(new Error("reCAPTCHA Enterprise is unavailable on the RSI page."));
                return;
              }

              window.grecaptcha.enterprise.ready(() => {
                window.grecaptcha.enterprise.execute(siteKey, { action })
                  .then(resolve)
                  .catch(error => reject(error instanceof Error ? error : new Error(String(error))));
              });
            });

            const response = await fetch('/graphql', {
              method: 'POST',
              credentials: 'include',
              headers: {
                'Content-Type': 'application/json',
                'X-CSRF-TOKEN': csrfToken,
                'Accept-Language': navigator.language || 'en-US'
              },
              body: JSON.stringify({
                operationName: 'signin',
                query,
                variables: {
                  captcha_code: null,
                  captchaToken,
                  email: loginIdentifier,
                  mark,
                  password,
                  remember: rememberMe
                }
              })
            });

            return {
              statusCode: response.status,
              body: await response.text()
            };
            """,
            arguments: [
                "loginIdentifier": loginIdentifier,
                "password": password,
                "rememberMe": rememberMe,
                "query": query,
                "siteKey": Self.siteKey,
                "action": RecaptchaAction.login.rawValue
            ],
            in: nil,
            contentWorld: .page
        )

        return try decodeBrowserResponse(result)
    }

    @MainActor
    func submitTwoFactor(code: String, deviceName: String, trustDuration: TrustedDeviceDuration, query: String) async throws -> BrowserGraphQLResponse {
        try await awaitReady()

        guard let webView else {
            throw AuthenticationError.unavailable("The RSI verification helper is not ready yet.")
        }

        let result = try await webView.callAsyncJavaScript(
            """
            const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
            if (!csrfToken) {
              throw new Error("The RSI page did not expose a CSRF token.");
            }

            const response = await fetch('/graphql', {
              method: 'POST',
              credentials: 'include',
              headers: {
                'Content-Type': 'application/json',
                'X-CSRF-TOKEN': csrfToken,
                'Accept-Language': navigator.language || 'en-US'
              },
              body: JSON.stringify({
                operationName: 'multistep',
                query,
                variables: {
                  code,
                  deviceType: 'computer',
                  deviceName,
                  duration
                }
              })
            });

            return {
              statusCode: response.status,
              body: await response.text()
            };
            """,
            arguments: [
                "code": code,
                "deviceName": deviceName,
                "duration": trustDuration.rawValue,
                "query": query
            ],
            in: nil,
            contentWorld: .page
        )

        return try decodeBrowserResponse(result)
    }

    @MainActor
    func currentRSICookies() async throws -> [SessionCookie] {
        let cookies = try await currentCookies()
        return cookies.map(SessionCookie.init)
            .sorted { lhs, rhs in
                if lhs.domain == rhs.domain {
                    return lhs.name < rhs.name
                }

                return lhs.domain < rhs.domain
            }
    }

    @MainActor
    private func awaitReady() async throws {
        if let readyError {
            throw readyError
        }

        if isReady {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            readyContinuations.append(continuation)
        }
    }

    @MainActor
    private func currentCookies() async throws -> [HTTPCookie] {
        let cookies = try await allCookies()
        return cookies.filter(\.isRSICookie)
    }

    @MainActor
    private func clearRSICookies() async throws {
        let store = try cookieStore()

        for cookie in try await currentCookies() {
            await withCheckedContinuation { continuation in
                store.delete(cookie) {
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    private func reloadHelperPage() async throws {
        guard let webView else {
            throw AuthenticationError.unavailable("The RSI verification helper is not ready yet.")
        }

        isReady = false
        readyError = nil
        webView.load(URLRequest(url: Self.helperURL))
        try await awaitReady()
    }

    @MainActor
    private func allCookies() async throws -> [HTTPCookie] {
        let store = try cookieStore()

        return await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    @MainActor
    private func cookieStore() throws -> WKHTTPCookieStore {
        guard let webView else {
            throw AuthenticationError.unavailable("The RSI verification helper is not ready yet.")
        }

        return webView.configuration.websiteDataStore.httpCookieStore
    }

    private func decodeBrowserResponse(_ result: Any?) throws -> BrowserGraphQLResponse {
        guard let payload = result as? [String: Any],
              let statusValue = payload["statusCode"] as? NSNumber,
              let body = payload["body"] as? String else {
            throw AuthenticationError.unavailable("The RSI verification helper returned an unexpected response.")
        }

        return BrowserGraphQLResponse(statusCode: statusValue.intValue, body: body)
    }

    @MainActor
    private func failReadyWaiters(with error: Error) {
        readyError = error
        isReady = false

        let continuations = readyContinuations
        readyContinuations.removeAll()
        continuations.forEach { $0.resume(throwing: error) }
    }
}

private extension HTTPCookie {
    var isRSICookie: Bool {
        domain.contains("robertsspaceindustries.com")
    }
}

struct RecaptchaBridgeView: UIViewRepresentable {
    let broker: RecaptchaBroker

    func makeCoordinator() -> Coordinator {
        Coordinator(broker: broker)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator

        Task { @MainActor in
            broker.attach(webView: webView)
        }

        webView.load(URLRequest(url: RecaptchaBroker.helperURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        Task { @MainActor in
            coordinator.broker.detach(webView: uiView)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let broker: RecaptchaBroker

        init(broker: RecaptchaBroker) {
            self.broker = broker
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                broker.markReady()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                broker.markFailed(error)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                broker.markFailed(error)
            }
        }
    }
}
