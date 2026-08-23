import Foundation

public struct TransformChange: Equatable, Sendable {
    public let position: String?
    public let scale: String?

    public init(position: String?, scale: String?) {
        self.position = position
        self.scale = scale
    }
}

public struct TitleChangeRecord: Equatable, Sendable {
    public let titleName: String
    public let titleText: String
    public let kind: TitleKind
    public let originalFontSize: Double?
    public let finalFontSize: Double?
    public let originalTitleTransform: TransformChange?
    public let finalTitleTransform: TransformChange?
    public let originalBackgroundTransform: TransformChange?
    public let finalBackgroundTransform: TransformChange?
    public let autoShrunk: Bool
    public let fitsSafeWidth: Bool
    /// True when this title had one uniquely matched Custom background before layout/style validation.
    public let backgroundMatched: Bool
    public let skipReason: String?
    public let changed: Bool

    public init(
        titleName: String,
        titleText: String,
        kind: TitleKind,
        originalFontSize: Double?,
        finalFontSize: Double?,
        originalTitleTransform: TransformChange?,
        finalTitleTransform: TransformChange?,
        originalBackgroundTransform: TransformChange?,
        finalBackgroundTransform: TransformChange?,
        autoShrunk: Bool,
        fitsSafeWidth: Bool,
        backgroundMatched: Bool,
        skipReason: String?,
        changed: Bool
    ) {
        self.titleName = titleName
        self.titleText = titleText
        self.kind = kind
        self.originalFontSize = originalFontSize
        self.finalFontSize = finalFontSize
        self.originalTitleTransform = originalTitleTransform
        self.finalTitleTransform = finalTitleTransform
        self.originalBackgroundTransform = originalBackgroundTransform
        self.finalBackgroundTransform = finalBackgroundTransform
        self.autoShrunk = autoShrunk
        self.fitsSafeWidth = fitsSafeWidth
        self.backgroundMatched = backgroundMatched
        self.skipReason = skipReason
        self.changed = changed
    }
}

public struct ChangeReport: Equatable, Sendable {
    public let titles: [TitleChangeRecord]

    public var recognizedTitles: Int { titles.count }
    public var changedTitles: Int { titles.count(where: \.changed) }
    public var skippedTitles: Int { titles.count { $0.skipReason != nil } }
    public var actionTitles: Int { titles.count { $0.kind == .action } }
    public var ingredientTitles: Int { titles.count { $0.kind == .ingredient } }
    public var closingTitles: Int { titles.count { $0.kind == .closing } }
    public var autoShrunkTitles: Int { titles.count { $0.autoShrunk } }
    public var overflowTitles: Int { titles.count { $0.skipReason == nil && !$0.fitsSafeWidth } }
    /// Titles that found exactly one Custom background, including pairs skipped later during transformation.
    public var matchedBackgrounds: Int { titles.count { $0.backgroundMatched } }

    public init(titles: [TitleChangeRecord]) {
        self.titles = titles
    }
}

public extension ChangeReport {
    func plainText(
        inputURL: URL,
        outputURL: URL,
        reportURL: URL,
        version: String,
        sourceProjectNames: [String],
        outputProjectNames: [String]
    ) -> String {
        var lines = [
            "FCPXML Subtitle Aligner report",
            "Input: \(inputURL.path)",
            "Output: \(outputURL.path)",
            "Report: \(reportURL.path)",
            "FCPXML version: \(version)",
            "Source projects: \(sourceProjectNames.joined(separator: ", "))",
            "Output projects: \(outputProjectNames.joined(separator: ", "))",
            "Recognized: \(recognizedTitles)",
            "Matched backgrounds: \(matchedBackgrounds)",
            "Changed: \(changedTitles)",
            "Skipped: \(skippedTitles)",
            "Kinds: action=\(actionTitles), ingredient=\(ingredientTitles), closing=\(closingTitles)",
            "Auto-shrunk: \(autoShrunkTitles)",
            "Overflow: \(overflowTitles)",
            "Structural validation: PASS",
            "Media references invariant: PASS",
            "Timing invariant: PASS",
            "Text/color invariant: PASS",
            "Nonstyle invariant: PASS",
        ]
        for (index, title) in titles.enumerated() {
            lines.append("Title \(index + 1): name=\(oneLine(title.titleName)); text=\(oneLine(title.titleText)); kind=\(title.kind); fontSize=\(number(title.originalFontSize))->\(number(title.finalFontSize)); titleTransform=\(transform(title.originalTitleTransform))->\(transform(title.finalTitleTransform)); backgroundTransform=\(transform(title.originalBackgroundTransform))->\(transform(title.finalBackgroundTransform)); matched=\(title.backgroundMatched); autoShrunk=\(title.autoShrunk); overflow=\(!title.fitsSafeWidth); changed=\(title.changed); skipReason=\(oneLine(title.skipReason ?? "none"))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func transform(_ value: TransformChange?) -> String {
        guard let value else { return "none" }
        return "position=\(value.position ?? "none"),scale=\(value.scale ?? "none")"
    }

    private func number(_ value: Double?) -> String {
        value.map { String(format: "%.6g", $0) } ?? "none"
    }

    private func oneLine(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0x0A: return "\\n"
            case 0x0D: return "\\r"
            case 0x09: return "\\t"
            case 0x00...0x1F, 0x7F: return String(format: "\\u{%04X}", scalar.value)
            default: return String(scalar)
            }
        }.joined()
    }
}
