import SwiftUI

@Observable
@MainActor
final class AIAssistantViewModel {
    var messages: [ChatMessage] = []
    var inputText = ""
    var isLoading = false

    let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        // Welcome message
        messages.append(ChatMessage(
            role: .assistant,
            content: "Hi! I'm your Pantry Chef assistant. Ask me anything about cooking, recipes, or what to make with what you have. 🍳"
        ))
    }

    var contextString: String {
        let pantryList = appState.pantryItems.prefix(20).map { item in
            "\(item.name)\(item.daysUntilExpiry.map { " (expires in \($0) days)" } ?? "")"
        }.joined(separator: ", ")

        let recipeCount = appState.recipes.count
        return "Pantry items: \(pantryList). Total recipes saved: \(recipeCount)."
    }

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""
        isLoading = true

        let response = await appState.aiService.chat(message: text, context: contextString)

        let assistantMessage = ChatMessage(role: .assistant, content: response)
        messages.append(assistantMessage)
        isLoading = false
    }

    // Quick action prompts
    func askWhatCanIMake() async {
        inputText = "What can I make with what I have in my pantry right now?"
        await sendMessage()
    }

    func askWhatToUseUp() async {
        let expiring = appState.expiringItems.map { $0.name }.joined(separator: ", ")
        inputText = "These items are expiring soon: \(expiring). What should I cook to use them up?"
        await sendMessage()
    }

    func askForEasyDinner() async {
        inputText = "Suggest a really easy dinner I can make tonight with what I have. I'm a beginner cook."
        await sendMessage()
    }

    func askForHealthyMeal() async {
        inputText = "Suggest a healthy, easy meal I can make with my pantry ingredients."
        await sendMessage()
    }
}
