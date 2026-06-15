import Foundation

/// The one way the app renders a numeric quantity for display: whole numbers drop
/// the decimal ("2"), others show two significant figures ("1.5", "0.25"). Every
/// amount string in the app goes through here so formatting can't diverge
/// (consolidation audit §5 — was copied in 6+ places with two different rules).
enum QuantityFormat {
    static func short(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2g", value)
    }
}
