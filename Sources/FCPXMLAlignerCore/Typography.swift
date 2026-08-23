import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum TypographyFontFace: String, Equatable, Sendable {
    case regular = "Regular"
    case italic = "Italic"
}

public enum TypographyAlignment: String, Equatable, Sendable {
    case center
    case left
}

public enum LayoutVariant: Equatable, Sendable {
    case ordinary
    case heroAction
}

public enum LayoutVariantSelector {
    public static func select(visibleText: String) -> LayoutVariant {
        let normalized = visibleText
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return normalized == "dish up" ? .heroAction : .ordinary
    }
}

public struct TypographyPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct TypographyRun: Equatable, Sendable {
    public let text: String
    public let isItalic: Bool

    public init(text: String, isItalic: Bool = false) {
        self.text = text
        self.isItalic = isItalic
    }
}

public protocol FontMetricsMeasuring {
    func width(
        of text: String,
        fontFamily: String,
        fontFace: TypographyFontFace,
        fontSize: Double
    ) throws -> Double

    func lineHeight(
        fontFamily: String,
        fontFace: TypographyFontFace,
        fontSize: Double
    ) throws -> Double
}

#if canImport(AppKit)
public struct AppKitFontMetrics: FontMetricsMeasuring {
    public init() {}

    public func width(
        of text: String,
        fontFamily: String,
        fontFace: TypographyFontFace,
        fontSize: Double
    ) throws -> Double {
        let font = try font(family: fontFamily, face: fontFace, size: fontSize)
        return NSAttributedString(string: text, attributes: [.font: font]).size().width
    }

    public func lineHeight(
        fontFamily: String,
        fontFace: TypographyFontFace,
        fontSize: Double
    ) throws -> Double {
        let font = try font(family: fontFamily, face: fontFace, size: fontSize)
        return NSLayoutManager().defaultLineHeight(for: font)
    }

    private func font(family: String, face: TypographyFontFace, size: Double) throws -> NSFont {
        let traits: NSFontTraitMask = face == .italic ? .italicFontMask : []
        guard
            let font = NSFontManager.shared.font(
                withFamily: family,
                traits: traits,
                weight: 5,
                size: size
            ),
            font.familyName?.caseInsensitiveCompare(family) == .orderedSame,
            NSFontManager.shared.traits(of: font).contains(.italicFontMask) == (face == .italic)
        else {
            throw AlignerError.targetFontUnavailable(family: family, face: face.rawValue)
        }
        return font
    }
}
#endif

public enum TemplateCalibration {
    public static let titleScale = 1.65437
    /// Least-squares fit against the comparable ordinary action and closing title widths in the gold fixture.
    public static let measuredWidthMultiplier = 1.696058061413046
    public static let fixedWidthPaddingPixels = 49.120673730289418
    /// Additional symmetric breathing room measured from the user's uppercase action screenshot.
    public static let actionExtraHorizontalPaddingPixels = 40.0
    public static let actionHeightAt17 = 0.0387046
    public static let uppercaseActionHeightAt17 = 0.04135
    public static let closingHeightAt17TwoLines = 0.0669004
    public static let ingredientHeightAt15FiveLines = 0.14387
    public static let uppercaseIngredientHeightAt15FiveLines = 0.15006

    public static let actionTitlePosition = TypographyPoint(x: -0.0112916, y: 30.3714)
    public static let uppercaseActionTitlePosition = TypographyPoint(x: -0.0112916, y: 30.246)
    public static let actionBackgroundPosition = TypographyPoint(x: 0.00640178, y: 31.1507)
    public static let ingredientTitlePosition = TypographyPoint(x: -9.86106, y: 35.7613)
    public static let uppercaseIngredientTitlePosition = TypographyPoint(x: -9.86106, y: 35.971)
    public static let ingredientReferenceBackgroundPosition = TypographyPoint(x: -0.0199015, y: 31.0997)
    public static let closingTitlePosition = TypographyPoint(x: -0.0112916, y: 31.9841)
    public static let closingBackgroundPosition = TypographyPoint(x: 0.00640178, y: 31.3437)

    static let ingredientReferenceBackgroundScaleX = 0.395549
    static let ingredientWidthCalibration = 1.038445354310869
}

