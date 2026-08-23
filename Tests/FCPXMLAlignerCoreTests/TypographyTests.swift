import Foundation
import XCTest
@testable import FCPXMLAlignerCore

final class TypographyTests: XCTestCase {
    private let actionReferenceWidth = 57.993174014734514
    private let ingredientReferenceWidth = 129.105
    private let closingReferenceWidth = 209.336334343504177

    func testLayoutVariantSelectorOnlyChoosesHeroForNormalizedDishUp() {
        XCTAssertEqual(LayoutVariantSelector.select(visibleText: " \nDiSh\t Up  "), .heroAction)
        XCTAssertEqual(LayoutVariantSelector.select(visibleText: "dishup"), .ordinary)
        XCTAssertEqual(LayoutVariantSelector.select(visibleText: "dish up now"), .ordinary)
    }

    func testHeroActionUsesExactGoldLayoutWithoutMeasuringAviano() throws {
        let metrics = CallCountingMetrics()
        let layout = try TypographyLayouter(metrics: metrics).layout(
            runs: [.init(text: "Dish Up")],
            kind: .action,
            variant: .heroAction,
            projectWidth: 1080,
            settings: .templateDefaults
        )

        XCTAssertEqual(metrics.callCount, 0)
        XCTAssertEqual(layout.variant, .heroAction)
        XCTAssertEqual(layout.finalFontSize, 36)
        XCTAssertEqual(layout.fontFamily, "Aviano Sans")
        XCTAssertTrue(layout.isBold)
        XCTAssertEqual(layout.alignment, .center)
        XCTAssertEqual(layout.lineSpacing, -2)
        XCTAssertEqual(layout.titlePosition, .init(x: -0.0112916, y: 29.9241))
        XCTAssertEqual(layout.titleScale, 1.65437)
        XCTAssertEqual(layout.backgroundPosition, .init(x: 0.00640178, y: 31.1586))
        XCTAssertEqual(layout.backgroundScaleX, 0.417778)
        XCTAssertEqual(layout.backgroundScaleY, 0.0536121)
        XCTAssertFalse(layout.autoShrunk)
        XCTAssertTrue(layout.fitsSafeWidth)
    }

    func testHeroActionScalesWithAdjustableActionSizeAndReportsSafeWidthOverflow() throws {
        let metrics = CallCountingMetrics()
        let settings = AlignmentSettings(
            actionBaseSize: 20,
            ingredientBaseSize: 15,
            minimumSize: 13,
            autoShrink: false,
            safeWidthFraction: 0.4
        )
        let layout = try TypographyLayouter(metrics: metrics).layout(
            runs: [.init(text: "Dish Up")],
            kind: .action,
            variant: .heroAction,
            projectWidth: 1080,
            settings: settings
        )

        let factor = 20.0 / 17.0
        XCTAssertEqual(metrics.callCount, 0)
        XCTAssertEqual(layout.finalFontSize, 36 * factor)
        XCTAssertEqual(layout.backgroundScaleX, 0.417778 * factor)
        XCTAssertEqual(layout.backgroundScaleY, 0.0536121 * factor)
        XCTAssertFalse(layout.autoShrunk)
        XCTAssertFalse(layout.fitsSafeWidth)
    }

    func testHeroActionAutoShrinkUsesItsFixedGeometryWithoutMeasuring() throws {
        let metrics = CallCountingMetrics()
        let settings = AlignmentSettings(
            actionBaseSize: 20,
            ingredientBaseSize: 15,
            minimumSize: 13,
            autoShrink: true,
            safeWidthFraction: 0.35
        )
        let layout = try TypographyLayouter(metrics: metrics).layout(
            runs: [.init(text: "Dish Up")],
            kind: .action,
            variant: .heroAction,
            projectWidth: 1080,
            settings: settings
        )

        let factor = settings.safeWidthFraction / 0.417778
        XCTAssertEqual(metrics.callCount, 0)
        XCTAssertTrue(layout.autoShrunk)
        XCTAssertTrue(layout.fitsSafeWidth)
        XCTAssertEqual(layout.finalFontSize, 36 * factor, accuracy: 1e-12)
        XCTAssertEqual(layout.backgroundScaleX, settings.safeWidthFraction, accuracy: 1e-12)
        XCTAssertEqual(layout.backgroundScaleY, 0.0536121 * factor, accuracy: 1e-12)
    }

