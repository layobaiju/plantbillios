import SwiftUI

/// The bill review, in the order Android's `CartSheetContent` uses: the
/// lines, Add item, the discount, the totals, the customer, payment, the
/// scan-to-pay QR, then Hold and Save — with remarks last because they're
/// rarely used.
struct CartReviewSheet: View {
    @ObservedObject var viewModel: BillingViewModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var remarksFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    linesSection

                    // Minimises the review so more plants can be tapped; the
                    // next tap opens it again.
                    SecondaryButton(title: "Add item", systemImage: "plus") { dismiss() }
                        .padding(.top, PlantbillSpacing.md)

                    discountSection
                        .padding(.top, PlantbillSpacing.lg)
                    totalsSection
                        .padding(.top, PlantbillSpacing.lg)
                    customerSection
                        .padding(.top, PlantbillSpacing.lg)
                    paymentSection
                        .padding(.top, PlantbillSpacing.lg)

                    // Scan-to-pay appears whenever any amount is being taken by UPI.
                    if viewModel.upiAmount.isPositive {
                        upiSection
                            .padding(.top, PlantbillSpacing.lg)
                    }

                    if case .error(let message) = viewModel.checkoutState {
                        InlineErrorText(message: LocalizedStringKey(message))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, PlantbillSpacing.md)
                    }

                    // Park this bill to serve another customer first.
                    SecondaryButton(title: "Hold bill — serve another customer", systemImage: "pause.fill") {
                        viewModel.holdCurrentBill()
                        dismiss()
                    }
                    .padding(.top, PlantbillSpacing.xl)

                    PrimaryButton(
                        title: "Save bill • \(viewModel.total.format())",
                        isLoading: viewModel.checkoutState == .submitting,
                        isDisabled: !viewModel.allLinesFilled
                    ) {
                        remarksFocused = false
                        dismissKeyboard()
                        Task { await viewModel.checkout() }
                    }
                    .padding(.top, PlantbillSpacing.md)

                    if viewModel.showsIncompleteLinesHint {
                        Text("Enter a quantity and price for every item.")
                            .font(PlantbillTypography.body)
                            .foregroundStyle(PlantbillColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, PlantbillSpacing.xs)
                    }

                    remarksField
                        .padding(.top, PlantbillSpacing.md)
                }
                .padding(.horizontal, PlantbillSpacing.lg)
                .padding(.top, PlantbillSpacing.sm)
                .padding(.bottom, PlantbillSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PlantbillColor.background)
            .navigationTitle("Review bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(PlantbillColor.textPrimary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("Close review"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.clearCart()
                        dismiss()
                    } label: {
                        Label("Clear cart", systemImage: "trash")
                            .labelStyle(.titleAndIcon)
                            .font(PlantbillTypography.caption.weight(.semibold))
                            .foregroundStyle(PlantbillColor.error)
                    }
                    .disabled(viewModel.cartLines.isEmpty)
                }
            }
            .onChange(of: viewModel.checkoutState) { newState in
                if case .success = newState { dismiss() }
            }
        }
    }

    // MARK: Lines

    private var linesSection: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.cartLines) { line in
                CartLineRow(
                    line: line,
                    onQuantityText: { viewModel.updateQuantityText(lineId: line.id, text: $0) },
                    onPriceText: { viewModel.updatePriceText(lineId: line.id, text: $0) },
                    onIncrement: { viewModel.incrementQuantity(lineId: line.id) },
                    onDecrement: { viewModel.decrementQuantity(lineId: line.id) },
                    onRemove: { viewModel.removeLine(lineId: line.id) }
                )
                Divider()
            }
        }
    }

    // MARK: Discount

    private var discountSection: some View {
        VStack(alignment: .leading, spacing: PlantbillSpacing.sm) {
            sectionHeader("Discount")
            HStack(spacing: PlantbillSpacing.sm) {
                FilterChip(title: "₹ Flat", isSelected: viewModel.discountType == .flat) {
                    viewModel.discountType = .flat
                }
                FilterChip(title: "% Percent", isSelected: viewModel.discountType == .percent) {
                    viewModel.discountType = .percent
                }
                Spacer(minLength: 0)
                NumberBox(
                    text: $viewModel.discountValueText,
                    placeholder: viewModel.discountType == .flat ? "Amount" : "Percent",
                    keyboardType: .decimalPad
                )
                .frame(minWidth: 96, maxWidth: 130)
            }
        }
    }

    // MARK: Totals

    private var totalsSection: some View {
        VStack(spacing: PlantbillSpacing.xs) {
            summaryRow("Subtotal", value: viewModel.subtotal.format())
            if viewModel.discountAmount.isPositive {
                summaryRow("Discount", value: viewModel.discountAmount.formatOutgoing())
            }
            HStack {
                Text("Total")
                    .font(PlantbillTypography.headline)
                    .foregroundStyle(PlantbillColor.textPrimary)
                Spacer()
                Text(viewModel.total.format())
                    .font(PlantbillTypography.headline)
                    .foregroundStyle(PlantbillColor.textPrimary)
            }
            .padding(.top, PlantbillSpacing.xs)
        }
    }

    private func summaryRow(_ label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .font(PlantbillTypography.body)
                .foregroundStyle(PlantbillColor.textSecondary)
            Spacer()
            Text(value)
                .font(PlantbillTypography.body)
                .foregroundStyle(PlantbillColor.textSecondary)
        }
    }

    // MARK: Customer

    /// Entered fresh on every bill; the phone becomes compulsory when there's a due.
    private var customerSection: some View {
        VStack(alignment: .leading, spacing: PlantbillSpacing.sm) {
            sectionHeader(viewModel.requiresCustomerPhone ? "Customer (required for due)" : "Customer (optional)")

            PlantbillTextField(label: "Name", text: $viewModel.customerName, textContentType: .name)

            PlantbillTextField(
                label: viewModel.requiresCustomerPhone ? "Phone (required — money owed)" : "Phone (for receipts)",
                text: $viewModel.customerPhone,
                keyboardType: .phonePad,
                textContentType: .telephoneNumber
            )

            if let rc = viewModel.returningCustomer {
                returningCustomerText(rc)
                    .font(PlantbillTypography.body)
                    .foregroundStyle(PlantbillColor.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// "Asha — Returning customer · came 3 time(s) before", or without the
    /// name when the server didn't have one. Android's `cart_returning_customer`.
    private func returningCustomerText(_ rc: CustomerLookup) -> Text {
        let prefix = rc.name.map { "\($0) — " } ?? ""
        return Text("\(prefix)Returning customer · came \(rc.visitCount) time(s) before")
    }

    // MARK: Payment

    private var paymentSection: some View {
        VStack(alignment: .leading, spacing: PlantbillSpacing.sm) {
            sectionHeader("Payment")
            HStack(spacing: PlantbillSpacing.sm) {
                FilterChip(title: "Cash", isSelected: viewModel.paymentMode == .cash) {
                    viewModel.paymentMode = .cash
                }
                FilterChip(title: "UPI", isSelected: viewModel.paymentMode == .upi) {
                    viewModel.paymentMode = .upi
                }
                FilterChip(title: "Split", isSelected: viewModel.paymentMode == .split) {
                    viewModel.paymentMode = .split
                }
            }

            if viewModel.paymentMode == .split {
                PlantbillTextField(
                    label: "Cash part",
                    text: $viewModel.cashPartText,
                    placeholder: "0",
                    keyboardType: .decimalPad,
                    selectAllOnFocus: true
                )
            }

            PlantbillTextField(
                label: "Due (owed later, optional)",
                text: $viewModel.dueAmountText,
                placeholder: "0",
                keyboardType: .decimalPad,
                selectAllOnFocus: true
            )

            HStack(spacing: PlantbillSpacing.lg) {
                payPill("Cash", viewModel.cashAmount)
                payPill("UPI", viewModel.upiAmount)
            }
            .padding(.top, PlantbillSpacing.xs)
        }
    }

    private func payPill(_ label: LocalizedStringKey, _ money: Money) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(PlantbillTypography.caption)
                .foregroundStyle(PlantbillColor.textSecondary)
            Text(money.format())
                .font(PlantbillTypography.bodyEmphasized)
                .foregroundStyle(PlantbillColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: UPI QR

    private var upiSection: some View {
        VStack(spacing: PlantbillSpacing.sm) {
            if let upi = viewModel.businessUpi, !upi.isEmpty {
                Text("SCAN TO PAY")
                    .font(PlantbillTypography.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(PlantbillColor.green)
                UpiQrCodeView(payeeVpa: upi, payeeName: viewModel.businessName, amount: viewModel.upiAmount, size: 220)
                    .padding(.top, PlantbillSpacing.xs)
                Text(viewModel.upiAmount.format())
                    .font(PlantbillTypography.title)
                    .foregroundStyle(PlantbillColor.textPrimary)
                    .padding(.top, PlantbillSpacing.xs)
                Text(verbatim: upi)
                    .font(PlantbillTypography.body)
                    .foregroundStyle(PlantbillColor.textSecondary)
            } else {
                Text("UPI not set up")
                    .font(PlantbillTypography.bodyEmphasized)
                    .foregroundStyle(PlantbillColor.error)
                Text("Ask your admin to add the shop's UPI ID so customers can scan to pay.")
                    .font(PlantbillTypography.body)
                    .foregroundStyle(PlantbillColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(PlantbillSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: PlantbillSpacing.cardCornerRadius, style: .continuous)
                .fill(PlantbillColor.greenTint.opacity(0.6))
        )
    }

    // MARK: Remarks

    private var remarksField: some View {
        VStack(alignment: .leading, spacing: PlantbillSpacing.xs) {
            Text("Remarks (optional)")
                .font(PlantbillTypography.caption)
                .foregroundStyle(PlantbillColor.textSecondary)
            TextField("", text: $viewModel.remarks, axis: .vertical)
                .lineLimit(2...5)
                .font(PlantbillTypography.body)
                .foregroundStyle(PlantbillColor.textPrimary)
                .focused($remarksFocused)
                .padding(PlantbillSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: PlantbillSpacing.controlCornerRadius)
                        .fill(PlantbillColor.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PlantbillSpacing.controlCornerRadius)
                        .stroke(remarksFocused ? PlantbillColor.green : PlantbillColor.border, lineWidth: remarksFocused ? 2 : 1)
                )
                .modifier(KeyboardDoneBar(isFocused: remarksFocused) { remarksFocused = false })
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(PlantbillTypography.bodyEmphasized)
            .foregroundStyle(PlantbillColor.textPrimary)
    }
}

/// One bill line — Android's layout: the name, the line total and a remove
/// button on top; the price box and the − Qty + stepper underneath.
private struct CartLineRow: View {
    let line: CartLine
    let onQuantityText: (String) -> Void
    let onPriceText: (String) -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    let onRemove: () -> Void

    /// Bound straight through to the view model rather than mirrored in local
    /// `@State`: the stepper mutates the line, and a local copy wouldn't see it.
    private var priceBinding: Binding<String> {
        Binding(get: { line.priceInput }, set: onPriceText)
    }
    private var quantityBinding: Binding<String> {
        Binding(get: { line.qtyInput }, set: onQuantityText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PlantbillSpacing.sm) {
            HStack(spacing: PlantbillSpacing.sm) {
                Text(verbatim: line.productName)
                    .font(PlantbillTypography.bodyEmphasized)
                    .foregroundStyle(PlantbillColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(line.lineTotal.format())
                    .font(PlantbillTypography.bodyEmphasized)
                    .foregroundStyle(PlantbillColor.textPrimary)
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(PlantbillColor.textSecondary)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove \(line.productName)"))
            }

            HStack(alignment: .bottom, spacing: PlantbillSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Price")
                        .font(PlantbillTypography.caption)
                        .foregroundStyle(PlantbillColor.textSecondary)
                    NumberBox(text: priceBinding, placeholder: "₹", keyboardType: .numberPad)
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: PlantbillSpacing.sm) {
                    stepperButton(systemName: "minus", enabled: line.quantity > 1, action: onDecrement)
                        .accessibilityLabel(Text("Decrease quantity for \(line.productName)"))
                    NumberBox(text: quantityBinding, placeholder: "Qty", keyboardType: .numberPad)
                        .frame(width: 72)
                    stepperButton(systemName: "plus", enabled: true, action: onIncrement)
                        .accessibilityLabel(Text("Increase quantity for \(line.productName)"))
                }
            }
        }
        .padding(.vertical, PlantbillSpacing.md)
    }

    /// `−` is disabled at 1 and below, as Android's stepper is — the remove
    /// button is the only way to take a line off.
    private func stepperButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(PlantbillColor.green)
                .frame(width: PlantbillSpacing.minTouchTarget, height: PlantbillSpacing.minTouchTarget + 8)
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
}

/// A compact bordered number box. Select-all on focus, so typing replaces the
/// value instead of inserting into it, and a Done bar because number pads have
/// no return key.
private struct NumberBox: View {
    @Binding var text: String
    let placeholder: LocalizedStringKey
    var keyboardType: UIKeyboardType = .numberPad

    @State private var isFocused = false

    var body: some View {
        ZStack {
            if text.isEmpty {
                Text(placeholder)
                    .font(PlantbillTypography.body)
                    .foregroundStyle(PlantbillColor.textSecondary)
                    .allowsHitTesting(false)
            }
            SelectAllTextField(
                text: $text,
                placeholder: "",
                keyboardType: keyboardType,
                textAlignment: .center,
                font: .systemFont(ofSize: 20, weight: .semibold),
                onFocusChange: { isFocused = $0 }
            )
            .frame(maxHeight: .infinity)
            .padding(.horizontal, PlantbillSpacing.xs)
        }
        .frame(height: PlantbillSpacing.minTouchTarget + 8)
        .background(
            RoundedRectangle(cornerRadius: PlantbillSpacing.controlCornerRadius)
                .fill(PlantbillColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PlantbillSpacing.controlCornerRadius)
                .stroke(isFocused ? PlantbillColor.green : PlantbillColor.border, lineWidth: isFocused ? 2 : 1)
        )
    }
}