public struct TypographyLayout: Equatable, Sendable {
    public let kind: TitleKind
    public let variant: LayoutVariant
    public let finalFontSize: Double
    public let fontFamily: String
    public let fontFace: String
    public let isBold: Bool
    public let alignment: TypographyAlignment
    public let lineSpacing: Double
    public let titlePosition: TypographyPoint
    public let titleScale: Double
    public let backgroundPosition: TypographyPoint
    public let backgroundScaleX: Double
    public let backgroundScaleY: Double
    public let autoShrunk: Bool
    public let fitsSafeWidth: Bool
}

public struct TypographyLayouter {
    private struct HeightProfile {
        let referenceHeight: Double
        let referenceFontSize: Double
        let referenceLineCount: Int
    }

    private let metrics: any FontMetricsMeasuring

    public init(metrics: any FontMetricsMeasuring) {
        self.metrics = metrics
    }

    public func layout(
        title: TitleRecord,
        kind: TitleKind,
        settings: AlignmentSettings
    ) throws -> TypographyLayout {
        guard let dimensions = title.projectDimensions else {
            throw AlignerError.invalidTypographySettings("The title's project dimensions are unavailable.")
        }
        return try layout(
            title: title,
            kind: kind,
            projectWidth: Double(dimensions.width),
            projectHeight: Double(dimensions.height),
            settings: settings
        )
    }

    public func layout(
        title: TitleRecord,
        kind: TitleKind,
        projectWidth: Double,
        projectHeight: Double = 1920,
        settings: AlignmentSettings
    ) throws -> TypographyLayout {
        try layout(
            runs: title.visibleTextRuns.map { TypographyRun(text: $0.string, isItalic: $0.isItalic) },
            kind: kind,
            variant: LayoutVariantSelector.select(visibleText: title.visibleText),
            projectWidth: projectWidth,
            projectHeight: projectHeight,
            settings: settings
        )
    }

    public func layout(
        runs: [TypographyRun],
        kind: TitleKind,
        projectWidth: Double,
        projectHeight: Double = 1920,
        settings: AlignmentSettings
    ) throws -> TypographyLayout {
        try layout(
            runs: runs,
            kind: kind,
            variant: .ordinary,
            projectWidth: projectWidth,
            projectHeight: projectHeight,
            settings: settings
        )
    }

