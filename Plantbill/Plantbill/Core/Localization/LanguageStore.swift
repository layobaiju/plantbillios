import Combine
import Foundation

@MainActor
final class LanguageStore: ObservableObject {
    private static let key = "app_language"

    @Published private(set) var current: AppLanguage

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.key), let language = AppLanguage(rawValue: raw) {
            current = language
        } else {
            current = .en
        }
    }

    func set(_ language: AppLanguage) {
        current = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.key)
    }
}
