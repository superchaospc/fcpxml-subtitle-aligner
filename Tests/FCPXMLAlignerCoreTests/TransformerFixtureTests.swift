import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import XCTest
@testable import FCPXMLAlignerCore

final class TransformerFixtureTests: XCTestCase {
    private let metrics = TransformerTestMetrics()

    private struct GoldGeometry {
        let titlePosition: String
        let backgroundPosition: String
        let backgroundScale: String
    }

    func testCurrentFixtureTransformsAllRecognizedPairsAndPreservesForbiddenInvariants() throws {
        let document = try currentFixtureDocument()
        let before = InvariantSnapshot(document: document)

        let report = try transformer().transform(document, settings: .templateDefaults)
        let after = InvariantSnapshot(document: document)

        XCTAssertEqual(report.recognizedTitles, 17)
        XCTAssertEqual(report.changedTitles, 17)
        XCTAssertEqual(report.skippedTitles, 0)
        XCTAssertEqual(report.actionTitles, 15)
        XCTAssertEqual(report.ingredientTitles, 1)
        XCTAssertEqual(report.closingTitles, 1)
        XCTAssertEqual(report.matchedBackgrounds, 17)
        XCTAssertEqual(report.titles.count, 17)
        XCTAssertEqual(report.titles.filter { $0.originalBackgroundTransform != $0.finalBackgroundTransform }.count, 17)
        XCTAssertTrue(report.titles.allSatisfy { $0.skipReason == nil })
        XCTAssertEqual(before.mediaReferences, after.mediaReferences)
        XCTAssertEqual(before.timing, after.timing)
        assertUppercaseTextAndColors(before: before, after: after, report: report)
        XCTAssertEqual(before.nonStyleStructure, after.nonStyleStructure)
    }

    func testSuccessfulTransformUppercasesEveryVisibleRunWithoutChangingRunStyles() throws {
        let document = try templateFixtureDocument()
        let sourceTexts = document.titles.map(\.visibleText)
        let before = InvariantSnapshot(document: document).visibleTextAndColors

        let report = try transformer().transform(document, settings: .templateDefaults)
        let reparsed = try FCPXMLDocument(xmlString: document.rootXML)
        let after = InvariantSnapshot(document: reparsed).visibleTextAndColors

        let expectedTexts = zip(sourceTexts, report.titles).map { sourceText, change in
            change.skipReason == nil ? sourceText.uppercased() : sourceText
        }
        XCTAssertEqual(report.titles.map(\.titleText), expectedTexts)
        XCTAssertEqual(after.count, before.count)
        for (titleIndex, titlePair) in zip(before, after).enumerated() {
            let (originalTitle, transformedTitle) = titlePair
            let shouldUppercase = report.titles[titleIndex].skipReason == nil
            XCTAssertEqual(
                transformedTitle.text,
                shouldUppercase ? originalTitle.text.uppercased() : originalTitle.text
            )
            XCTAssertEqual(transformedTitle.runs.count, originalTitle.runs.count)
            for (originalRun, transformedRun) in zip(originalTitle.runs, transformedTitle.runs) {
                XCTAssertEqual(
                    transformedRun.text,
                    shouldUppercase ? originalRun.text.uppercased() : originalRun.text
                )
                XCTAssertEqual(transformedRun.ref, originalRun.ref)
                XCTAssertEqual(transformedRun.colors, originalRun.colors)
            }
        }
    }

    func testFixtureProfilesNormalizeStylesParamsAndGeometry() throws {
        let document = try currentFixtureDocument()
        let report = try transformer().transform(document, settings: .templateDefaults)

        let ingredient = try XCTUnwrap(report.titles.first { $0.kind == .ingredient })
        let action = try XCTUnwrap(report.titles.first { $0.kind == .action })
        let closing = try XCTUnwrap(report.titles.first { $0.kind == .closing })
        XCTAssertEqual(ingredient.finalFontSize, 15)
        XCTAssertEqual(action.finalFontSize, 17)
        XCTAssertEqual(closing.finalFontSize, 17)
        XCTAssertEqual(closing.titleText.split(whereSeparator: \.isNewline).count, 2)

        try assertNormalizedStyle(in: document, titleText: ingredient.titleText, font: "Avenir Next", size: "15", alignment: "left")
        try assertNormalizedStyle(in: document, titleText: action.titleText, font: "Avenir Next Condensed", size: "17", alignment: "center")
        try assertNormalizedStyle(in: document, titleText: closing.titleText, font: "Avenir Next Condensed", size: "17", alignment: "center")

        let reparsed = try FCPXMLDocument(xmlString: document.rootXML)
        let sourceIngredient = try XCTUnwrap(reparsed.titles.first { $0.visibleText == ingredient.titleText })
        let expected = try TypographyLayouter(metrics: metrics).layout(
            title: sourceIngredient,
            kind: .ingredient,
            settings: .templateDefaults
        )
        XCTAssertEqual(ingredient.finalTitleTransform?.position, format(expected.titlePosition.x, expected.titlePosition.y))
        XCTAssertEqual(ingredient.finalTitleTransform?.scale, format(expected.titleScale, expected.titleScale))
        XCTAssertEqual(ingredient.finalBackgroundTransform?.position, format(expected.backgroundPosition.x, expected.backgroundPosition.y))
        XCTAssertEqual(ingredient.finalBackgroundTransform?.scale, format(expected.backgroundScaleX, expected.backgroundScaleY))
    }

