import SwiftUI
import UIKit

struct OwnerShopDetailView: View {
    let shopId: UUID
    let shopName: String

    @StateObject private var viewModel: OwnerShopDetailViewModel
    @State private var pendingStaffDelete: OwnerStaff?
    @State private var pendingStaffReset: OwnerStaff?

    init(shopId: UUID, shopName: String) {
        self.shopId = shopId
        self.shopName = shopName
        _viewModel = StateObject(wrappedValue: OwnerShopDetailViewModel(shopId: shopId))
    }

    var body: some View {
        List {
            Section {
                OwnerPeriodSelector(period: $viewModel.period, customFrom: $viewModel.customFrom, customTo: $viewModel.customTo)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            // Cash in hand is the number the owner opens this screen for, so it
            // sits outside the report block — it comes from its own endpoint
            // and must not disappear when the report is empty, slow or failed.
            Section {
                cashInHandCard
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            if let report = viewModel.report {
                Section {
                    HStack(spacing: PlantbillSpacing.sm) {
                        kpiCard("Sales", report.totalSalesMoney.format())
                        kpiCard("Expenses", report.totalExpensesMoney.formatOutgoing())
                        kpiCard("Net", report.netSalesMoney.format(), tint: PlantbillColor.green)
                    }
                    HStack(spacing: PlantbillSpacing.sm) {
                        kpiCard("Cash", report.cashTotalMoney.format())
                        kpiCard("UPI", report.upiTotalMoney.format())
                        kpiCard("Due", report.dueTotalMoney.format(), tint: report.dueTotalMoney.isPositive ? PlantbillColor.error : PlantbillColor.textPrimary)
                    }

                    if !report.expenses.isEmpty {
                        Text("Expenses")
                            .font(PlantbillTypography.headline)
                            .foregroundStyle(PlantbillColor.textPrimary)
                        ForEach(report.expenses) { e in
                            HStack {
                                Text(e.title).font(PlantbillTypography.body).foregroundStyle(PlantbillColor.textPrimary)
                                Spacer()
                                Text(e.amountMoney.formatOutgoing()).font(PlantbillTypography.body).foregroundStyle(PlantbillColor.error)
                            }
                        }
                    }

                    if !report.topProducts.isEmpty {
                        Text("Top products")
                            .font(PlantbillTypography.headline)
                            .foregroundStyle(PlantbillColor.textPrimary)
                        ForEach(report.topProducts.prefix(8)) { p in
                            HStack {
                                Text("\(p.productName) × \(p.quantity)").font(PlantbillTypography.body).foregroundStyle(PlantbillColor.textPrimary)
                                Spacer()
                                Text(p.totalSalesMoney.format()).font(PlantbillTypography.body).foregroundStyle(PlantbillColor.textPrimary)
                            }
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            Section {
                Text("Bills")
                    .font(PlantbillTypography.headline)
                    .foregroundStyle(PlantbillColor.textPrimary)
                if viewModel.billsLoading && viewModel.bills.isEmpty {
                    Text("Loading bills…").font(PlantbillTypography.body).foregroundStyle(PlantbillColor.textSecondary)
                } else if viewModel.bills.isEmpty {
                    Text("No bills in this period.").font(PlantbillTypography.body).foregroundStyle(PlantbillColor.textSecondary)
                } else {
                    ForEach(viewModel.bills) { bill in
                        OwnerBillRowView(bill: bill) { viewModel.openBill(bill.id) }
                    }
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                Text("Labour")
                    .font(PlantbillTypography.headline)
                    .foregroundStyle(PlantbillColor.textPrimary)
                if viewModel.labourers.isEmpty {
                    Text("No workers on this shop's roster.").font(PlantbillTypography.body).foregroundStyle(PlantbillColor.textSecondary)
                } else {
                    ForEach(viewModel.labourers) { l in
                        OwnerLabourerRowView(labourer: l) { viewModel.openLabourer(l) }
                    }
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                Text("Business details")
                    .font(PlantbillTypography.headline)
                    .foregroundStyle(PlantbillColor.textPrimary)
                BusinessDetailsCard(viewModel: viewModel)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                Text("Staff")
                    .font(PlantbillTypography.headline)
                    .foregroundStyle(PlantbillColor.textPrimary)
                ForEach(viewModel.staff) { s in
                    OwnerStaffRowView(
                        staff: s,
                        onResetPassword: { pendingStaffReset = s },
                        onRemove: { pendingStaffDelete = s }
                    )
                }
                AddStaffCard(viewModel: viewModel)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PlantbillColor.background)
        .navigationTitle(shopName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.onAppear() }
        .alert("Something went wrong", isPresented: Binding(
            get: { viewModel.message != nil },
            set: { if !$0 { viewModel.dismissMessage() } }
        )) {
            Button("OK") { viewModel.dismissMessage() }
        } message: {
            Text(viewModel.message ?? "")
        }
        .sheet(isPresented: Binding(get: { viewModel.labourerDetail != nil }, set: { if !$0 { viewModel.closeLabourer() } })) {
            OwnerLabourerDetailSheet(viewModel: viewModel)
        }
        .sheet(isPresented: Binding(get: { viewModel.billDetail != nil }, set: { if !$0 { viewModel.closeBill() } })) {
            OwnerBillDetailSheet(viewModel: viewModel)
        }
        // Android gates this behind TypeEmailToDeleteDialog rather than a
        // one-tap confirm, so a mis-tap can't remove the wrong account.
        .sheet(item: $pendingStaffDelete) { staff in
            TypeEmailToDeleteSheet(
                email: staff.email,
                title: "Remove staff?",
                message: "\(staff.email) will lose access to this shop immediately. This can't be undone.",
                confirmLabel: "Delete account"
            ) {
                Task { await viewModel.deleteStaff(staff) }
            }
        }
        .sheet(item: $pendingStaffReset) { staff in
            ResetStaffPasswordSheet(staff: staff, viewModel: viewModel)
        }
        .alert("Password reset", isPresented: Binding(
            get: { viewModel.resetResult != nil },
            set: { if !$0 { viewModel.dismissResetResult() } }
        )) {
            Button("Copy") {
                if let r = viewModel.resetResult {
                    UIPasteboard.general.string = "\(r.email)\n\(r.password)"
                }
                viewModel.dismissResetResult()
            }
            Button("Done", role: .cancel) { viewModel.dismissResetResult() }
        } message: {
            if let r = viewModel.resetResult {
                Text("Share these securely — they won't be shown again.\n\nEmail: \(r.email)\nPassword: \(r.password)")
            }
        }
    }

    private var cashInHandCard: some View {
        PlantbillCard {
            VStack(alignment: .leading, spacing: PlantbillSpacing.sm) {
                Text("Cash in hand")
                    .font(PlantbillTypography.caption)
                    .foregroundStyle(PlantbillColor.textSecondary)
                Text((viewModel.cashFull ? viewModel.cashInHand?.runningMoney : viewModel.cashInHand?.todayMoney)?.format() ?? Money.zero.format())
                    .font(PlantbillTypography.title)
                    .foregroundStyle(PlantbillColor.green)
                HStack(spacing: PlantbillSpacing.sm) {
                    FilterChip(title: "All time", isSelected: viewModel.cashFull) { viewModel.cashFull = true }
                    FilterChip(title: "This day", isSelected: !viewModel.cashFull) { viewModel.cashFull = false }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func kpiCard(_ title: LocalizedStringKey, _ value: String, tint: Color = PlantbillColor.textPrimary) -> some View {
        PlantbillCard {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(PlantbillTypography.caption).foregroundStyle(PlantbillColor.textSecondary)
                Text(value).font(PlantbillTypography.bodyEmphasized).foregroundStyle(tint).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private func ownerGenderLabel(_ gender: String) -> String { gender == "female" ? "Female" : "Male" }

private func ownerPaymentLabel(_ method: String) -> String {
    switch method.lowercased() {
    case "cash": return "Cash"
    case "upi": return "UPI"
    case "split": return "Split"
    case "due": return "Due"
    default: return method
    }
}

private struct OwnerBillRowView: View {
    let bill: OwnerBillRow
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            PlantbillCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bill.customerName?.isEmpty == false ? bill.customerName! : "Walk-in customer")
                            .font(PlantbillTypography.bodyEmphasized)
                            .foregroundStyle(PlantbillColor.textPrimary)
                        Text("\(ShopCalendar.billTime(bill.createdAt)) • \(bill.salespersonEmail?.components(separatedBy: "@").first ?? "Unknown")")
                            .font(PlantbillTypography.caption)
                            .foregroundStyle(PlantbillColor.textSecondary)
                        Text("\(bill.itemCount) item\(bill.itemCount == 1 ? "" : "s") • \(ownerPaymentLabel(bill.paymentMethod))" + (bill.dueAmountMoney.isPositive ? " • Due \(bill.dueAmountMoney.format())" : ""))
                            .font(PlantbillTypography.caption)
                            .foregroundStyle(bill.dueAmountMoney.isPositive ? PlantbillColor.error : PlantbillColor.textSecondary)
                    }
                    Spacer()
                    Text(bill.totalMoney.format())
                        .font(PlantbillTypography.bodyEmphasized)
                        .foregroundStyle(PlantbillColor.green)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct OwnerLabourerRowView: View {
    let labourer: Labourer
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            PlantbillCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(labourer.name)
                            .font(PlantbillTypography.bodyEmphasized)
                            .foregroundStyle(PlantbillColor.textPrimary)
                        Text([ownerGenderLabel(labourer.gender), "\(labourer.defaultWageMoney.format())/day", "\(labourer.daysWorked) days", labourer.phone].compactMap { $0 }.joined(separator: " • "))
                            .font(PlantbillTypography.caption)
                            .foregroundStyle(PlantbillColor.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text((labourer.balanceToPayMoney.isNegative ? Money.zero - labourer.balanceToPayMoney : labourer.balanceToPayMoney).format())
                            .font(PlantbillTypography.bodyEmphasized)
                            .foregroundStyle(labourer.balanceToPayMoney.isPositive ? PlantbillColor.error : (labourer.balanceToPayMoney.isNegative ? PlantbillColor.green : PlantbillColor.textPrimary))
                        Text(labourer.balanceToPayMoney.isNegative ? "Paid ahead" : "To pay")
                            .font(PlantbillTypography.caption)
                            .foregroundStyle(PlantbillColor.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct OwnerStaffRowView: View {
    let staff: OwnerStaff
    let onResetPassword: () -> Void
    let onRemove: () -> Void

    var body: some View {
        PlantbillCard {
            VStack(alignment: .leading, spacing: PlantbillSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(staff.email)
                        .font(PlantbillTypography.bodyEmphasized)
                        .foregroundStyle(PlantbillColor.textPrimary)
                    Text("\(roleLabel(staff.role)) • \(staff.isActive ? "Active" : "Inactive")")
                        .font(PlantbillTypography.caption)
                        .foregroundStyle(PlantbillColor.textSecondary)
                }
                // Laid out as full-width buttons rather than hidden behind a
                // "…" menu: the audience is older shop owners, and the design
                // brief calls for obvious affordances and 48pt touch targets.
                HStack(spacing: PlantbillSpacing.sm) {
                    Button(action: onResetPassword) {
                        Text("Reset password")
                            .font(PlantbillTypography.caption)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: PlantbillSpacing.minTouchTarget)
                            .foregroundStyle(PlantbillColor.green)
                            .background(
                                RoundedRectangle(cornerRadius: PlantbillSpacing.controlCornerRadius)
                                    .stroke(PlantbillColor.green, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onRemove) {
                        Text("Remove")
                            .font(PlantbillTypography.caption)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: PlantbillSpacing.minTouchTarget)
                            .foregroundStyle(PlantbillColor.error)
                            .background(
                                RoundedRectangle(cornerRadius: PlantbillSpacing.controlCornerRadius)
                                    .stroke(PlantbillColor.error, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Owner-side password reset. The new password is shown once afterwards so the
/// owner can pass it on — the server keeps only a hash.
private struct ResetStaffPasswordSheet: View {
    let staff: OwnerStaff
    @ObservedObject var viewModel: OwnerShopDetailViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: PlantbillSpacing.lg) {
                Text("Set a new password for \(staff.email). Write it down — it's shown only once.")
                    .font(PlantbillTypography.body)
                    .foregroundStyle(PlantbillColor.textPrimary)

                PlantbillTextField(label: "New password (8+ characters)", text: $password, placeholder: "")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecondaryButton(title: "Suggest a strong password") {
                    password = Self.suggestPassword()
                }

                PrimaryButton(title: "Reset password", isDisabled: password.count < 8) {
                    Task {
                        await viewModel.resetStaffPassword(staff, newPassword: password)
                        dismiss()
                    }
                }

                SecondaryButton(title: "Cancel") { dismiss() }
                Spacer()
            }
            .padding(PlantbillSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PlantbillColor.background)
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Ambiguous characters left out — these get read aloud and copied by hand.
    private static func suggestPassword() -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<12).map { _ in alphabet.randomElement()! })
    }
}

/// What prints on this shop's bills and what customers pay into. Editable by
/// the owner — this is the only place a multi-shop owner can set it per shop.
private struct BusinessDetailsCard: View {
    @ObservedObject var viewModel: OwnerShopDetailViewModel

    var body: some View {
        PlantbillCard {
            VStack(alignment: .leading, spacing: PlantbillSpacing.sm) {
                field("Business name", text: $viewModel.businessForm.name, placeholder: "Shown on bills")
                field("Address", text: $viewModel.businessForm.address, placeholder: "Shop address")
                field("Phone", text: $viewModel.businessForm.phone, placeholder: "Business phone", keyboard: .phonePad)
                field("Email", text: $viewModel.businessForm.email, placeholder: "Business email", keyboard: .emailAddress)
                field("UPI ID", text: $viewModel.businessForm.upi, placeholder: "name@bank — used for the payment QR")

                PrimaryButton(
                    title: "Save business details",
                    isLoading: viewModel.savingProfile,
                    isDisabled: viewModel.savingProfile || !viewModel.profileEdited
                ) {
                    Task { await viewModel.saveShopProfile() }
                }
            }
        }
    }

    @ViewBuilder
    private func field(
        _ label: LocalizedStringKey,
        text: Binding<String>,
        placeholder: LocalizedStringKey,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        PlantbillTextField(
            label: label,
            // Any keystroke marks the form dirty, so a background refresh
            // can't overwrite what's being typed.
            text: Binding(get: { text.wrappedValue }, set: { newValue in
                text.wrappedValue = newValue
                viewModel.profileEdited = true
            }),
            placeholder: placeholder,
            keyboardType: keyboard
        )
    }
}

private struct AddStaffCard: View {
    @ObservedObject var viewModel: OwnerShopDetailViewModel

    var body: some View {
        PlantbillCard {
            VStack(alignment: .leading, spacing: PlantbillSpacing.sm) {
                Text("Add staff")
                    .font(PlantbillTypography.bodyEmphasized)
                    .foregroundStyle(PlantbillColor.textPrimary)
                PlantbillTextField(label: "Login email", text: $viewModel.newStaff.email, placeholder: "you@example.com", keyboardType: .emailAddress)
                PlantbillTextField(label: "Password (8+ characters)", text: $viewModel.newStaff.password)
                // Salesperson only — a manager account is created by the
                // platform admin along with the shop, not added here.
                if let error = viewModel.newStaff.error {
                    InlineErrorText(message: LocalizedStringKey(error))
                }
                PrimaryButton(title: "Add staff", isLoading: viewModel.newStaff.saving, isDisabled: !viewModel.newStaff.canSave) {
                    Task { await viewModel.addStaff() }
                }
            }
        }
    }
}

private struct OwnerLabourerDetailSheet: View {
    @ObservedObject var viewModel: OwnerShopDetailViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                if let d = viewModel.labourerDetail {
                    let l = d.labourer
                    VStack(alignment: .leading, spacing: PlantbillSpacing.md) {
                        Text(l.name).font(PlantbillTypography.headline).foregroundStyle(PlantbillColor.textPrimary)
                        Text([ownerGenderLabel(l.gender), l.phone, l.aadhaar].compactMap { $0 }.joined(separator: " • "))
                            .font(PlantbillTypography.body)
                            .foregroundStyle(PlantbillColor.textSecondary)

                        statementRow("Days worked", l.daysWorked)
                        Divider()
                        statementRow("Earned (\(l.defaultWageMoney.format())/day)", l.earnedMoney.format())
                        Divider()
                        statementRow("Total paid", l.totalPaidMoney.format())
                        Divider()
                        HStack {
                            Text(l.balanceToPayMoney.isNegative ? "Paid ahead" : "Balance to pay")
                                .font(PlantbillTypography.bodyEmphasized)
                                .foregroundStyle(PlantbillColor.textPrimary)
                            Spacer()
                            Text((l.balanceToPayMoney.isNegative ? Money.zero - l.balanceToPayMoney : l.balanceToPayMoney).format())
                                .font(PlantbillTypography.headline)
                                .foregroundStyle(l.balanceToPayMoney.isPositive ? PlantbillColor.error : (l.balanceToPayMoney.isNegative ? PlantbillColor.green : PlantbillColor.textPrimary))
                        }

                        Text("Payment history")
                            .font(PlantbillTypography.bodyEmphasized)
                            .foregroundStyle(PlantbillColor.textPrimary)
                        if d.loading {
                            LoadingStateView(message: "Loading…").frame(height: 100)
                        } else if d.payments.isEmpty {
                            Text("No payments recorded yet.").font(PlantbillTypography.body).foregroundStyle(PlantbillColor.textSecondary)
                        } else {
                            ForEach(d.payments.prefix(50)) { p in
                                HStack {
                                    Text("\(ShopCalendar.billTime(p.createdAt)) • \(ownerPaymentLabel(p.paymentMethod.rawValue))")
                                        .font(PlantbillTypography.body)
                                        .foregroundStyle(PlantbillColor.textPrimary)
                                    Spacer()
                                    Text(p.totalAmountMoney.format())
                                        .font(PlantbillTypography.bodyEmphasized)
                                        .foregroundStyle(PlantbillColor.textPrimary)
                                }
                            }
                        }
                    }
                    .padding(PlantbillSpacing.lg)
                }
            }
            .background(PlantbillColor.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { viewModel.closeLabourer() }
                }
            }
        }
    }

    private func statementRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label).font(PlantbillTypography.body).foregroundStyle(PlantbillColor.textSecondary)
            Spacer()
            Text(value).font(PlantbillTypography.bodyEmphasized).foregroundStyle(PlantbillColor.textPrimary)
        }
    }
}

private struct OwnerBillDetailSheet: View {
    @ObservedObject var viewModel: OwnerShopDetailViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                if let state = viewModel.billDetail {
                    if state.loading || state.bill == nil {
                        LoadingStateView(message: "Loading bill…").frame(height: 200)
                    } else if let bill = state.bill {
                        VStack(alignment: .leading, spacing: PlantbillSpacing.md) {
                            Text("\(ShopCalendar.billTime(bill.createdAt)) • \(bill.salespersonEmail?.components(separatedBy: "@").first ?? "Unknown")" + (bill.isEdited ? " • Edited" : ""))
                                .font(PlantbillTypography.body)
                                .foregroundStyle(PlantbillColor.textSecondary)
                            Text(bill.customerName?.isEmpty == false ? bill.customerName! : "Walk-in customer")
                                .font(PlantbillTypography.headline)
                                .foregroundStyle(PlantbillColor.textPrimary)
                            if let phone = bill.customerPhone, !phone.isEmpty {
                                Text(phone).font(PlantbillTypography.body).foregroundStyle(PlantbillColor.textSecondary)
                            }

                            ForEach(bill.items) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.productName).font(PlantbillTypography.body).foregroundStyle(PlantbillColor.textPrimary)
                                        Text("\(item.unitPriceMoney.format()) × \(item.quantity)").font(PlantbillTypography.caption).foregroundStyle(PlantbillColor.textSecondary)
                                    }
                                    Spacer()
                                    Text(item.lineTotalMoney.format()).font(PlantbillTypography.body).foregroundStyle(PlantbillColor.textPrimary)
                                }
                            }

                            Divider()
                            row("Subtotal", bill.subtotalMoney)
                            if bill.discountAmountMoney.isPositive { row("Discount", Money.zero - bill.discountAmountMoney) }
                            row("Total", bill.totalMoney, emphasized: true)
                            if bill.cashAmountMoney.isPositive { row("Cash", bill.cashAmountMoney) }
                            if bill.upiAmountMoney.isPositive { row("UPI", bill.upiAmountMoney) }
                            if bill.dueAmountMoney.isPositive { row("Due", bill.dueAmountMoney, tint: PlantbillColor.error) }
                            if let remarks = bill.remarks, !remarks.isEmpty {
                                Text(remarks).font(PlantbillTypography.body).foregroundStyle(PlantbillColor.textSecondary)
                            }
                        }
                        .padding(PlantbillSpacing.lg)
                    }
                }
            }
            .background(PlantbillColor.background)
            .navigationTitle("Bill details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { viewModel.closeBill() }
                }
            }
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: Money, emphasized: Bool = false, tint: Color = PlantbillColor.textPrimary) -> some View {
        HStack {
            Text(label)
                .font(emphasized ? PlantbillTypography.headline : PlantbillTypography.body)
                .foregroundStyle(emphasized ? PlantbillColor.textPrimary : PlantbillColor.textSecondary)
            Spacer()
            Text(value.format())
                .font(emphasized ? PlantbillTypography.headline : PlantbillTypography.body)
                .foregroundStyle(tint)
        }
    }
}
