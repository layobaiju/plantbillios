import SwiftUI

/// Quick add a one-off item — Android's `QuickAddSheet`: name, price, quantity
/// and "Add to bill", which saves it under "Quick Add" and puts it straight on
/// the bill.
struct QuickAddSheet: View {
    @ObservedObject var viewModel: BillingViewModel
    /// Called once the item is on the bill, so the screen can open the review.
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var priceText = ""
    @State private var quantity = 1
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// The price may be ₹0 (a free item) — only a blank one blocks it.
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !priceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PlantbillSpacing.lg) {
                    VStack(alignment: .leading, spacing: PlantbillSpacing.xs) {
                        Text("Quick add custom item")
                            .font(PlantbillTypography.title)
                            .foregroundStyle(PlantbillColor.textPrimary)
                        Text("Adds a one-off item to this bill (saved under \"Quick Add\").")
                            .font(PlantbillTypography.body)
                            .foregroundStyle(PlantbillColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    PlantbillTextField(label: "Item name", text: $name, placeholder: "e.g. Ad-hoc plant, pot, soil")
                    PlantbillTextField(
                        label: "Price (₹)",
                        text: $priceText,
                        placeholder: "0",
                        keyboardType: .decimalPad,
                        selectAllOnFocus: true
                    )

                    HStack {
                        Text("Quantity")
                            .font(PlantbillTypography.bodyEmphasized)
                            .foregroundStyle(PlantbillColor.textPrimary)
                        Spacer()
                        stepper
                    }

                    if let errorMessage {
                        InlineErrorText(message: LocalizedStringKey(errorMessage))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PrimaryButton(title: "Add to bill", isLoading: isSaving, isDisabled: !canSave, action: save)
                }
                .padding(PlantbillSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PlantbillColor.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var stepper: some View {
        HStack(spacing: PlantbillSpacing.sm) {
            stepButton(systemName: "minus", enabled: quantity > 1) { quantity = max(1, quantity - 1) }
                .accessibilityLabel(Text("Decrease quantity"))
            Text("\(quantity)")
                .font(PlantbillTypography.headline)
                .foregroundStyle(PlantbillColor.textPrimary)
                .frame(minWidth: 44)
            stepButton(systemName: "plus", enabled: true) { quantity += 1 }
                .accessibilityLabel(Text("Increase quantity"))
        }
    }

    private func stepButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(PlantbillColor.green)
                .frame(width: PlantbillSpacing.minTouchTarget, height: PlantbillSpacing.minTouchTarget)
                .background(
                    RoundedRectangle(cornerRadius: PlantbillSpacing.controlCornerRadius)
                        .fill(PlantbillColor.greenTint)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawPrice = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let price = Decimal(string: rawPrice, locale: Locale(identifier: "en_US_POSIX")), price >= 0 else {
            errorMessage = "Please enter a valid price (0 or more)."
            return
        }
        errorMessage = nil
        isSaving = true
        Task {
            let failure = await viewModel.quickAdd(name: trimmedName, price: Money(amount: price), quantity: quantity)
            isSaving = false
            if let failure {
                errorMessage = failure
            } else {
                onAdded()
                dismiss()
            }
        }
    }
}
