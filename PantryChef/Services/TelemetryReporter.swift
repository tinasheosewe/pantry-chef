import Foundation

enum TelemetrySeverity: String, Sendable {
    case debug
    case info
    case warning
    case error
}

struct TelemetryEvent: Sendable {
    let name: String
    let severity: TelemetrySeverity
    let metadata: [String: String]

    init(name: String, severity: TelemetrySeverity, metadata: [String: String] = [:]) {
        self.name = name
        self.severity = severity
        self.metadata = metadata
    }

    func formattedMessage(prefix: String) -> String {
        let details = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        return details.isEmpty
            ? "\(prefix) \(name)"
            : "\(prefix) \(name) \(details)"
    }
}

protocol TelemetryReporting: Sendable {
    func record(_ event: TelemetryEvent)
}

struct AppTelemetryReporter: TelemetryReporting {
    private let crashReporter: any CrashReporting

    init(crashReporter: any CrashReporting = SentryCrashReporter()) {
        self.crashReporter = crashReporter
    }

    func record(_ event: TelemetryEvent) {
        let message = event.formattedMessage(prefix: "[Telemetry]")

        switch event.severity {
        case .debug:
            AppLog.debug(message)
        case .info:
            AppLog.info(message)
        case .warning:
            AppLog.warn(message)
        case .error:
            AppLog.error(message)
        }

        crashReporter.record(event)
    }
}