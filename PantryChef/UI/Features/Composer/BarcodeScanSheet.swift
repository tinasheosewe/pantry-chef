import SwiftUI
import VisionKit

/// Live barcode scanning to build the pantry fast (deterministic + free — no AI). Stays
/// open so you can scan a row of jars and cans in one go; each scan resolves through
/// Open Food Facts → the catalog, and lands in a running "added" list you can correct
/// (branded names can mis-resolve, so review matters). Needs a real device camera —
/// the simulator and pre-A12 devices fall back to a friendly note.
struct BarcodeScanSheet: View {
    var store: KitchenStore
    var onClose: () -> Void

    @State private var added: [String] = []
    @State private var seen: Set<String> = []
    @State private var looking = false

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if scannerAvailable {
                BarcodeScannerView { code in handle(code) }
                    .overlay(alignment: .top) { hint }
            } else {
                unsupported
            }
            footer
        }
        .background(KitchenBackground())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scan your pantry").font(Theme.Typography.dish(22)).foregroundStyle(Theme.Palette.ink)
                Text("Point at a barcode — keep going to add a whole shelf.")
                    .font(Theme.Typography.note(11.5)).foregroundStyle(Theme.Palette.warmGray)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Palette.warmGray).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Done")
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
    }

    private var hint: some View {
        HStack(spacing: 6) {
            if looking { ProgressView().controlSize(.small).tint(Theme.Palette.cream) }
            Text(looking ? "Looking it up…" : "Hold steady over a barcode")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.Palette.cream)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(.black.opacity(0.55)))
        .padding(.top, 12)
    }

    private var unsupported: some View {
        VStack(spacing: 10) {
            Image(systemName: "barcode.viewfinder").font(.system(size: 40)).foregroundStyle(Theme.Palette.warmGraySoft)
            Text("Barcode scanning needs a device camera")
                .font(Theme.Typography.fact(15, weight: .medium)).foregroundStyle(Theme.Palette.ink)
            Text("Open PantryChef on your iPhone to scan. For now, add items by tapping or typing.")
                .font(Theme.Typography.note(13)).foregroundStyle(Theme.Palette.warmGray)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var footer: some View {
        VStack(spacing: 0) {
            SolidRule()
            if added.isEmpty {
                Text(scannerAvailable ? "Nothing scanned yet." : " ")
                    .font(Theme.Typography.note(12)).foregroundStyle(Theme.Palette.warmGraySoft)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(added.count) ADDED").font(Theme.Typography.eyebrow)
                            .tracking(Theme.Metric.eyebrowTracking).foregroundStyle(Theme.Palette.warmGraySoft)
                            .padding(.bottom, 6)
                        ForEach(Array(added.enumerated()), id: \.offset) { i, name in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.Palette.sage)
                                Text(name).font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.ink)
                                Spacer()
                                Button { remove(i, name: name) } label: {
                                    Image(systemName: "minus.circle.fill").font(.system(size: 15))
                                        .foregroundStyle(Theme.Palette.warmGraySoft.opacity(0.7))
                                }
                                .buttonStyle(.plain).accessibilityLabel("Remove \(name)")
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 10)
                }
                .frame(maxHeight: 150)
            }
            PaprikaButton(title: added.isEmpty ? "Done" : "Done · \(added.count) added") { onClose() }
                .frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.bottom, 12)
        }
        .background(Theme.Palette.cream)
    }

    private func handle(_ code: String) {
        guard seen.insert(code).inserted else { return }   // ignore the same barcode held in view
        looking = true
        Task {
            let name = await ProductLookup.lookup(barcode: code).map { store.addScannedProduct(name: $0.name) }
            looking = false
            if let name {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation { added.append(name) }
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                seen.remove(code)   // not found → allow a retry
            }
        }
    }

    private func remove(_ index: Int, name: String) {
        store.removeStockByName(name)
        withAnimation { if added.indices.contains(index) { added.remove(at: index) } }
    }
}

/// VisionKit live barcode scanner. Reports each newly-seen barcode payload.
private struct BarcodeScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        try? vc.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    onScan(payload)
                }
            }
        }
    }
}
