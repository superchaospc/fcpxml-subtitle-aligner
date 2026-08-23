import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

typealias ProjectTransformerTestHook = (FCPXMLDocument, TitleRecord, XMLElement) throws -> Void
typealias ProjectTransformerPostCommitTestHook = (FCPXMLDocument) throws -> Void

public struct ProjectTransformer {
    private struct SuccessfulPair {
        let index: Int
        let layout: TypographyLayout
    }

    private let layouter: TypographyLayouter
    private let testHook: ProjectTransformerTestHook?
    private let postCommitTestHook: ProjectTransformerPostCommitTestHook?

#if canImport(AppKit)
    public init(layouter: TypographyLayouter = TypographyLayouter(metrics: AppKitFontMetrics())) {
        self.layouter = layouter
        testHook = nil
        postCommitTestHook = nil
    }
#else
    public init(layouter: TypographyLayouter) {
        self.layouter = layouter
        testHook = nil
        postCommitTestHook = nil
    }
#endif

    init(
        layouter: TypographyLayouter,
        testHook: ProjectTransformerTestHook?,
        postCommitTestHook: ProjectTransformerPostCommitTestHook? = nil
    ) {
        self.layouter = layouter
        self.testHook = testHook
        self.postCommitTestHook = postCommitTestHook
    }

    public func transform(
        _ document: FCPXMLDocument,
        settings: AlignmentSettings
    ) throws -> ChangeReport {
        try Self.validateDocumentWide(settings)

        let invariantBefore = InvariantSnapshot(document: document)
        let workingDocument = try FCPXMLDocument(xmlString: document.rootXML)
        let workingMatches = TitleBackgroundMatcher.matches(in: workingDocument)
        var records: [TitleChangeRecord] = []
        var successfulPairs: [SuccessfulPair] = []

        for (index, match) in workingMatches.enumerated() {
            let title = match.title
            let kind = TitleClassifier.classify(title.visibleText)
            let originalTitleTransform = Self.transformChange(in: title.element)
            let originalBackgroundTransform = match.background.flatMap(Self.transformChange(in:))
            let originalFontSize = Self.firstReferencedFontSize(in: title)

            guard let background = match.background else {
                records.append(Self.skippedRecord(
                    title: title,
                    kind: kind,
                    originalFontSize: originalFontSize,
                    titleTransform: originalTitleTransform,
                    backgroundTransform: originalBackgroundTransform,
                    backgroundMatched: false,
                    reason: match.skipReason ?? "missing background"
                ))
                continue
            }

            let titleBackup = title.element.xmlString
            let backgroundBackup = background.xmlString
            do {
                guard title.projectDimensions != nil else {
                    throw PairTransformError("The title's project dimensions are unavailable.")
                }
                let styles = try Self.referencedDefinitionStyles(in: title)
                let uppercasedTitle = Self.uppercasedRecord(from: title)
                let layout = try layouter.layout(title: uppercasedTitle, kind: kind, settings: settings)
                Self.apply(layout: layout, to: title.element, background: background, styles: styles)
                Self.uppercaseVisibleText(in: title)
                try testHook?(workingDocument, title, background)

                let finalTitleTransform = Self.transformChange(in: title.element)
                let finalBackgroundTransform = Self.transformChange(in: background)
                let changed = titleBackup != title.element.xmlString || backgroundBackup != background.xmlString
                records.append(TitleChangeRecord(
                    titleName: title.name,
                    titleText: uppercasedTitle.visibleText,
                    kind: kind,
                    originalFontSize: originalFontSize,
                    finalFontSize: layout.finalFontSize,
                    originalTitleTransform: originalTitleTransform,
                    finalTitleTransform: finalTitleTransform,
                    originalBackgroundTransform: originalBackgroundTransform,
                    finalBackgroundTransform: finalBackgroundTransform,
                    autoShrunk: layout.autoShrunk,
                    fitsSafeWidth: layout.fitsSafeWidth,
                    backgroundMatched: true,
                    skipReason: nil,
                    changed: changed
                ))
                successfulPairs.append(SuccessfulPair(index: index, layout: layout))
            } catch {
                try Self.restore(title.element, from: titleBackup)
                try Self.restore(background, from: backgroundBackup)
                records.append(Self.skippedRecord(
                    title: title,
                    kind: kind,
                    originalFontSize: originalFontSize,
                    titleTransform: originalTitleTransform,
                    backgroundTransform: originalBackgroundTransform,
                    backgroundMatched: true,
                    reason: Self.diagnostic(for: error)
                ))
            }
        }

        let invariantAfter = InvariantSnapshot(document: workingDocument)
        let uppercasedTitleIndices = Set(successfulPairs.map(\.index))
        guard Self.invariantsMatch(
            before: invariantBefore,
            after: invariantAfter,
            uppercasedTitleIndices: uppercasedTitleIndices
        ) else {
            throw AlignerError.invariantViolation(Self.invariantDifference(
                before: invariantBefore,
                after: invariantAfter,
                uppercasedTitleIndices: uppercasedTitleIndices
            ))
        }

        // Nothing reaches the caller's document until every pair and the whole-document
        // invariant check have succeeded on the isolated working copy.
        let originalMatches = TitleBackgroundMatcher.matches(in: document)
        let documentBackup = document.rootXML
        do {
            for success in successfulPairs {
                let match = originalMatches[success.index]
                guard let background = match.background else {
                    throw AlignerError.invariantViolation("A validated title/background pair was unavailable during commit.")
                }
                let styles = try Self.referencedDefinitionStyles(in: match.title)
                Self.apply(layout: success.layout, to: match.title.element, background: background, styles: styles)
                Self.uppercaseVisibleText(in: match.title)
            }

            try postCommitTestHook?(document)
            let committedInvariant = InvariantSnapshot(document: document)
            guard Self.invariantsMatch(
                before: invariantBefore,
                after: committedInvariant,
                uppercasedTitleIndices: uppercasedTitleIndices
            ) else {
                throw AlignerError.invariantViolation(Self.invariantDifference(
                    before: invariantBefore,
                    after: committedInvariant,
                    uppercasedTitleIndices: uppercasedTitleIndices
                ))
            }
        } catch {
            try Self.restore(document.rootElement, from: documentBackup)
            throw error
        }
        return ChangeReport(titles: records)
    }

