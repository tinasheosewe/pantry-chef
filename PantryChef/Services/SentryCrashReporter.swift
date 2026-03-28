import Foundation
import Sentry

protocol CrashReporting: Sendable {
    func startIfConfigured()
    func record(_ event: TelemetryEvent)
}

struct SentryCrashReporter: CrashReporting {
    private let dsn: String?

    init(dsn: String? = AppConfig.sentryDSN) {
        self.dsn = dsn
    }

    func startIfConfigured() {
        guard let dsn, !dsn.isEmpty else {
            AppLog.info("[CrashReporter] Sentry disabled: no DSN configured")
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = AppConfig.runtimeEnvironment
            options.enableAppHangTracking = true
            options.enableMetricKit = true
            options.attachStacktrace = true
        }

        AppLog.info("[CrashReporter] Sentry initialized for \(AppConfig.runtimeEnvironment)")
    }

    func record(_ event: TelemetryEvent) {
        guard dsn != nil else {
            return
        }

        let breadcrumb = Breadcrumb()
        breadcrumb.category = "telemetry"
        breadcrumb.type = "info"
        breadcrumb.level = sentryLevel(for: event.severity)
        breadcrumb.message = event.formattedMessage(prefix: "[Telemetry]")
        breadcrumb.data = event.metadata
        SentrySDK.addBreadcrumb(breadcrumb)

        guard event.severity == .error else {
            return
        }

        SentrySDK.capture(message: event.formattedMessage(prefix: "[Telemetry]"))
    }

    private func sentryLevel(for severity: TelemetrySeverity) -> SentryLevel {
        switch severity {
        case .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .warning
        case .error:
            return .error
        }
    }
}
