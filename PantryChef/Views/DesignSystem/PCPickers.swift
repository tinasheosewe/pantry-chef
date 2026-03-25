import SwiftUI

// MARK: - PCSegmentedPicker

struct PCSegmentedPicker<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let label: (Item) -> String
    var badge: ((Item) -> Int?)?
    var onSelect: ((Item) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = item
                    }
                    onSelect?(item)
                } label: {
                    HStack(spacing: PCTokens.spacingXS) {
                        Text(label(item))
                            .font(PCFont.captionBold)
                            .lineLimit(1)
                        if let badge, let count = badge(item), count > 0 {
                            Text("\(count)")
                                .font(PCFont.micro)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    selection == item
                                        ? Color.white.opacity(0.3)
                                        : PCColors.fillSecondary
                                )
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundStyle(selection == item ? .white : PCColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PCTokens.spacingSM)
                    .background(selection == item ? PCColors.accent : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: PCTokens.cornerRadiusSmall))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(PCColors.fillTertiary)
        .clipShape(RoundedRectangle(cornerRadius: PCTokens.cornerRadiusSmall + 3))
    }
}

// MARK: - PCChipPicker (Single Select)

struct PCChipPicker<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item?
    let label: (Item) -> String
    var icon: ((Item) -> String)?
    var heroItem: Item?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PCTokens.spacingSM) {
                ForEach(items, id: \.self) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selection = selection == item ? nil : item
                        }
                    } label: {
                        chipLabel(for: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, PCTokens.spacingLG)
        }
    }

    @ViewBuilder
    private func chipLabel(for item: Item) -> some View {
        let isSelected = selection == item
        let isHero = item == heroItem

        HStack(spacing: PCTokens.spacingXS) {
            if let icon, let iconName = Optional(icon(item)), !iconName.isEmpty {
                Image(systemName: iconName)
                    .font(.system(size: 12))
            }
            Text(label(item))
                .font(PCFont.captionBold)
                .lineLimit(1)
        }
        .padding(.horizontal, PCTokens.spacingMD)
        .padding(.vertical, PCTokens.spacingSM)
        .background(chipBackground(selected: isSelected, hero: isHero))
        .foregroundStyle(chipForeground(selected: isSelected, hero: isHero))
        .clipShape(Capsule())
    }

    private func chipBackground(selected: Bool, hero: Bool) -> Color {
        if selected { return hero ? PCColors.accent : PCColors.accent }
        if hero { return PCColors.accent.opacity(0.12) }
        return PCColors.fillTertiary
    }

    private func chipForeground(selected: Bool, hero: Bool) -> Color {
        if selected { return .white }
        if hero { return PCColors.accent }
        return PCColors.textPrimary
    }
}

// MARK: - PCMultiChipPicker (Multi Select)

struct PCMultiChipPicker<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Set<Item>
    let label: (Item) -> String
    var icon: ((Item) -> String)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PCTokens.spacingSM) {
                ForEach(items, id: \.self) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if selection.contains(item) {
                                selection.remove(item)
                            } else {
                                selection.insert(item)
                            }
                        }
                    } label: {
                        let isSelected = selection.contains(item)
                        HStack(spacing: PCTokens.spacingXS) {
                            if let icon, let iconName = Optional(icon(item)), !iconName.isEmpty {
                                Image(systemName: iconName)
                                    .font(.system(size: 12))
                            }
                            Text(label(item))
                                .font(PCFont.captionBold)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, PCTokens.spacingMD)
                        .padding(.vertical, PCTokens.spacingSM)
                        .background(isSelected ? PCColors.accent : PCColors.fillTertiary)
                        .foregroundStyle(isSelected ? .white : PCColors.textPrimary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, PCTokens.spacingLG)
        }
    }
}
