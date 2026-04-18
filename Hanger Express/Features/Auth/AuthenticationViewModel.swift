import Foundation
import Observation
import UIKit
import WebKit

@MainActor
@Observable
final class AuthenticationViewModel {
    enum Step {
        case signIn
        case twoFactor
    }

    var step: Step = .signIn
    var loginIdentifier = ""
    var password = ""
    var rememberMe = true
    var verificationCode = ""
    var deviceName = UIDevice.current.name
    var trustDuration: TrustedDeviceDuration = .year
    var errorMessage: String?
    var errorDebugDetails: String?
    var isSubmitting = false

    private let appModel: AppModel
    private let authService: any AuthenticationServicing

    init(appModel: AppModel) {
        self.appModel = appModel
        authService = appModel.authService
    }

    func submitCredentials() async {
        guard !isSubmitting else {
            return
        }

        clearError()
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let result = try await authService.signIn(
                loginIdentifier: loginIdentifier,
                password: password,
                rememberMe: rememberMe
            )

            switch result {
            case let .authenticated(session):
                password = ""
                await appModel.completeAuthentication(session)
            case .requiresTwoFactor:
                step = .twoFactor
                verificationCode = ""
            }
        } catch {
            showError(error)
        }
    }

    func submitVerificationCode() async {
        guard !isSubmitting else {
            return
        }

        clearError()
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let session = try await authService.submitTwoFactor(
                code: verificationCode,
                deviceName: deviceName,
                trustDuration: trustDuration
            )

            password = ""
            verificationCode = ""
            await appModel.completeAuthentication(session)
        } catch {
            showError(error)
        }
    }

    func returnToSignIn() {
        clearError()
        verificationCode = ""
        step = .signIn

        Task {
            await authService.cancelPendingAuthentication()
        }
    }

    func loadDemoHangar() async {
        await appModel.enablePreviewSession()
    }

    private func showError(_ error: Error) {
        let presentation = AuthenticationDebugFormatter.present(error)
        errorMessage = presentation.message
        errorDebugDetails = presentation.debugDetails
    }

    private func clearError() {
        errorMessage = nil
        errorDebugDetails = nil
    }
}

struct AuthenticationErrorPresentation: Sendable {
    let message: String
    let debugDetails: String?
}

enum AuthenticationDebugFormatter {
    private static let javaScriptExceptionKeys = [
        "WKJavaScriptExceptionMessage",
        "WKJavaScriptExceptionLineNumber",
        "WKJavaScriptExceptionColumnNumber",
        "WKJavaScriptExceptionSourceURL"
    ]

    static func present(_ error: Error) -> AuthenticationErrorPresentation {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let debugDetails = debugDescription(for: error)

        return AuthenticationErrorPresentation(
            message: message,
            debugDetails: debugDetails == message ? nil : debugDetails
        )
    }

    static func debugDescription(for error: Error) -> String {
        var lines: [String] = []
        append(error, title: "Error", into: &lines, indent: "")
        return lines.joined(separator: "\n")
    }

    private static func append(_ error: Error, title: String, into lines: inout [String], indent: String) {
        let nsError = error as NSError

        lines.append("\(indent)\(title)")
        lines.append("\(indent)type: \(String(reflecting: type(of: error)))")
        lines.append("\(indent)localizedDescription: \(nsError.localizedDescription)")
        lines.append("\(indent)domain: \(nsError.domain)")

        if let codeName = webKitCodeName(for: nsError) {
            lines.append("\(indent)code: \(nsError.code) (\(codeName))")
        } else {
            lines.append("\(indent)code: \(nsError.code)")
        }

        let javaScriptDetails = javaScriptDetails(from: nsError)
        if !javaScriptDetails.isEmpty {
            lines.append("\(indent)javascriptDetails:")
            javaScriptDetails.forEach { lines.append("\(indent)- \($0)") }
        }

        let renderedUserInfo = renderUserInfo(nsError.userInfo)
        if !renderedUserInfo.isEmpty {
            lines.append("\(indent)userInfo:")
            renderedUserInfo.forEach { lines.append("\(indent)- \($0)") }
        }

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            append(underlyingError, title: "Underlying Error", into: &lines, indent: indent + "  ")
        }
    }

    private static func javaScriptDetails(from error: NSError) -> [String] {
        javaScriptExceptionKeys.compactMap { key in
            guard let value = error.userInfo[key] else {
                return nil
            }

            return "\(key): \(render(value))"
        }
    }

    private static func renderUserInfo(_ userInfo: [String: Any]) -> [String] {
        userInfo.keys.sorted().compactMap { key in
            guard key != NSUnderlyingErrorKey else {
                return nil
            }

            guard let value = userInfo[key] else {
                return nil
            }

            return "\(key): \(render(value))"
        }
    }

    private static func render(_ value: Any) -> String {
        if let error = value as? NSError {
            return "\(error.domain) (\(error.code)): \(error.localizedDescription)"
        }

        if let url = value as? URL {
            return url.absoluteString
        }

        if let array = value as? [Any] {
            return "[" + array.map(render).joined(separator: ", ") + "]"
        }

        if let dictionary = value as? [String: Any] {
            return "{" + dictionary.keys.sorted().map { key in
                let renderedValue = dictionary[key].map(render) ?? "nil"
                return "\(key): \(renderedValue)"
            }.joined(separator: ", ") + "}"
        }

        return String(describing: value)
    }

    private static func webKitCodeName(for error: NSError) -> String? {
        guard error.domain == WKErrorDomain,
              let code = WKError.Code(rawValue: error.code) else {
            return nil
        }

        switch code {
        case .unknown:
            return "unknown"
        case .webContentProcessTerminated:
            return "webContentProcessTerminated"
        case .webViewInvalidated:
            return "webViewInvalidated"
        case .javaScriptExceptionOccurred:
            return "javaScriptExceptionOccurred"
        case .javaScriptResultTypeIsUnsupported:
            return "javaScriptResultTypeIsUnsupported"
        case .contentRuleListStoreCompileFailed:
            return "contentRuleListStoreCompileFailed"
        case .contentRuleListStoreLookUpFailed:
            return "contentRuleListStoreLookUpFailed"
        case .contentRuleListStoreRemoveFailed:
            return "contentRuleListStoreRemoveFailed"
        case .contentRuleListStoreVersionMismatch:
            return "contentRuleListStoreVersionMismatch"
        case .attributedStringContentFailedToLoad:
            return "attributedStringContentFailedToLoad"
        case .attributedStringContentLoadTimedOut:
            return "attributedStringContentLoadTimedOut"
        case .javaScriptInvalidFrameTarget:
            return "javaScriptInvalidFrameTarget"
        case .navigationAppBoundDomain:
            return "navigationAppBoundDomain"
        case .javaScriptAppBoundDomain:
            return "javaScriptAppBoundDomain"
        case .duplicateCredential:
            return "duplicateCredential"
        case .malformedCredential:
            return "malformedCredential"
        case .credentialNotFound:
            return "credentialNotFound"
        @unknown default:
            return "unknownFutureWKError"
        }
    }
}
