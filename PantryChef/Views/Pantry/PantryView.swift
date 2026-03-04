import SwiftUI

struct PantryView: View {
    @State private var viewModel: PantryViewModel

    init(appState: AppState) {
        _viewModel = State(initialValue: PantryViewModel(appState: appState))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            VStack(spacing: 0) {
                inputMethodsBar
                searchAndSortBar

                if viewModel.appState.pantryItems.isEmpty {
                    EmptyStateView(
                        icon: "refrigerator",
                        title: "Your pantry is empty",
                        message: "Add items by scanning barcodes, photographing receipts, or entering them manually.",
                        actionTitle: "Add First Item"
                    ) {
                        viewModel.showAddItem = true
                    }
                } else {
                    pantryList
                }
            }
            .background(AppColors.background)
            .navigationTitle("Pantry")
            .sheet(isPresented: $viewModel.showAddItem) {
                AddPantryItemView { item in
                    Task { await viewModel.addItem(item) }
                }
            }
            .sheet(isPresented: $viewModel.showBarcodeScanner) {
                BarcodeScannerView { barcode in
                    Task { await viewModel.handleBarcodeScanned(barcode) }
                }
            }
            .sheet(isPresented: $viewModel.showReceiptScanner) {
                ReceiptScannerView { items in
                    Task { await viewModel.handleReceiptScanned(items: items) }
                }
            }
        }
    }

    // MARK: - Input Methods Bar
    private var inputMethodsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                InputMethodButton(icon: "plus.circle.fill", title: "Add", color: AppColors.primaryGreen) {
                    viewModel.showAddItem = true
                }
                InputMethodButton(icon: "barcode.viewfinder", title: "Barcode", color: .blue) {
                    viewModel.showBarcodeScanner = true
                }
                InputMethodButton(icon: "doc.text.viewfinder", title: "Receipt", color: AppColors.warmOrange) {
                    viewModel.showReceiptScanner = true
                }
                InputMethodButton(icon: "mic.fill", title: "Voice", color: .purple) {
                    viewModel.showVoiceInput = true
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(AppColors.cardBackground)
    }

    // MARK: - Search & Sort
    private var searchAndSortBar: some View {
        @Bindable var viewModel = viewModel
        return VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColors.mediumGray)
                TextField("Search pantry...", text: $viewModel.searchText)
                    .font(.subheadline)

                if !viewModel.searchText.isEmpty {
                    Button { viewModel.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.mediumGray)
                    }
                }
            }
            .padding(10)
            .background(AppColors.lightGray)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryPill(title: "All", isSelected: viewModel.selectedCategory == nil) {
                        viewModel.selectedCategory = nil
                    }
                    ForEach(FoodCategory.allCases) { category in
                        if let count = viewModel.activeCategoryCount[category], count > 0 {
                            CategoryPill(
                                title: "\(category.rawValue) (\(count))",
                                isSelected: viewModel.selectedCategory == category
                            ) {
                                viewModel.selectedCategory = viewModel.selectedCategory == category ? nil : category
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Pantry List
    private var pantryList: some View {
        List {
            ForEach(viewModel.groupedByCategory, id: \.0) { category, items in
                Section {
                    ForEach(items) { item in
                        PantryItemRow(item: item)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteItem(item) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    HStack(spacing: 8) {
                        CategoryIcon(category: category, size: 24)
                        Text(category.rawValue)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Input Method Button
struct InputMethodButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(AppColors.darkText)
            }
            .frame(width: 70, height: 56)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Category Pill
struct CategoryPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? AppColors.primaryGreen : AppColors.lightGray)
                .foregroundStyle(isSelected ? .white : AppColors.subtleText)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Pantry Item Row
struct PantryItemRow: View {
    let item: PantryItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if !item.displayQuantity.isEmpty {
                    Text(item.displayQuantity)
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }
            }

            Spacer()

            if item.expiryDate != nil {
                ExpiryBadge(status: item.expiryStatus, daysLeft: item.daysUntilExpiry)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Pantry Item View
struct AddPantryItemView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category: FoodCategory = .other
    @State private var quantity: String = ""
    @State private var unit: MeasurementUnit = .piece
    @State private var expiryDate = Date()
    @State private var hasExpiry = false
    @State private var notes = ""

    let onSave: (PantryItem) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $category) {
                        ForEach(FoodCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon)
                                .tag(cat)
                        }
                    }
                }

                Section("Quantity") {
                    HStack {
                        TextField("Amount", text: $quantity)
                            .keyboardType(.decimalPad)
                        Picker("Unit", selection: $unit) {
                            ForEach(MeasurementUnit.allCases) { u in
                                Text(u.rawValue).tag(u)
                            }
                        }
                    }
                }

                Section("Expiry") {
                    Toggle("Has expiry date", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("Expires on", selection: $expiryDate, displayedComponents: .date)
                    }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3)
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let item = PantryItem(
                            name: name,
                            category: category,
                            quantity: Double(quantity),
                            unit: unit,
                            expiryDate: hasExpiry ? expiryDate : nil,
                            notes: notes.isEmpty ? nil : notes
                        )
                        onSave(item)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

// MARK: - Barcode Scanner View
struct BarcodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scannedCode: String?
    @State private var isScanning = true

    let onScan: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.black)
                        .aspectRatio(4/3, contentMode: .fit)

                    VStack(spacing: 12) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 64))
                            .foregroundStyle(.white)
                        Text("Point camera at barcode")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding()

                if let code = scannedCode {
                    VStack(spacing: 8) {
                        Text("Scanned: \(code)")
                            .font(.headline)
                        Button("Add to Pantry") {
                            onScan(code)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.primaryGreen)
                    }
                }

                Spacer()
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Receipt Scanner View
struct ReceiptScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var extractedItems: [String] = []
    @State private var selectedItems: Set<String> = []
    @State private var hasScanned = false

    let onSave: ([String]) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if !hasScanned {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 64))
                            .foregroundStyle(AppColors.warmOrange)

                        Text("Take a photo of your receipt")
                            .font(.headline)

                        Text("We'll use AI to extract the grocery items")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.subtleText)

                        Button("Take Photo") {
                            hasScanned = true
                            extractedItems = ["Milk", "Eggs", "Bread", "Tomatoes", "Chicken"]
                            selectedItems = Set(extractedItems)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.warmOrange)
                    }
                    .padding()
                } else {
                    List {
                        Section("Found Items") {
                            ForEach(extractedItems, id: \.self) { item in
                                HStack {
                                    Image(systemName: selectedItems.contains(item) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedItems.contains(item) ? AppColors.primaryGreen : AppColors.mediumGray)
                                    Text(item)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if selectedItems.contains(item) {
                                        selectedItems.remove(item)
                                    } else {
                                        selectedItems.insert(item)
                                    }
                                }
                            }
                        }
                    }

                    Button("Add \(selectedItems.count) Items to Pantry") {
                        onSave(Array(selectedItems))
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.primaryGreen)
                    .padding()
                }
            }
            .navigationTitle("Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