    func testTemplateFixturePreservesYellowItalicEmphasisAndRunBoundaries() throws {
        let document = try templateFixtureDocument()
        let before = InvariantSnapshot(document: document)
        let ingredient = try XCTUnwrap(document.titles.first { TitleClassifier.classify($0.visibleText) == .ingredient })
        let runCount = ingredient.visibleTextRuns.count

        let report = try transformer().transform(document, settings: .templateDefaults)

        let after = InvariantSnapshot(document: document)
        assertUppercaseTextAndColors(
            before: before,
            after: after,
            report: report
        )
        let transformed = try XCTUnwrap(document.titles.first { $0.visibleText == ingredient.visibleText })
        XCTAssertEqual(transformed.visibleTextRuns.count, runCount)
        let referencedStyles = try referencedDefinitionStyles(for: transformed)
        XCTAssertTrue(referencedStyles.contains { $0.attribute(forName: "italic")?.stringValue == "1" })
        XCTAssertTrue(referencedStyles.contains {
            ($0.attribute(forName: "fontColor")?.stringValue ?? "") != "1 1 1 1"
        })
        XCTAssertTrue(referencedStyles.allSatisfy { $0.attribute(forName: "font")?.stringValue == "Avenir Next" })
        XCTAssertTrue(referencedStyles.allSatisfy { $0.attribute(forName: "fontSize")?.stringValue == "15" })
        XCTAssertTrue(referencedStyles.allSatisfy { $0.attribute(forName: "alignment")?.stringValue == "left" })
    }

    func testDefinitionLevelItalicAndBoldFacesArePreserved() throws {
        for face in ["Italic", "Bold"] {
            let document = try syntheticDocument(text: "Mix well", backgroundCount: 1, fontFace: face)

            _ = try transformer().transform(document, settings: .templateDefaults)

            XCTAssertEqual(try styleAttribute("fontFace", in: document), face)
        }
    }

    func testAdjustableSettingsAndAutoShrinkAreReflectedInXMLAndReport() throws {
        let adjustable = try syntheticDocument(text: "Adjust me", backgroundCount: 1)
        let adjustableSettings = AlignmentSettings(
            actionBaseSize: 20,
            ingredientBaseSize: 18,
            minimumSize: 10,
            autoShrink: false,
            safeWidthFraction: 1
        )
        let adjustableReport = try transformer().transform(adjustable, settings: adjustableSettings)
        XCTAssertEqual(adjustableReport.titles.first?.finalFontSize, 20)
        XCTAssertEqual(try styleAttribute("fontSize", in: adjustable), "20")

        let shrinking = try syntheticDocument(text: String(repeating: "very wide ", count: 20), backgroundCount: 1)
        let shrinkSettings = AlignmentSettings(
            actionBaseSize: 17,
            ingredientBaseSize: 16,
            minimumSize: 10,
            autoShrink: true,
            safeWidthFraction: 0.2
        )
        let shrinkReport = try transformer().transform(shrinking, settings: shrinkSettings)
        let change = try XCTUnwrap(shrinkReport.titles.first)
        XCTAssertTrue(change.autoShrunk)
        XCTAssertEqual(shrinkReport.autoShrunkTitles, 1)
        XCTAssertEqual(try styleAttribute("fontSize", in: shrinking), canonical(change.finalFontSize ?? 0))

        let overflowing = try syntheticDocument(text: String(repeating: "overflow ", count: 40), backgroundCount: 1)
        let overflowReport = try transformer().transform(overflowing, settings: shrinkSettings)
        XCTAssertEqual(overflowReport.overflowTitles, 1)
        XCTAssertFalse(try XCTUnwrap(overflowReport.titles.first).fitsSafeWidth)
    }

