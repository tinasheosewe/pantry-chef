import Foundation
import UserNotifications

/// Local notifications — the two things worth interrupting for: a cook timer that
/// finished while you stepped away, and a perishable about to turn. Permission is
/// asked *in context* (the first time you start a cook timer, or when you switch on
/// use-it-up reminders), never cold on launch.
///
/// Cook timers are wall-clock anchored in the cook instrument; we mirror each running
/// one as a pending notification at its end instant, so backgrounding the app doesn't
/// silence it. Finishing a timer while the app is foreground cancels its pending
/// notification (the in-app heartbeat already fired) — so you never get a banner for
/// something you just watched land.
enum NotificationService {
    private static var center: UNUserNotificationCenter { .current() }
    private static let cookPrefix = "cook-timer-"
    private static let expiryPrefix = "expiry-"
    /// Generous ceiling for clearing cook-timer ids without tracking them all.
    private static let maxConcurrentTimers = 64

    /// One day's worth of soon-to-turn items, fired on their last good morning.
    struct ExpiryReminderPlan: Equatable {
        let names: [String]
        let fireAt: Date
    }

    // MARK: - Authorization

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Ask for permission if it's never been decided; returns whether we can post.
    /// Call this only at a moment the user clearly wants to be told something.
    @discardableResult
    static func ensureAuthorized() async -> Bool {
        switch await authorizationStatus() {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    // MARK: - Cook timers

    /// Mirror a running step timer as a pending banner at `fireAt`. Requests permission
    /// in-context on the first call. Replaces any existing notification for this step.
    static func scheduleCookTimer(index: Int, stepNumber: Int, dishName: String, fireAt: Date) {
        let interval = fireAt.timeIntervalSinceNow
        guard interval > 0 else { return }
        Task {
            guard await ensureAuthorized() else { return }
            let content = UNMutableNotificationContent()
            content.title = "Timer’s up — \(dishName)"
            content.body = "Step \(stepNumber) is ready."
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let req = UNNotificationRequest(identifier: "\(cookPrefix)\(index)", content: content, trigger: trigger)
            center.removePendingNotificationRequests(withIdentifiers: [req.identifier])
            try? await center.add(req)
        }
    }

    static func cancelCookTimer(index: Int) {
        center.removePendingNotificationRequests(withIdentifiers: ["\(cookPrefix)\(index)"])
    }

    /// Clear every pending cook-timer banner — called when the cook instrument closes.
    static func cancelAllCookTimers() {
        let ids = (0..<maxConcurrentTimers).map { "\(cookPrefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Expiry reminders

    /// Reconcile the use-it-up reminders to exactly `plans`. Silent on permission: it
    /// only posts when notifications are *already* authorized, so a background sync
    /// never triggers a cold prompt (that opt-in happens in Settings).
    static func syncExpiryReminders(_ plans: [ExpiryReminderPlan]) async {
        let pending = await center.pendingNotificationRequests()
        let stale = pending.filter { $0.identifier.hasPrefix(expiryPrefix) }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard await authorizationStatus() == .authorized, !plans.isEmpty else { return }
        for (i, plan) in plans.enumerated() {
            let interval = plan.fireAt.timeIntervalSinceNow
            guard interval > 0, !plan.names.isEmpty else { continue }
            let content = UNMutableNotificationContent()
            content.title = plan.names.count == 1 ? "Use it up soon" : "\(plan.names.count) things to use up"
            content.body = "\(sentence(plan.names)) turning soon — cook with \(plan.names.count == 1 ? "it" : "them") today."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "\(expiryPrefix)\(i)", content: content, trigger: trigger))
        }
    }

    /// "Spinach", "Spinach and milk", "Spinach, milk and feta".
    private static func sentence(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and \(names.last!)"
        }
    }
}
