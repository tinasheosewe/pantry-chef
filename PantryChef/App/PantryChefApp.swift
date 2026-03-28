import SwiftUI
import UserNotifications

@main
struct PantryChefApp: App {
    @State private var appState = AppState()

    init() {
        KeyboardBehaviorInstaller.configureGlobalBehavior()
        SentryCrashReporter().startIfConfigured()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.light)
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NotificationService.didReceiveActionNotification
                    )
                ) { notification in
                    handleNotificationAction(notification.userInfo)
                }
                .onAppear {
                    if let delegate = appState.notificationService as? UNUserNotificationCenterDelegate {
                        UNUserNotificationCenter.current().delegate = delegate
                    }
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
        let recipeUUID = UUID(uuidString: recipeId)

        if actionId == NotificationService.actionDone {
            // "Done ✓" action — advance step in persisted session without opening UI
            if let uuid = recipeUUID,
               var session = appState.cookingSessionStore.load(recipeId: uuid) {
                session.currentStepIndex = min(stepIndex + 1, session.totalSteps - 1)
                appState.cookingSessionStore.save(session)
                AppLog.info("[PantryChefApp] Step \(stepIndex + 1) marked done via notification")
            }
        } else {
            // Default tap or "Open Cook Mode" — update persisted session step and deep-link
            if let uuid = recipeUUID,
               var session = appState.cookingSessionStore.load(recipeId: uuid) {
                session.currentStepIndex = stepIndex
                appState.cookingSessionStore.save(session)
            }
            Task {
                await appState.navigator.resolveCookModeDeepLink(
                    recipeId: recipeId,
                    recipeLookup: appState.recipeByIdString,
                    maxRetries: AppConfig.deepLinkMaxRetries,
                    retryDelayMs: AppConfig.deepLinkRetryDelayMs
                )
            }
            AppLog.info("[PantryChefApp] Deep-link to cook mode for recipe \(recipeId.prefix(8))… step \(stepIndex + 1)")
        }
    }

    private func cleanUpExpiredSessions() {
        let sessions = appState.cookingSessionStore.loadAll()
        if !sessions.isEmpty {
            for session in sessions {
                AppLog.info("[PantryChefApp] Active cooking session: \(session.recipeName) (step \(session.currentStepIndex + 1)/\(session.totalSteps))")
            }
        }
        appState.activeCooks.refresh()
    }
}