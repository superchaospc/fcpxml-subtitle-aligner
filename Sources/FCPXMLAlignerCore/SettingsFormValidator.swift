import Foundation

public struct SettingsFormFields: Equatable, Sendable {
    public var actionBaseSize: String
    public var ingredientBaseSize: String
    public var minimumSize: String
    public var autoShrink: Bool

    public init(actionBaseSize: String, ingredientBaseSize: String, minimumSize: String, autoShrink: Bool) {
        self.actionBaseSize = actionBaseSize
        self.ingredientBaseSize = ingredientBaseSize
        self.minimumSize = minimumSize
        self.autoShrink = autoShrink
    }

    public init(settings: AlignmentSettings) {
        actionBaseSize = Self.text(for: settings.actionBaseSize)
        ingredientBaseSize = Self.text(for: settings.ingredientBaseSize)
        minimumSize = Self.text(for: settings.minimumSize)
        autoShrink = settings.autoShrink
    }

    private static func text(for value: Double) -> String {
        String(value)
    }
}

public enum SettingsField: Equatable, Sendable {
    case actionBaseSize
    case ingredientBaseSize
    case minimumSize

    var label: String {
        switch self {
        case .actionBaseSize: "Action caption size"
        case .ingredientBaseSize: "Ingredient card size"
        case .minimumSize: "Minimum size"
        }
    }
}

public enum SettingsValidationError: Error, LocalizedError, Equatable, Sendable {
    case invalidNumber(field: SettingsField)
    case mustBePositive(field: SettingsField)
    case minimumExceedsBase

    public var errorDescription: String? {
        switch self {
        case .invalidNumber(let field):
            "\(field.label) must be a finite decimal number, using a period as the decimal separator."
        case .mustBePositive(let field):
            "\(field.label) must be greater than zero."
        case .minimumExceedsBase:
            "Minimum size must not exceed either Action caption size or Ingredient card size."
        }
    }
}

public enum SettingsFormValidator {
    public static func validate(_ fields: SettingsFormFields) -> Result<AlignmentSettings, SettingsValidationError> {
        guard let action = finiteNumber(from: fields.actionBaseSize) else {
            return .failure(.invalidNumber(field: .actionBaseSize))
        }
        guard action > 0 else { return .failure(.mustBePositive(field: .actionBaseSize)) }
        guard let ingredient = finiteNumber(from: fields.ingredientBaseSize) else {
            return .failure(.invalidNumber(field: .ingredientBaseSize))
        }
        guard ingredient > 0 else { return .failure(.mustBePositive(field: .ingredientBaseSize)) }
        guard let minimum = finiteNumber(from: fields.minimumSize) else {
            return .failure(.invalidNumber(field: .minimumSize))
        }
        guard minimum > 0 else { return .failure(.mustBePositive(field: .minimumSize)) }
        guard minimum <= action, minimum <= ingredient else { return .failure(.minimumExceedsBase) }

        return .success(AlignmentSettings(
            actionBaseSize: action,
            ingredientBaseSize: ingredient,
            minimumSize: minimum,
            autoShrink: fields.autoShrink,
            safeWidthFraction: AlignmentSettings.templateDefaults.safeWidthFraction
        ))
    }

    private static func finiteNumber(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)$"
        guard trimmed.range(of: pattern, options: .regularExpression) != nil,
              let value = Double(trimmed), value.isFinite
        else { return nil }
        return value
    }
}
