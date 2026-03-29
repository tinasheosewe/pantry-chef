import Foundation

/// Response model for the LLM-generated batch cook schedule.
/// Decoded from the structured JSON returned by the AI.
struct LLMBatchSchedule: Codable, Sendable {
    let blocks: [Block]

    struct Block: Codable, Sendable {
        let taskIDs: [String]
        let instruction: String
        let isPassive: Bool
        let durationSeconds: Int
    }
}

/// Errors from the LLM batch schedule generation flow.
enum BatchScheduleError: LocalizedError {
    case llmRequestFailed
    case invalidResponse
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .llmRequestFailed:
            return "Couldn't reach the AI to plan your cook session. Check your connection and try again."
        case .invalidResponse:
            return "The AI returned an unexpected response. Please try again."
        case .validationFailed(let detail):
            return "The AI schedule was incomplete (\(detail)). Please try again."
        }
    }
}