    func testSecondTransformHasIdenticalCompleteStyleAndGeometrySnapshot() throws {
        let document = try currentFixtureDocument()
        _ = try transformer().transform(document, settings: .templateDefaults)
        let once = try styleGeometrySnapshot(document)

        _ = try transformer().transform(document, settings: .templateDefaults)
        let twice = try styleGeometrySnapshot(document)

        XCTAssertEqual(twice, once)
    }

    func testCurrentFixtureUppercaseProfilesApplyScreenshotCenteredGeometryAndFitSafeArea() throws {
        let document = try currentFixtureDocument()
        let before = InvariantSnapshot(document: document)
        let report = try ProjectTransformer().transform(document, settings: .templateDefaults)
        let goldMatches = try goldGeometryByNormalizedText()

        XCTAssertEqual(goldMatches.count, 17, "Gold geometry keys: \(goldMatches.keys.sorted())")
        XCTAssertNotNil(
            goldMatches["flour 500g salt 1 tsp three eggs yeast 5g warm water 300ml"],
            "Gold geometry keys: \(goldMatches.keys.sorted())"
        )

        XCTAssertEqual(report.autoShrunkTitles, 1)
        XCTAssertEqual(report.overflowTitles, 0)

        for change in report.titles {
            let normalizedText = normalize(change.titleText)
            let gold = try XCTUnwrap(goldMatches[normalizedText], "Missing gold geometry for: \(change.titleText)")
            let title = try XCTUnwrap(change.finalTitleTransform)
            let background = try XCTUnwrap(change.finalBackgroundTransform)

            XCTAssertEqual(title.position, gold.titlePosition)
            XCTAssertEqual(background.position, gold.backgroundPosition)
            XCTAssertEqual(background.scale, gold.backgroundScale)

            switch change.kind {
            case .ingredient:
                XCTAssertEqual(change.finalFontSize, 15)
                let backgroundScaleX = try firstNumber(in: background.scale)
                let expectedTitleX = TemplateCalibration.uppercaseIngredientTitlePosition.x
                    - (backgroundScaleX - TemplateCalibration.ingredientReferenceBackgroundScaleX)
                    * 1080 * 50 / 1920
                XCTAssertEqual(
                    try firstNumber(in: title.position),
                    expectedTitleX,
                    accuracy: 0.000_000_01
                )
                XCTAssertEqual(
                    try secondNumber(in: title.position),
                    TemplateCalibration.uppercaseIngredientTitlePosition.y,
                    accuracy: 0.000_000_01
                )
                XCTAssertEqual(
                    try firstNumber(in: background.position),
                    TemplateCalibration.ingredientReferenceBackgroundPosition.x,
                    accuracy: 0.000_000_01
                )
                XCTAssertEqual(try secondNumber(in: background.position), try secondNumber(in: gold.backgroundPosition), accuracy: 0.000_000_01)
                XCTAssertEqual(
                    try secondNumber(in: background.scale),
                    TemplateCalibration.uppercaseIngredientHeightAt15FiveLines,
                    accuracy: 0.000_000_01
                )
            case .closing:
                XCTAssertEqual(try secondNumber(in: background.scale), try secondNumber(in: gold.backgroundScale), accuracy: 0.000_000_01)
            case .action:
                // Dish Up has a separately approved fixed-layout variant outside Phase A.
                guard normalizedText != "dish up" else { continue }
                XCTAssertEqual(
                    title.position,
                    format(
                        TemplateCalibration.uppercaseActionTitlePosition.x,
                        TemplateCalibration.uppercaseActionTitlePosition.y
                    )
                )
                XCTAssertEqual(background.position, gold.backgroundPosition)
                let actualHeight = try secondNumber(in: background.scale)
                if change.autoShrunk {
                    XCTAssertLessThan(actualHeight, TemplateCalibration.uppercaseActionHeightAt17)
                    XCTAssertGreaterThan(actualHeight, 0)
                } else {
                    XCTAssertEqual(
                        actualHeight,
                        TemplateCalibration.uppercaseActionHeightAt17,
                        accuracy: 0.000_000_01
                    )
                }
            }
        }

        let after = InvariantSnapshot(document: document)
        XCTAssertEqual(after.mediaReferences, before.mediaReferences)
        XCTAssertEqual(after.timing, before.timing)
        assertUppercaseTextAndColors(before: before, after: after, report: report)
        XCTAssertEqual(after.nonStyleStructure, before.nonStyleStructure)

    }