    func testActionReferenceUsesCalibratedWidthAndGeometry() throws {
        let metrics = TableFontMetrics(widthAtOnePoint: ["warm the skillet": actionReferenceWidth / 17])

        let layout = try TypographyLayouter(metrics: metrics).layout(
            runs: [.init(text: "warm the skillet")],
            kind: .action,
            projectWidth: 1080,
            settings: .templateDefaults
        )

        XCTAssertEqual(layout.kind, .action)
        XCTAssertEqual(layout.finalFontSize, 17)
        XCTAssertEqual(layout.fontFamily, "Avenir Next Condensed")
        XCTAssertEqual(layout.fontFace, "Regular")
        XCTAssertEqual(layout.alignment, .center)
        XCTAssertEqual(layout.lineSpacing, -2)
        XCTAssertEqual(layout.titleScale, 1.65437)
        XCTAssertEqual(layout.titlePosition.x, -0.0112916)
        XCTAssertEqual(layout.titlePosition.y, 30.3714)
        XCTAssertEqual(layout.backgroundPosition.x, 0.00640178)
        XCTAssertEqual(layout.backgroundPosition.y, 31.1507)
        XCTAssertEqual(layout.backgroundScaleX, 0.196152, accuracy: 0.000_000_1)
        XCTAssertEqual(layout.backgroundScaleY, 0.0387046, accuracy: 0.000_000_1)
        XCTAssertFalse(layout.autoShrunk)
        XCTAssertTrue(layout.fitsSafeWidth)
    }

    func testScreenshotCalibrationAddsActionBreathingRoomAndCentersCapHeight() throws {
        let metrics = TableFontMetrics(widthAtOnePoint: ["CAREFULLY SPREAD THE BATTER ACROSS THE WARM SKILLET SURFACE": 1])

        let layout = try TypographyLayouter(metrics: metrics).layout(
            runs: [.init(text: "CAREFULLY SPREAD THE BATTER ACROSS THE WARM SKILLET SURFACE")],
            kind: .action,
            projectWidth: 1080,
            settings: noShrinkSettings
        )

        XCTAssertEqual(layout.titlePosition.y, 30.246, accuracy: 0.000_001)
        XCTAssertEqual(layout.backgroundScaleY, 0.04135, accuracy: 0.000_000_1)
        XCTAssertEqual(
            layout.backgroundScaleX,
            widthScale(measuredWidth: 17) + 40.0 / 1080.0,
            accuracy: 0.000_000_1
        )
    }

    func testIngredientReferenceUsesFiveLineHeightAndLeftAnchoredWidth() throws {
        let longest = "Flour 500g"
        let metrics = TableFontMetrics(widthAtOnePoint: [longest: ingredientReferenceWidth / 15])
        let text = "\(longest)\nSalt 1 tsp\nThree eggs\nYeast 5g\nWarm water 300ml"

        let layout = try TypographyLayouter(metrics: metrics).layout(
            runs: [.init(text: text)],
            kind: .ingredient,
            projectWidth: 1080,
            settings: .templateDefaults
        )

        XCTAssertEqual(layout.fontFamily, "Avenir Next")
        XCTAssertEqual(layout.alignment, .left)
        XCTAssertEqual(layout.finalFontSize, 15)
        XCTAssertEqual(layout.titlePosition.x, -9.86106, accuracy: 0.000_000_1)
        XCTAssertEqual(layout.titlePosition.y, 35.7613, accuracy: 0.000_000_1)
        XCTAssertEqual(layout.backgroundScaleX, 0.395549, accuracy: 0.000_000_1)
        XCTAssertEqual(layout.backgroundScaleY, 0.14387, accuracy: 0.000_000_1)
        XCTAssertEqual(layout.backgroundPosition.x, -0.0199015, accuracy: 0.000_000_1)
        XCTAssertEqual(layout.backgroundPosition.y, 31.0997)
    }

