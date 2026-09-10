import SwiftUI
import UIKit

/// The one place the support number and address live, and the one place that
/// knows how to actually reach them.
///
/// `Link` and a bare `UIApplication.open` both fail silently when there's no
/// Phone or Mail account configured — which is the Simulator always, and a
/// real iPhone whose owner never set up Mail. For a shop owner locked out of
/// their own till, a Contact-us button that does nothing is worse than no
/// button, so every call here reports back whether it worked and the caller
/// falls back to putting the contact on the clipboard.
enum SupportContact {
    static let phoneDigits = "917975402266"
    static let phoneDisplay = "+91 79754 02266"
    static let email = "plantparkgroup@gmail.com"

    /// Opens the dialler with the number already filled in. `tel://` goes
    /// straight to a call on some iOS versions; `telprompt://` always asks
    /// first, which is the right default when an elderly user may have
    /// mis-tapped.
    @MainActor
    static func call(completion: @escaping (Bool) -> Void) {
        open(URL(string: "telprompt://\(phoneDigits)"), fallback: URL(string: "tel://\(phoneDigits)"), completion: completion)
    }

    @MainActor
    static func whatsApp(completion: @escaping (Bool) -> Void) {
        open(URL(string: "https://wa.me/\(phoneDigits)"), fallback: nil, completion: completion)
    }

    /// Opens Mail with the subject and body already written, so the shop owner
    /// only has to press Send. The body carries the details we'd otherwise
    /// have to ask for over the phone — which shop, which account, which
    /// version — because a trial user who has just been locked out is the
    /// least able to go and look them up.
    @MainActor
    static func email(
        subject: String,
        body: String,
        completion: @escaping (Bool) -> Void
    ) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        open(components.url, fallback: URL(string: "mailto:\(email)"), completion: completion)
    }

    /// The pre-written enquiry for a shop whose trial has ended.
    static func continueAccessBody(shopName: String?, accountEmail: String) -> String {
        var lines = [
            "Hello Plantbill team,",
            "",
            "My free trial has ended and I would like to continue using Plantbill.",
            "Please tell me the plans and how to pay.",
            "",
            "My details:",
        ]
        if let shopName, !shopName.isEmpty {
            lines.append("Shop: \(shopName)")
        }
        lines.append("Account: \(accountEmail)")
        lines.append("App: \(versionString)")
        lines.append("")
        lines.append("Thank you.")
        return lines.joined(separator: "\n")
    }

    static var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Plantbill iOS \(version) (\(build))"
    }

    @MainActor
    private static func open(_ url: URL?, fallback: URL?, completion: @escaping (Bool) -> Void) {
        guard let url, UIApplication.shared.canOpenURL(url) else {
            guard let fallback, UIApplication.shared.canOpenURL(fallback) else {
                completion(false)
                return
            }
            UIApplication.shared.open(fallback) { completion($0) }
            return
        }
        UIApplication.shared.open(url) { completion($0) }
    }
}
