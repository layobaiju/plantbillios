import SwiftUI

/// "Your trial ended — here's how to keep going." Two buttons, both automated:
/// Call opens the dialler with our number already in it, Email opens Mail with
/// the whole message already written so the shop owner only presses Send.
///
/// Nothing here asks the user to type a payment detail or copy a number by
/// hand. The audience is elderly shop owners who have just found their till
/// gone read-only mid-day; the fewest possible steps between that moment and
/// us picking up the phone is the whole design.
struct TrialContinueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var trial = TrialStore.shared

    /// Set when a link couldn't be opened and we put the contact on the
    /// clipboard instead, so the button never silently does nothing.
    @State private var notice: String?

    private var shopName: String? {
        BusinessProfile.shared.businessName ?? BusinessProfile.shared.shopName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PlantbillSpacing.lg) {
                    header

                    VStack(spacing: PlantbillSpacing.md) {
                        PrimaryButton(title: "Call us", systemImage: "phone.fill") {
                            SupportContact.call { opened in
                                if !opened { copy(SupportContact.phoneDisplay, label: "number") }
                            }
                        }

                        SecondaryButton(title: "Email us", systemImage: "envelope.fill") {
                            SupportContact.email(
                                subject: "Plantbill — continue after my free trial",
                                body: SupportContact.continueAccessBody(
                                    shopName: shopName,
                                    accountEmail: trial.accountEmail
                                )
                            ) { opened in
                                if !opened { copy(SupportContact.email, label: "email") }
                            }
                        }

                        SecondaryButton(title: "WhatsApp", systemImage: "message.fill") {
                            SupportContact.whatsApp { opened in
                                if !opened { copy(SupportContact.phoneDisplay, label: "number") }
                            }
                        }
                    }

                    if let notice {
                        Text(notice)
                            .font(PlantbillTypography.body)
                            .foregroundStyle(PlantbillColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    reassurance
                }
                .padding(PlantbillSpacing.lg)
            }
            .background(PlantbillColor.background)
            .navigationTitle(trial.isLocked ? "Trial ended" : "Keep using Plantbill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PlantbillSpacing.sm) {
            Image(systemName: trial.isLocked ? "lock.fill" : "clock.fill")
                .font(.system(size: 36))
                .foregroundStyle(trial.isLocked ? PlantbillColor.error : PlantbillColor.warning)

            Text(headline)
                .font(PlantbillTypography.title)
                .foregroundStyle(PlantbillColor.textPrimary)

            Text(explanation)
                .font(PlantbillTypography.body)
                .foregroundStyle(PlantbillColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headline: LocalizedStringKey {
        if trial.isLocked { return "Your free trial has ended" }
        guard let days = trial.daysLeft else { return "Keep using Plantbill" }
        if days == 0 { return "Your free trial ends today" }
        return days == 1 ? "1 day left in your free trial" : "\(days) days left in your free trial"
    }

    private var explanation: LocalizedStringKey {
        trial.isLocked
            ? "Everything you entered is still here and you can still look at all of it. To start making bills again, talk to us and we'll set up your plan."
            : "When the trial ends you'll still be able to see all your data, but making bills and adding items will stop. Talk to us before then and nothing changes."
    }

    private var reassurance: some View {
        PlantbillCard {
            VStack(alignment: .leading, spacing: PlantbillSpacing.xs) {
                Label("Nothing is deleted", systemImage: "checkmark.shield.fill")
                    .font(PlantbillTypography.bodyEmphasized)
                    .foregroundStyle(PlantbillColor.green)
                Text("Your bills, items, customers and day book stay exactly as they are.")
                    .font(PlantbillTypography.body)
                    .foregroundStyle(PlantbillColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func copy(_ value: String, label: String) {
        UIPasteboard.general.string = value
        notice = "We couldn't open that on this phone, so we copied our \(label): \(value)"
    }
}
