import Combine
import Foundation

/// App-wide free-trial state.
///
/// A singleton rather than state threaded through `CurrentUser` because two
/// things update it from opposite directions: `/auth/me` on launch and login,
/// and a 402 arriving from any screen mid-session. When a save is refused
/// because the trial ran out, every other screen has to know immediately —
/// otherwise the owner keeps tapping Save around the app and collects the same
/// refusal one screen at a time.
@MainActor
final class TrialStore: ObservableObject {
    static let shared = TrialStore()

    /// nil when this shop has no trial at all — every admin-provisioned shop,
    /// where none of this UI should appear.
    @Published private(set) var daysLeft: Int?
    @Published private(set) var isLocked = false
    @Published private(set) var isSelfSignup = false
    /// Kept here so the contact sheet can quote the account in its pre-written
    /// email without reaching for an @EnvironmentObject — it is presented from
    /// a root-level modifier, where relying on inherited environment is a
    /// fragile place to be.
    @Published private(set) var accountEmail = ""

    /// Raised when a write is actually refused, so the app can put the
    /// "here's how to continue" sheet in front of the owner at the moment it
    /// matters — not leave them staring at an inline error under a Save
    /// button that no longer works.
    @Published var isPromptingToContinue = false

    /// Whether to show anything trial-related. False for the shops the admin
    /// set up, which is what the Android app and the website use.
    var isTrialShop: Bool { daysLeft != nil || isLocked }

    /// The nudge only earns its place on screen in the last stretch. A banner
    /// on day 1 of 14 is noise the shop owner learns to ignore, and then it's
    /// still being ignored on day 13.
    var shouldWarn: Bool {
        guard !isLocked, let daysLeft else { return false }
        return daysLeft <= 5
    }

    private init() {
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .apiTrialExpired) {
                self?.lock()
                self?.isPromptingToContinue = true
            }
        }
    }

    func update(from user: CurrentUser) {
        daysLeft = user.trialDaysLeft
        isLocked = user.isTrialLocked
        isSelfSignup = user.isSelfSignup
        accountEmail = user.email
    }

    /// Called when the server refuses a write with 402.
    func lock() {
        guard !isLocked else { return }
        isLocked = true
        daysLeft = 0
    }

    func clear() {
        daysLeft = nil
        isLocked = false
        isSelfSignup = false
        accountEmail = ""
        isPromptingToContinue = false
    }

    /// Opens the contact sheet from a button the owner pressed themselves.
    func promptToContinue() {
        isPromptingToContinue = true
    }
}
