import SwiftUI

@main
struct PantryChefApp: App {
    init() {
        KeyboardBehaviorInstaller.configureGlobalBehavior()
        SentryCrashReporter().startIfConfigured()
    }

    var body: some Scene {
        WindowGroup {
            RedesignRootView()
        }
    }
}
