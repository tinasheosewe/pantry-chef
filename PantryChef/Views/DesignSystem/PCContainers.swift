import SwiftUI

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
