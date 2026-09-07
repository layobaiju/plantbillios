import SwiftUI

/// A hard stop before an irreversible account deletion: Delete stays disabled
/// until the account's email is re-typed (case- and whitespace-insensitive).
/// Ported from Android's `TypeEmailToDeleteDialog`.
///
/// A one-tap "Are you sure?" is not enough here — the audience is elderly shop
/// owners and the wrong tap removes a staff account outright.
struct TypeEmailToDeleteSheet: View {
    let email: String
    let title: LocalizedStringKey
    let message: String
    let confirmLabel: LocalizedStringKey
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    private var matches: Bool {
        let entered = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let expected = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !expected.isEmpty && entered.caseInsensitiveCompare(expected) == .orderedSame
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: PlantbillSpacing.lg) {
                Text(message)
                    .font(PlantbillTypography.body)
                    .foregroundStyle(PlantbillColor.textPrimary)

                VStack(alignment: .leading, spacing: PlantbillSpacing.xs) {
                    Text("Type the email to confirm:")
                        .font(PlantbillTypography.caption)
                        .foregroundStyle(PlantbillColor.textSecondary)
                    Text(email)
                        .font(PlantbillTypography.bodyEmphasized)
                        .foregroundStyle(PlantbillColor.textPrimary)
                        .textSelection(.enabled)
                }

                PlantbillTextField(
                    label: "Enter email",
                    text: $typed,
                    placeholder: LocalizedStringKey(email),
                    keyboardType: .emailAddress
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                if !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !matches {
                    InlineErrorText(message: "That doesn't match.")
                }

                PrimaryButton(title: confirmLabel, isDisabled: !matches) {
                    onConfirm()
                    dismiss()
                }

                SecondaryButton(title: "Cancel") { dismiss() }

                Spacer()
            }
            .padding(PlantbillSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PlantbillColor.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
