import SwiftUI

/// The app's one Settings surface — household preferences and the dietary profile,
/// gathered out of the Dishes header so each space stays about its own content. New
/// preferences live here (the page floor, not a feature's corner).
struct SettingsView: View {
    var store: KitchenStore
    var onClose: () -> Void

    private var autoAdjust: Binding<Bool> {
        Binding(get: { store.autoAdjustDaysOnStorageChange },
                set: { store.autoAdjustDaysOnStorageChange = $0 })
    }
    private var assumeSpiceRack: Binding<Bool> {
        Binding(get: { store.assumeSpiceRack }, set: { store.assumeSpiceRack = $0 })
    }
    /// Turning reminders on asks for notification permission in context (never cold on
    /// launch); either way we reconcile the scheduled reminders to the new setting.
    private var expiryReminders: Binding<Bool> {
        Binding(get: { store.expiryReminders }, set: { on in
            store.expiryReminders = on
            Task {
                if on { await NotificationService.ensureAuthorized() }
                await NotificationService.syncExpiryReminders(store.expiryReminderPlans())
            }
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Theme.Palette.hairline).frame(width: 36, height: 4).padding(.top, 10)
            HStack {
                Text("Settings").font(Theme.Typography.dish(22)).foregroundStyle(Theme.Palette.ink)
                Spacer()
                Button("Done", action: onClose)
                    .font(Theme.Typography.fact(14, weight: .medium))
                    .foregroundStyle(Theme.Palette.paprika)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    pantrySection
                    dietarySection
                }
                .padding(20)
            }
        }
        .background(KitchenBackground())
    }

    // MARK: - Pantry

    private var pantrySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Pantry")
            DashedRule()
            Toggle(isOn: autoAdjust) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Adjust days-left on storage change")
                        .font(Theme.Typography.fact(15)).foregroundStyle(Theme.Palette.ink)
                    Text("Moving an item to the fridge or freezer re-projects how long it keeps. Turn off to move things without touching your own estimate.")
                        .font(Theme.Typography.note(12)).foregroundStyle(Theme.Palette.warmGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.Palette.paprika)
            Toggle(isOn: assumeSpiceRack) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Assume a basic spice rack")
                        .font(Theme.Typography.fact(15)).foregroundStyle(Theme.Palette.ink)
                    Text("Treat everyday dried spices (cumin, paprika, oregano, cinnamon…) as on hand, so a dish isn't \"a shop away\" over spices you almost certainly keep. Specialty ones (saffron, ras el hanout…) still count. Turn off to require every spice in your pantry.")
                        .font(Theme.Typography.note(12)).foregroundStyle(Theme.Palette.warmGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.Palette.paprika)
            Toggle(isOn: expiryReminders) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Use-it-up reminders")
                        .font(Theme.Typography.fact(15)).foregroundStyle(Theme.Palette.ink)
                    Text("Get a notification on the last good morning for anything about to turn, so it gets cooked instead of binned. Cook timers always notify; this covers the fridge.")
                        .font(Theme.Typography.note(12)).foregroundStyle(Theme.Palette.warmGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.Palette.paprika)
        }
    }

    // MARK: - Dietary

    private var dietarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Dietary")
            DashedRule()
            Text("What do you avoid?").font(Theme.Typography.fact(15)).foregroundStyle(Theme.Palette.ink)
            Text("Dishes containing these get flagged across the catalog.")
                .font(Theme.Typography.note(12)).foregroundStyle(Theme.Palette.warmGray)
            FlowChips(items: Allergen.allCases) { allergen in
                let on = store.profile.avoided.contains(allergen)
                Button {
                    if on { store.profile.avoided.remove(allergen) } else { store.profile.avoided.insert(allergen) }
                } label: {
                    Text(allergen.title.uppercased()).font(.system(size: 10)).tracking(1.4)
                        .foregroundStyle(on ? Theme.Palette.cream : Theme.Palette.ink.opacity(0.7))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Rectangle().fill(on ? Theme.Palette.paprika : .clear))
                        .overlay(Rectangle().strokeBorder(
                            on ? Theme.Palette.paprika : Theme.Palette.ink.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
    }
}

/// A simple wrapping row of chips.
private struct FlowChips<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 90), spacing: 8)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items) { content($0) }
        }
    }
}
