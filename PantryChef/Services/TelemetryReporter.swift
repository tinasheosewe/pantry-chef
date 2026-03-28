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
}

protocol TelemetryReporting: Sendable {
    func record(_ event: TelemetryEvent)
}

struct AppTelemetryReporter: TelemetryReporting {
    func record(_ event: TelemetryEvent) {
        let details = event.metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        let message = details.isEmpty
            ? "[Telemetry] \(event.name)"
            : "[Telemetry] \(event.name) \(details)"

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
    }
}