    public func layout(
        runs: [TypographyRun],
        kind: TitleKind,
        variant: LayoutVariant,
        projectWidth: Double,
        projectHeight: Double = 1920,
        settings: AlignmentSettings
    ) throws -> TypographyLayout {
        try validate(settings: settings, projectWidth: projectWidth, projectHeight: projectHeight)

        if variant == .heroAction {
            guard kind == .action else {
                throw AlignerError.invalidTypographySettings("The hero action layout can only be used for action titles.")
            }
            return heroActionLayout(settings: settings)
        }

        let fontFamily = kind == .ingredient ? "Avenir Next" : "Avenir Next Condensed"
        let baseSize = kind == .ingredient ? settings.ingredientBaseSize : settings.actionBaseSize
        let lines = nonEmptyLines(from: runs)
        let visibleText = runs.map(\.text).joined()
        let usesUppercaseCalibration = visibleText == visibleText.uppercased()
            && visibleText != visibleText.lowercased()

        func measuredScale(at fontSize: Double) throws -> Double {
            var lineWidths: [Double] = []
            for (lineIndex, line) in lines.enumerated() {
                var lineWidth = 0.0
                for (runIndex, run) in line.enumerated() {
                    let runWidth = try metrics.width(
                        of: run.text,
                        fontFamily: fontFamily,
                        fontFace: run.isItalic ? .italic : .regular,
                        fontSize: fontSize
                    )
                    try validateMeasurement(
                        runWidth,
                        name: "run width at line \(lineIndex + 1), run \(runIndex + 1)",
                        allowsZero: true
                    )
                    lineWidth += runWidth
                    try validateMeasurement(
                        lineWidth,
                        name: "accumulated line width at line \(lineIndex + 1)",
                        allowsZero: true
                    )
                }
                lineWidths.append(lineWidth)
            }
            let maximumWidth = lineWidths.max() ?? 0
            try validateMeasurement(maximumWidth, name: "maximum line width", allowsZero: true)
            let titleScaledWidth = maximumWidth * TemplateCalibration.titleScale
            try validateMeasurement(titleScaledWidth, name: "title-scaled calibrated width", allowsZero: true)
            let measuredWidth = titleScaledWidth * TemplateCalibration.measuredWidthMultiplier
            try validateMeasurement(measuredWidth, name: "measured calibrated width", allowsZero: true)
            let profilePadding = kind == .action && usesUppercaseCalibration
                ? TemplateCalibration.actionExtraHorizontalPaddingPixels
                : 0
            let paddedWidth = measuredWidth + TemplateCalibration.fixedWidthPaddingPixels + profilePadding
            try validateMeasurement(paddedWidth, name: "padded calibrated width", allowsZero: false)
            var scale = paddedWidth / projectWidth
            if kind == .ingredient {
                scale *= TemplateCalibration.ingredientWidthCalibration
            }
            try validateMeasurement(scale, name: "normalized final width scale", allowsZero: false)
            return scale
        }

        var finalSize = baseSize
        var finalScaleX = try measuredScale(at: baseSize)
        if settings.autoShrink, finalScaleX > settings.safeWidthFraction {
            let minimumScale = try measuredScale(at: settings.minimumSize)
            if minimumScale > settings.safeWidthFraction {
                finalSize = settings.minimumSize
                finalScaleX = minimumScale
            } else {
                var fittingSize = settings.minimumSize
                var overflowingSize = baseSize
                for _ in 0..<60 {
                    let candidate = (fittingSize + overflowingSize) / 2
                    if try measuredScale(at: candidate) <= settings.safeWidthFraction {
                        fittingSize = candidate
                    } else {
                        overflowingSize = candidate
                    }
                }
                finalSize = fittingSize
                finalScaleX = try measuredScale(at: fittingSize)
            }
        }
        try validateMeasurement(finalScaleX, name: "final background width scale", allowsZero: false)

        let backgroundScaleY = try measuredHeightScale(
            lines: lines,
            kind: kind,
            fontFamily: fontFamily,
            fontSize: finalSize,
            projectHeight: projectHeight,
            usesUppercaseCalibration: usesUppercaseCalibration
        )

        let titlePosition: TypographyPoint
        let backgroundPosition: TypographyPoint
        let alignment: TypographyAlignment
        switch kind {
        case .action:
            titlePosition = usesUppercaseCalibration
                ? TemplateCalibration.uppercaseActionTitlePosition
                : TemplateCalibration.actionTitlePosition
            backgroundPosition = TemplateCalibration.actionBackgroundPosition
            alignment = .center
        case .closing:
            titlePosition = TemplateCalibration.closingTitlePosition
            backgroundPosition = TemplateCalibration.closingBackgroundPosition
            alignment = .center
        case .ingredient:
            let referenceTitlePosition = usesUppercaseCalibration
                ? TemplateCalibration.uppercaseIngredientTitlePosition
                : TemplateCalibration.ingredientTitlePosition
            let halfWidthChangeInPositionUnits = (
                finalScaleX - TemplateCalibration.ingredientReferenceBackgroundScaleX
            ) * projectWidth * 50 / projectHeight
            titlePosition = TypographyPoint(
                x: referenceTitlePosition.x - halfWidthChangeInPositionUnits,
                y: referenceTitlePosition.y
            )
            backgroundPosition = TemplateCalibration.ingredientReferenceBackgroundPosition
            alignment = .left
        }

        return TypographyLayout(
            kind: kind,
            variant: .ordinary,
            finalFontSize: finalSize,
            fontFamily: fontFamily,
            fontFace: TypographyFontFace.regular.rawValue,
            isBold: false,
            alignment: alignment,
            lineSpacing: -2,
            titlePosition: titlePosition,
            titleScale: TemplateCalibration.titleScale,
            backgroundPosition: backgroundPosition,
            backgroundScaleX: finalScaleX,
            backgroundScaleY: backgroundScaleY,
            autoShrunk: finalSize < baseSize,
            fitsSafeWidth: finalScaleX <= settings.safeWidthFraction
        )
    }

