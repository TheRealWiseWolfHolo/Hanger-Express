import Foundation
import Testing
import WebKit
@testable import Hanger_Express

struct Hanger_ExpressTests {
    @Test func sampleSnapshotRollsUpMetrics() async throws {
        let snapshot = PreviewHangarRepository.sampleSnapshot

        #expect(snapshot.metrics.packageCount == 4)
        #expect(snapshot.metrics.shipCount == 4)
        #expect(snapshot.metrics.giftableCount == 2)
        #expect(snapshot.metrics.reclaimableCount == 3)
        #expect(snapshot.metrics.totalOriginalValue == 1070)
        #expect(snapshot.metrics.totalCurrentValue == 1295)
    }

    @Test func sessionCookieRoundTripsBackToHTTPCookie() async throws {
        let expiresAt = Date(timeIntervalSince1970: 1_800_000_000)
        let sourceCookie = try #require(
            HTTPCookie(
                properties: [
                    .name: "Rsi-Token",
                    .value: "cookie-value",
                    .domain: ".robertsspaceindustries.com",
                    .path: "/",
                    .expires: expiresAt,
                    .secure: "TRUE",
                    HTTPCookiePropertyKey("HttpOnly"): "TRUE"
                ]
            )
        )

        let storedCookie = SessionCookie(sourceCookie)
        let rebuiltCookie = try #require(storedCookie.httpCookie)