    func testDishUpHeroActionUsesGoldStyleGeometryAndLeavesOrdinaryActionsOrdinary() throws {
        let document = try currentFixtureDocument()
        let before = InvariantSnapshot(document: document)
        let fontAndSizeParamsBefore = try document.xmlDocument.nodes(
            forXPath: "//title/param[@name='Font' or @name='Size']"
        ).count

        let report = try ProjectTransformer().transform(document, settings: .templateDefaults)

        let hero = try XCTUnwrap(report.titles.first { normalize($0.titleText) == "dish up" })
        XCTAssertEqual(hero.kind, .action)
        XCTAssertEqual(hero.finalFontSize, 36)
        XCTAssertFalse(hero.autoShrunk)
        XCTAssertTrue(hero.fitsSafeWidth)
        XCTAssertEqual(hero.finalTitleTransform?.position, "-0.0112916 29.9241")
        XCTAssertEqual(hero.finalBackgroundTransform?.position, "0.00640178 31.1586")
        XCTAssertEqual(hero.finalBackgroundTransform?.scale, "0.417778 0.0536121")

        let heroTitle = try XCTUnwrap(document.titles.first { normalize($0.visibleText) == "dish up" })
        let heroStyles = try referencedDefinitionStyles(for: heroTitle)
        XCTAssertTrue(heroStyles.allSatisfy { $0.attribute(forName: "font")?.stringValue == "Aviano Sans" })
        XCTAssertTrue(heroStyles.allSatisfy { $0.attribute(forName: "fontSize")?.stringValue == "36" })
        XCTAssertTrue(heroStyles.allSatisfy { $0.attribute(forName: "fontFace")?.stringValue == "Bold" })
        XCTAssertTrue(heroStyles.allSatisfy { $0.attribute(forName: "bold")?.stringValue == "1" })

        let ordinary = try XCTUnwrap(report.titles.first {
            $0.kind == .action && normalize($0.titleText) == "warm the skillet"
        })
        XCTAssertEqual(ordinary.finalFontSize, 17)
        let ordinaryTitle = try XCTUnwrap(document.titles.first { normalize($0.visibleText) == "warm the skillet" })
        let ordinaryStyles = try referencedDefinitionStyles(for: ordinaryTitle)
        XCTAssertTrue(ordinaryStyles.allSatisfy { $0.attribute(forName: "font")?.stringValue == "Avenir Next Condensed" })
        XCTAssertTrue(ordinaryStyles.allSatisfy { $0.attribute(forName: "fontFace")?.stringValue == "Regular" })

        XCTAssertEqual(
            try document.xmlDocument.nodes(forXPath: "//title/param[@name='Font' or @name='Size']").count,
            fontAndSizeParamsBefore
        )
        let after = InvariantSnapshot(document: document)
        XCTAssertEqual(after.mediaReferences, before.mediaReferences)
        XCTAssertEqual(after.timing, before.timing)
        assertUppercaseTextAndColors(before: before, after: after, report: report)
        XCTAssertEqual(after.nonStyleStructure, before.nonStyleStructure)

        let once = try styleGeometrySnapshot(document)
        let secondReport = try ProjectTransformer().transform(document, settings: .templateDefaults)
        XCTAssertEqual(secondReport.titles.first { normalize($0.titleText) == "dish up" }?.finalFontSize, 36)
        XCTAssertEqual(try styleGeometrySnapshot(document), once)
    }

    func testMissingAndAmbiguousBackgroundsAreSkippedWithoutMutation() throws {
        for count in [0, 2] {
            let document = try syntheticDocument(text: "Mix well", backgroundCount: count)
            let before = document.rootXML

            let report = try transformer().transform(document, settings: .templateDefaults)

            XCTAssertEqual(document.rootXML, before)
            XCTAssertEqual(report.changedTitles, 0)
            XCTAssertEqual(report.skippedTitles, 1)
            XCTAssertEqual(report.matchedBackgrounds, 0)
            XCTAssertFalse(try XCTUnwrap(report.titles.first).backgroundMatched)
            XCTAssertEqual(report.titles.first?.skipReason, count == 0 ? "missing background" : "ambiguous backgrounds")
        }
    }

    func testMissingDimensionsStyleDefinitionAndLayoutFailureAreSkippedWithoutPartialMutation() throws {
        let missingDimensions = try syntheticDocument(text: "Mix well", backgroundCount: 1, includeFormat: false)
        let missingStyle = try syntheticDocument(text: "Mix well", backgroundCount: 1, includeStyleDefinition: false)
        let layoutFailure = try syntheticDocument(text: "metric failure", backgroundCount: 1)

        for (document, transformer, reasonFragment) in [
            (missingDimensions, self.transformer(), "dimensions"),
            (missingStyle, self.transformer(), "style definition"),
            (layoutFailure, ProjectTransformer(layouter: TypographyLayouter(metrics: ThrowingTransformerMetrics())), "metric failure"),
        ] {
            let before = document.rootXML
            let report = try transformer.transform(document, settings: .templateDefaults)
            XCTAssertEqual(document.rootXML, before)
            XCTAssertEqual(report.skippedTitles, 1)
            XCTAssertEqual(report.matchedBackgrounds, 1)
            XCTAssertTrue(try XCTUnwrap(report.titles.first).backgroundMatched)
            XCTAssertTrue(
                (report.titles.first?.skipReason ?? "").localizedCaseInsensitiveContains(reasonFragment),
                report.titles.first?.skipReason ?? "missing reason"
            )
        }
    }

