import Foundation
import SwiftUI

// MARK: - Date Extensions
extension Date {
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(self)
    }

    var isThisWeek: Bool {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .weekOfYear)
    }

    var relativeDisplay: String {
        if isToday { return "Today" }
        if isTomorrow { return "Tomorrow" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var shortDisplay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }

    var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: self)
    }

    func daysFrom(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: date, to: self).day ?? 0
    }
}

// MARK: - String Extensions
extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValidURL: Bool {
        guard let url = URL(string: self) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }
}

// MARK: - Array Extensions
extension Array where Element: Identifiable {
    mutating func update(_ element: Element) {
        if let index = firstIndex(where: { $0.id as AnyHashable == element.id as AnyHashable }) {
            self[index] = element
        }
    }
}

// MARK: - View Extensions
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Unit Conversion Helpers
struct UnitConverter {
    // Volume conversions (to milliliters)
    static func toML(_ value: Double, from unit: MeasurementUnit) -> Double? {
        switch unit {
        case .teaspoon: return value * 4.929
        case .tablespoon: return value * 14.787
        case .cup: return value * 236.588
        case .fluidOunce: return value * 29.574
        case .milliliter: return value
        case .liter: return value * 1000
        default: return nil
        }
    }

    // Weight conversions (to grams)
    static func toGrams(_ value: Double, from unit: MeasurementUnit) -> Double? {
        switch unit {
        case .gram: return value
        case .kilogram: return value * 1000
        case .ounce: return value * 28.3495
        case .pound: return value * 453.592
        default: return nil
        }
    }

    // Convert between units
    static func convert(_ value: Double, from: MeasurementUnit, to: MeasurementUnit) -> Double? {
        // Volume to volume
        if let ml = toML(value, from: from), let targetML = toML(1, from: to) {
            return ml / targetML
        }
        // Weight to weight
        if let g = toGrams(value, from: from), let targetG = toGrams(1, from: to) {
            return g / targetG
        }
        return nil
    }

    // Format for display
    static func formatQuantity(_ value: Double) -> String {
        if value == value.rounded() {
            return "\(Int(value))"
        }

        // Common fractions
        let fractions: [(Double, String)] = [
            (0.25, "¼"), (0.33, "⅓"), (0.5, "½"),
            (0.67, "⅔"), (0.75, "¾"),
        ]

        let whole = Int(value)
        let decimal = value - Double(whole)

        for (fraction, symbol) in fractions {
            if abs(decimal - fraction) < 0.05 {
                return whole > 0 ? "\(whole) \(symbol)" : symbol
            }
        }

        return String(format: "%.1f", value)
    }
}

// MARK: - Debounce Helpers

/// Reusable main-actor debouncer for UI-driven events like search text changes.
@MainActor
final class TaskDebouncer {
    private var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }

    func schedule(after nanoseconds: UInt64, action: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

enum DebounceDurations {
    static let quickSearch: UInt64 = 150_000_000
    static let apiSearch: UInt64 = 400_000_000
}

// MARK: - Logging

enum AppLogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

enum AppLog {
    private static let formatterLock = NSLock()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func debug(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        line: Int = #line,
        function: String = #function
    ) {
        log(level: .debug, message: message(), file: file, line: line, function: function)
    }

    static func info(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        line: Int = #line,
        function: String = #function
    ) {
        log(level: .info, message: message(), file: file, line: line, function: function)
    }

    static func warn(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        line: Int = #line,
        function: String = #function
    ) {
        log(level: .warning, message: message(), file: file, line: line, function: function)
    }

    static func error(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        line: Int = #line,
        function: String = #function
    ) {
        log(level: .error, message: message(), file: file, line: line, function: function)
    }

    private static func log(level: AppLogLevel, message: String, file: String, line: Int, function: String) {
        formatterLock.lock()
        let timestamp = formatter.string(from: Date())
        formatterLock.unlock()
        let fileName = file.split(separator: "/").last.map(String.init) ?? file
        Swift.print("\(timestamp) [\(level.rawValue)] \(fileName):\(line) \(function) | \(message)")
    }
}
