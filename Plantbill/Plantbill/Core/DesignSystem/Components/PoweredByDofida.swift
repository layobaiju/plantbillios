import SwiftUI

/// "Powered by Dofida" — the company credit. Small and quiet on purpose: it
/// sits below what the shop owner came to the screen for and never competes
/// with it. The logo artwork has a light and a dark version in the asset
/// catalog, so it stays visible in dark mode.
struct PoweredByDofida: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Powered by")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PlantbillColor.textSecondary)
            Image("DofidaLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: 18)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Powered by Dofida"))
    }
}

#Preview {
    PoweredByDofida()
        .padding()
        .background(PlantbillColor.background)
}