    private func heroActionLayout(settings: AlignmentSettings) -> TypographyLayout {
        let referenceActionSize = 17.0
        let referenceHeroSize = 36.0
        let referenceBackgroundScaleX = 0.417778
        let referenceBackgroundScaleY = 0.0536121

        var effectiveActionSize = settings.actionBaseSize
        var factor = effectiveActionSize / referenceActionSize
        if settings.autoShrink, referenceBackgroundScaleX * factor > settings.safeWidthFraction {
            let largestFittingActionSize = settings.safeWidthFraction / referenceBackgroundScaleX * referenceActionSize
            effectiveActionSize = max(settings.minimumSize, min(settings.actionBaseSize, largestFittingActionSize))
            factor = effectiveActionSize / referenceActionSize
        }

        let backgroundScaleX = referenceBackgroundScaleX * factor
        return TypographyLayout(
            kind: .action,
            variant: .heroAction,
            finalFontSize: referenceHeroSize * factor,
            fontFamily: "Aviano Sans",
            fontFace: "Bold",
            isBold: true,
            alignment: .center,
            lineSpacing: -2,
            titlePosition: .init(x: -0.0112916, y: 29.9241),
            titleScale: TemplateCalibration.titleScale,
            backgroundPosition: .init(x: 0.00640178, y: 31.1586),
            backgroundScaleX: backgroundScaleX,
            backgroundScaleY: referenceBackgroundScaleY * factor,
            autoShrunk: effectiveActionSize < settings.actionBaseSize,
            fitsSafeWidth: backgroundScaleX <= settings.safeWidthFraction
        )
    }

