import SwiftUI

/// Turns a control that starts a write into a route to the "keep using
/// Plantbill" sheet, for as long as the trial is locked.
///
/// The server is the actual lock — this is only about not walking the shop
/// owner into it. Being refused after filling in a whole bill is a far worse
/// moment than being told at the button that this needs a plan, and a 76-year
/// old who has just lost ten minutes of typing is not going to try again.
///
/// Applied at the few places a write *begins* rather than everywhere a write
/// could happen: anything that slips through still gets a plain-language
/// refusal and the same sheet, because `APIClient` raises one on every 402.
private struct TrialGateModifier: ViewModifier {
    @ObservedObject private var trial = TrialStore.shared

    func body(content: Content) -> some View {
        content
            // Not `.disabled()`: a disabled control swallows the tap and says
            // nothing, which is exactly the dead end this exists to prevent.
            // It looks unavailable, and pressing it explains why.
            .opacity(trial.isLocked ? 0.5 : 1)
            .overlay {
                if trial.isLocked {
                    Button {
                        trial.promptToContinue()
                    } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Needs a plan")
                    .accessibilityHint("Your free trial has ended. Opens how to continue.")
                }
            }
    }
}

extension View {
    /// Marks a control that starts a write, so it explains itself instead of
    /// failing once the trial has ended.
    func trialGated() -> some View {
        modifier(TrialGateModifier())
    }
}
