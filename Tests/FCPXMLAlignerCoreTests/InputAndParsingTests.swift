import Foundation
import XCTest
@testable import FCPXMLAlignerCore

final class InputAndParsingTests: XCTestCase {
    func testBundleResolvesInfoFCPXML() throws {
        let bundleURL = try fixtureURL("sample-current")

        let input = try InputDocument(sourceURL: bundleURL)

        XCTAssertEqual(input.kind, .bundle)
        XCTAssertEqual(input.xmlURL, bundleURL.appendingPathComponent("Info.fcpxml"))
    }

    func testFCPXMLFileResolvesAsFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let copyURL = directory.appendingPathComponent("Current.FCPXML")
        try FileManager.default.copyItem(
            at: try fixtureURL("sample-current").appendingPathComponent("Info.fcpxml"),
            to: copyURL
        )

        let input = try InputDocument(sourceURL: copyURL)

        XCTAssertEqual(input.kind, .file)
        XCTAssertEqual(input.xmlURL, copyURL)
    }

    func testUnsupportedExtensionIsRejected() throws {
        let url = URL(fileURLWithPath: "/tmp/subtitles.xml")

        XCTAssertThrowsError(try InputDocument(sourceURL: url)) { error in
            XCTAssertEqual(error as? AlignerError, .unsupportedInput("xml"))
        }
    }

    func testBundleWithoutInfoFCPXMLIsRejected() throws {
        let directory = try makeTemporaryDirectory().appendingPathExtension("fcpxmld")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(try InputDocument(sourceURL: directory)) { error in
            XCTAssertEqual(error as? AlignerError, .missingInfoXML)
        }
    }

    func testMalformedXMLIsReported() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("broken.fcpxml")
        try Data("<fcpxml>".utf8).write(to: fileURL)

        XCTAssertThrowsError(try FCPXMLDocument(inputDocument: InputDocument(sourceURL: fileURL))) { error in
            guard case .malformedXML = error as? AlignerError else {
                return XCTFail("Expected malformedXML, received \(error)")
            }
        }
    }

    func testDuplicateNonemptyFormatIDsAreReportedWithoutCrashingProcessing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("duplicate-format.fcpxml")
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fcpxml version="1.14">
          <resources>
            <format id="r1" width="1920" height="1080"/>
            <format id="r1" width="1080" height="1920"/>
            <effect id="r2" name="Basic Title" uid="Basic Title.moti"/>
          </resources>
          <library><event name="Event"><project name="Project"><sequence format="r1"><spine><title name="Title" ref="r2" offset="0s" start="0s" duration="1s"><text><text-style>Text</text-style></text></title></spine></sequence></project></event></library>
        </fcpxml>
        """
        try Data(xml.utf8).write(to: fileURL)
        let input = try InputDocument(sourceURL: fileURL)

        XCTAssertThrowsError(try FCPXMLDocument(inputDocument: input)) { error in
            XCTAssertEqual(error as? AlignerError, .malformedXML("Duplicate nonempty format id: r1."))
        }
        XCTAssertThrowsError(try OutputWriter().process(input: fileURL, settings: .templateDefaults)) { error in
            XCTAssertEqual(error as? AlignerError, .malformedXML("Duplicate nonempty format id: r1."))
        }
        XCTAssertNoThrow(try currentFixtureDocument())
    }

    func testCurrentFixtureParsesBasicTitlesAndVisibleText() throws {
        let document = try currentFixtureDocument()

        XCTAssertEqual(document.version, "1.14")
        XCTAssertEqual(document.titles.count, 17)
        XCTAssertEqual(document.titles[3].visibleText, "fold the edges")
        XCTAssertFalse(document.titles[3].visibleText.contains("\n                                "))

        let ingredients = try XCTUnwrap(document.titles.first { $0.visibleLines.count == 5 })
        XCTAssertEqual(ingredients.visibleLines.count, 5)
        XCTAssertEqual(ingredients.visibleLines.first, "flour 500g")
        XCTAssertEqual(ingredients.visibleLines.last, "warm water 300ml")
    }

    func testTemplateFixtureDiscoversBasicTitlesAndCustomResources() throws {
        let document = try templateFixtureDocument()

        XCTAssertEqual(document.titles.count, 17)
        XCTAssertFalse(document.customResourceIDs.isEmpty)
    }

    func testValidDocumentWithoutBasicTitleThrowsNoBasicTitles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("no-titles.fcpxml")
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fcpxml version="1.14"><resources><effect id="r1" name="Lower Third" uid="example.moti"/></resources><library/></fcpxml>
        """
        try Data(xml.utf8).write(to: fileURL)

        XCTAssertThrowsError(try FCPXMLDocument(inputDocument: InputDocument(sourceURL: fileURL))) { error in
            XCTAssertEqual(error as? AlignerError, .noBasicTitles)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
