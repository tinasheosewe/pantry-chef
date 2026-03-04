import SwiftUI

@main
struct PantryChefApp: App {
    @State private var appState = AppState()

    init() {
        // Set window background to match splash so pre-render isn't black
        let green = UIColor(red: 0.30, green: 0.69, blue: 0.31, alpha: 1)
        UIWindow.appearance().backgroundColor = green
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
    }
}
