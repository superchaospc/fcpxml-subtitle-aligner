import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import XCTest
@testable import FCPXMLAlignerCore

final class MatchingAndInvariantTests: XCTestCase {
    func testRationalTimeParsesIntegerAndRationalSeconds() throws {
        XCTAssertEqual(try XCTUnwrap(RationalTime(parsing: "1s")), try XCTUnwrap(RationalTime(numerator: 1, denominator: 1)))
        XCTAssertEqual(try XCTUnwrap(RationalTime(parsing: "3724s")), try XCTUnwrap(RationalTime(numerator: 3724, denominator: 1)))
        XCTAssertEqual(try XCTUnwrap(RationalTime(parsing: "167300/3000s")), try XCTUnwrap(RationalTime(numerator: 1673, denominator: 30)))
    }

    func testRationalTimeRejectsMalformedAndZeroDenominatorValues() {
        for value in ["", "1", "1/0s", "1/2", "abc", "1//2s", "1.5s", " 1s"] {
            XCTAssertNil(RationalTime(parsing: value), "Expected invalid time: \(value)")
        }
    }

    func testRationalTimeOrdersLargeAdjacentValuesWithoutDoublePrecisionLoss() throws {
        let earlier = try XCTUnwrap(RationalTime(parsing: "9007199254740992s"))
        let later = try XCTUnwrap(RationalTime(parsing: "9007199254740993s"))
        let minimumInt64 = try XCTUnwrap(RationalTime(parsing: "-9223372036854775808s"))
        let largeRational = try XCTUnwrap(RationalTime(parsing: "99999999999999999999999999999999999999/3s"))

        XCTAssertLessThan(earlier, later)
        XCTAssertLessThan(minimumInt64, earlier)
        XCTAssertLessThan(later, largeRational)
    }

    func testMatcherSafelySkipsUnrepresentableTimingValues() throws {
        let huge = String(repeating: "9", count: 100) + "s"
        let document = try syntheticDocument(titleOffset: huge, titleDuration: "1s", backgrounds: [("custom", huge, "1s")])

        let match = try XCTUnwrap(TitleBackgroundMatcher.matches(in: document).only)

        XCTAssertNil(match.background)
        XCTAssertEqual(match.skipReason, "missing background")
    }

    func testCurrentFixtureMatchesEveryBasicTitleToOneCustomBackground() throws {
        let document = try currentFixtureDocument()
        let matches = TitleBackgroundMatcher.matches(in: document)

        XCTAssertEqual(matches.count, 17)
        XCTAssertEqual(matches.compactMap(\.background).count, 17)
        XCTAssertTrue(matches.allSatisfy { $0.skipReason == nil })
        XCTAssertEqual(Set(matches.compactMap { $0.background?.xmlString }).count, 17)
    }

    func testMatcherLeavesInMemoryFixtureXMLUnchanged() throws {
        let fixture = try currentFixtureDocument()
        let document = try FCPXMLDocument(xmlString: fixture.rootXML)
        let before = document.rootXML

        _ = TitleBackgroundMatcher.matches(in: document)

        XCTAssertEqual(document.rootXML, before)
    }

    func testMatcherUsesAUniqueOverlappingCustomBackgroundWhenExactTimingIsUnavailable() throws {
        let document = try syntheticDocument(titleOffset: "3s", titleDuration: "2s", backgrounds: [("custom", "0s", "10s")])

        let match = try XCTUnwrap(TitleBackgroundMatcher.matches(in: document).only)

        XCTAssertEqual(match.background?.attribute(forName: "ref")?.stringValue, "custom")
        XCTAssertNil(match.skipReason)
    }

    func testMatcherMarksMissingBackgroundWhenOnlyABaseVideoOverlaps() throws {
        let document = try syntheticDocument(titleOffset: "0s", titleDuration: "1s", backgrounds: [], baseVideoRef: "asset")

        let match = try XCTUnwrap(TitleBackgroundMatcher.matches(in: document).only)

        XCTAssertNil(match.background)
        XCTAssertEqual(match.skipReason, "missing background")
    }

    func testMatcherMarksEquallyValidCustomBackgroundsAsAmbiguous() throws {
        let document = try syntheticDocument(
            titleOffset: "0s",
            titleDuration: "1s",
            backgrounds: [("custom", "0s", "1s"), ("custom", "0s", "1s")]
        )

        let match = try XCTUnwrap(TitleBackgroundMatcher.matches(in: document).only)

        XCTAssertNil(match.background)
        XCTAssertEqual(match.skipReason, "ambiguous backgrounds")
    }

