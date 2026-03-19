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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    pantryList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityIdentifier("pantry.screen")
            .background(AppColors.background)
            .navigationTitle("Pantry")
            .sheet(isPresented: $viewModel.showAddItem) {
                AddPantryItemView { item in
                    Task { await viewModel.addItem(item) }
                }
            }
            .sheet(isPresented: $viewModel.showBarcodeScanner) {
                BarcodeScannerView { item in
                    Task { await viewModel.addItem(item) }
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
                InputMethodButton(icon: "barcode.viewfinder", title: "Barcode", color: AppColors.accentBlue) {
                    viewModel.showBarcodeScanner = true
                }
                InputMethodButton(icon: "doc.text.viewfinder", title: "Receipt", color: AppColors.warmOrange) {
                    viewModel.showReceiptScanner = true
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
                    .accessibilityIdentifier("pantry.searchField")
                    .onChange(of: viewModel.searchText) {
                        viewModel.onSearchTextChanged()
                    }

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
        .accessibilityIdentifier("pantry.list")
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

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedQuantity: Double? {
        guard !quantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Double(quantity)
    }

    private var quantityIsInvalid: Bool {
        !quantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsedQuantity == nil
    }

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
                    if quantityIsInvalid {
                        Text("Enter a valid number for quantity")
                            .font(.caption)
                            .foregroundStyle(AppColors.softRed)
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
                            name: trimmedName,
                            category: category,
                            quantity: parsedQuantity,
                            unit: unit,
                            expiryDate: hasExpiry ? expiryDate : nil,
                            notes: notes.isEmpty ? nil : notes
                        )
                        onSave(item)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty || quantityIsInvalid)
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
    @State private var isLookingUp = false
    @State private var lookupResult: BarcodeLookupResult?
    @State private var lookupDone = false
    @State private var manualName = ""
    @State private var selectedCategory: FoodCategory = .other

    private let barcodeService = BarcodeScannerService()
    let onItemScanned: (PantryItem) -> Void

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
                        Task { await performLookup(code) }
                    }
                    .ignoresSafeArea()

                    // Overlay
                    VStack {
                        Spacer()

                        if scannedCode == nil {
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
                        }

                        Spacer()

                        // Result overlay
                        if scannedCode != nil {
                            resultOverlay
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

    // MARK: - Result Overlay
    @ViewBuilder
    private var resultOverlay: some View {
        VStack(spacing: 12) {
            if isLookingUp {
                ProgressView()
                    .tint(.white)
                Text("Looking up product...")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            } else if lookupDone {
                if let result = lookupResult {
                    // Product found
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColors.primaryGreen)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.productName)
                                .font(.headline)
                                .foregroundStyle(.white)
                            if let brand = result.brand {
                                Text(brand)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            Text(result.category?.rawValue ?? "Other")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                } else {
                    // Product not found — manual entry
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "questionmark.circle.fill")
                                .foregroundStyle(.orange)
                            Text("Product not found")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        }
                        TextField("Enter product name", text: $manualName)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(FoodCategory.allCases, id: \.self) { cat in
                                Text(cat.rawValue).tag(cat)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.white)
                    }
                }

                // Action buttons
                HStack(spacing: 16) {
                    Button("Scan Again") {
                        resetScan()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.2))
                    .clipShape(Capsule())

                    Button("Add to Pantry") {
                        addToPantry()
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(addButtonDisabled ? AppColors.mediumGray : AppColors.primaryGreen)
                    .clipShape(Capsule())
                    .disabled(addButtonDisabled)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private var addButtonDisabled: Bool {
        lookupResult == nil && manualName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions
    private func performLookup(_ code: String) async {
        isLookingUp = true
        lookupResult = await barcodeService.lookupBarcode(code)
        isLookingUp = false
        lookupDone = true
    }

    private func resetScan() {
        scannedCode = nil
        lookupResult = nil
        lookupDone = false
        isLookingUp = false
        manualName = ""
        selectedCategory = .other
    }

    private func addToPantry() {
        guard let code = scannedCode else { return }
        let name: String
        let category: FoodCategory
        let imageURL: String?

        if let result = lookupResult {
            name = result.productName
            category = result.category ?? .other
            imageURL = result.imageURL
        } else {
            name = manualName.trimmingCharacters(in: .whitespaces)
            category = selectedCategory
            imageURL = nil
        }
        guard !name.isEmpty else { return }

        let item = PantryItem(
            name: name,
            category: category,
            quantity: 1,
            unit: .piece,
            barcode: code,
            imageURL: imageURL
        )
        onItemScanned(item)
        dismiss()
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
    @State private var isProcessing = false
    @State private var showImagePicker = false
    @State private var capturedImage: UIImage?
    @State private var errorText: String?

    private let receiptService = ReceiptScannerService()
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

                        Text("We'll use OCR to extract the grocery items")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.subtleText)

                        if isProcessing {
                            ProgressView("Scanning receipt...")
                                .padding()
                        } else {
                            Button("Take Photo") {
                                showImagePicker = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppColors.warmOrange)
                        }

                        if let errorText {
                            Text(errorText)
                                .font(.caption)
                                .foregroundStyle(AppColors.softRed)
                                .padding(.horizontal)
                        }
                    }
                    .padding()
                } else {
                    if extractedItems.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundStyle(AppColors.mediumGray)
                            Text("No items found")
                                .font(.headline)
                            Text("Try taking a clearer photo of the receipt.")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.subtleText)
                            Button("Try Again") {
                                hasScanned = false
                                capturedImage = nil
                                extractedItems = []
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppColors.warmOrange)
                        }
                        .padding()
                    } else {
                        List {
                            Section("Found Items (\(extractedItems.count))") {
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

                        HStack(spacing: 12) {
                            Button("Scan Again") {
                                hasScanned = false
                                capturedImage = nil
                                extractedItems = []
                                selectedItems = []
                            }
                            .buttonStyle(.bordered)

                            Button("Add \(selectedItems.count) Items to Pantry") {
                                onSave(Array(selectedItems))
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppColors.primaryGreen)
                            .disabled(selectedItems.isEmpty)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $capturedImage)
            }
            .onChange(of: capturedImage) { _, newImage in
                guard let image = newImage else { return }
                Task {
                    await processReceipt(image: image)
                }
            }
        }
    }

    private func processReceipt(image: UIImage) async {
        isProcessing = true
        errorText = nil
        let items = await receiptService.scanReceipt(image: image)
        isProcessing = false
        if items.isEmpty {
            errorText = "Could not find any grocery items. Try a clearer photo."
            hasScanned = true
        } else {
            extractedItems = items
            selectedItems = Set(items)
            hasScanned = true
        }
    }
}

// MARK: - Image Picker (Camera + Photo Library)
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        // Use camera if available, otherwise photo library
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            picker.sourceType = .photoLibrary
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
