import SwiftUI

/// The shopping run (spec §3): a checklist you use in the aisle. Check things as
/// they go in the cart, adjust the amount you actually bought, add anything extra
/// you picked up — then "Done" moves everything checked into Stores, freshly
/// confirmed, and leaves the rest on the list. Printed-receipt furniture to match
/// the Field Notes world.
struct ShoppingChecklistView: View {
    var store: KitchenStore
    var onClose: () -> Void

    /// Local cart state — committed only on Done, so a mistaken tap costs nothing.
    @State private var checked: Set<String> = []
    @State private var amounts: [String: String] = [:]
    @State private var extras: [String] = []
    @State private var newItem = ""
    @FocusState private var addingFocused: Bool

    private var allNames: [String] { store.shoppingList + extras }
    private var boughtCount: Int { checked.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            DashedRule().padding(.horizontal, 20).padding(.top, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(allNames, id: \.self) { name in
                        row(name)
                        if name != allNames.last { DashedRule(opacity: 0.5) }
                    }
                    addRow.padding(.top, 14)
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
            footer
        }
        .background(KitchenBackground())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shopping").font(Theme.Typography.dish(22)).foregroundStyle(Theme.Palette.ink)
                Text("Check things off as they go in the cart.")
                    .font(Theme.Typography.note(11.5)).foregroundStyle(Theme.Palette.warmGray)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Palette.warmGray)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.top, 18)
    }

    private func row(_ name: String) -> some View {
        let isChecked = checked.contains(name)
        return HStack(spacing: 11) {
            Button { toggle(name) } label: {
                InkCheck(on: isChecked, size: 22)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            PlateView(name: name, composition: store.plate(forName: name), size: 28)
            Text(name).font(Theme.Typography.fact(14.5)).foregroundStyle(Theme.Palette.ink)
                .strikethrough(isChecked, color: Theme.Palette.warmGraySoft)
            Spacer(minLength: 6)
            // Amount you actually bought — only worth asking once it's in the cart.
            if isChecked {
                TextField("amt", text: Binding(
                    get: { amounts[name] ?? "" }, set: { amounts[name] = $0 }))
                    .font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.ink)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .padding(.horizontal, 8).frame(minHeight: 34)
                    .overlay(Rectangle().strokeBorder(Theme.Palette.ink.opacity(0.3), lineWidth: 1))
            }
        }
        .padding(.vertical, 4)
        .animation(.spring(response: 0.3, dampingFraction: 1), value: isChecked)
    }

    private var addRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus").font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Palette.paprika).frame(width: 22)
            TextField("Add something you grabbed", text: $newItem)
                .font(Theme.Typography.fact(14)).foregroundStyle(Theme.Palette.ink)
                .focused($addingFocused)
                .onSubmit(commitNewItem)
            if !newItem.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Add", action: commitNewItem)
                    .font(Theme.Typography.fact(13, weight: .medium))
                    .foregroundStyle(Theme.Palette.paprika)
                    .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            SolidRule()
            HStack {
                Text("\(boughtCount) IN THE CART")
                    .font(.system(size: 10, weight: .medium)).tracking(1.4)
                    .foregroundStyle(Theme.Palette.warmGray)
                Spacer()
                BlockButton(title: boughtCount > 0 ? "Put \(boughtCount) away" : "Done") {
                    for name in checked { store.purchase(name: name, amount: amounts[name]) }
                    onClose()
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(Theme.Palette.cream)
    }

    private func toggle(_ name: String) {
        if checked.contains(name) { checked.remove(name) } else { checked.insert(name) }
    }

    private func commitNewItem() {
        let trimmed = newItem.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let entry = trimmed.prefix(1).capitalized + trimmed.dropFirst()
        if !allNames.contains(entry) { extras.append(entry) }
        checked.insert(entry)   // you grabbed it, so it's already in the cart
        newItem = ""
        addingFocused = true
    }
}
