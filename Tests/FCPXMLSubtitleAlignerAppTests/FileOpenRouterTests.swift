import XCTest
@testable import FCPXMLSubtitleAlignerApp

final class FileOpenRouterTests: XCTestCase {
    func testOneFCPXMLFileIsAccepted() {
        let url = URL(fileURLWithPath: "/tmp/recipe.fcpxml")

        XCTAssertEqual(FileOpenRouter.decision(for: [url]), .process(url))
    }

    func testMultipleFilesAreRejectedBeforeProcessing() {
        let urls = [
            URL(fileURLWithPath: "/tmp/recipe.fcpxml"),
            URL(fileURLWithPath: "/tmp/other.fcpxmld"),
        ]

        XCTAssertEqual(FileOpenRouter.decision(for: urls), .rejectMultipleFiles)
    }

    func testUnsupportedFileIsRejected() {
        XCTAssertEqual(
            FileOpenRouter.decision(for: [URL(fileURLWithPath: "/tmp/recipe.xml")]),
            .rejectUnsupportedFile
        )
    }
}
