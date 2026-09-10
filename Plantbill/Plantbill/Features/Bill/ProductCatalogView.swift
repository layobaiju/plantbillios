import SwiftUI

/// Blocks or a compact list — Android's `ProductViewMode`. Stored per device,
/// outside the bill: Android found that a layout setting kept in the bill's
/// state silently reset after every sale.
enum ProductViewMode: String {
    case grid, list
}

/// The billing catalogue in either layout, mirroring Android's
/// `ProductCatalog(addable = true)`: two fixed columns of photo blocks, or a
/// compact list, each carrying the "+" that tells the salesperson a tap puts
/// the plant on the bill.
struct ProductCatalogView: View {
    let products: [Product]
    let viewMode: ProductViewMode
    let onTap: (Product) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: PlantbillSpacing.md),
        GridItem(.flexible(), spacing: PlantbillSpacing.md),
    ]

    var body: some View {
        ScrollView {
            switch viewMode {
            case .grid:
                LazyVGrid(columns: columns, spacing: PlantbillSpacing.md) {
                    ForEach(products) { product in
                        Button { onTap(product) } label: { ProductBlock(product: product) }
                            .buttonStyle(ProductPressStyle())
                            .accessibilityLabel(Text("Add \(product.name)"))
                    }
                }
                .padding(PlantbillSpacing.md)
            case .list:
                LazyVStack(spacing: PlantbillSpacing.md) {
                    ForEach(products) { product in
                        Button { onTap(product) } label: { ProductListRow(product: product) }
                            .buttonStyle(ProductPressStyle())
                            .accessibilityLabel(Text("Add \(product.name)"))
                    }
                }
                .padding(PlantbillSpacing.md)
            }

            // Room to scroll the last row clear of the corner buttons.
            Color.clear.frame(height: 150)
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

/// Blocks ↔ list switch. Labelled by what the tap DOES, not the current
/// state — that's what a VoiceOver user needs to hear before pressing it.
struct ProductViewToggle: View {
    let mode: ProductViewMode
    let onChange: (ProductViewMode) -> Void

    var body: some View {
        Button {
            onChange(mode == .grid ? .list : .grid)
        } label: {
            Image(systemName: mode == .grid ? "list.bullet" : "square.grid.2x2")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(PlantbillColor.textSecondary)
                .frame(width: PlantbillSpacing.minTouchTarget, height: PlantbillSpacing.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode == .grid ? Text("Show as a list") : Text("Show as blocks"))
    }
}

private struct ProductBlock: View {
    let product: Product

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(1.4, contentMode: .fit)
                .overlay { ProductPhoto(product: product) }
                .overlay(alignment: .bottomTrailing) {
                    AddBadge()
                        .padding(PlantbillSpacing.sm)
                }
                .clipped()

            VStack(alignment: .leading, spacing: PlantbillSpacing.xs) {
                Text(verbatim: product.name)
                    .font(PlantbillTypography.bodyEmphasized)
                    .foregroundStyle(PlantbillColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
                Text(product.price.format())
                    .font(PlantbillTypography.body)
                    .foregroundStyle(PlantbillColor.green)
            }
            .padding(PlantbillSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(PlantbillColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: PlantbillSpacing.cardCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 4, y: 1)
    }
}

private struct ProductListRow: View {
    let product: Product

    var body: some View {
        HStack(spacing: PlantbillSpacing.md) {
            ProductPhoto(product: product)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(verbatim: product.name)
                .font(PlantbillTypography.bodyEmphasized)
                .foregroundStyle(PlantbillColor.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(product.price.format())
                .font(PlantbillTypography.bodyEmphasized)
                .foregroundStyle(PlantbillColor.green)

            AddBadge()
        }
        .padding(PlantbillSpacing.md)
        .background(PlantbillColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: PlantbillSpacing.cardCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 4, y: 1)
    }
}

private struct ProductPhoto: View {
    let product: Product

    var body: some View {
        if let url = product.resolvedPhotoURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            PlantbillColor.greenTint
            Image(systemName: "leaf.fill")
                .font(.system(size: 26))
                .foregroundStyle(PlantbillColor.green.opacity(0.55))
        }
    }
}

/// The "+" that marks a tap as "put this on the bill".
private struct AddBadge: View {
    var body: some View {
        Image(systemName: "plus.circle.fill")
            .font(.system(size: 26, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, PlantbillColor.green)
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }
}

private struct ProductPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
