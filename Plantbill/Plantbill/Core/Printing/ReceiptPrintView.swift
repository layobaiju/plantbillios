import SwiftUI

/// The printed receipt, laid out like Android's `ReceiptRenderer` and sized in
/// printer dots: 384 wide (58mm paper) with Android's text sizes, so a bill
/// comes out of the printer looking the same from either phone. Plain black on
/// white — a receipt, not a screen — and in English on paper, as Android's is.
struct ReceiptPrintView: View {
    let data: ReceiptPrintData

    private let width: CGFloat = 384

    // Android's paints, in dots.
    private let bodySize: CGFloat = 28
    private let smallSize: CGFloat = 24
    private let headerSize: CGFloat = 46
    private let totalSize: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let logo = data.logo {
                // Never upscaled, and never so tall it pushes the bill off the paper.
                Image(uiImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: min(width, logo.size.width), maxHeight: min(200, logo.size.height))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
            }

            para(data.businessName, size: headerSize, bold: true, center: true)
            if let address = nonBlank(data.businessAddress) {
                para(address, size: smallSize, center: true)
            }
            if let phone = nonBlank(data.businessPhone) {
                para("Contact: \(phone)", size: smallSize, center: true)
            }
            divider

            para("Bill: #\(data.billNumber)", size: smallSize)
            para("Date: \(Self.dateFormatter.string(from: data.createdAt))", size: smallSize)
            if let staff = data.staffEmail {
                para("Staff: \(staff)", size: smallSize)
            }
            if let name = data.customerName {
                para("Customer: " + (data.customerPhone.map { "\(name) (\($0))" } ?? name), size: smallSize)
            }
            if let remarks = nonBlank(data.remarks) {
                para("Remarks: \(remarks)", size: smallSize)
            }
            divider

            ForEach(Array(data.items.enumerated()), id: \.offset) { _, item in
                para(item.name, size: bodySize, bold: true)
                twoColumn("  \(item.quantity) x \(money(item.unitPrice))", money(item.lineTotal), size: bodySize)
            }
            divider

            twoColumn("Subtotal", money(data.subtotal), size: bodySize)
            if data.discountAmount.isPositive {
                twoColumn(data.discountLabel, "-\(money(data.discountAmount))", size: bodySize)
            }
            divider
            twoColumn("TOTAL", money(data.total), size: totalSize, bold: true)
            divider

            if data.cashAmount.isPositive { twoColumn("Paid via Cash", money(data.cashAmount), size: bodySize) }
            if data.upiAmount.isPositive { twoColumn("Paid via UPI", money(data.upiAmount), size: bodySize) }
            if data.dueAmount.isPositive { twoColumn("Remaining Due", money(data.dueAmount), size: bodySize) }
            if !data.cashAmount.isPositive && !data.upiAmount.isPositive && !data.dueAmount.isPositive {
                twoColumn("Paid via Cash", money(.zero), size: bodySize)
            }
            divider

            Spacer().frame(height: 8)
            para("Thank you for shopping with us!", size: smallSize, center: true)
            para("Please visit us again.", size: smallSize, center: true)
        }
        .foregroundStyle(.black)
        .padding(.top, 16)
        .padding(.bottom, 40)
        .frame(width: width)
        .background(Color.white)
    }

    private func para(_ text: String, size: CGFloat, bold: Bool = false, center: Bool = false) -> some View {
        Text(verbatim: text)
            .font(.system(size: size, weight: bold ? .bold : .regular))
            .multilineTextAlignment(center ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: center ? .center : .leading)
            .padding(.bottom, 6)
    }

    /// A label on the left and a right-aligned amount.
    private func twoColumn(_ left: String, _ right: String, size: CGFloat, bold: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: left)
                .font(.system(size: size, weight: bold ? .bold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Text(verbatim: right)
                .font(.system(size: size, weight: bold ? .bold : .regular))
                .lineLimit(1)
        }
        .padding(.bottom, 6)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.black)
            .frame(height: 2)
            .padding(.vertical, 8)
    }

    private func money(_ value: Money) -> String {
        "₹" + value.toWire()
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Android's "d MMM yyyy, h:mm a" in English, in the shop's time zone.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        formatter.dateFormat = "d MMM yyyy, h:mm a"
        return formatter
    }()
}
