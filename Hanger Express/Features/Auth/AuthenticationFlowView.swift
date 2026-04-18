import SwiftUI

struct AuthenticationFlowView: View {
    let appModel: AppModel

    @AppStorage("auth.debug.showFullErrors") private var showsFullErrorDetails = false
    @State private var viewModel: AuthenticationViewModel

    init(appModel: AppModel) {
        self.appModel = appModel
        _viewModel = State(initialValue: AuthenticationViewModel(appModel: appModel))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("The live RSI sign-in flow accepts your RSI email or Login ID, uses RSI’s own reCAPTCHA flow, then asks for a verification code if multi-step auth is enabled. Depending on your account settings, that code may come from email or an authenticator app. Successful sign-ins save the RSI cookies, login identifier, and password in Keychain for later account actions.")
                        .font(.body)
                } header: {
                    Text("RSI Login")
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)

                        if showsFullErrorDetails, let errorDebugDetails = viewModel.errorDebugDetails {
                            Text(verbatim: errorDebugDetails)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                switch viewModel.step {
                case .signIn:
                    signInSection
                case .twoFactor:
                    twoFactorSection
                }

                Section {
                    Button("Load Demo Hangar") {
                        Task {
                            await viewModel.loadDemoHangar()
                        }
                    }
                } footer: {
                    Text("Preview mode still uses sample hangar data, but signed-in RSI sessions now refresh from the live pledge pages.")
                }

                Section {
                    Toggle("Show Full Auth Errors", isOn: $showsFullErrorDetails)
                } header: {
                    Text("Debug")
                } footer: {
                    Text("When enabled, the app shows the full WebKit and JavaScript error payload for sign-in troubleshooting.")
                }
            }
            .navigationTitle("Hanger Express")
        }
        .background(
            RecaptchaBridgeView(broker: appModel.recaptchaBroker)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
        )
    }

    private var signInSection: some View {
        Section {
            TextField("RSI Email or Login ID", text: $viewModel.loginIdentifier)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .textContentType(.username)

            SecureField("Password", text: $viewModel.password)
                .textContentType(.password)

            Toggle("Keep me signed in", isOn: $viewModel.rememberMe)

            Button("Continue") {
                Task {
                    await viewModel.submitCredentials()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isSubmitting)
        } header: {
            Text("Credentials")
        } footer: {
            Text("RSI’s live client still submits this as the GraphQL `email` field, even though their support docs say you can also use a Login ID if one is set.")
        }
    }

    private var twoFactorSection: some View {
        Section {
            TextField("Verification Code", text: $viewModel.verificationCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)

            TextField("Device Name", text: $viewModel.deviceName)
                .textInputAutocapitalization(.words)

            Picker("Remember This Device", selection: $viewModel.trustDuration) {
                ForEach(TrustedDeviceDuration.allCases) { duration in
                    Text(duration.displayName)
                        .tag(duration)
                }
            }

            Button("Verify") {
                Task {
                    await viewModel.submitVerificationCode()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isSubmitting)

            Button("Back to Sign In") {
                viewModel.returnToSignIn()
            }
            .disabled(viewModel.isSubmitting)
        } header: {
            Text("Verification")
        } footer: {
            Text("This mirrors the live RSI `account_multistep` flow and defaults the trusted-device duration to 1 year.")
        }
    }
}
