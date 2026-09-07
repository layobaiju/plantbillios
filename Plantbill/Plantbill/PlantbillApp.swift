import SwiftUI

@main
struct PlantbillApp: App {
    @StateObject private var session = AuthSession()
    @StateObject private var languageStore = LanguageStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .offlineBanner()
                .environmentObject(session)
                .environmentObject(languageStore)
                .environment(\.locale, languageStore.current.locale)
                // Forces the whole tree to rebuild on language change —
                // mirrors Android's activity-recreation-on-language-switch,
                // since SwiftUI otherwise won't re-evaluate already-resolved
                // LocalizedStringKey text on a plain environment change.
                .id(languageStore.current)
        }
    }
}
