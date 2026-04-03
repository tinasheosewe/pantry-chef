import SwiftUI

enum PCFormValueEmphasis {
    case editable
    case readOnly

    var foregroundStyle: Color {
        switch self {
        case .editable:
            return PCColors.textPrimary
        case .readOnly:
            return PCColors.textSecondary
        }
    }
}

private struct PCFormValueStyleModifier: ViewModifier {
    let emphasis: PCFormValueEmphasis

    func body(content: Content) -> some View {
        content
            .foregroundStyle(emphasis.foregroundStyle)
            .tint(emphasis.foregroundStyle)
    }
}

extension View {
    func pcFormValueStyle(_ emphasis: PCFormValueEmphasis) -> some View {
        modifier(PCFormValueStyleModifier(emphasis: emphasis))
    }

    func pcFormValueStyle(isEditable: Bool) -> some View {
        pcFormValueStyle(isEditable ? .editable : .readOnly)
    }
}

// MARK: - PCTextField

struct PCTextField: View {
    let label: String?
    @Binding var text: String
    var placeholder: String = ""
    var axis: Axis = .horizontal
    var autocapitalization: TextInputAutocapitalization? = .words

    init(
        _ label: String? = nil,
        text: Binding<String>,
        placeholder: String = "",
        axis: Axis = .horizontal,
        autocapitalization: TextInputAutocapitalization? = .words
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.axis = axis
        self.autocapitalization = autocapitalization
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PCTokens.spacingXS) {
            if let label {
                Text(label)
                    .font(PCFont.caption)
                    .foregroundStyle(PCColors.textSecondary)
            }
            TextField(placeholder, text: $text, axis: axis)
                .font(PCFont.body)
                .textInputAutocapitalization(autocapitalization)
                .padding(PCTokens.spacingMD)
                .background(PCColors.fillTertiary)
                .clipShape(RoundedRectangle(cornerRadius: PCTokens.cornerRadiusSmall))
        }
    }
}

// MARK: - PCSearchField

struct PCSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var focus: FocusState<Bool>.Binding?
    var onTextChange: ((String) -> Void)?

    var body: some View {
        HStack(spacing: PCTokens.spacingSM) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PCColors.textTertiary)
                .font(.system(size: PCTokens.iconSizeSmall))

            searchField

            if !text.isEmpty {
                Button {
                    trackedText.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(PCColors.textTertiary)
                }
            }
        }
        .padding(PCTokens.spacingMD)
        .background(PCColors.fillTertiary)
        .clipShape(RoundedRectangle(cornerRadius: PCTokens.cornerRadiusSmall))
        .contentShape(RoundedRectangle(cornerRadius: PCTokens.cornerRadiusSmall))
        .onTapGesture {
            focus?.wrappedValue = true
        }
    }

    private var trackedText: Binding<String> {
        Binding(
            get: { text },
            set: { newValue in
                text = newValue
                onTextChange?(newValue)
            }
        )
    }

    @ViewBuilder
    private var searchField: some View {
        let field = TextField(placeholder, text: trackedText)
            .font(PCFont.body)
            .textInputAutocapitalization(.words)
            .disableAutocorrection(true)

        if let focus {
            field.focused(focus)
        } else {
            field
        }
    }
}

// MARK: - PCNumberField

struct PCNumberField: View {
    let label: String?
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...9999
    var step: Double = 1
    var unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PCTokens.spacingXS) {
            if let label {
                Text(label)
                    .font(PCFont.caption)
                    .foregroundStyle(PCColors.textSecondary)
            }
            HStack(spacing: PCTokens.spacingMD) {
                Button {
                    value = max(range.lowerBound, value - step)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: PCTokens.iconSize))
                        .foregroundStyle(PCColors.accent)
                }
                .disabled(value <= range.lowerBound)

                Text(formattedValue)
                    .font(PCFont.headline)
                    .foregroundStyle(PCColors.textPrimary)
                    .frame(minWidth: 40)
                    .multilineTextAlignment(.center)

                if let unit {
                    Text(unit)
                        .font(PCFont.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }

                Button {
                    value = min(range.upperBound, value + step)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: PCTokens.iconSize))
                        .foregroundStyle(PCColors.accent)
                }
                .disabled(value >= range.upperBound)
            }
        }
    }

    private var formattedValue: String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

// MARK: - PCDateField

struct PCDateField: View {
    let label: String
    @Binding var date: Date
    var isEstimated: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: PCTokens.spacingXS) {
                Text(label)
                    .font(PCFont.caption)
                    .foregroundStyle(PCColors.textSecondary)
                if isEstimated {
                    PCBadge(text: "estimated", color: PCColors.expiring)
                }
            }
            Spacer()
            DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
        }
    }
}

// MARK: - PCMultilineInput

struct PCMultilineInput: View {
    @Binding var text: String
    var prompt: String
    var minHeight: CGFloat = 80

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(prompt)
                    .font(PCFont.body)
                    .foregroundStyle(PCColors.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            }
            TextEditor(text: $text)
                .font(PCFont.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
        }
        .frame(minHeight: minHeight)
        .background(PCColors.fillTertiary)
        .clipShape(RoundedRectangle(cornerRadius: PCTokens.cornerRadiusSmall))
    }
}
