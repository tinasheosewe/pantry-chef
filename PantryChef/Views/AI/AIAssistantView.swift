import SwiftUI

struct AIAssistantView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: AIAssistantViewModel
    @FocusState private var isInputFocused: Bool

    init() {
        _viewModel = StateObject(wrappedValue: AIAssistantViewModel(appState: AppState()))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Quick Actions
                quickActions

                Divider()

                // Chat Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }

                            if viewModel.isLoading {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Thinking...")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.subtleText)
                                }
                                .padding()
                                .id("loading")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(viewModel.messages.last?.id ?? "loading", anchor: .bottom)
                        }
                    }
                }

                Divider()

                // Input Bar
                inputBar
            }
            .navigationTitle("Pantry Chef AI")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Quick Actions
    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                QuickChatAction(title: "What can I make?", icon: "fork.knife") {
                    Task { await viewModel.askWhatCanIMake() }
                }
                QuickChatAction(title: "Use up expiring", icon: "exclamationmark.triangle") {
                    Task { await viewModel.askWhatToUseUp() }
                }
                QuickChatAction(title: "Easy dinner", icon: "moon.fill") {
                    Task { await viewModel.askForEasyDinner() }
                }
                QuickChatAction(title: "Healthy meal", icon: "heart.fill") {
                    Task { await viewModel.askForHealthyMeal() }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(AppColors.lightGray)
    }

    // MARK: - Input Bar
    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask anything about cooking...", text: $viewModel.inputText, axis: .vertical)
                .font(.subheadline)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .padding(10)
                .background(AppColors.lightGray)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            Button {
                Task { await viewModel.sendMessage() }
                isInputFocused = false
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? AppColors.mediumGray
                            : AppColors.primaryGreen
                    )
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(AppColors.cardBackground)
    }
}

// MARK: - Chat Bubble
struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .assistant {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(AppColors.primaryGreen)
                        Text("Pantry Chef")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColors.subtleText)
                    }
                }

                Text(message.content)
                    .font(.subheadline)
                    .foregroundStyle(message.role == .user ? .white : AppColors.darkText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.role == .user
                            ? AppColors.primaryGreen
                            : AppColors.lightGray
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: 18)
                    )

                Text(message.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.mediumGray)
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Quick Chat Action
struct QuickChatAction: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(AppColors.primaryGreen)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.primaryGreen.opacity(0.1))
            .clipShape(Capsule())
        }
    }
}
