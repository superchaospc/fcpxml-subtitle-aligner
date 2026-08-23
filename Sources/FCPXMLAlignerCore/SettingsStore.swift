import Foundation

/// Persists the last accepted alignment choices without making persistence a precondition for processing.
public struct SettingsStore {
    public static let defaultKey = "FCPXMLSubtitleAligner.alignmentSettings"

    private let defaults: UserDefaults
    private let key: String
    private static let previousTemplateDefaults = AlignmentSettings(
        actionBaseSize: 17,
        ingredientBaseSize: 16,
        minimumSize: 13,
        autoShrink: true,
        safeWidthFraction: 0.72
    )

    public init(defaults: UserDefaults = .standard, key: String = defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> AlignmentSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AlignmentSettings.self, from: data)
        else {
            return .templateDefaults
        }
        guard settings == Self.previousTemplateDefaults else { return settings }
        let migrated = AlignmentSettings.templateDefaults
        save(migrated)
        return migrated
    }

    public func save(_ settings: AlignmentSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }

    @discardableResult
    public func restoreDefaults() -> AlignmentSettings {
        let settings = AlignmentSettings.templateDefaults
        save(settings)
        return settings
    }
}
