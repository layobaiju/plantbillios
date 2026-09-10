import SwiftUI

/// The line that says a screen is showing the copy saved on this phone, and
/// when it was saved. Sits at the top of Sales, Customers and the detail
/// screens whenever the server couldn't be reached.
///
/// The time is the whole point: a shop owner looking at a total with no
/// internet has to know it's "as of 3:42 PM", not live — sales made on another
/// phone since then aren't in it.
struct SavedCopyNote: View {
    enum Kind {
        case sales, customers, customer, bill, dues
    }

    let kind: Kind
    let savedAt: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PlantbillSpacing.sm) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 14, weight: .semibold))
            message
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(PlantbillTypography.caption)
        .foregroundStyle(PlantbillColor.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PlantbillSpacing.md)
        .padding(.vertical, PlantbillSpacing.sm)
        .background(PlantbillColor.warning.opacity(0.18))
        .accessibilityElement(children: .combine)
    }

    private var message: Text {
        let time = Self.format(savedAt)
        switch kind {
        case .sales: return Text("No internet. Showing sales saved at \(time).")
        case .customers: return Text("No internet. Showing customers saved at \(time).")
        case .customer: return Text("No internet. Showing this customer as saved at \(time).")
        case .bill: return Text("No internet. Showing this bill as saved at \(time).")
        case .dues: return Text("No internet. Showing dues saved at \(time).")
        }
    }

    /// "3:42 PM" today, "9 Sep, 3:42 PM" for anything older.
    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "h:mm a" : "d MMM, h:mm a"
        return formatter.string(from: date)
    }
}

extension View {
    /// Pins the saved-copy line above a screen's content while `savedAt` is set.
    func savedCopyNote(_ kind: SavedCopyNote.Kind, savedAt: Date?) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if let savedAt {
                SavedCopyNote(kind: kind, savedAt: savedAt)
            }
        }
    }
}
