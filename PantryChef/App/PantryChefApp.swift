import SwiftUI
import UserNotifications

@main
struct PantryChefApp: App {
    @State private var appState = AppState()

    init() {
        // Register notification delegate early so we catch actions even on cold launch
        UNUserNotificationCenter.current().delegate = NotificationService.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NotificationService.didReceiveActionNotification
                    )
                ) { notification in
                    handleNotificationAction(notification.userInfo)
                }
                .onAppear {
                    cleanUpExpiredSessions()
                }
        }
    }

    // MARK: - Notification Action Handling

    private func handleNotificationAction(_ userInfo: [AnyHashable: Any]?) {
        guard let info = userInfo,
              let recipeId = info["recipeId"] as? String,
              let stepIndex = info["stepIndex"] as? Int else { return }

        let actionId = info["actionIdentifier"] as? String ?? ""

        if actionId == NotificationService.actionDone {
            // "Done ✓" action — advance step in persisted session without opening UI
            if var session = CookingSession.load(),
               session.recipeId.uuidString == recipeId {
                session.currentStepIndex = min(stepIndex + 1, session.totalSteps - 1)
                session.save()
                print("[PantryChefApp] Step \(stepIndex + 1) marked done via notification")
            }
        } else {
            // Default tap or "Open Cook Mode" — update persisted session step and deep-link
            if var session = CookingSession.load(),
               session.recipeId.uuidString == recipeId {
                session.currentStepIndex = stepIndex
                session.save()
            }
            appState.deepLinkCookModeRecipeId = recipeId
            print("[PantryChefApp] Deep-link to cook mode for recipe \(recipeId.prefix(8))… step \(stepIndex + 1)")
        }
    }

    private func cleanUpExpiredSessions() {
        if let session = CookingSession.load() {
            print("[PantryChefApp] Active cooking session: \(session.recipeName) (step \(session.currentStepIndex + 1)/\(session.totalSteps))")
        }
    }
}