    func testDuplicateReferencedStyleDefinitionsAreSkippedWithoutMutationOrInvariantCrash() throws {
        let document = try syntheticDocument(
            text: "Mix well",
            backgroundCount: 1,
            duplicateStyleDefinitions: true
        )
        let title = try XCTUnwrap(try document.xmlDocument.nodes(forXPath: "//title").first as? XMLElement)
        let background = try XCTUnwrap(try document.xmlDocument.nodes(forXPath: "//video").first as? XMLElement)
        let titleBefore = title.xmlString
        let backgroundBefore = background.xmlString

        _ = InvariantSnapshot(document: document)
        let report = try transformer().transform(document, settings: .templateDefaults)

        XCTAssertEqual(report.skippedTitles, 1)
        XCTAssertEqual(report.matchedBackgrounds, 1)
        XCTAssertTrue((try XCTUnwrap(report.titles.first).skipReason ?? "").localizedCaseInsensitiveContains("ambiguous"))
        XCTAssertEqual(title.xmlString, titleBefore)
        XCTAssertEqual(background.xmlString, backgroundBefore)
    }

    func testFailureAfterPairMutationRollsBackThatPairAndContinues() throws {
        let document = try syntheticDocument(text: "Mix well", backgroundCount: 1)
        let before = document.rootXML
        let transformer = ProjectTransformer(
            layouter: TypographyLayouter(metrics: metrics),
            testHook: { _, _, _ in throw TransformerHookError.forced }
        )

        let report = try transformer.transform(document, settings: .templateDefaults)

        XCTAssertEqual(document.rootXML, before)
        XCTAssertEqual(report.skippedTitles, 1)
        XCTAssertTrue((report.titles.first?.skipReason ?? "").contains("forced"))
    }

    func testInvariantGuardRollsBackEntireDocumentAndThrows() throws {
        let document = try syntheticDocument(text: "Mix well", backgroundCount: 1)
        let before = document.rootXML
        let transformer = ProjectTransformer(
            layouter: TypographyLayouter(metrics: metrics),
            testHook: nil,
            postCommitTestHook: { committed in
                let duration = try XCTUnwrap(try committed.xmlDocument.nodes(forXPath: "//title/@duration").first)
                duration.stringValue = "9s"
            }
        )

        XCTAssertThrowsError(try transformer.transform(document, settings: .templateDefaults)) { error in
            guard case .invariantViolation = error as? AlignerError else {
                return XCTFail("Expected invariantViolation, got \(error)")
            }
        }
        XCTAssertEqual(document.rootXML, before)

        let recovered = try self.transformer().transform(document, settings: .templateDefaults)
        XCTAssertEqual(recovered.changedTitles, 1)
    }

    func testInvariantGuardRejectsPostCommitBoldMutationOnOrdinaryAction() throws {
        let document = try syntheticDocument(text: "Mix well", backgroundCount: 1)
        let before = document.rootXML
        let transformer = ProjectTransformer(
            layouter: TypographyLayouter(metrics: metrics),
            testHook: nil,
            postCommitTestHook: { committed in
                let style = try XCTUnwrap(
                    try committed.xmlDocument.nodes(forXPath: "//title/text-style-def/text-style").first as? XMLElement
                )
                let bold = try XCTUnwrap(XMLNode.attribute(withName: "bold", stringValue: "1") as? XMLNode)
                style.addAttribute(bold)
            }
        )

        XCTAssertThrowsError(try transformer.transform(document, settings: .templateDefaults)) { error in
            guard case .invariantViolation = error as? AlignerError else {
                return XCTFail("Expected invariantViolation, got \(error)")
            }
        }
        XCTAssertEqual(document.rootXML, before)
    }

