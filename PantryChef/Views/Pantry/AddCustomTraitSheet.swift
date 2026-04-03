import SwiftUI

struct AddCustomTraitSheet: View {
    let existingKeys: Set<PantryFacetKey>
    let onSave: (PantryFacetKey, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedKey: PantryFacetKey?
    @State private var value = ""

    private var availableKeys: [PantryFacetKey] {
        PantryFacetKey.allCases.filter { !existingKeys.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trait Type") {
                    if availableKeys.isEmpty {
                        Text("All trait types have been added.")
                            .foregroundStyle(PCColors.textSecondary)
                    } else {
                        ForEach(availableKeys) { key in
                            Button {
                                selectedKey = key
                            } label: {
                                HStack {
                                    Text(key.title)
                                        .foregroundStyle(PCColors.textPrimary)
                                    Spacer()
                                    if selectedKey == key {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(PCColors.accent)
                                    }
                                }
                            }
                        }
                    }
                }

                if selectedKey != nil {
                    Section("Value") {
                        TextField("Enter value", text: $value)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                    }
                }
            }
            .navigationTitle("Add Trait")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(selectedKey == nil || value.trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let selectedKey, !value.trimmed.isEmpty else { return }
        onSave(selectedKey, value.trimmed)
        dismiss()
    }
}
