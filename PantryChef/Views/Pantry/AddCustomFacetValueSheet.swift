import SwiftUI

struct AddCustomFacetValueSheet: View {
    let itemID: String
    let itemName: String
    let facetKey: PantryFacetKey
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("New \(facetKey.title.lowercased()) value", text: $value)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Add \(facetKey.title) to \(itemName)")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add \(facetKey.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(value.trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else { return }

        let result = PantryCatalog.addFacetExtension(catalogItemID: itemID, key: facetKey, value: trimmed)
        switch result {
        case .success:
            onSave(trimmed)
            dismiss()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
