import SwiftUI

struct FilterChip: View {
    private let title: Text
    let isSelected: Bool
    let action: () -> Void

    init(title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) {
        self.title = Text(title)
        self.isSelected = isSelected
        self.action = action
    }

    /// For shop data — a category the owner typed in — which must show exactly
    /// as written and never be looked up as a translation key.
    init(verbatim title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = Text(verbatim: title)
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            title
                .font(PlantbillTypography.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, PlantbillSpacing.md)
                .padding(.vertical, PlantbillSpacing.sm)
                .foregroundStyle(isSelected ? .white : PlantbillColor.textPrimary)
                .background(
                    Capsule().fill(isSelected ? PlantbillColor.green : PlantbillColor.surface)
                )
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : PlantbillColor.border, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        // Without an explicit style, multiple sibling chips inside one List
        // row can mis-route taps to the wrong chip (List applies its own
        // button-handling to unstyled Buttons) — same root cause as the
        // date-selector chevron bug. `.plain` keeps each chip independent.
        .buttonStyle(.plain)
    }
}