    func testSnapshotIgnoresAllowedStyleAndProjectMutations() throws {
        let original = try currentFixtureDocument()
        let mutated = try copiedDocument(from: original)

        try setAttribute(in: mutated, at: "//title/text-style-def/text-style/@font", to: "Helvetica")
        try setAttribute(in: mutated, at: "//title/text-style-def/text-style/@fontSize", to: "99")
        try setAttribute(in: mutated, at: "//title/text-style-def/text-style/@fontFace", to: "Bold")
        try setAttribute(in: mutated, at: "//title/text-style-def/text-style/@alignment", to: "left")
        try setAttribute(in: mutated, at: "//title/text-style-def/text-style/@lineSpacing", to: "42")
        try setAttribute(in: mutated, at: "//title/param[@name='Alignment']/@value", to: "0 (Left)")
        try setAttribute(in: mutated, at: "//title/param[@name='Line Spacing']/@value", to: "42")
        try setAttribute(in: mutated, at: "//title/adjust-transform/@position", to: "0 0")
        try setAttribute(in: mutated, at: "//video[@ref='r3']/adjust-transform/@position", to: "0 0")
        try setAttribute(in: mutated, at: "//project/@name", to: "renamed")
        try setAttribute(in: mutated, at: "//project/@uid", to: "different")

        XCTAssertEqual(InvariantSnapshot(document: original), InvariantSnapshot(document: mutated))
    }

    func testSnapshotTracksStyleChangesOnAnUnrecognizedTitle() throws {
        let fixture = try currentFixtureDocument()
        let marker = "<title ref=\"r4\""
        var xml = fixture.rootXML
        let range = try XCTUnwrap(xml.range(of: marker))
        xml.replaceSubrange(range, with: "<title ref=\"unrecognized\"")
        let original = try FCPXMLDocument(xmlString: xml)
        let mutated = try copiedDocument(from: original)
        try setAttribute(in: mutated, at: "//title[@ref='unrecognized']/text-style-def/text-style/@font", to: "Helvetica")

        XCTAssertNotEqual(InvariantSnapshot(document: original).nonStyleStructure, InvariantSnapshot(document: mutated).nonStyleStructure)
    }

    func testSnapshotIgnoresBoldOnlyForHeroTitle() throws {
        let original = try currentFixtureDocument()
        let heroMutated = try copiedDocument(from: original)
        let ordinaryMutated = try copiedDocument(from: original)

        let hero = try XCTUnwrap(heroMutated.titles.first {
            LayoutVariantSelector.select(visibleText: $0.visibleText) == .heroAction
        })
        let ordinary = try XCTUnwrap(ordinaryMutated.titles.first {
            LayoutVariantSelector.select(visibleText: $0.visibleText) == .ordinary
        })
        try setOrAddAttribute("bold", inReferencedStyleOf: hero, to: "0")
        try setOrAddAttribute("bold", inReferencedStyleOf: ordinary, to: "1")

        XCTAssertEqual(InvariantSnapshot(document: original), InvariantSnapshot(document: heroMutated))
        XCTAssertNotEqual(InvariantSnapshot(document: original), InvariantSnapshot(document: ordinaryMutated))
    }

    func testSnapshotTracksTransformsOutsideMatchedCustomBackgrounds() throws {
        let unmatchedBase = try syntheticDocument(
            titleOffset: "0s",
            titleDuration: "1s",
            backgrounds: [("custom", "5s", "1s")]
        )
        let unmatchedXML = unmatchedBase.rootXML.replacingOccurrences(
            of: "<video ref=\"custom\" offset=\"5s\" duration=\"1s\"/>",
            with: "<video ref=\"custom\" offset=\"5s\" duration=\"1s\"><adjust-transform position=\"1 1\"/></video>"
        )
        let unmatchedOriginal = try FCPXMLDocument(xmlString: unmatchedXML)
        let unmatchedMutated = try copiedDocument(from: unmatchedOriginal)
        try setAttribute(in: unmatchedMutated, at: "//video[@ref='custom']/adjust-transform/@position", to: "2 2")
        XCTAssertNotEqual(
            InvariantSnapshot(document: unmatchedOriginal).nonStyleStructure,
            InvariantSnapshot(document: unmatchedMutated).nonStyleStructure
        )

        let generatorBase = try syntheticDocument(titleOffset: "0s", titleDuration: "1s", backgrounds: [])
        let generatorXML = generatorBase.rootXML.replacingOccurrences(
            of: "</clip>",
            with: "<generator ref=\"asset\" offset=\"2s\" duration=\"1s\"><adjust-transform position=\"1 1\"/></generator></clip>"
        )
        let generatorOriginal = try FCPXMLDocument(xmlString: generatorXML)
        let generatorMutated = try copiedDocument(from: generatorOriginal)
        try setAttribute(in: generatorMutated, at: "//generator/adjust-transform/@position", to: "2 2")
        XCTAssertNotEqual(
            InvariantSnapshot(document: generatorOriginal).nonStyleStructure,
            InvariantSnapshot(document: generatorMutated).nonStyleStructure
        )
    }

