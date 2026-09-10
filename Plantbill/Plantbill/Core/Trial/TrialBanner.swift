import SwiftUI

/// App-wide free-trial bar. Amber while the trial is running out, red once it
/// has ended, and absent entirely for a shop the admin set up.
///
/// A bar rather than a popup, for the same reason the offline banner is a bar:
/// a locked shop can still read everything it owns, and a modal that reappears
/// on every screen would block the one thing that still works.
struct TrialBanner: View {
    @ObservedObject private var trial = TrialStore.shared

    var body: some View {
        if trial.isLocked {
            bar(
                icon: "lock.fill",
                tint: PlantbillColor.error,
                title: Text("Free trial ended"),
                subtitle: Text("You can still see everything. Adding and editing needs a plan."),
                actionTitle: Text("Continue")
            )
        } else if trial.shouldWarn, let days = trial.daysLeft {
            bar(
                icon: "clock.fill",
                tint: PlantbillColor.warning,
                title: days == 0
                    ? Text("Free trial ends today")
                    : Text("\(days) \(days == 1 ? "day" : "days") left in your free trial"),
                subtitle: Text("Talk to us to keep your shop running after that."),
                actionTitle: Text("Contact us")
            )
        }
    }

    private func bar(
        icon: String,
        tint: Color,
        title: Text,
        subtitle: Text,
        actionTitle: Text
    ) -> some View {
        HStack(spacing: PlantbillSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))

            VStack(alignment: .leading, spacing: 1) {
                title
                    .font(PlantbillTypography.bodyEmphasized)
                subtitle
                    .font(PlantbillTypography.caption)
                    .opacity(0.9)
            }

            Spacer(minLength: PlantbillSpacing.sm)

            Button {
                trial.promptToContinue()
            } label: {
                actionTitle
                    .font(PlantbillTypography.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, PlantbillSpacing.sm)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(0.22))
                    )
            }
            .frame(minHeight: 36)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, PlantbillSpacing.md)
        .padding(.vertical, PlantbillSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(tint)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

extension View {
    /// Pins the trial bar above the app's content, under the offline banner.
    func trialBanner() -> some View {
        modifier(TrialBannerModifier())
    }
}

private struct TrialBannerModifier: ViewModifier {
    @ObservedObject private var trial = TrialStore.shared

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                TrialBanner()
                    .animation(.easeInOut(duration: 0.2), value: trial.isLocked)
                    .animation(.easeInOut(duration: 0.2), value: trial.daysLeft)
            }
            // Presented at the root so a refused write surfaces this wherever
            // it happened, including from a screen that is itself a sheet.
            .sheet(isPresented: $trial.isPromptingToContinue) {
                TrialContinueSheet()
            }
    }
}