    func testScreenshotCalibrationCentersIngredientBackgroundAndBalancesMargins() throws {
        let longest = "FLOUR 500G"
        let metrics = TableFontMetrics(widthAtOnePoint: [longest: ingredientReferenceWidth / 15 * 1.2])
        let text = "\(longest)\nSALT 1 TSP\nTHREE EGGS\nYEAST 5G\nWARM WATER 300ML"

        let layout = try TypographyLayouter(metrics: metrics).layout(
            runs: [.init(text: text)],
            kind: .ingredient,
            projectWidth: 1080,
            settings: noShrinkSettings
        )

        XCTAssertEqual(layout.titlePosition.y, 35.971, accuracy: 0.000_001)
        XCTAssertEqual(layout.backgroundScaleY, 0.15006, accuracy: 0.000_000_1)
        XCTAssertEqual(
            layout.backgroundPosition.x,
            TemplateCalibration.ingredientReferenceBackgroundPosition.x,
            accuracy: 0.000_000_1
        )
        let expectedTitleX = TemplateCalibration.uppercaseIngredientTitlePosition.x
            - (layout.backgroundScaleX - 0.395549) * 1080 * 50 / 1920
        XCTAssertEqual(layout.titlePosition.x, expectedTitleX, accuracy: 0.000_000_1)
    }

    func testClosingTwoLineReferenceUsesClosingGeometry() throws {
        let firstLine = "simple kitchen notes"
        let metrics = TableFontMetrics(widthAtOnePoint: [firstLine: closingReferenceWidth / 17])

        let layout = try TypographyLayouter(metrics: metrics).layout(
            runs: [.init(text: "\(firstLine)\nfollow for more")],
            kind: .closing,
            projectWidth: 1080,
            settings: .templateDefaults
        )

        XCTAssertEqual(layout.titlePosition, .init(x: -0.0112916, y: 31.9841))
        XCTAssertEqual(layout.backgroundPosition, .init(x: 0.00640178, y: 31.3437))
        XCTAssertEqual(layout.backgroundScaleX, 0.589351, accuracy: 0.000_001)
        XCTAssertEqual(layout.backgroundScaleY, 0.0669004, accuracy: 0.000_000_1)
    }

    func testAdjustableBaseSizesAffectFontWidthAndHeight() throws {
        let metrics = TableFontMetrics(widthAtOnePoint: ["warm the skillet": actionReferenceWidth / 17])
        let settings = AlignmentSettings(
            actionBaseSize: 20,
            ingredientBaseSize: 18,
            minimumSize: 10,
            autoShrink: false,
            safeWidthFraction: 1
        )

        let layout = try TypographyLayouter(metrics: metrics).layout(
            runs: [.init(text: "warm the skillet")], kind: .action, projectWidth: 1080, settings: settings
        )

        XCTAssertEqual(layout.finalFontSize, 20)
        XCTAssertEqual(layout.backgroundScaleX, widthScale(measuredWidth: actionReferenceWidth * 20 / 17), accuracy: 1e-12)
        XCTAssertEqual(
            layout.backgroundScaleY,
            expectedHeight(kind: .action, fontSize: 20, lineCount: 1),
            accuracy: 1e-12
        )
    }

    func testAutoShrinkFindsLargestFittingSize() throws {
        let metrics = TableFontMetrics(widthAtOnePoint: ["wide": 10])
        let settings = AlignmentSettings(
            actionBaseSize: 17,
            ingredientBaseSize: 16,
            minimumSize: 10,
            autoShrink: true,
            safeWidthFraction: 0.4
        )

        let layout = try TypographyLayouter(metrics: metrics).layout(
            runs: [.init(text: "wide")], kind: .action, projectWidth: 1080, settings: settings
        )

        XCTAssertTrue(layout.autoShrunk)
        XCTAssertTrue(layout.fitsSafeWidth)
        XCTAssertLessThan(layout.finalFontSize, 17)
        XCTAssertGreaterThan(layout.finalFontSize, 10)
        XCTAssertEqual(layout.backgroundScaleX, 0.4, accuracy: 1e-9)
    }

