import SwiftUI

/// Start a free 14-day trial. One screen, five fields, no plan chooser and no
/// card details — the shop owner is trying to find out whether this thing
/// makes bills, and anything between them and that is a reason to put the
/// phone down.
///
/// Signup creates a single workspace with every feature in it. There is no
/// "trial edition" of the product: billing, items, sales, day book, dues,
/// labour, staff and reports are all there from the first minute, because a
/// cut-down trial can't answer the only question the owner is asking.
struct SignupView: View {
    @EnvironmentObject private var session: AuthSession
    @StateObject private var viewModel = SignupViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field { case shop, name, phone, email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: PlantbillSpacing.xl) {
                header
                trialCard
                form

                PrimaryButton(
                    title: "Start free trial",
                    isLoading: viewModel.isSubmitting,
                    isDisabled: !viewModel.canSubmit,
                    action: submit
                )

                Text("No card needed. We'll never charge you without asking first.")
                    .font(PlantbillTypography.caption)
                    .foregroundStyle(PlantbillColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(PlantbillSpacing.lg)
        }
        .background(PlantbillColor.background)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Create your shop")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: PlantbillSpacing.sm) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 40))
                .foregroundStyle(PlantbillColor.green)
            Text("Try Plantbill free")
                .font(PlantbillTypography.title)
                .foregroundStyle(PlantbillColor.textPrimary)
            Text("14 days, everything included.")
                .font(PlantbillTypography.body)
                .foregroundStyle(PlantbillColor.textSecondary)
        }
        .padding(.top, PlantbillSpacing.sm)
    }

    private var trialCard: some View {
        PlantbillCard {
            VStack(alignment: .leading, spacing: PlantbillSpacing.sm) {
                perk("Make bills and print them", icon: "cart.fill")
                perk("Your plants, prices and photos", icon: "leaf.fill")
                perk("Daily sales, cash book and dues", icon: "chart.bar.fill")
                perk("Add your salespeople", icon: "person.2.fill")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func perk(_ title: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: PlantbillSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PlantbillColor.green)
                .frame(width: 24)
            Text(title)
                .font(PlantbillTypography.body)
                .foregroundStyle(PlantbillColor.textPrimary)
        }
    }

    private var form: some View {
        VStack(spacing: PlantbillSpacing.md) {
            PlantbillTextField(
                label: "Shop name",
                text: $viewModel.shopName,
                placeholder: "Green Leaf Nursery",
                textContentType: .organizationName
            )
            .focused($focusedField, equals: .shop)
            .submitLabel(.next)
            .onSubmit { focusedField = .name }

            PlantbillTextField(
                label: "Your name",
                text: $viewModel.ownerName,
                placeholder: "Optional",
                textContentType: .name
            )
            .focused($focusedField, equals: .name)
            .submitLabel(.next)
            .onSubmit { focusedField = .phone }

            PlantbillTextField(
                label: "Phone number",
                text: $viewModel.ownerPhone,
                placeholder: "Optional",
                keyboardType: .phonePad,
                textContentType: .telephoneNumber
            )
            .focused($focusedField, equals: .phone)

            PlantbillTextField(
                label: "Email",
                text: $viewModel.email,
                placeholder: "you@example.com",
                keyboardType: .emailAddress,
                textContentType: .username
            )
            .focused($focusedField, equals: .email)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .onSubmit { focusedField = .password }

            VStack(alignment: .leading, spacing: PlantbillSpacing.xs) {
                PlantbillTextField(
                    label: "Create a password",
                    text: $viewModel.password,
                    placeholder: "At least 8 characters",
                    isSecure: true,
                    textContentType: .newPassword
                )
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit { submit() }

                if let hint = viewModel.passwordHint {
                    Text(hint)
                        .font(PlantbillTypography.caption)
                        .foregroundStyle(PlantbillColor.textSecondary)
                }
            }

            Text("This email and password are how you'll sign in. Write them down somewhere safe.")
                .font(PlantbillTypography.caption)
                .foregroundStyle(PlantbillColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let errorMessage = viewModel.errorMessage {
                InlineErrorText(message: LocalizedStringKey(errorMessage))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func submit() {
        focusedField = nil
        Task { await viewModel.submit(session: session) }
    }
}

#Preview {
    NavigationStack {
        SignupView()
            .environmentObject(AuthSession())
    }
}
