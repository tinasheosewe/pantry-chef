import Foundation

struct PresentedAppError: Identifiable, Sendable {
    let id = UUID()
    let error: AppError

    var localizedDescription: String {
        error.localizedDescription
    }
}

/// Typed error for domain-aware error reporting across the app.
enum AppError: Sendable {
    case storage(any Error)
    case validation(String)
    case loadFailure([String])
    case ai(operation: String, message: String)

    var localizedDescription: String {
        switch self {
        case .storage(let error): return error.localizedDescription
        case .validation(let message): return message
        case .loadFailure(let messages): return messages.joined(separator: "\n")
        case .ai(_, let message): return message
        }
    }

    var telemetryType: String {
        switch self {
        case .storage:
            return "storage"
        case .validation:
            return "validation"
        case .loadFailure:
            return "load_failure"
        case .ai(let operation, _):
            return "ai_\(operation.replacingOccurrences(of: " ", with: "_"))"
        }
    }
}