    func testAutoShrinkClampsAtMinimumAndExposesOverflow() throws {
        let metrics = TableFontMetrics(widthAtOnePoint: ["too wide": 10])
        let settings = AlignmentSettings(
            actionBaseSize: 17,
            ingredientBaseSize: 16,
            minimumSize: 13,
            autoShrink: true,
            safeWidthFraction: 0.1
        )

        let layout = try TypographyLayouter(metrics: metrics).layout(
            runs: [.init(text: "too wide")], kind: .action, projectWidth: 1080, settings: settings
        )

        XCTAssertEqual(layout.finalFontSize, 13)
        XCTAssertTrue(layout.autoShrunk)
        XCTAssertFalse(layout.fitsSafeWidth)
        XCTAssertGreaterThan(layout.backgroundScaleX, settings.safeWidthFraction)
    }

    func testDisabledAutoShrinkKeepsBaseSizeAndReportsOverflow() throws {
        let metrics = TableFontMetrics(widthAtOnePoint: ["wide": 10])
        let settings = AlignmentSettings(
            actionBaseSize: 17,
            ingredientBaseSize: 16,
            minimumSize: 13,
            autoShrink: false,
            safeWidthFraction: 0.1
        )

        let layout = try TypographyLayouter(metrics: metrics).layout(
            runs: [.init(text: "wide")], kind: .action, projectWidth: 1080, settings: settings
        )

        XCTAssertEqual(layout.finalFontSize, 17)
        XCTAssertFalse(layout.autoShrunk)
        XCTAssertFalse(layout.fitsSafeWidth)
    }

    func testInvalidSettingsAreRejected() throws {
        let metrics = TableFontMetrics(widthAtOnePoint: [:])
        let invalidSettings: [AlignmentSettings] = [
            .init(actionBaseSize: 0, ingredientBaseSize: 16, minimumSize: 13, autoShrink: true, safeWidthFraction: 0.72),
            .init(actionBaseSize: 17, ingredientBaseSize: .infinity, minimumSize: 13, autoShrink: true, safeWidthFraction: 0.72),
            .init(actionBaseSize: 17, ingredientBaseSize: 16, minimumSize: -1, autoShrink: true, safeWidthFraction: 0.72),
            .init(actionBaseSize: 12, ingredientBaseSize: 16, minimumSize: 13, autoShrink: true, safeWidthFraction: 0.72),
            .init(actionBaseSize: 17, ingredientBaseSize: 12, minimumSize: 13, autoShrink: true, safeWidthFraction: 0.72),
            .init(actionBaseSize: 17, ingredientBaseSize: 16, minimumSize: 13, autoShrink: true, safeWidthFraction: 0),
            .init(actionBaseSize: 17, ingredientBaseSize: 16, minimumSize: 13, autoShrink: true, safeWidthFraction: 1.01),
        ]

        for settings in invalidSettings {
            XCTAssertThrowsError(
                try TypographyLayouter(metrics: metrics).layout(
                    runs: [.init(text: "text")], kind: .action, projectWidth: 1080, settings: settings
                )
            ) { error in
                guard case .invalidTypographySettings = error as? AlignerError else {
                    return XCTFail("Expected invalidTypographySettings, got \(error)")
                }
            }
        }
    }

    func testLineWidthUsesMaximumRatherThanSum() throws {
        let metrics = TableFontMetrics(widthAtOnePoint: ["first": 4, "second": 2])
        let layouter = TypographyLayouter(metrics: metrics)
        let multiline = try layouter.layout(
            runs: [.init(text: "first\nsecond")], kind: .action, projectWidth: 1080, settings: noShrinkSettings
        )
        let longestOnly = try layouter.layout(
            runs: [.init(text: "first")], kind: .action, projectWidth: 1080, settings: noShrinkSettings
        )

        XCTAssertEqual(multiline.backgroundScaleX, longestOnly.backgroundScaleX, accuracy: 1e-12)
    }

