import Foundation

/// Typed error for domain-aware error reporting across the app.
enum AppError: Identifiable, Sendable {
    case storage(any Error)
    case validation(String)
    case loadFailure([String])

    var id: String { localizedDescription }

    var localizedDescription: String {
        switch self {
        case .storage(let error): return error.localizedDescription
        case .validation(let message): return message
        case .loadFailure(let messages): return messages.joined(separator: "\n")
        }
    }
}
