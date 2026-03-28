import XCTest
@testable import PantryChef

final class TelemetryReporterTests: XCTestCase {
    func testFormattedMessageSortsMetadataKeys() {
        let event = TelemetryEvent(
            name: "ai.request.completed",
            severity: .info,
            metadata: ["status_code": "200", "attempt": "1"]
        )

        XCTAssertEqual(
            event.formattedMessage(prefix: "[Telemetry]"),
            "[Telemetry] ai.request.completed attempt=1 status_code=200"
        )
    }

    func testAppTelemetryReporterForwardsToCrashReporter() {
        let crashReporter = SpyCrashReporter()
        let reporter = AppTelemetryReporter(crashReporter: crashReporter)
        let event = TelemetryEvent(name: "app.error.presented", severity: .error, metadata: ["type": "ai_recipe_generation"])

        reporter.record(event)

        XCTAssertEqual(crashReporter.recordedEvents.count, 1)
        XCTAssertEqual(crashReporter.recordedEvents.first?.name, event.name)
        XCTAssertEqual(crashReporter.recordedEvents.first?.metadata, event.metadata)
    }
}

private final class SpyCrashReporter: CrashReporting, @unchecked Sendable {
    private(set) var recordedEvents: [TelemetryEvent] = []

    func startIfConfigured() {}

    func record(_ event: TelemetryEvent) {
        recordedEvents.append(event)
    }
}
