public struct AlignmentSettings: Codable, Equatable, Sendable {
    public var actionBaseSize: Double
    public var ingredientBaseSize: Double
    public var minimumSize: Double
    public var autoShrink: Bool
    public var safeWidthFraction: Double

    public static let templateDefaults = AlignmentSettings(
        actionBaseSize: 17,
        ingredientBaseSize: 15,
        minimumSize: 13,
        autoShrink: true,
        safeWidthFraction: 0.9
    )

    public init(
        actionBaseSize: Double,
        ingredientBaseSize: Double,
        minimumSize: Double,
        autoShrink: Bool,
        safeWidthFraction: Double
    ) {
        self.actionBaseSize = actionBaseSize
        self.ingredientBaseSize = ingredientBaseSize
        self.minimumSize = minimumSize
        self.autoShrink = autoShrink
        self.safeWidthFraction = safeWidthFraction
    }
}