    func testEveryRunWidthIsValidatedBeforeAccumulation() throws {
        let metrics = TableFontMetrics(widthAtOnePoint: ["positive": 10, "negative": -9])

        assertInvalidMeasurement(containing: "run width") {
            try TypographyLayouter(metrics: metrics).layout(
                runs: [.init(text: "positive"), .init(text: "negative")],
                kind: .action,
                projectWidth: 1080,
                settings: noShrinkSettings
            )
        }
    }

    func testLaterLineNaNIsRejectedRatherThanHiddenByMaximumSelection() throws {
        let metrics = TableFontMetrics(widthAtOnePoint: ["valid": 1, "nan": .nan])

        assertInvalidMeasurement(containing: "run width") {
            try TypographyLayouter(metrics: metrics).layout(
                runs: [.init(text: "valid\nnan")],
                kind: .action,
                projectWidth: 1080,
                settings: noShrinkSettings
            )
        }
    }

    func testAccumulatedLineWidthOverflowIsRejected() throws {
        let large = Double.greatestFiniteMagnitude * 0.75
        let metrics = FixedFontMetrics(widths: ["first": large, "second": large], lineHeight: 17)

        assertInvalidMeasurement(containing: "line width") {
            try TypographyLayouter(metrics: metrics).layout(
                runs: [.init(text: "first"), .init(text: "second")],
                kind: .action,
                projectWidth: 1080,
                settings: noShrinkSettings
            )
        }
    }

    func testInfiniteRunWidthIsRejected() throws {
        let metrics = FixedFontMetrics(widths: ["infinite": .infinity], lineHeight: 17)

        assertInvalidMeasurement(containing: "run width") {
            try TypographyLayouter(metrics: metrics).layout(
                runs: [.init(text: "infinite")],
                kind: .action,
                projectWidth: 1080,
                settings: noShrinkSettings
            )
        }
    }

    func testCalibratedWidthMultiplicationOverflowIsRejected() throws {
        let metrics = FixedFontMetrics(
            widths: ["overflow": Double.greatestFiniteMagnitude * 0.75],
            lineHeight: 17
        )

        assertInvalidMeasurement(containing: "calibrated width") {
            try TypographyLayouter(metrics: metrics).layout(
                runs: [.init(text: "overflow")],
                kind: .action,
                projectWidth: 1080,
                settings: noShrinkSettings
            )
        }
    }

    func testActionHeightsUseOneFixedPaddingForOneTwoThreeAndFiveLines() throws {
        try assertProfileHeights(kind: .action, fontSize: 17)
    }

    func testClosingHeightsUseOneFixedPaddingForOneTwoThreeAndFiveLines() throws {
        try assertProfileHeights(kind: .closing, fontSize: 17)
    }

    func testIngredientHeightsUseOneFixedPaddingForOneTwoThreeAndFiveLines() throws {
        try assertProfileHeights(kind: .ingredient, fontSize: 15)
    }

    func testInvalidLineHeightIsRejected() throws {
        for badHeight in [Double.nan, -Double.infinity, -1, 0] {
            let metrics = FixedFontMetrics(widths: ["text": 10], lineHeight: badHeight)
            assertInvalidMeasurement(containing: "line height") {
                try TypographyLayouter(metrics: metrics).layout(
                    runs: [.init(text: "text")],
                    kind: .action,
                    projectWidth: 1080,
                    settings: noShrinkSettings
                )
            }
        }
    }

    func testCalibratedHeightOverflowIsRejected() throws {
        let metrics = FixedFontMetrics(
            widths: ["text": 10],
            lineHeight: Double.greatestFiniteMagnitude * 0.75
        )

        assertInvalidMeasurement(containing: "height") {
            try TypographyLayouter(metrics: metrics).layout(
                runs: [.init(text: "text")],
                kind: .action,
                projectWidth: 1080,
                settings: noShrinkSettings
            )
        }
    }

    func testStyleRunWidthsAreSummedPerLineAndItalicIsPreserved() throws {
        let metrics = TableFontMetrics(
            widthAtOnePoint: ["plain": 1, "emphasis": 1],
            italicWidthAtOnePoint: ["emphasis": 2]
        )

        let layout = try TypographyLayouter(metrics: metrics).layout(
            runs: [.init(text: "plain"), .init(text: "emphasis", isItalic: true)],
            kind: .action,
            projectWidth: 1080,
            settings: noShrinkSettings
        )

        XCTAssertEqual(layout.backgroundScaleX, widthScale(measuredWidth: 3 * 17), accuracy: 1e-12)
    }

