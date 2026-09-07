import SwiftUI

/// Persistent "no internet" banner shown across the whole app whenever the
/// backend can't be reached.
///
/// Android shows a blocking popup here. This is deliberately a banner instead:
/// a modal would stop the shop owner reading the things that still work
/// offline — the held bills sitting on the device, the day's saved figures
/// already on screen, the shop's UPI QR — and on a patchy rural connection a
/// popup that keeps reappearing mid-sale is worse than a line of text. It
/// stays until the connection is actually back, so it can't be missed.
struct OfflineBanner: View {
    @ObservedObject private var monitor = NetworkMonitor.shared

    var body: some View {
        if !monitor.isConnected {
            HStack(spacing: PlantbillSpacing.sm) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 17, weight: .semibold))

                VStack(alignment: .leading, spacing: 1) {
                    Text("No internet")
                        .font(PlantbillTypography.bodyEmphasized)
                    Text("Saved bills and held bills are safe on this phone.")
                        .font(PlantbillTypography.caption)
                        .opacity(0.9)
                }

                Spacer()

                Button {
                    Task { await monitor.recheck() }
                } label: {
                    if monitor.isRechecking {
                        ProgressView().tint(.white)
                    } else {
                        Text("Try again")
                            .font(PlantbillTypography.caption)
                            .fontWeight(.semibold)
                    }
                }
                .frame(minWidth: 72, minHeight: 36)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, PlantbillSpacing.md)
            .padding(.vertical, PlantbillSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(PlantbillColor.error)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

extension View {
    /// Pins the offline banner above the app's content.
    func offlineBanner() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            OfflineBanner()
                .animation(.easeInOut(duration: 0.2), value: NetworkMonitor.shared.isConnected)
        }
    }
}
