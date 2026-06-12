import SwiftUI

@main
struct PantryChefApp: App {
    init() {
        FontLoader.registerBundledFonts()
        KeyboardBehaviorInstaller.configureGlobalBehavior()
        SentryCrashReporter().startIfConfigured()
    }

    var body: some Scene {
        WindowGroup {
            RedesignRootView()
        }
    }
}