    func testIngredientBackgroundRemainsCenteredWhenWidthChanges() throws {
        let layouter = TypographyLayouter(metrics: TableFontMetrics(widthAtOnePoint: ["short": 2, "long": 4]))
        let short = try layouter.layout(
            runs: [.init(text: "short")], kind: .ingredient, projectWidth: 1080, settings: noShrinkSettings
        )
        let long = try layouter.layout(
            runs: [.init(text: "long")], kind: .ingredient, projectWidth: 1080, settings: noShrinkSettings
        )

        XCTAssertEqual(short.backgroundPosition.x, TemplateCalibration.ingredientReferenceBackgroundPosition.x)
        XCTAssertEqual(long.backgroundPosition.x, TemplateCalibration.ingredientReferenceBackgroundPosition.x)
    }

    func testIngredientTitleTracksHalfWidthChangeToKeepMarginsSymmetric() throws {
        let projectWidth = 1080.0
        let projectHeight = 1920.0
        let layouter = TypographyLayouter(metrics: TableFontMetrics(widthAtOnePoint: ["short": 2, "long": 4]))
        let short = try layouter.layout(
            runs: [.init(text: "short")],
            kind: .ingredient,
            projectWidth: projectWidth,
            projectHeight: projectHeight,
            settings: noShrinkSettings
        )
        let long = try layouter.layout(
            runs: [.init(text: "long")],
            kind: .ingredient,
            projectWidth: projectWidth,
            projectHeight: projectHeight,
            settings: noShrinkSettings
        )

        XCTAssertEqual(
            long.titlePosition.x - short.titlePosition.x,
            -(long.backgroundScaleX - short.backgroundScaleX) * projectWidth * 50 / projectHeight,
            accuracy: 1e-12
        )
    }

    func testIdenticalInputProducesIdenticalLayout() throws {
        let layouter = TypographyLayouter(metrics: TableFontMetrics(widthAtOnePoint: ["same": 3]))

        let first = try layouter.layout(
            runs: [.init(text: "same")], kind: .action, projectWidth: 1080, settings: .templateDefaults
        )
        let second = try layouter.layout(
            runs: [.init(text: "same")], kind: .action, projectWidth: 1080, settings: .templateDefaults
        )

        XCTAssertEqual(first, second)
    }

    func testFixturesExposeProjectDimensionsAndResolvedSourceStyleMetadata() throws {
        let current = try currentFixtureDocument()
        let template = try templateFixtureDocument()

        XCTAssertEqual(current.projectDimensions, .init(width: 1080, height: 1920))
        XCTAssertEqual(template.projectDimensions, .init(width: 1080, height: 1920))

        let ingredient = try XCTUnwrap(template.titles.first { TitleClassifier.classify($0.visibleText) == .ingredient })
        let italicRun = try XCTUnwrap(ingredient.visibleTextRuns.first { $0.isItalic })
        XCTAssertEqual(italicRun.sourceFontFamily, "Avenir Next")
        XCTAssertNil(italicRun.sourceFontFace)
    }