    private static func validateDocumentWide(_ settings: AlignmentSettings) throws {
        let sizes = [settings.actionBaseSize, settings.ingredientBaseSize, settings.minimumSize]
        guard sizes.allSatisfy({ $0.isFinite && $0 > 0 }) else {
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
    }

    private static func apply(
        layout: TypographyLayout,
        to title: XMLElement,
        background: XMLElement,
        styles: [XMLElement]
    ) {
        for style in styles {
            setAttribute("font", value: layout.fontFamily, on: style)
            setAttribute("fontSize", value: canonical(layout.finalFontSize), on: style)
            if layout.isBold {
                setAttribute("fontFace", value: layout.fontFace, on: style)
                setAttribute("bold", value: "1", on: style)
            } else {
                setAttribute("fontFace", value: preservedFontFace(in: style, fallback: layout.fontFace), on: style)
            }
            setAttribute("alignment", value: layout.alignment.rawValue, on: style)
            setAttribute("lineSpacing", value: canonical(layout.lineSpacing), on: style)
        }

        let directParams = (title.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.name == "param" }
        for parameter in directParams {
            switch parameter.attribute(forName: "name")?.stringValue {
            case "Alignment":
                setAttribute(
                    "value",
                    value: layout.alignment == .left ? "0 (Left)" : "1 (Center)",
                    on: parameter
                )
            case "Line Spacing":
                setAttribute("value", value: canonical(layout.lineSpacing), on: parameter)
            default:
                break
            }
        }

        let titleTransform = directTransform(in: title, createIfMissing: true)!
        setAttribute("position", value: point(layout.titlePosition), on: titleTransform)
        setAttribute("scale", value: pair(layout.titleScale, layout.titleScale), on: titleTransform)

        let backgroundTransform = directTransform(in: background, createIfMissing: true)!
        setAttribute("position", value: point(layout.backgroundPosition), on: backgroundTransform)
        setAttribute("scale", value: pair(layout.backgroundScaleX, layout.backgroundScaleY), on: backgroundTransform)
    }

    private static func referencedDefinitionStyles(in title: TitleRecord) throws -> [XMLElement] {
        let references = Set(title.visibleTextRuns.map(\.ref))
        guard !references.isEmpty, !references.contains("") else {
            throw PairTransformError("A visible text run is missing its style definition reference.")
        }
        let definitions = (title.element.children ?? []).compactMap { $0 as? XMLElement }.filter {
            $0.name == "text-style-def"
        }
        var result: [XMLElement] = []
        for reference in references.sorted() {
            let matching = definitions.filter { $0.attribute(forName: "id")?.stringValue == reference }
            guard matching.count == 1 else {
                throw PairTransformError("The visible text style definition '\(reference)' is missing or ambiguous.")
            }
            let styles = (matching[0].children ?? []).compactMap { $0 as? XMLElement }.filter { $0.name == "text-style" }
            guard styles.count == 1 else {
                throw PairTransformError("The visible text style definition '\(reference)' has no unique text-style element.")
            }
            result.append(styles[0])
        }
        return result
    }

    private static func firstReferencedFontSize(in title: TitleRecord) -> Double? {
        guard let styles = try? referencedDefinitionStyles(in: title) else { return nil }
        return styles.lazy.compactMap { style in
            style.attribute(forName: "fontSize")?.stringValue.flatMap(Double.init)
        }.first
    }

    private static func directTransform(in element: XMLElement, createIfMissing: Bool) -> XMLElement? {
        if let existing = (element.children ?? []).compactMap({ $0 as? XMLElement }).first(where: {
            $0.name == "adjust-transform"
        }) {
            return existing
        }
        guard createIfMissing else { return nil }
        let transform = XMLElement(name: "adjust-transform")
        element.addChild(transform)
        return transform
    }

    private static func transformChange(in element: XMLElement) -> TransformChange? {
        guard let transform = directTransform(in: element, createIfMissing: false) else { return nil }
        return TransformChange(
            position: transform.attribute(forName: "position")?.stringValue,
            scale: transform.attribute(forName: "scale")?.stringValue
        )
    }

    private static func setAttribute(_ name: String, value: String, on element: XMLElement) {
        if let attribute = element.attribute(forName: name) {
            if attribute.stringValue != value {
                attribute.stringValue = value
            }
        } else {
            element.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
        }
    }

    private static func canonical(_ value: Double) -> String {
        let formatted = String(format: "%.12g", locale: Locale(identifier: "en_US_POSIX"), value)
        return formatted == "-0" ? "0" : formatted
    }

    private static func point(_ point: TypographyPoint) -> String {
        pair(point.x, point.y)
    }

    private static func pair(_ first: Double, _ second: Double) -> String {
        "\(canonical(first)) \(canonical(second))"
    }

    private static func skippedRecord(
        title: TitleRecord,
        kind: TitleKind,
        originalFontSize: Double?,
        titleTransform: TransformChange?,
        backgroundTransform: TransformChange?,
        backgroundMatched: Bool,
        reason: String
    ) -> TitleChangeRecord {
        TitleChangeRecord(
            titleName: title.name,
            titleText: title.visibleText,
            kind: kind,
            originalFontSize: originalFontSize,
            finalFontSize: originalFontSize,
            originalTitleTransform: titleTransform,
            finalTitleTransform: titleTransform,
            originalBackgroundTransform: backgroundTransform,
            finalBackgroundTransform: backgroundTransform,
            autoShrunk: false,
            fitsSafeWidth: false,
            backgroundMatched: backgroundMatched,
            skipReason: reason,
            changed: false
        )
    }

    private static func diagnostic(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }

    private static func preservedFontFace(in style: XMLElement, fallback: String) -> String {
        guard let sourceFace = style.attribute(forName: "fontFace")?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !sourceFace.isEmpty,
              sourceFace.caseInsensitiveCompare(TypographyFontFace.regular.rawValue) != .orderedSame
        else {
            return fallback
        }
        return sourceFace
    }

    private static func uppercasedRecord(from title: TitleRecord) -> TitleRecord {
        TitleRecord(
            element: title.element,
            name: title.name,
            ref: title.ref,
            lane: title.lane,
            offset: title.offset,
            start: title.start,
            duration: title.duration,
            visibleText: title.visibleText.uppercased(),
            visibleLines: title.visibleLines.map { $0.uppercased() },
            visibleTextRuns: title.visibleTextRuns.map { run in
                TitleTextRun(
                    element: run.element,
                    ref: run.ref,
                    string: run.string.uppercased(),
                    sourceFontFamily: run.sourceFontFamily,
                    sourceFontFace: run.sourceFontFace,
                    isItalic: run.isItalic
                )
            },
            projectDimensions: title.projectDimensions
        )
    }

    private static func uppercaseVisibleText(in title: TitleRecord) {
        for run in title.visibleTextRuns {
            let uppercased = run.string.uppercased()
            if uppercased != run.string {
                run.element.stringValue = uppercased
            }
        }
    }

    private static func invariantsMatch(
        before: InvariantSnapshot,
        after: InvariantSnapshot,
        uppercasedTitleIndices: Set<Int>
    ) -> Bool {
        guard before.timing == after.timing,
              before.mediaReferences == after.mediaReferences,
              before.nonStyleStructure == after.nonStyleStructure
        else { return false }

        return visibleTextAndColorsMatch(
            before: before.visibleTextAndColors,
            after: after.visibleTextAndColors,
            uppercasedTitleIndices: uppercasedTitleIndices
        )
    }

    private static func visibleTextAndColorsMatch(
        before: [InvariantSnapshot.VisibleTitle],
        after: [InvariantSnapshot.VisibleTitle],
        uppercasedTitleIndices: Set<Int>
    ) -> Bool {
        guard before.count == after.count else { return false }
        for (index, pair) in zip(before, after).enumerated() {
            let (originalTitle, transformedTitle) = pair
            guard originalTitle.path == transformedTitle.path,
                  originalTitle.runs.count == transformedTitle.runs.count
            else { return false }
            let shouldUppercase = uppercasedTitleIndices.contains(index)
            let expectedText = shouldUppercase ? originalTitle.text.uppercased() : originalTitle.text
            guard transformedTitle.text == expectedText else { return false }
            for (originalRun, transformedRun) in zip(originalTitle.runs, transformedTitle.runs) {
                let expectedRunText = shouldUppercase ? originalRun.text.uppercased() : originalRun.text
                guard transformedRun.text == expectedRunText,
                      transformedRun.ref == originalRun.ref,
                      transformedRun.colors == originalRun.colors
                else { return false }
            }
        }
        return true
    }

    private static func invariantDifference(
        before: InvariantSnapshot,
        after: InvariantSnapshot,
        uppercasedTitleIndices: Set<Int>
    ) -> String {
        var differences: [String] = []
        if before.timing != after.timing { differences.append("timing") }
        if before.mediaReferences != after.mediaReferences { differences.append("media references") }
        if !Self.visibleTextAndColorsMatch(
            before: before.visibleTextAndColors,
            after: after.visibleTextAndColors,
            uppercasedTitleIndices: uppercasedTitleIndices
        ) {
            differences.append(Self.visibleTextAndColorsDifference(
                before: before.visibleTextAndColors,
                after: after.visibleTextAndColors,
                uppercasedTitleIndices: uppercasedTitleIndices
            ))
        }
        if before.nonStyleStructure != after.nonStyleStructure { differences.append("non-style structure") }
        return "Forbidden invariant mutation detected in: \(differences.joined(separator: ", "))."
    }

    private static func visibleTextAndColorsDifference(
        before: [InvariantSnapshot.VisibleTitle],
        after: [InvariantSnapshot.VisibleTitle],
        uppercasedTitleIndices: Set<Int>
    ) -> String {
        guard before.count == after.count else {
            return "visible title count \(before.count)->\(after.count)"
        }
        for (index, pair) in zip(before, after).enumerated() {
            let (originalTitle, transformedTitle) = pair
            guard originalTitle.path == transformedTitle.path else {
                return "visible title path at index \(index)"
            }
            guard originalTitle.runs.count == transformedTitle.runs.count else {
                return "visible run count at title \(index + 1)"
            }
            let shouldUppercase = uppercasedTitleIndices.contains(index)
            let expectedText = shouldUppercase ? originalTitle.text.uppercased() : originalTitle.text
            guard transformedTitle.text == expectedText else {
                return "visible text at title \(index + 1)"
            }
            for (runIndex, runPair) in zip(originalTitle.runs, transformedTitle.runs).enumerated() {
                let (originalRun, transformedRun) = runPair
                let expectedRunText = shouldUppercase ? originalRun.text.uppercased() : originalRun.text
                guard transformedRun.text == expectedRunText else {
                    return "visible text at title \(index + 1) run \(runIndex + 1)"
                }
                guard transformedRun.ref == originalRun.ref else {
                    return "style reference at title \(index + 1) run \(runIndex + 1)"
                }
                guard transformedRun.colors == originalRun.colors else {
                    return "text color at title \(index + 1) run \(runIndex + 1)"
                }
            }
        }
        return "visible text or colors"
    }

    private static func restore(_ target: XMLElement, from xml: String) throws {
        let sourceDocument = try XMLDocument(xmlString: "<rollback>\(xml)</rollback>", options: .nodePreserveAll)
        guard let source = sourceDocument.rootElement()?.children?.compactMap({ $0 as? XMLElement }).first else {
            throw AlignerError.invariantViolation("Unable to restore a title/background after a pair transformation failed.")
        }
        restoreInPlace(target, from: source)
    }

    private static func restoreInPlace(_ target: XMLElement, from source: XMLElement) {
        let sourceAttributes = Dictionary(uniqueKeysWithValues: (source.attributes ?? []).compactMap { attribute in
            attribute.name.map { ($0, attribute.stringValue ?? "") }
        })
        for attribute in target.attributes ?? [] {
            if let name = attribute.name, sourceAttributes[name] == nil {
                target.removeAttribute(forName: name)
            }
        }
        for attribute in source.attributes ?? [] {
            guard let name = attribute.name else { continue }
            if let targetAttribute = target.attribute(forName: name) {
                targetAttribute.stringValue = attribute.stringValue
            } else {
                target.addAttribute(attribute.copy() as! XMLNode)
            }
        }

        let sourceChildren = source.children ?? []
        for (index, sourceChild) in sourceChildren.enumerated() {
            guard index < target.childCount else {
                target.addChild(sourceChild.copy() as! XMLNode)
                continue
            }
            guard let targetChild = target.child(at: index) else { continue }
            if let targetElement = targetChild as? XMLElement,
               let sourceElement = sourceChild as? XMLElement,
               targetElement.name == sourceElement.name {
                restoreInPlace(targetElement, from: sourceElement)
            } else if targetChild.xmlString != sourceChild.xmlString {
                target.removeChild(at: index)
                target.insertChild(sourceChild.copy() as! XMLNode, at: index)
            }
        }
        while target.childCount > sourceChildren.count {
            target.removeChild(at: sourceChildren.count)
        }
    }
}

private struct PairTransformError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