    func testSnapshotTracksTitleTextColorAndTimingSeparately() throws {
        let original = try currentFixtureDocument()

        let changedText = try copiedDocument(from: original)
        try setText(in: changedText, at: "//title[1]/text/text-style", to: "Different subtitle")
        XCTAssertNotEqual(InvariantSnapshot(document: original).visibleTextAndColors, InvariantSnapshot(document: changedText).visibleTextAndColors)

        let changedColor = try copiedDocument(from: original)
        try setAttribute(in: changedColor, at: "//title[1]/text-style-def/text-style/@fontColor", to: "0 0 0 1")
        XCTAssertNotEqual(InvariantSnapshot(document: original).visibleTextAndColors, InvariantSnapshot(document: changedColor).visibleTextAndColors)

        let changedTiming = try copiedDocument(from: original)
        try setAttribute(in: changedTiming, at: "//title[1]/@duration", to: "1s")
        XCTAssertNotEqual(InvariantSnapshot(document: original).timing, InvariantSnapshot(document: changedTiming).timing)
    }

    func testSnapshotTracksMediaReferencesAndUnrelatedEffectsAndTransitions() throws {
        let original = try currentFixtureDocument()

        let changedMedia = try copiedDocument(from: original)
        try setAttribute(in: changedMedia, at: "//resources/asset/media-rep/@src", to: "file:///different.mov")
        XCTAssertNotEqual(InvariantSnapshot(document: original).mediaReferences, InvariantSnapshot(document: changedMedia).mediaReferences)

        let changedEffect = try copiedDocument(from: original)
        try setAttribute(in: changedEffect, at: "//resources/effect[@id='r26']/@name", to: "Different effect")
        XCTAssertNotEqual(InvariantSnapshot(document: original).nonStyleStructure, InvariantSnapshot(document: changedEffect).nonStyleStructure)

        let transitionDocument = try syntheticDocument(
            titleOffset: "0s",
            titleDuration: "1s",
            backgrounds: [("custom", "0s", "1s")],
            transitionName: "Cross Dissolve"
        )
        let changedTransition = try copiedDocument(from: transitionDocument)
        try setAttribute(in: changedTransition, at: "//transition/@name", to: "Flow")
        XCTAssertNotEqual(InvariantSnapshot(document: transitionDocument).nonStyleStructure, InvariantSnapshot(document: changedTransition).nonStyleStructure)
    }

    private func syntheticDocument(
        titleOffset: String,
        titleDuration: String,
        backgrounds: [(String, String, String)],
        baseVideoRef: String = "asset",
        transitionName: String? = nil
    ) throws -> FCPXMLDocument {
        let backgroundXML = backgrounds.map { background in
            "<video ref=\"\(background.0)\" offset=\"\(background.1)\" duration=\"\(background.2)\"/>"
        }.joined()
        let transitionXML = transitionName.map { "<transition name=\"\($0)\" offset=\"0s\" duration=\"1s\"/>" } ?? ""
        let xml = """
        <fcpxml version="1.14">
          <resources>
            <effect id="basic" name="Basic Title" uid="Basic Title.moti"/>
            <effect id="custom" name="Custom" uid="Generators.localized/Solids.localized/Custom.motn"/>
            <asset id="asset" name="Source"><media-rep src="file:///source.mov"/></asset>
          </resources>
          <library><event><project name="Project" uid="project-uid"><sequence><spine><clip offset="0s" duration="10s">
            <video ref="\(baseVideoRef)" offset="0s" duration="10s"/>
            \(backgroundXML)
            <title ref="basic" offset="\(titleOffset)" duration="\(titleDuration)"><text><text-style ref="style">Hello</text-style></text><text-style-def id="style"><text-style font="Avenir" fontColor="1 1 1 1"/></text-style-def></title>
            \(transitionXML)
          </clip></spine></sequence></project></event></library>
        </fcpxml>
        """
        return try FCPXMLDocument(xmlString: xml)
    }

    private func copiedDocument(from document: FCPXMLDocument) throws -> FCPXMLDocument {
        try FCPXMLDocument(xmlString: document.rootXML)
    }

    private func setAttribute(in document: FCPXMLDocument, at xpath: String, to value: String) throws {
        let node = try XCTUnwrap(try document.xmlDocument.nodes(forXPath: xpath).first)
        node.stringValue = value
    }

    private func setText(in document: FCPXMLDocument, at xpath: String, to value: String) throws {
        let element = try XCTUnwrap(try document.xmlDocument.nodes(forXPath: xpath).first as? XMLElement)
        element.stringValue = value
    }

    private func setOrAddAttribute(_ name: String, inReferencedStyleOf title: TitleRecord, to value: String) throws {
        let reference = try XCTUnwrap(title.visibleTextRuns.first?.ref)
        let style = try XCTUnwrap(
            try title.element.nodes(forXPath: "./text-style-def[@id='\(reference)']/text-style").first as? XMLElement
        )
        if let attribute = style.attribute(forName: name) {
            attribute.stringValue = value
        } else {
            let attribute = try XCTUnwrap(XMLNode.attribute(withName: name, stringValue: value) as? XMLNode)
            style.addAttribute(attribute)
        }
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
