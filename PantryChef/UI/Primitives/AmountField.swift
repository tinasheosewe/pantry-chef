import SwiftUI

/// Splits and rebuilds a structured amount string ("300 g") into a numeric quantity
/// and a unit — the one place the app does this, so recipe lines and the shopping
/// cart capture amounts under an identical contract (number + unit-from-the-list,
/// never freeform).
enum AmountText {
    /// The numeric part: "300 g" → "300", "2" → "2", nil → "".
    static func qty(_ amount: String?) -> String {
        guard let amount, !amount.isEmpty else { return "" }
        return amount.split(separator: " ", maxSplits: 1).map(String.init).first ?? ""
    }

    /// The unit part: "300 g" → .gram, "2" → nil.
    static func unit(_ amount: String?) -> MeasurementUnit? {
        guard let amount else { return nil }
        let parts = amount.split(separator: " ", maxSplits: 1).map(String.init)
        return parts.count > 1 ? MeasurementUnit(rawValue: parts[1]) : nil
    }

    /// Rebuild "300 g" from a numeric string + unit; nil when the quantity is blank.
    static func compose(qty: String, unit: MeasurementUnit?) -> String? {
        let q = qty.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        return unit.map { "\(q) \($0.rawValue)" } ?? q
    }
}

/// The shared quantity-and-unit control: a decimal-pad number plus a unit picked
/// from the fixed list. Used wherever the app captures an amount — recipe
/// ingredients and the shopping cart — so the interface is the same everywhere.
struct AmountField: View {
    @Binding var amount: String?
    var qtyWidth: CGFloat = 48
    var unitWidth: CGFloat = 56

    var body: some View {
        HStack(spacing: 8) {
            TextField("qty", text: Binding(
                get: { AmountText.qty(amount) },
                set: { amount = AmountText.compose(qty: $0, unit: AmountText.unit(amount)) }))
                .keyboardType(.decimalPad)
                .frame(width: qtyWidth)
            unitMenu
        }
    }

    private var unitMenu: some View {
        let current = AmountText.unit(amount)
        return Menu {
            Button("—") { amount = AmountText.compose(qty: AmountText.qty(amount), unit: nil) }
            ForEach(MeasurementUnit.allCases) { u in
                Button(u.rawValue) { amount = AmountText.compose(qty: AmountText.qty(amount), unit: u) }
            }
        } label: {
            HStack(spacing: 2) {
                Text(current?.rawValue ?? "unit")
                    .foregroundStyle(current != nil ? Theme.Palette.ink : Theme.Palette.warmGraySoft)
                Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(Theme.Palette.warmGraySoft)
            }
            .frame(width: unitWidth)
        }
    }
}
