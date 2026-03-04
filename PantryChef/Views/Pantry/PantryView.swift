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
    @State private var permissionGranted = false
    @State private var permissionDenied = false

    let onScan: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                if permissionDenied {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(AppColors.mediumGray)
                        Text("Camera Access Required")
                            .font(.headline)
                        Text("Go to Settings → Pantry Chef and enable Camera access to scan barcodes.")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.subtleText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.primaryGreen)
                    }
                } else if permissionGranted {
                    // Live camera feed
                    BarcodeCameraView { code in
                        guard scannedCode == nil else { return }
                        scannedCode = code
                    }
                    .ignoresSafeArea()

                    // Overlay
                    VStack {
                        Spacer()

                        // Viewfinder guide
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(.white.opacity(0.6), lineWidth: 2)
                            .frame(width: 280, height: 160)
                            .overlay(
                                Text("Point at barcode")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .offset(y: 90)
                            )

                        Spacer()

                        // Result display
                        if let code = scannedCode {
                            VStack(spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppColors.primaryGreen)
                                    Text(code)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                }

                                HStack(spacing: 16) {
                                    Button("Scan Again") {
                                        scannedCode = nil
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(.white.opacity(0.2))
                                    .clipShape(Capsule())

                                    Button("Add to Pantry") {
                                        onScan(code)
                                        dismiss()
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(AppColors.primaryGreen)
                                    .clipShape(Capsule())
                                }
                            }
                            .padding()
                            .background(.ultraThinMaterial.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding()
                        }
                    }
                } else {
                    ProgressView("Requesting camera access...")
                }
            }
            .background(.black)
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .task {
                await checkCameraPermission()
            }
        }
    }

    private func checkCameraPermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionGranted = granted
            permissionDenied = !granted
        default:
            permissionDenied = true
        }
    }
}

// MARK: - Camera UIViewControllerRepresentable
import AVFoundation

struct BarcodeCameraView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let vc = BarcodeScannerViewController()
        vc.onCodeScanned = onCodeScanned
        return vc
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
}

final class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: ((String) -> Void)?

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let feedbackGenerator = UINotificationFeedbackGenerator()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.stopRunning()
            }
        }
    }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        let metadataOutput = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            metadataOutput.metadataObjectTypes = [
                .ean8, .ean13, .upce, .code128, .code39,
                .code93, .itf14, .pdf417, .qr, .dataMatrix
            ]
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = view.bounds
        if let previewLayer {
            view.layer.addSublayer(previewLayer)
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = object.stringValue else { return }

        // Stop scanning after first hit
        captureSession.stopRunning()
        feedbackGenerator.notificationOccurred(.success)
        onCodeScanned?(code)
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
