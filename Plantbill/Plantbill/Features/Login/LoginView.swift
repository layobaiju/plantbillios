import SwiftUI
import UIKit

struct LoginView: View {
    @EnvironmentObject private var session: AuthSession
    @StateObject private var viewModel = LoginViewModel()
    @FocusState private var focusedField: Field?
    /// Shown when a support link couldn't be opened and the contact was
    /// copied to the clipboard instead.
    @State private var supportNotice: String?

    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: PlantbillSpacing.xl) {
                header

                VStack(spacing: PlantbillSpacing.md) {
                    PlantbillTextField(
                        label: "Email",
                        text: $viewModel.email,
                        placeholder: "you@example.com",
                        keyboardType: .emailAddress,
                        textContentType: .username
                    )
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }

                    PlantbillTextField(
                        label: "Password",
                        text: $viewModel.password,
                        placeholder: "Your password",
                        isSecure: true,
                        textContentType: .password
                    )
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { submit() }

                    if let errorMessage = viewModel.errorMessage {
                        InlineErrorText(message: LocalizedStringKey(errorMessage))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                PrimaryButton(
                    title: "Sign in",
                    isLoading: viewModel.isSubmitting,
                    isDisabled: !viewModel.canSubmit,
                    action: submit
                )

                supportFooter

                PoweredByDofida()
                    .padding(.top, PlantbillSpacing.sm)
            }
            .padding(PlantbillSpacing.lg)
            .padding(.top, PlantbillSpacing.xxl)
        }
        .background(PlantbillColor.background)
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        VStack(spacing: PlantbillSpacing.sm) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 44))
                .foregroundStyle(PlantbillColor.green)
            Text("Plantbill")
                .font(PlantbillTypography.largeTitle)
                .foregroundStyle(PlantbillColor.textPrimary)
            Text("Sign in to your shop")
                .font(PlantbillTypography.body)
                .foregroundStyle(PlantbillColor.textSecondary)
        }
    }

    /// `Link` silently does nothing when the destination can't be opened —
    /// which is every `tel:`/`mailto:` on a device with no Phone or Mail
    /// account set up, and always on the Simulator. These are buttons that
    /// check first and fall back to copying the contact, so "get help" never
    /// dead-ends for a shop owner who can't sign in.
    private var supportFooter: some View {
        VStack(spacing: PlantbillSpacing.sm) {
            Text("Need help signing in?")
                .font(PlantbillTypography.caption)
                .foregroundStyle(PlantbillColor.textSecondary)

            HStack(spacing: PlantbillSpacing.lg) {
                Button {
                    open(URL(string: "https://wa.me/\(Self.supportPhoneDigits)"), copyOnFailure: Self.supportPhoneDisplay, label: "number")
                } label: {
                    Label("WhatsApp", systemImage: "message.fill")
                }
                Button {
                    open(URL(string: "tel://\(Self.supportPhoneDigits)"), copyOnFailure: Self.supportPhoneDisplay, label: "number")
                } label: {
                    Label("Call support", systemImage: "phone.fill")
                }
                Button {
                    open(URL(string: "mailto:\(Self.supportEmail)"), copyOnFailure: Self.supportEmail, label: "email")
                } label: {
                    Label("Email", systemImage: "envelope.fill")
                }
            }
            .font(PlantbillTypography.caption)
            .foregroundStyle(PlantbillColor.green)

            if let supportNotice {
                Text(supportNotice)
                    .font(PlantbillTypography.caption)
                    .foregroundStyle(PlantbillColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, PlantbillSpacing.lg)
    }

    /// Same number the More screen uses, so support is one contact everywhere.
    private static let supportPhoneDigits = "917975402266"
    private static let supportPhoneDisplay = "+91 79754 02266"
    private static let supportEmail = "plantparkgroup@gmail.com"

    private func open(_ url: URL?, copyOnFailure value: String, label: String) {
        guard let url, UIApplication.shared.canOpenURL(url) else {
            UIPasteboard.general.string = value
            supportNotice = "Copied our \(label): \(value)"
            return
        }
        UIApplication.shared.open(url) { opened in
            if !opened {
                UIPasteboard.general.string = value
                supportNotice = "Copied our \(label): \(value)"
            }
        }
    }

    private func submit() {
        Task { await viewModel.submit(session: session) }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthSession())
}
