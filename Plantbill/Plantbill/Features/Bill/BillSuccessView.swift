import SwiftUI

/// After a save — Android's `SuccessView`: the tick, "Bill saved", the total,
/// the customer, then Print receipt as the main action and New bill beneath it.
struct BillSuccessView: View {
    let bill: BillOut
    let onNewBill: () -> Void

    @State private var isPreparingPrint = false
    @State private var hasPrinted = false
    @State private var printFailed = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(PlantbillColor.green)

            Text(bill.idempotentReplay ? "Bill already saved" : "Bill saved")
                .font(PlantbillTypography.title)
                .foregroundStyle(PlantbillColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, PlantbillSpacing.lg)

            Text(Money.parse(bill.total).format())
                .font(PlantbillTypography.largeTitle)
                .foregroundStyle(PlantbillColor.textPrimary)
                .padding(.top, PlantbillSpacing.sm)

            if let customerName = bill.customerName, !customerName.isEmpty {
                Text(verbatim: customerName)
                    .font(PlantbillTypography.body)
                    .foregroundStyle(PlantbillColor.textSecondary)
                    .padding(.top, PlantbillSpacing.xs)
            }

            Spacer().frame(height: PlantbillSpacing.xxl)

            PrimaryButton(
                title: hasPrinted ? "Print again" : "Print receipt",
                systemImage: "printer.fill",
                isLoading: isPreparingPrint
            ) {
                printReceipt()
            }

            if printFailed {
                Text("Printing failed.")
                    .font(PlantbillTypography.body)
                    .foregroundStyle(PlantbillColor.error)
                    .multilineTextAlignment(.center)
                    .padding(.top, PlantbillSpacing.sm)
            }

            SecondaryButton(title: "New bill", action: onNewBill)
                .padding(.top, PlantbillSpacing.md)

            Spacer()
        }
        .padding(PlantbillSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PlantbillColor.background)
    }

    private func printReceipt() {
        isPreparingPrint = true
        printFailed = false
        Task {
            let data = await ReceiptPrinter.receipt(forBillId: bill.id, fallback: bill.receiptData)
            isPreparingPrint = false
            ReceiptPrinter.print(data) { printed, failed in
                if printed { hasPrinted = true }
                printFailed = failed
            }
        }
    }
}