    func testExistingTransformsAreUpdatedAndMissingTransformsCreatedOnlyForMatchedPair() throws {
        let existing = try syntheticDocument(text: "Mix well", backgroundCount: 1, includeTransforms: true)
        _ = try transformer().transform(existing, settings: .templateDefaults)
        XCTAssertNotEqual(try transformAttribute("position", xpath: "//title/adjust-transform", in: existing), "99 99")
        XCTAssertNotEqual(try transformAttribute("position", xpath: "//video/adjust-transform", in: existing), "88 88")

        let created = try syntheticDocument(text: "Mix well", backgroundCount: 1, includeTransforms: false)
        _ = try transformer().transform(created, settings: .templateDefaults)
        XCTAssertEqual(try created.xmlDocument.nodes(forXPath: "//title/adjust-transform").count, 1)
        XCTAssertEqual(try created.xmlDocument.nodes(forXPath: "//video/adjust-transform").count, 1)

        let unmatched = try syntheticDocument(text: "Mix well", backgroundCount: 0, includeTransforms: false)
        _ = try transformer().transform(unmatched, settings: .templateDefaults)
        XCTAssertEqual(try unmatched.xmlDocument.nodes(forXPath: "//title/adjust-transform").count, 0)
    }

    func testInvalidSettingsAreFatalAndLeaveDocumentUntouched() throws {
        let document = try syntheticDocument(text: "Mix well", backgroundCount: 1)
        let before = document.rootXML
        let invalid = AlignmentSettings(
            actionBaseSize: 0,
            ingredientBaseSize: 16,
            minimumSize: 13,
            autoShrink: true,
            safeWidthFraction: 0.72
        )

        XCTAssertThrowsError(try transformer().transform(document, settings: invalid)) { error in
            guard case .invalidTypographySettings = error as? AlignerError else {
                return XCTFail("Expected invalidTypographySettings, got \(error)")
            }
        }
        XCTAssertEqual(document.rootXML, before)
    }

    private func transformer() -> ProjectTransformer {
        ProjectTransformer(layouter: TypographyLayouter(metrics: metrics))
    }

    private func goldGeometryByNormalizedText() throws -> [String: GoldGeometry] {
        var result: [String: GoldGeometry] = [:]
        let goldXML = try XMLDocument(
            contentsOf: try fixtureURL("sample-gold").appendingPathComponent("Info.fcpxml"),
            options: .nodePreserveAll
        )
        var goldTextByName: [String: String] = [:]
        let goldDocument = try goldFixtureDocument()
        for title in goldDocument.titles where goldTextByName[title.name] == nil {
            goldTextByName[title.name] = title.visibleText
        }
        let customResourceIDs = goldDocument.customGeneratorResourceIDs
        let titles = try goldXML.nodes(forXPath: "//title").compactMap { $0 as? XMLElement }
        for title in titles {
            guard
                let background = matchingGoldBackground(for: title, customResourceIDs: customResourceIDs),
                let name = title.attribute(forName: "name")?.stringValue,
                let visibleText = goldTextByName[name]
            else {
                continue
            }
            let titleTransform = try XCTUnwrap(directTransform(in: title))
            let backgroundTransform = try XCTUnwrap(directTransform(in: background))
            result[normalize(visibleText)] = GoldGeometry(
                titlePosition: try attribute("position", in: titleTransform),
                backgroundPosition: try attribute("position", in: backgroundTransform),
                backgroundScale: try attribute("scale", in: backgroundTransform)
            )
        }
        return result
    }

