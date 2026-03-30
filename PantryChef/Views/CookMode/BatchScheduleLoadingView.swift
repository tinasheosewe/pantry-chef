import SwiftUI

/// Intermediate view that runs the async LLM schedule call, then presents MultiCookModeView.
struct BatchScheduleLoadingView: View {
    @Environment(AppState.self) private var appState

    let recipes: [Recipe]
    let aiService: AIServiceProtocol
    let queueID: UUID?
    let queueStageID: UUID?

    @State private var blocks: [MultiRecipeScheduler.ScheduledBlock]?
    @State private var error: String?
    @State private var isLoading = true

    init(recipes: [Recipe], aiService: AIServiceProtocol, queueID: UUID? = nil, queueStageID: UUID? = nil) {
        self.recipes = recipes
        self.aiService = aiService
        self.queueID = queueID
        self.queueStageID = queueStageID
    }

    var body: some View {
        Group {
            if let blocks {
                MultiCookModeView(
                    recipes: recipes,
                    blocks: blocks,
                    queueID: queueID,
                    queueStageID: queueStageID
                )
            } else if let error {
                errorView(error)
            } else {
                loadingView
            }
        }
        .task {
            await loadSchedule()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.3)
                .tint(PCColors.accent)

            Text("Planning your cook session…")
                .font(.headline)
                .foregroundStyle(PCColors.textPrimary)

            Text("The AI is figuring out the best way to interleave \(recipes.count) recipes.")
                .font(.subheadline)
                .foregroundStyle(PCColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PCColors.background.ignoresSafeArea())
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(PCColors.expired)

            Text("Couldn't Plan This Session")
                .font(.headline)
                .foregroundStyle(PCColors.textPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(PCColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Retry") {
                error = nil
                isLoading = true
                Task { await loadSchedule() }
            }
            .font(.headline)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(PCColors.accent)
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PCColors.background.ignoresSafeArea())
    }

    private func loadSchedule() async {
        do {
            let result = try await MultiRecipeScheduler.schedule(recipes: recipes, aiService: aiService)
            blocks = result
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
