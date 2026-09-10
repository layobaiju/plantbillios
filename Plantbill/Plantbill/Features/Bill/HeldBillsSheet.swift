import SwiftUI

/// Bills parked to serve another customer — Android's `HeldBillsSheet`: who
/// it's for, how many items, the total and when it was held, with Discard and
/// "Resume this bill".
struct HeldBillsSheet: View {
    @ObservedObject var viewModel: BillingViewModel
    let onResume: (HeldBill) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PlantbillSpacing.md) {
                    Text("Bills you parked to serve another customer. Tap Resume to continue one.")
                        .font(PlantbillTypography.body)
                        .foregroundStyle(PlantbillColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(viewModel.heldBills) { held in
                        HeldBillCard(
                            held: held,
                            onResume: { onResume(held) },
                            onDiscard: { viewModel.discardHeld(held) }
                        )
                    }
                }
                .padding(PlantbillSpacing.lg)
            }
            .background(PlantbillColor.background)
            .navigationTitle("Held bills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            // Nothing left to resume once the last one is discarded.
            .onChange(of: viewModel.heldBills.isEmpty) { isEmpty in
                if isEmpty { dismiss() }
            }
        }
    }
}

private struct HeldBillCard: View {
    let held: HeldBill
    let onResume: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        PlantbillCard {
            VStack(alignment: .leading, spacing: PlantbillSpacing.sm) {
                HStack(alignment: .top, spacing: PlantbillSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        label
                            .font(PlantbillTypography.bodyEmphasized)
                            .foregroundStyle(PlantbillColor.textPrimary)
                        (itemCountText + Text(verbatim: " • \(held.displayTotal.format()) • \(Self.timeFormatter.string(from: held.savedAt))"))
                            .font(PlantbillTypography.caption)
                            .foregroundStyle(PlantbillColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: onDiscard) {
                        Text("Discard")
                            .font(PlantbillTypography.bodyEmphasized)
                            .foregroundStyle(PlantbillColor.error)
                            .frame(minHeight: PlantbillSpacing.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                PrimaryButton(title: "Resume this bill", action: onResume)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var label: Text {
        held.customerName.trimmingCharacters(in: .whitespaces).isEmpty
            ? Text("Walk-in customer")
            : Text(verbatim: held.customerName)
    }

    private var itemCountText: Text {
        held.displayItemCount == 1 ? Text("1 item") : Text("\(held.displayItemCount) items")
    }

    /// Android's "d MMM, h:mm a".
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM, h:mm a"
        return formatter
    }()
}
