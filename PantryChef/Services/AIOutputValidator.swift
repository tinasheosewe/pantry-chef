import Foundation
import NaturalLanguage

enum AIOutputIssue: Equatable, CustomStringConvertible {
    case emptyTitle
    case missingIngredients
    case missingSteps
    case wrongLanguage(expected: String, actual: String?)
    case nonSequentialStepNumbers(actual: [Int])
    case invalidTimer(stepNumber: Int)
    case invalidEstimatedDuration(stepNumber: Int)
    case invalidIngredientQuantity(name: String)
    case invalidTaskDuration(stepNumber: Int)

    var description: String {
        switch self {
        case .emptyTitle:
            return "emptyTitle"
        case .missingIngredients:
            return "missingIngredients"
        case .missingSteps:
            return "missingSteps"
        case .wrongLanguage(let expected, let actual):
            let actualLanguage = actual ?? "unknown"
            return "wrongLanguage(expected: \(expected), actual: \(actualLanguage))"
        case .nonSequentialStepNumbers(let actual):
            return "nonSequentialStepNumbers(\(actual))"
        case .invalidTimer(let stepNumber):
            return "invalidTimer(step: \(stepNumber))"
        case .invalidEstimatedDuration(let stepNumber):
            return "invalidEstimatedDuration(step: \(stepNumber))"
        case .invalidIngredientQuantity(let name):
            return "invalidIngredientQuantity(\(name))"
        case .invalidTaskDuration(let stepNumber):
            return "invalidTaskDuration(step: \(stepNumber))"
        }
    }
}

enum AIOutputValidator {
    static func validate(importResult: RecipeImportResult, expectedLanguage: NLLanguage = .english) -> [AIOutputIssue] {
        validate(recipe: importResult.toRecipe(), expectedLanguage: expectedLanguage)
    }

    static func validate(recipe: Recipe, expectedLanguage: NLLanguage = .english) -> [AIOutputIssue] {
        var issues: [AIOutputIssue] = []

        if recipe.title.trimmed.isEmpty {
            issues.append(.emptyTitle)
        }

        if recipe.ingredients.isEmpty {
            issues.append(.missingIngredients)
        }

        if recipe.steps.isEmpty {
            issues.append(.missingSteps)
        }

        let actualStepNumbers = recipe.steps.map(\.stepNumber)
        let expectedStepNumbers = recipe.steps.isEmpty ? [] : Array(1...recipe.steps.count)
        if !recipe.steps.isEmpty, actualStepNumbers != expectedStepNumbers {
            issues.append(.nonSequentialStepNumbers(actual: actualStepNumbers))
        }

        for ingredient in recipe.ingredients where ingredient.quantity <= 0 {
            issues.append(.invalidIngredientQuantity(name: ingredient.name))
        }

        for step in recipe.steps {
            if let timerMinutes = step.timerMinutes, timerMinutes < 0 {
                issues.append(.invalidTimer(stepNumber: step.stepNumber))
            }
            if let estimatedDurationSeconds = step.estimatedDurationSeconds, estimatedDurationSeconds <= 0 {
                issues.append(.invalidEstimatedDuration(stepNumber: step.stepNumber))
            }
            if step.tasks.contains(where: { $0.durationSeconds <= 0 }) {
                issues.append(.invalidTaskDuration(stepNumber: step.stepNumber))
            }
        }

        if let detectedLanguage = dominantLanguage(for: recipe),
           shouldEnforceLanguage(for: recipe),
           detectedLanguage != expectedLanguage {
            issues.append(.wrongLanguage(expected: expectedLanguage.rawValue, actual: detectedLanguage.rawValue))
        }

        return issues
    }

    static func dominantLanguage(for recipe: Recipe) -> NLLanguage? {
        let text = [recipe.title, recipe.description ?? "", recipe.steps.map(\.instruction).joined(separator: " ")]
            .joined(separator: " ")
        return dominantLanguage(for: text)
    }

    static func dominantLanguage(for text: String) -> NLLanguage? {
        let trimmed = text.trimmed
        guard trimmed.count >= 20 else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        guard let detected = hypotheses.first else { return nil }
        guard detected.value >= 0.5 else { return nil }
        return detected.key
    }

    private static func shouldEnforceLanguage(for recipe: Recipe) -> Bool {
        let combinedText = [recipe.title, recipe.description ?? "", recipe.steps.map(\.instruction).joined(separator: " ")]
            .joined(separator: " ")
            .trimmed
        return combinedText.count >= 20
    }
}