    func testTitlesResolveDimensionsFromTheirOwnContainingSequences() throws {
        let document = try FCPXMLDocument(xmlString: """
        <?xml version="1.0" encoding="UTF-8"?>
        <fcpxml version="1.14">
          <resources>
            <format id="portrait" width="1080" height="1920"/>
            <format id="landscape" width="1920" height="1080"/>
            <effect id="basic" name="Basic Title" uid="Basic Title.moti"/>
          </resources>
          <library><event name="event">
            <project name="portrait project"><sequence format="portrait"><spine>
              <title ref="basic" name="portrait title"><text><text-style ref="p">same text</text-style></text>
                <text-style-def id="p"><text-style font="Avenir Next Condensed"/></text-style-def>
              </title>
            </spine></sequence></project>
            <project name="landscape project"><sequence format="landscape"><spine>
              <title ref="basic" name="landscape title"><text><text-style ref="l">same text</text-style></text>
                <text-style-def id="l"><text-style font="Avenir Next Condensed"/></text-style-def>
              </title>
            </spine></sequence></project>
          </event></library>
        </fcpxml>
        """)

        XCTAssertNil(document.projectDimensions)
        let portrait = try XCTUnwrap(document.titles.first { $0.name == "portrait title" })
        let landscape = try XCTUnwrap(document.titles.first { $0.name == "landscape title" })
        XCTAssertEqual(portrait.projectDimensions, .init(width: 1080, height: 1920))
        XCTAssertEqual(landscape.projectDimensions, .init(width: 1920, height: 1080))

        let layouter = TypographyLayouter(metrics: TableFontMetrics(widthAtOnePoint: ["same text": 3]))
        let portraitLayout = try layouter.layout(title: portrait, kind: .action, settings: noShrinkSettings)
        let landscapeLayout = try layouter.layout(title: landscape, kind: .action, settings: noShrinkSettings)

        XCTAssertEqual(portraitLayout.backgroundScaleX, widthScale(measuredWidth: 3 * 17), accuracy: 1e-12)
        XCTAssertEqual(
            landscapeLayout.backgroundScaleX,
            portraitLayout.backgroundScaleX * 1080 / 1920,
            accuracy: 1e-12
        )
        XCTAssertEqual(portraitLayout.backgroundScaleY, TemplateCalibration.actionHeightAt17, accuracy: 1e-12)
        XCTAssertEqual(
            landscapeLayout.backgroundScaleY,
            TemplateCalibration.actionHeightAt17 * 1920 / 1080,
            accuracy: 1e-12
        )
    }

#if canImport(AppKit)
    func testAppKitMetricsReproduceTemplateReferenceWidthsWithinTolerance() throws {
        let document = try templateFixtureDocument()
        let layouter = TypographyLayouter(metrics: AppKitFontMetrics())
        let samples: [(text: String, expected: Double)] = [
            ("warm the skillet", 0.290565),
            ("flour 500g\nsalt 1 tsp\nthree eggs\nyeast 5g\nwarm water 300ml", 0.387860),
            ("follow for more\nsimple kitchen notes", 0.365296),
        ]

        for sample in samples {
            let title = try XCTUnwrap(document.titles.first { $0.visibleText.contains(sample.text.split(separator: "\n")[0]) })
            let layout = try layouter.layout(
                title: title,
                kind: TitleClassifier.classify(title.visibleText),
                projectWidth: 1080,
                settings: .templateDefaults
            )
            XCTAssertEqual(layout.backgroundScaleX, sample.expected, accuracy: 0.02, sample.text)
        }
    }
#endif

    private var noShrinkSettings: AlignmentSettings {
        .init(actionBaseSize: 17, ingredientBaseSize: 15, minimumSize: 10, autoShrink: false, safeWidthFraction: 1)
    }

    private func widthScale(measuredWidth: Double) -> Double {
        (
            measuredWidth * TemplateCalibration.titleScale * TemplateCalibration.measuredWidthMultiplier
                + TemplateCalibration.fixedWidthPaddingPixels
        ) / 1080
    }

    private func expectedHeight(
        kind: TitleKind,
        fontSize: Double,
        lineCount: Int,
        projectHeight: Double = 1920,
        lineHeightAtOnePoint: Double = 1
    ) -> Double {
        let profile: (referenceHeight: Double, referenceSize: Double, referenceLines: Int)
        switch kind {
        case .action:
            profile = (TemplateCalibration.actionHeightAt17, 17, 1)
        case .closing:
            profile = (TemplateCalibration.closingHeightAt17TwoLines, 17, 2)
        case .ingredient:
            profile = (TemplateCalibration.ingredientHeightAt15FiveLines, 15, 5)
        }
        let lineSpacing = -2.0
        let referenceContent = (
            lineHeightAtOnePoint * profile.referenceSize * Double(profile.referenceLines)
                + Double(profile.referenceLines - 1) * lineSpacing
        ) * TemplateCalibration.titleScale
        let fixedPadding = profile.referenceHeight * 1920 - referenceContent
        let content = (
            lineHeightAtOnePoint * fontSize * Double(lineCount)
                + Double(lineCount - 1) * lineSpacing
        ) * TemplateCalibration.titleScale
        return (content + fixedPadding) / projectHeight
    }

