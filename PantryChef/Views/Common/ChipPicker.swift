import SwiftUI

struct ChipPicker: View {
    let label: String
    let options: [String]
    let selection: String?
    let onSelect: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(PCColors.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        let isActive = selection == option
                        Button {
                            onSelect(isActive ? nil : option)
                        } label: {
                            Text(option.capitalized)
                                .font(.caption)
                                .fontWeight(isActive ? .semibold : .regular)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isActive ? PCColors.accent : PCColors.fillTertiary)
                                .foregroundStyle(isActive ? Color.white : PCColors.textPrimary)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(isActive ? Color.clear : PCColors.textSecondary.opacity(0.3), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