    private func validate(
        settings: AlignmentSettings,
        projectWidth: Double,
        projectHeight: Double
    ) throws {
        let positiveValues = [settings.actionBaseSize, settings.ingredientBaseSize, settings.minimumSize]
        guard positiveValues.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw AlignerError.invalidTypographySettings("Font sizes must be positive and finite.")
        }
        guard settings.minimumSize <= settings.actionBaseSize,
              settings.minimumSize <= settings.ingredientBaseSize
        else {
            throw AlignerError.invalidTypographySettings("Minimum size must not exceed either base size.")
        }
        guard settings.safeWidthFraction.isFinite,
              settings.safeWidthFraction > 0,
              settings.safeWidthFraction <= 1
        else {
            throw AlignerError.invalidTypographySettings("Safe width fraction must be in (0, 1].")
        }
        guard projectWidth.isFinite, projectWidth > 0 else {
            throw AlignerError.invalidTypographySettings("Project width must be positive and finite.")
        }
        guard projectHeight.isFinite, projectHeight > 0 else {
            throw AlignerError.invalidTypographySettings("Project height must be positive and finite.")
        }
    }

    private func measuredHeightScale(
        lines: [[TypographyRun]],
        kind: TitleKind,
        fontFamily: String,
        fontSize: Double,
        projectHeight: Double,
        usesUppercaseCalibration: Bool
    ) throws -> Double {
        let profile = heightProfile(for: kind, usesUppercaseCalibration: usesUppercaseCalibration)
        let referenceLineHeight = try metrics.lineHeight(
            fontFamily: fontFamily,
            fontFace: .regular,
            fontSize: profile.referenceFontSize
        )
        try validateMeasurement(referenceLineHeight, name: "reference line height", allowsZero: false)

        let referenceLinesHeight = referenceLineHeight * Double(profile.referenceLineCount)
        try validateMeasurement(referenceLinesHeight, name: "reference lines height", allowsZero: false)
        let referenceSpacing = Double(max(0, profile.referenceLineCount - 1)) * -2
        let referenceUnscaledContentHeight = referenceLinesHeight + referenceSpacing
        try validateMeasurement(
            referenceUnscaledContentHeight,
            name: "reference content height",
            allowsZero: false
        )
        let referenceContentHeight = referenceUnscaledContentHeight * TemplateCalibration.titleScale
        try validateMeasurement(
            referenceContentHeight,
            name: "title-scaled reference content height",
            allowsZero: false
        )
        let referenceBoxHeight = profile.referenceHeight * 1920
        try validateMeasurement(referenceBoxHeight, name: "reference calibrated box height", allowsZero: false)
        let fixedPadding = referenceBoxHeight - referenceContentHeight
        try validateMeasurement(fixedPadding, name: "fixed vertical padding", allowsZero: true)

        var lineHeights: [Double] = []
        for (lineIndex, line) in lines.enumerated() {
            var maximumLineHeight = 0.0
            for (runIndex, run) in line.enumerated() {
                let runLineHeight = try metrics.lineHeight(
                    fontFamily: fontFamily,
                    fontFace: run.isItalic ? .italic : .regular,
                    fontSize: fontSize
                )
                try validateMeasurement(
                    runLineHeight,
                    name: "line height at line \(lineIndex + 1), run \(runIndex + 1)",
                    allowsZero: false
                )
                maximumLineHeight = max(maximumLineHeight, runLineHeight)
            }
            try validateMeasurement(
                maximumLineHeight,
                name: "measured line height at line \(lineIndex + 1)",
                allowsZero: false
            )
            lineHeights.append(maximumLineHeight)
        }

        var totalLinesHeight = 0.0
        for (index, lineHeight) in lineHeights.enumerated() {
            totalLinesHeight += lineHeight
            try validateMeasurement(
                totalLinesHeight,
                name: "accumulated lines height through line \(index + 1)",
                allowsZero: true
            )
        }
        let actualSpacing = Double(max(0, lines.count - 1)) * -2
        let unscaledContentHeight = totalLinesHeight + actualSpacing
        if lines.isEmpty {
            try validateMeasurement(unscaledContentHeight, name: "empty content height", allowsZero: true)
        } else {
            try validateMeasurement(unscaledContentHeight, name: "content height", allowsZero: false)
        }
        let contentHeight = unscaledContentHeight * TemplateCalibration.titleScale
        try validateMeasurement(contentHeight, name: "title-scaled content height", allowsZero: true)
        let boxHeight = contentHeight + fixedPadding
        try validateMeasurement(boxHeight, name: "final calibrated box height", allowsZero: false)
        let scale = boxHeight / projectHeight
        try validateMeasurement(scale, name: "normalized final height scale", allowsZero: false)
        return scale
    }

    private func heightProfile(for kind: TitleKind, usesUppercaseCalibration: Bool) -> HeightProfile {
        switch kind {
        case .action:
            HeightProfile(
                referenceHeight: usesUppercaseCalibration
                    ? TemplateCalibration.uppercaseActionHeightAt17
                    : TemplateCalibration.actionHeightAt17,
                referenceFontSize: 17,
                referenceLineCount: 1
            )
        case .closing:
            HeightProfile(
                referenceHeight: TemplateCalibration.closingHeightAt17TwoLines,
                referenceFontSize: 17,
                referenceLineCount: 2
            )
        case .ingredient:
            HeightProfile(
                referenceHeight: usesUppercaseCalibration
                    ? TemplateCalibration.uppercaseIngredientHeightAt15FiveLines
                    : TemplateCalibration.ingredientHeightAt15FiveLines,
                referenceFontSize: 15,
                referenceLineCount: 5
            )
        }
    }

    private func validateMeasurement(
        _ value: Double,
        name: String,
        allowsZero: Bool
    ) throws {
        guard value.isFinite, value >= 0, allowsZero || value > 0 else {
            throw AlignerError.invalidTypographyMeasurement(
                "The \(name) must be \(allowsZero ? "finite and nonnegative" : "finite and positive"); received \(value)."
            )
        }
    }

    private func nonEmptyLines(from runs: [TypographyRun]) -> [[TypographyRun]] {
        var lines: [[TypographyRun]] = []
        var currentLine: [TypographyRun] = []

        for run in runs {
            var fragment = ""
            func appendFragment() {
                guard !fragment.isEmpty else { return }
                currentLine.append(TypographyRun(text: fragment, isItalic: run.isItalic))
                fragment = ""
            }

            for character in run.text {
                if character.isNewline {
                    appendFragment()
                    lines.append(currentLine)
                    currentLine = []
                } else {
                    fragment.append(character)
                }
            }
            appendFragment()
        }
        lines.append(currentLine)

        return lines.filter { line in
            let text = line.map(\.text).joined()
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

}
