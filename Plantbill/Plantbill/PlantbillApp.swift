import SwiftUI

@main
struct PlantbillApp: App {
    @StateObject private var session = AuthSession()
    @StateObject private var languageStore = LanguageStore()
    /// Once per launch: the opening animation plays over the app while it
    /// loads, then this goes false and stays false until the next launch —
    /// coming back from the background doesn't replay it.
    @State private var showsLaunchAnimation = true

    var body: some Scene {
        WindowGroup {
            ZStack {
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

                if showsLaunchAnimation {
                    LaunchAnimationView {
                        withAnimation(.easeOut(duration: 0.35)) { showsLaunchAnimation = false }
                    }
                    .environment(\.locale, languageStore.current.locale)
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
        }
    }
}