    private func matchingGoldBackground(
        for title: XMLElement,
        customResourceIDs: Set<String>
    ) -> XMLElement? {
        guard
            let parent = title.parent as? XMLElement,
            let titleOffset = title.attribute(forName: "offset")?.stringValue.flatMap(RationalTime.init(parsing:))
        else {
            return nil
        }
        let matches = (parent.children ?? []).compactMap { $0 as? XMLElement }.filter { candidate in
            guard
                candidate.name == "video",
                let reference = candidate.attribute(forName: "ref")?.stringValue,
                customResourceIDs.contains(reference),
                let offset = candidate.attribute(forName: "offset")?.stringValue.flatMap(RationalTime.init(parsing:))
            else {
                return false
            }
            return offset == titleOffset
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private func directTransform(in element: XMLElement) -> XMLElement? {
        (element.children ?? []).compactMap { $0 as? XMLElement }.first { $0.name == "adjust-transform" }
    }

    private func attribute(_ name: String, in element: XMLElement) throws -> String {
        try XCTUnwrap(element.attribute(forName: name)?.stringValue)
    }

    private func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "mintues", with: "minutes", options: [.caseInsensitive])
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func firstNumber(in pair: String?) throws -> Double {
        let value = try XCTUnwrap(pair)
        return try XCTUnwrap(value.split(separator: " ").first.flatMap { Double($0) })
    }

    private func secondNumber(in pair: String?) throws -> Double {
        let value = try XCTUnwrap(pair)
        let numbers = value.split(separator: " ").compactMap { Double($0) }
        XCTAssertEqual(numbers.count, 2)
        return try XCTUnwrap(numbers.last)
    }

    private func assertUppercaseTextAndColors(
        before: InvariantSnapshot,
        after: InvariantSnapshot,
        report: ChangeReport,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(after.visibleTextAndColors.count, before.visibleTextAndColors.count, file: file, line: line)
        for (index, pair) in zip(before.visibleTextAndColors, after.visibleTextAndColors).enumerated() {
            let (originalTitle, transformedTitle) = pair
            let shouldUppercase = report.titles[index].skipReason == nil
            XCTAssertEqual(transformedTitle.path, originalTitle.path, file: file, line: line)
            XCTAssertEqual(
                transformedTitle.text,
                shouldUppercase ? originalTitle.text.uppercased() : originalTitle.text,
                file: file,
                line: line
            )
            XCTAssertEqual(transformedTitle.runs.count, originalTitle.runs.count, file: file, line: line)
            for (originalRun, transformedRun) in zip(originalTitle.runs, transformedTitle.runs) {
                XCTAssertEqual(
                    transformedRun.text,
                    shouldUppercase ? originalRun.text.uppercased() : originalRun.text,
                    file: file,
                    line: line
                )
                XCTAssertEqual(transformedRun.ref, originalRun.ref, file: file, line: line)
                XCTAssertEqual(transformedRun.colors, originalRun.colors, file: file, line: line)
            }
        }
    }

    private func assertPair(_ actual: String?, equals expected: String, accuracy: Double) throws {
        let actualValues = try XCTUnwrap(actual).split(separator: " ").compactMap { Double($0) }
        let expectedValues = expected.split(separator: " ").compactMap { Double($0) }
        XCTAssertEqual(actualValues.count, 2)
        XCTAssertEqual(expectedValues.count, 2)
        XCTAssertEqual(actualValues[0], expectedValues[0], accuracy: accuracy)
        XCTAssertEqual(actualValues[1], expectedValues[1], accuracy: accuracy)
    }

    private func assertNormalizedStyle(
        in document: FCPXMLDocument,
        titleText: String,
        font: String,
        size: String,
        alignment: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let title = try XCTUnwrap(
            document.titles.first { $0.visibleText.uppercased() == titleText },
            file: file,
            line: line
        )
        let styles = try referencedDefinitionStyles(for: title)
        XCTAssertFalse(styles.isEmpty, file: file, line: line)
        for style in styles {
            XCTAssertEqual(style.attribute(forName: "font")?.stringValue, font, file: file, line: line)
            XCTAssertEqual(style.attribute(forName: "fontSize")?.stringValue, size, file: file, line: line)
            XCTAssertEqual(style.attribute(forName: "fontFace")?.stringValue, "Regular", file: file, line: line)
            XCTAssertEqual(style.attribute(forName: "alignment")?.stringValue, alignment, file: file, line: line)
            XCTAssertEqual(style.attribute(forName: "lineSpacing")?.stringValue, "-2", file: file, line: line)
        }
        let params = try title.element.nodes(forXPath: ".//param[@name='Alignment']").compactMap { $0 as? XMLElement }
        let expectedParam = alignment == "left" ? "0 (Left)" : "1 (Center)"
        XCTAssertTrue(params.allSatisfy { $0.attribute(forName: "value")?.stringValue == expectedParam }, file: file, line: line)
        let spacing = try title.element.nodes(forXPath: ".//param[@name='Line Spacing']").compactMap { $0 as? XMLElement }
        XCTAssertTrue(spacing.allSatisfy { $0.attribute(forName: "value")?.stringValue == "-2" }, file: file, line: line)
    }

    private func referencedDefinitionStyles(for title: TitleRecord) throws -> [XMLElement] {
        let refs = Set(title.visibleTextRuns.map(\.ref))
        return try title.element.nodes(forXPath: "./text-style-def").compactMap { $0 as? XMLElement }.compactMap { definition in
            guard let identifier = definition.attribute(forName: "id")?.stringValue, refs.contains(identifier) else { return nil }
            return (definition.children ?? []).compactMap { $0 as? XMLElement }.first { $0.name == "text-style" }
        }
    }

    private func styleAttribute(_ name: String, in document: FCPXMLDocument) throws -> String {
        let style = try XCTUnwrap(try document.xmlDocument.nodes(forXPath: "//title/text-style-def/text-style").first as? XMLElement)
        return try XCTUnwrap(style.attribute(forName: name)?.stringValue)
    }

    private func transformAttribute(_ name: String, xpath: String, in document: FCPXMLDocument) throws -> String {
        let transform = try XCTUnwrap(try document.xmlDocument.nodes(forXPath: xpath).first as? XMLElement)
        return try XCTUnwrap(transform.attribute(forName: name)?.stringValue)
    }

    private func styleGeometrySnapshot(_ document: FCPXMLDocument) throws -> [String] {
        let nodes = try document.xmlDocument.nodes(
            forXPath: "//title/text-style-def/text-style | //title/param[@name='Alignment' or @name='Line Spacing'] | //title/adjust-transform | //video/adjust-transform | //generator/adjust-transform"
        ).compactMap { $0 as? XMLElement }
        return nodes.map { element in
            let attributes = (element.attributes ?? []).compactMap { attribute -> String? in
                guard let name = attribute.name else { return nil }
                return "\(name)=\(attribute.stringValue ?? "")"
            }.sorted().joined(separator: "|")
            return "\(element.name ?? ""):\(attributes)"
        }
    }

    private func syntheticDocument(
        text: String,
        backgroundCount: Int,
        includeFormat: Bool = true,
        includeStyleDefinition: Bool = true,
        includeTransforms: Bool = false,
        fontFace: String? = nil,
        duplicateStyleDefinitions: Bool = false
    ) throws -> FCPXMLDocument {
        let format = includeFormat ? #"<format id="format" width="1080" height="1920"/>"# : ""
        let sequenceFormat = includeFormat ? #" format="format""# : ""
        let backgroundTransform = includeTransforms ? #"<adjust-transform position="88 88" scale="8 8"/>"# : ""
        let backgrounds = (0..<backgroundCount).map { _ in
            #"<video ref="custom" offset="0s" duration="1s">\#(backgroundTransform)</video>"#
        }.joined()
        let faceAttribute = fontFace.map { #" fontFace="\#($0)""# } ?? ""
        let styleDefinition = #"<text-style-def id="style"><text-style font="Helvetica" fontSize="31" fontColor="1 0.9 0 1" italic="1" custom="keep"\#(faceAttribute)/></text-style-def>"#
        let style = includeStyleDefinition
            ? styleDefinition + (duplicateStyleDefinitions ? styleDefinition : "")
            : ""
        let titleTransform = includeTransforms ? #"<adjust-transform position="99 99" scale="9 9"/>"# : ""
        let escapedText = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return try FCPXMLDocument(xmlString: """
        <fcpxml version="1.14">
          <resources>
            \(format)
            <effect id="basic" name="Basic Title" uid="Basic Title.moti"/>
            <effect id="custom" name="Custom" uid="Generators.localized/Solids.localized/Custom.motn"/>
          </resources>
          <library><event><project name="Project"><sequence\(sequenceFormat)><spine><clip offset="0s" duration="10s">
            \(backgrounds)
            <title ref="basic" name="Synthetic" offset="0s" duration="1s">
              <param name="Alignment" key="opaque/alignment/key" value="9"/>
              <param name="Line Spacing" key="opaque/spacing/key" value="9"/>
              <text><text-style ref="style">\(escapedText)</text-style></text>
              \(style)
              \(titleTransform)
            </title>
          </clip></spine></sequence></project></event></library>
        </fcpxml>
        """)
    }

    private func format(_ x: Double, _ y: Double) -> String {
        "\(canonical(x)) \(canonical(y))"
    }

    private func canonical(_ value: Double) -> String {
        String(format: "%.12g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

private struct TransformerTestMetrics: FontMetricsMeasuring {
    func width(of text: String, fontFamily: String, fontFace: TypographyFontFace, fontSize: Double) throws -> Double {
        Double(text.count) * (fontFace == .italic ? 0.22 : 0.2) * fontSize
    }

    func lineHeight(fontFamily: String, fontFace: TypographyFontFace, fontSize: Double) throws -> Double {
        fontSize
    }
}

private struct ThrowingTransformerMetrics: FontMetricsMeasuring {
    func width(of text: String, fontFamily: String, fontFace: TypographyFontFace, fontSize: Double) throws -> Double {
        throw TransformerHookError.metricFailure
    }

    func lineHeight(fontFamily: String, fontFace: TypographyFontFace, fontSize: Double) throws -> Double {
        throw TransformerHookError.metricFailure
    }
}

private enum TransformerHookError: Error, LocalizedError {
    case forced
    case metricFailure

    var errorDescription: String? {
        switch self {
        case .forced: "forced post-mutation failure"
        case .metricFailure: "metric failure"
        }
    }
}