        #expect(rebuiltCookie.name == sourceCookie.name)
        #expect(rebuiltCookie.value == sourceCookie.value)
        #expect(rebuiltCookie.domain == sourceCookie.domain)
        #expect(rebuiltCookie.path == sourceCookie.path)
        #expect(rebuiltCookie.expiresDate == expiresAt)
        #expect(rebuiltCookie.isSecure)
        #expect(rebuiltCookie.isHTTPOnly)
    }

    @Test func trustedDeviceDurationIncludesYearOption() async throws {
        #expect(TrustedDeviceDuration.allCases.contains(.year))
        #expect(TrustedDeviceDuration.year.displayName == "1 year")
    }

    @Test func refreshProgressCalculatesFractionWhenTotalUnitsAreKnown() async throws {
        let progress = RefreshProgress(
            stage: .pledges,
            detail: "Finished page 2 of 5. 100 pledges synced so far.",
            completedUnitCount: 2,
            totalUnitCount: 5
        )

        #expect(progress.stepLabel == "Step 2 of 4")
        #expect(progress.fractionCompleted == 0.4)
    }

    @Test func authenticationDebugFormatterIncludesJavaScriptDetails() async throws {
        let error = NSError(
            domain: WKErrorDomain,
            code: WKError.Code.javaScriptExceptionOccurred.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "A JavaScript exception occurred",
                "WKJavaScriptExceptionMessage": "Can't find variable: arguments",
                "WKJavaScriptExceptionLineNumber": 1,
                "WKJavaScriptExceptionColumnNumber": 18
            ]
        )

        let presentation = AuthenticationDebugFormatter.present(error)

        #expect(presentation.message == "JavaScript error: Can't find variable: arguments (line 1, column 18)")
        #expect(presentation.debugDetails?.contains("javaScriptExceptionOccurred") == true)
        #expect(presentation.debugDetails?.contains("Can't find variable: arguments") == true)
    }

    @Test func authenticationDebugFormatterShowsRawRSIResponseBodyForUnexpectedResponses() async throws {
        let error = NSError(
            domain: "RSIAuthService",
            code: 200,
            userInfo: [
                NSLocalizedDescriptionKey: "RSI returned a response the app could not decode yet.",
                "RSIResponseBody": #"{"errors":[{"message":"SomethingNew","extensions":{"details":{"reason":"backend surprise"}}}]}"#
            ]
        )

        let presentation = AuthenticationDebugFormatter.present(error)

        #expect(presentation.message.contains("RSI returned a response the app could not decode yet."))
        #expect(presentation.message.contains(#""message":"SomethingNew""#))
    }

    @Test func signInAcceptsTwoFactorResponsesWithFlexibleGraphQLPayloads() async throws {
        let webSession = FakeAuthenticationWebSession(
            signInResponse: BrowserGraphQLResponse(
                statusCode: 200,
                body: """
                {
                  "data": {
                    "account_signin": false
                  },
                  "errors": [
                    {
                      "message": "MultiStepRequired",
                      "extensions": {
                        "category": "authorization",
                        "details": {
                          "delivery": "email",
                          "channels": ["email"],
                          "rememberDevice": {
                            "year": true
                          }
                        }
                      }
                    }
                  ]
                }
                """
            )
        )

        let service = RSIAuthService(recaptchaBroker: webSession)
        let outcome = try await service.signIn(
            loginIdentifier: "pilot@example.com",
            password: "secret-password",
            rememberMe: true
        )

        switch outcome {
        case .requiresTwoFactor:
            #expect(true)
        case .authenticated:
            Issue.record("Expected the auth flow to require a verification code.")
        }
    }

    @Test func signInHumanizesInvalidCredentialsErrors() async throws {
        let webSession = FakeAuthenticationWebSession(
            signInResponse: BrowserGraphQLResponse(
                statusCode: 200,
                body: """
                {
                  "data": {
                    "account_signin": null
                  },
                  "errors": [
                    {
                      "message": "InvalidPasswordException",
                      "extensions": {
                        "category": "authorization",
                        "details": {
                          "password": "Invalid"
                        }
                      }
                    }
                  ]
                }
                """
            )
        )

        let service = RSIAuthService(recaptchaBroker: webSession)

        do {
            try await service.signIn(
                loginIdentifier: "pilot@example.com",
                password: "wrong-password",
                rememberMe: true
            )
            Issue.record("Expected invalid credentials to throw an authentication error.")
        } catch let error as AuthenticationError {
            guard case let .signInFailed(message) = error else {
                Issue.record("Expected a sign-in failure message, got \(error).")
                return
            }

            #expect(message == "Incorrect RSI email/Login ID or password. Check your credentials and try again.")
        } catch {
            Issue.record("Expected AuthenticationError, got \(error).")
        }
    }

    @Test func signInHumanizesTooManyAttemptsErrors() async throws {
        let webSession = FakeAuthenticationWebSession(
            signInResponse: BrowserGraphQLResponse(
                statusCode: 200,
                body: """
                {
                  "data": {
                    "account_signin": null
                  },
                  "errors": [
                    {
                      "message": "ErrValidationFailed",
                      "extensions": {
                        "category": "authorization",
                        "details": {
                          "form": "Error Code 1034 - Maximum number of failed login attempts exceeded"
                        }
                      }
                    }
                  ]
                }
                """
            )
        )

        let service = RSIAuthService(recaptchaBroker: webSession)

        do {
            try await service.signIn(
                loginIdentifier: "pilot@example.com",
                password: "wrong-password",
                rememberMe: true
            )
            Issue.record("Expected RSI lockout to throw an authentication error.")
        } catch let error as AuthenticationError {
            guard case let .signInFailed(message) = error else {
                Issue.record("Expected a sign-in failure message, got \(error).")
                return
            }

            #expect(message == "Too many login attempts. RSI temporarily locked this account. Wait about an hour before trying again.")
        } catch {
            Issue.record("Expected AuthenticationError, got \(error).")
        }
    }

    @Test func signInSurfacesUnknownRSIErrorsWithoutGenericFallback() async throws {
        let webSession = FakeAuthenticationWebSession(
            signInResponse: BrowserGraphQLResponse(
                statusCode: 200,
                body: """
                {
                  "data": {
                    "account_signin": null
                  },
                  "errors": [
                    {
                      "message": "SomethingBrandNew",
                      "code": "ZX-42",
                      "extensions": {
                        "category": "backend",
                        "details": {
                          "reason": "Unexpected upstream rejection"
                        }
                      }
                    }
                  ]
                }
                """
            )
        )

        let service = RSIAuthService(recaptchaBroker: webSession)

        do {
            try await service.signIn(
                loginIdentifier: "pilot@example.com",
                password: "secret-password",
                rememberMe: true
            )
            Issue.record("Expected the unknown RSI error to throw an authentication error.")
        } catch let error as AuthenticationError {
            guard case let .signInFailed(message) = error else {
                Issue.record("Expected a sign-in failure message, got \(error).")
                return
            }

            #expect(message.contains("SomethingBrandNew"))
            #expect(message.contains("ZX-42"))
            #expect(message.contains("Unexpected upstream rejection"))
        } catch {
            Issue.record("Expected AuthenticationError, got \(error).")
        }
    }

    @Test func submitTwoFactorHumanizesInvalidOrAlreadyUsedCodes() async throws {
        let webSession = FakeAuthenticationWebSession(
            signInResponse: BrowserGraphQLResponse(
                statusCode: 200,
                body: """
                {
                  "data": {
                    "account_signin": false
                  },
                  "errors": [
                    {
                      "message": "MultiStepRequired",
                      "extensions": {
                        "category": "authorization",
                        "details": {
                          "delivery": "email"
                        }
                      }
                    }
                  ]
                }
                """
            ),
            twoFactorResponse: BrowserGraphQLResponse(
                statusCode: 200,
                body: """
                {
                  "data": {
                    "account_multistep": null
                  },
                  "errors": [
                    {
                      "message": "ErrValidationFailed",
                      "extensions": {
                        "category": "authorization",
                        "details": {
                          "code": "invalid or already used"
                        }
                      }
                    }
                  ]
                }
                """
            )
        )

        let service = RSIAuthService(recaptchaBroker: webSession)
        _ = try await service.signIn(
            loginIdentifier: "pilot@example.com",
            password: "secret-password",
            rememberMe: true
        )

        do {
            try await service.submitTwoFactor(
                code: "123456",
                deviceName: "iPhone",
                trustDuration: .year
            )
            Issue.record("Expected the invalid verification code to throw an authentication error.")
        } catch let error as AuthenticationError {
            guard case let .signInFailed(message) = error else {
                Issue.record("Expected a sign-in failure message, got \(error).")
                return
            }

            #expect(message == "That verification code was not accepted. Use the newest RSI code and try again.")
        } catch {
            Issue.record("Expected AuthenticationError, got \(error).")
        }
    }

    @Test func upgradeTitleParserExtractsSourceAndTargetShips() async throws {
        let path = try #require(UpgradeTitleParser.parse("Upgrade - Cutlass Black to Zeus Mk II MR CCU"))

        #expect(path.sourceShipName == "Cutlass Black")
        #expect(path.targetShipName == "Zeus Mk II MR")
    }

    @Test func shipCatalogMatchesHangarNamesWithManufacturerPrefixes() async throws {
        let catalog = RSIShipCatalog(
            ships: [
                .init(
                    id: 1,
                    name: "Zeus Mk II MR",
                    msrpUSD: 190,
                    imageURL: URL(string: "https://example.com/zeus.jpg")
                )
            ]
        )

        let match = catalog.matchShip(named: "RSI Zeus Mk II MR")

        #expect(match?.name == "Zeus Mk II MR")
        #expect(match?.msrpUSD == 190)
    }

    @Test func legacyStoredSessionPayloadStillDecodes() async throws {
        let json = """
        {
          "handle": "citizen-1",
          "displayName": "Citizen One",
          "email": "citizen@example.com",
          "credentials": {
            "loginIdentifier": "citizen@example.com",
            "password": "secret"
          },
          "cookies": [
            {
              "name": "Rsi-Token",
              "value": "cookie-value",
              "domain": ".robertsspaceindustries.com",
              "expiresAt": "2026-04-18T04:00:00Z"
            }
          ]
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(UserSession.self, from: Data(json.utf8))

        #expect(session.handle == "citizen-1")
        #expect(session.displayName == "Citizen One")
        #expect(session.authMode == .rsiNativeLogin)
        #expect(session.notes == "")
        #expect(session.cookies.count == 1)
        #expect(session.cookies.first?.path == "/")
        #expect(session.cookies.first?.isSecure == true)
        #expect(session.cookies.first?.isHTTPOnly == true)
    }
}

private final class FakeAuthenticationWebSession: AuthenticationWebSessionProviding, @unchecked Sendable {
    let signInResponse: BrowserGraphQLResponse
    let twoFactorResponse: BrowserGraphQLResponse
    let cookies: [SessionCookie]

    init(
        signInResponse: BrowserGraphQLResponse,
        twoFactorResponse: BrowserGraphQLResponse = BrowserGraphQLResponse(statusCode: 200, body: #"{"data":{"account_multistep":null},"errors":[]}"#),
        cookies: [SessionCookie] = []
    ) {
        self.signInResponse = signInResponse
        self.twoFactorResponse = twoFactorResponse
        self.cookies = cookies
    }

    @MainActor
    func resetAuthenticationSession() async throws {}

    @MainActor
    func signIn(loginIdentifier: String, password: String, rememberMe: Bool, query: String) async throws -> BrowserGraphQLResponse {
        signInResponse
    }

    @MainActor
    func submitTwoFactor(code: String, deviceName: String, trustDuration: TrustedDeviceDuration, query: String) async throws -> BrowserGraphQLResponse {
        twoFactorResponse
    }

    @MainActor
    func currentRSICookies() async throws -> [SessionCookie] {
        cookies
    }
}
