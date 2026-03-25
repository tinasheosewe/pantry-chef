import SwiftUI

// MARK: - PCScreen

struct PCScreen<Content: View>: View {
    private let screenID: String
    private let content: Content

    init(_ screenID: String, @ViewBuilder content: () -> Content) {
        self.screenID = screenID
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .accessibilityIdentifier(screenID)
                .background(PCColors.background)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - PCSheet

struct PCSheet<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

extension View {
    func pcSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        sheet(isPresented: isPresented) {
            PCSheet(content: content)
        }
    }

    func pcSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        sheet(item: item) { item in
            PCSheet {
                content(item)
            }
        }
    }
}

// MARK: - PCScrollView

struct PCScrollView<Content: View>: View {
    private let axes: Axis.Set
    private let showsIndicators: Bool
    private let content: () -> Content

    init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content
    }

    var body: some View {
        ScrollView(axes, showsIndicators: showsIndicators) {
            content()
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - PCList

struct PCList<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        List {
            content()
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - PCForm

struct PCForm<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        Form {
            content()
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