    private func assertProfileHeights(kind: TitleKind, fontSize: Double) throws {
        let layouter = TypographyLayouter(metrics: TableFontMetrics(widthAtOnePoint: [:]))
        var layouts: [Int: TypographyLayout] = [:]
        for lineCount in [1, 2, 3, 5] {
            let text = Array(repeating: "line", count: lineCount).joined(separator: "\n")
            let layout = try layouter.layout(
                runs: [.init(text: text)],
                kind: kind,
                projectWidth: 1080,
                projectHeight: 1920,
                settings: noShrinkSettings
            )
            layouts[lineCount] = layout
            XCTAssertEqual(
                layout.backgroundScaleY,
                expectedHeight(kind: kind, fontSize: fontSize, lineCount: lineCount),
                accuracy: 1e-12,
                "\(kind) \(lineCount) lines"
            )
        }

        let oneLine = try XCTUnwrap(layouts[1]).backgroundScaleY
        let twoLines = try XCTUnwrap(layouts[2]).backgroundScaleY
        XCTAssertEqual(
            twoLines - oneLine,
            ((fontSize - 2) * TemplateCalibration.titleScale) / 1920,
            accuracy: 1e-12,
            "Fixed padding must not be added again for another line."
        )
    }

    private func assertInvalidMeasurement<T>(
        containing diagnostic: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard case .invalidTypographyMeasurement = error as? AlignerError else {
                return XCTFail("Expected invalidTypographyMeasurement, got \(error)", file: file, line: line)
            }
            XCTAssertTrue(
                error.localizedDescription.localizedCaseInsensitiveContains(diagnostic),
                "Expected diagnostic containing '\(diagnostic)', got '\(error.localizedDescription)'",
                file: file,
                line: line
            )
        }
    }
}

private final class CallCountingMetrics: FontMetricsMeasuring {
    private(set) var callCount = 0

    func width(of text: String, fontFamily: String, fontFace: TypographyFontFace, fontSize: Double) throws -> Double {
        callCount += 1
        return 1
    }

    func lineHeight(fontFamily: String, fontFace: TypographyFontFace, fontSize: Double) throws -> Double {
        callCount += 1
        return 1
    }
}

private struct TableFontMetrics: FontMetricsMeasuring {
    let widthAtOnePoint: [String: Double]
    var italicWidthAtOnePoint: [String: Double] = [:]
    var lineHeightAtOnePoint: Double = 1

    func width(
        of text: String,
        fontFamily: String,
        fontFace: TypographyFontFace,
        fontSize: Double
    ) throws -> Double {
        let unitWidth: Double
        if fontFace == .italic, let italicWidth = italicWidthAtOnePoint[text] {
            unitWidth = italicWidth
        } else if let regularWidth = widthAtOnePoint[text] {
            unitWidth = regularWidth
        } else {
            unitWidth = Double(text.count) * 0.25
        }
        return unitWidth * fontSize
    }

    func lineHeight(
        fontFamily: String,
        fontFace: TypographyFontFace,
        fontSize: Double
    ) throws -> Double {
        lineHeightAtOnePoint * fontSize
    }
}

private struct FixedFontMetrics: FontMetricsMeasuring {
    let widths: [String: Double]
    let fixedLineHeight: Double

    init(widths: [String: Double], lineHeight: Double) {
        self.widths = widths
        fixedLineHeight = lineHeight
    }

    func width(
        of text: String,
        fontFamily: String,
        fontFace: TypographyFontFace,
        fontSize: Double
    ) throws -> Double {
        widths[text] ?? 1
    }

    func lineHeight(
        fontFamily: String,
        fontFace: TypographyFontFace,
        fontSize: Double
    ) throws -> Double {
        fixedLineHeight
    }
}
