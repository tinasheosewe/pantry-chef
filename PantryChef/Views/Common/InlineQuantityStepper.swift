import SwiftUI

struct InlineQuantityStepper: View {
    let quantity: Double?
    let unit: MeasurementUnit?
    let onQuantityChanged: (String) -> Void

    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var textFieldFocused: Bool

    private var displayText: String {
        guard let q = quantity else { return "—" }
        return q.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", q)
            : String(format: "%.1f", q)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("Qty")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(PCColors.textSecondary)

            HStack(spacing: 0) {
                Button {
                    if isEditing { commitEdit() }
                    let current = quantity ?? 1.0
                    let newVal = max(0.5, current - 0.5)
                    onQuantityChanged(formatForStorage(newVal))
                } label: {
                    Image(systemName: "minus")
                        .font(.caption2.weight(.bold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(PCColors.textPrimary)
                }
                .buttonStyle(.plain)

                ZStack {
                    // Hidden text field always in the hierarchy to avoid RTI sessionID warnings
                    TextField("", text: $editText)
                        .keyboardType(.decimalPad)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .focused($textFieldFocused)
                        .opacity(isEditing ? 1 : 0)
                        .onChange(of: textFieldFocused) { _, focused in
                            if !focused && isEditing { commitEdit() }
                        }

                    if !isEditing {
                        Text(displayText)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editText = quantity.map { formatForStorage($0) } ?? ""
                                isEditing = true
                                textFieldFocused = true
                            }
                    }
                }
                .frame(width: 48, height: 30)

                Button {
                    if isEditing { commitEdit() }
                    let current = quantity ?? 0
                    let newVal = current + 0.5
                    onQuantityChanged(formatForStorage(newVal))
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2.weight(.bold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(PCColors.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .background(PCColors.fillTertiary)
            .clipShape(Capsule())

            if let unit {
                Text(unit.rawValue)
                    .font(.caption2)
                    .foregroundStyle(PCColors.textSecondary)
            }
        }
    }

    private func commitEdit() {
        isEditing = false
        textFieldFocused = false
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let val = Double(trimmed), val > 0 {
            onQuantityChanged(formatForStorage(val))
        }
    }

    private func formatForStorage(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}
