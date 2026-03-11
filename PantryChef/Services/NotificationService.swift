import Foundation
import UserNotifications

// MARK: - Notification Service
//
// Manages local notifications for cook mode's "Continue in Background" feature.
// The AI schedules notifications for remaining recipe steps before the voice
// session disconnects. Notifications are self-contained (rich enough to cook
// from) and deep-link back to cook mode on tap.

@MainActor
final class NotificationService: NSObject {

    static let shared = NotificationService()

    /// Category identifier for cook mode step notifications.
    static let cookModeCategoryId = "COOK_MODE_STEP"

    /// Action identifiers within the notification category.
    static let actionDone = "COOK_MODE_DONE"
    static let actionOpen = "COOK_MODE_OPEN"

    /// Notification identifier prefix for cook-mode steps.
    nonisolated static let identifierPrefix = "cookmode"

    /// Posted when a notification action is tapped. Payload: ["recipeId": String, "stepIndex": Int]
    nonisolated static let didReceiveActionNotification = Notification.Name("NotificationService.didReceiveAction")

    private let center = UNUserNotificationCenter.current()
    private var isRegistered = false

    // MARK: - Setup

    /// Request notification permission and register categories.
    /// Safe to call multiple times — only prompts once.
    func requestPermission() async -> Bool {
        registerCategories()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                AppLog.info("[NotificationService] Permission granted")
            } else {
                AppLog.warn("[NotificationService] Permission denied")
            }
            return granted
        } catch {
            AppLog.error("[NotificationService] ❌ Permission error: \(error)")
            return false
        }
    }

    /// Returns true if notifications are currently authorized.
    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    private func registerCategories() {
        guard !isRegistered else { return }
        isRegistered = true

        let doneAction = UNNotificationAction(
            identifier: Self.actionDone,
            title: "Done ✓",
            options: []
        )
        let openAction = UNNotificationAction(
            identifier: Self.actionOpen,
            title: "Open Cook Mode",
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: Self.cookModeCategoryId,
            actions: [doneAction, openAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([category])
    }

    // MARK: - Schedule

    /// Schedule a local notification for a recipe step.
    ///
    /// - Parameters:
    ///   - recipeId: The recipe UUID string, used to group/cancel notifications.
    ///   - stepIndex: 0-based step index.
    ///   - totalSteps: Total number of steps in the recipe.
    ///   - recipeName: Recipe title for the notification title.
    ///   - message: The step instruction / body text.
    ///   - nextStepPreview: Optional preview of the next step (shown as subtitle).
    ///   - delaySeconds: Seconds from now until the notification fires.
    func scheduleStepNotification(
        recipeId: String,
        stepIndex: Int,
        totalSteps: Int,
        recipeName: String,
        message: String,
        nextStepPreview: String?,
        delaySeconds: TimeInterval
    ) {
        guard delaySeconds >= 0 else {
            AppLog.warn("[NotificationService] Skipping step \(stepIndex + 1) — delay < 0")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Step \(stepIndex + 1) of \(totalSteps) — \(recipeName)"
        content.body = message
        if let next = nextStepPreview {
            content.subtitle = "Next: \(next)"
        }
        content.sound = .default
        content.categoryIdentifier = Self.cookModeCategoryId
        content.userInfo = [
            "recipeId": recipeId,
            "stepIndex": stepIndex,
            "totalSteps": totalSteps
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, delaySeconds),
            repeats: false
        )

        let identifier = notificationId(recipeId: recipeId, stepIndex: stepIndex)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                AppLog.error("[NotificationService] ❌ Schedule failed for step \(stepIndex + 1): \(error)")
            } else {
                let minutes = Int(delaySeconds) / 60
                let seconds = Int(delaySeconds) % 60
                AppLog.info("[NotificationService] Scheduled step \(stepIndex + 1) in \(minutes)m \(seconds)s")
            }
        }
    }

    /// Schedule a session-expiry notification.
    func scheduleSessionExpiry(recipeId: String, recipeName: String, delaySeconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Cooking session ended"
        content.body = "\(recipeName) — your cooking session has expired."
        content.sound = .default
        content.userInfo = [
            "recipeId": recipeId,
            "isExpiry": true
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, delaySeconds),
            repeats: false
        )

        let identifier = "\(Self.identifierPrefix)-\(recipeId)-expiry"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request) { error in
            if let error {
                AppLog.error("[NotificationService] ❌ Failed to schedule session expiry: \(error)")
            }
        }
    }

    // MARK: - Cancel

    /// Cancel all cook-mode notifications for a specific recipe.
    func cancelAllNotifications(recipeId: String) {
        let prefix = "\(Self.identifierPrefix)-\(recipeId)"
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            AppLog.info("[NotificationService] Cancelled \(ids.count) notifications for recipe \(recipeId.prefix(8))…")
        }
    }

    /// Cancel all cook-mode notifications across all recipes.
    func cancelAllCookModeNotifications() {
        let identifierPrefix = Self.identifierPrefix
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(identifierPrefix) }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            AppLog.info("[NotificationService] Cancelled all \(ids.count) cook-mode notifications")
        }
    }

    // MARK: - Helpers

    private func notificationId(recipeId: String, stepIndex: Int) -> String {
        "\(Self.identifierPrefix)-\(recipeId)-step-\(stepIndex)"
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    /// Called when a notification is tapped or actioned.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard let recipeId = userInfo["recipeId"] as? String else {
            completionHandler()
            return
        }
        let stepIndex = userInfo["stepIndex"] as? Int ?? 0

        AppLog.info("[NotificationService] Action: \(response.actionIdentifier) for step \(stepIndex + 1)")

        // Post a notification so the app can handle deep-linking
        NotificationCenter.default.post(
            name: Self.didReceiveActionNotification,
            object: nil,
            userInfo: [
                "recipeId": recipeId,
                "stepIndex": stepIndex,
                "actionIdentifier": response.actionIdentifier
            ]
        )

        completionHandler()
    }

    /// Show notifications even when the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
