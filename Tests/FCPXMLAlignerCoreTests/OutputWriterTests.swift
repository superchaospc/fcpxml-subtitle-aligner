import Foundation
import CryptoKit
import Darwin
import XCTest
@testable import FCPXMLAlignerCore

final class OutputWriterTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutputWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testBundleOutputIsIndependentValidatedAndReported() throws {
        let input = try copyFixtureBundle(named: "sample-current")
        let inputFingerprint = try recursiveFingerprint(of: input)

        let result = try OutputWriter().process(input: input, settings: .templateDefaults)

        XCTAssertEqual(result.outputURL.lastPathComponent, "sample-current-aligned.fcpxmld")
        XCTAssertEqual(result.reportURL.lastPathComponent, "sample-current-aligned-report.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.appendingPathComponent("Info.fcpxml").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.reportURL.path))
        XCTAssertEqual(try recursiveFingerprint(of: input), inputFingerprint)

        let original = try FCPXMLDocument(inputDocument: InputDocument(sourceURL: input))
        let output = try FCPXMLDocument(inputDocument: InputDocument(sourceURL: result.outputURL))
        XCTAssertEqual(output.version, "1.14")
        XCTAssertTrue(output.projectNames.allSatisfy { $0.hasSuffix("-aligned") })
        let originalUIDs = try projectUIDs(in: original)
        let outputUIDs = try projectUIDs(in: output)
        XCTAssertEqual(outputUIDs.count, originalUIDs.count)
        XCTAssertTrue(outputUIDs.allSatisfy { UUID(uuidString: $0) != nil })
        XCTAssertTrue(zip(originalUIDs, outputUIDs).allSatisfy { $0 != $1 })
        XCTAssertEqual(output.titles.map(\.visibleText), original.titles.map { $0.visibleText.uppercased() })
        XCTAssertEqual(result.report.titles.map(\.titleText), original.titles.map { $0.visibleText.uppercased() })
        XCTAssertEqual(result.report.recognizedTitles, 17)
        XCTAssertEqual(result.report.matchedBackgrounds, 17)
        XCTAssertEqual(result.report.changedTitles, 17)
        XCTAssertEqual(result.report.skippedTitles, 0)
    }

    func testExistingOutputReservesNextNumberWithoutOverwrite() throws {
        let input = try copyFixtureBundle(named: "sample-current")
        let existingOutput = temporaryDirectory.appendingPathComponent("sample-current-aligned.fcpxmld")
        try FileManager.default.createDirectory(at: existingOutput, withIntermediateDirectories: false)

        let result = try OutputWriter().process(input: input, settings: .templateDefaults)

        XCTAssertEqual(result.outputURL.lastPathComponent, "sample-current-aligned-2.fcpxmld")
        XCTAssertEqual(result.reportURL.lastPathComponent, "sample-current-aligned-2-report.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingOutput.path))
    }

    func testExistingReportReservesNextNumberWithoutOverwrite() throws {
        let input = try copyFixtureBundle(named: "sample-current")
        let existingReport = temporaryDirectory.appendingPathComponent("sample-current-aligned-report.txt")
        try Data("keep".utf8).write(to: existingReport)

        let result = try OutputWriter().process(input: input, settings: .templateDefaults)

        XCTAssertEqual(result.outputURL.lastPathComponent, "sample-current-aligned-2.fcpxmld")
        XCTAssertEqual(result.reportURL.lastPathComponent, "sample-current-aligned-2-report.txt")
        XCTAssertEqual(try String(contentsOf: existingReport), "keep")
    }

    func testSingleFCPXMLIsCopiedAndRetainsVersionAndDoctype() throws {
        let bundle = try fixtureURL("sample-current")
        let input = temporaryDirectory.appendingPathComponent("source.fcpxml")
        try FileManager.default.copyItem(at: bundle.appendingPathComponent("Info.fcpxml"), to: input)

        let result = try OutputWriter().process(input: input, settings: .templateDefaults)

        XCTAssertEqual(result.outputURL.lastPathComponent, "source-aligned.fcpxml")
        XCTAssertEqual(result.reportURL.lastPathComponent, "source-aligned-report.txt")
        let xml = try String(contentsOf: result.outputURL, encoding: .utf8)
        XCTAssertTrue(xml.contains("<!DOCTYPE fcpxml>"))
        XCTAssertTrue(xml.contains("<fcpxml version=\"1.14\""))
        XCTAssertEqual(try FCPXMLDocument(inputDocument: InputDocument(sourceURL: result.outputURL)).version, "1.14")
    }

    func testFailuresLeaveNoFinalOrTemporaryArtifactsAndInputUntouched() throws {
        let validInput = try copyFixtureBundle(named: "sample-current")
        let fingerprint = try recursiveFingerprint(of: validInput)
        let invalid = AlignmentSettings(actionBaseSize: 0, ingredientBaseSize: 16, minimumSize: 13, autoShrink: true, safeWidthFraction: 0.72)
        XCTAssertThrowsError(try OutputWriter().process(input: validInput, settings: invalid))
        XCTAssertEqual(try recursiveFingerprint(of: validInput), fingerprint)
        XCTAssertEqual(try visibleSiblingNames(), [validInput.lastPathComponent])

        let missingInfo = temporaryDirectory.appendingPathComponent("missing.fcpxmld")
        try FileManager.default.createDirectory(at: missingInfo, withIntermediateDirectories: false)
        XCTAssertThrowsError(try OutputWriter().process(input: missingInfo, settings: .templateDefaults))
        let malformed = temporaryDirectory.appendingPathComponent("malformed.fcpxml")
        try Data("<fcpxml>".utf8).write(to: malformed)
        let malformedBytes = try Data(contentsOf: malformed)
        XCTAssertThrowsError(try OutputWriter().process(input: malformed, settings: .templateDefaults))
        XCTAssertEqual(try Data(contentsOf: malformed), malformedBytes)

        let serializationFailure = OutputWriter(hooks: OutputWriterHooks(
            serialize: { _ in throw OutputWriterTestError.forced },
            beforeFinalization: {}
        ))
        XCTAssertThrowsError(try serializationFailure.process(input: validInput, settings: .templateDefaults))
        XCTAssertEqual(try visibleSiblingNames(), [malformed.lastPathComponent, missingInfo.lastPathComponent, validInput.lastPathComponent].sorted())

        let finalizationFailure = OutputWriter(hooks: OutputWriterHooks(
            serialize: nil,
            beforeFinalization: { throw OutputWriterTestError.forced }
        ))
        XCTAssertThrowsError(try finalizationFailure.process(input: validInput, settings: .templateDefaults))
        XCTAssertEqual(try visibleSiblingNames(), [malformed.lastPathComponent, missingInfo.lastPathComponent, validInput.lastPathComponent].sorted())
    }

    func testReportContainsStableCountsPathsAndInvariantStatements() throws {
        let input = try copyFixtureBundle(named: "sample-current")
        let result = try OutputWriter().process(input: input, settings: .templateDefaults)
        let text = try String(contentsOf: result.reportURL, encoding: .utf8)

        for required in [
            "Input: \(input.path)", "Output: \(result.outputURL.path)", "Report: \(result.reportURL.path)", "FCPXML version: 1.14",
            "Recognized: 17", "Matched backgrounds: 17", "Changed: 17", "Skipped: 0",
            "Structural validation: PASS", "Media references invariant: PASS", "Timing invariant: PASS",
            "Text/color invariant: PASS", "Nonstyle invariant: PASS", "Title 1:", "kind=",
            "fontSize=", "titleTransform=", "backgroundTransform=", "skipReason="
        ] {
            XCTAssertTrue(text.contains(required), "Missing report text: \(required)")
        }
    }

    func testIndependentRunsProduceSameTransformedXMLExceptProjectIdentity() throws {
        let firstInput = try copyFixtureBundle(named: "sample-current", as: "first.fcpxmld")
        let secondInput = try copyFixtureBundle(named: "sample-current", as: "second.fcpxmld")
        let first = try OutputWriter().process(input: firstInput, settings: .templateDefaults)
        let second = try OutputWriter().process(input: secondInput, settings: .templateDefaults)

        XCTAssertEqual(
            try normalizedOutputXML(at: first.outputURL.appendingPathComponent("Info.fcpxml")),
            try normalizedOutputXML(at: second.outputURL.appendingPathComponent("Info.fcpxml"))
        )
    }

    func testStagingCollisionNeverDeletesPathThisProcessDidNotCreate() throws {
        let input = try copyFixtureBundle(named: "sample-current")
        let collisionID = "00000000-0000-0000-0000-000000000001"
        let workspaceID = "00000000-0000-0000-0000-000000000002"
        let collision = temporaryDirectory.appendingPathComponent(".fcpxml-aligner-stage-\(collisionID)")
        let sentinel = Data("preserve me".utf8)
        try sentinel.write(to: collision)
        let writer = OutputWriter(hooks: OutputWriterHooks(makeUUID: sequenceUUIDs([
            collisionID, workspaceID, "00000000-0000-0000-0000-000000000003"
        ])))

        _ = try writer.process(input: input, settings: .templateDefaults)

        XCTAssertEqual(try Data(contentsOf: collision), sentinel)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent(".fcpxml-aligner-stage-\(workspaceID)").path))
    }

    func testDeferredWorkspaceCleanupDoesNotDeleteAReplacement() throws {
        let input = try copyFixtureBundle(named: "sample-current")
        let workspaceID = "00000000-0000-0000-0000-000000000010"
        let workspace = temporaryDirectory.appendingPathComponent(".fcpxml-aligner-stage-\(workspaceID)")
        let sentinel = Data("replacement".utf8)
        let writer = OutputWriter(hooks: OutputWriterHooks(
            makeUUID: sequenceUUIDs([workspaceID]),
            serialize: { _ in throw OutputWriterTestError.forced },
            beforeWorkspaceCleanup: {
                try FileManager.default.removeItem(at: workspace)
                try sentinel.write(to: workspace)
            }
        ))

        XCTAssertThrowsError(try writer.process(input: input, settings: .templateDefaults))

        XCTAssertEqual(try Data(contentsOf: workspace), sentinel)
    }

    func testLateFinalNameCollisionIsRecomputedWhileFinalizationLockIsHeld() throws {
        let input = try copyFixtureBundle(named: "sample-current")
        let collidingOutput = temporaryDirectory.appendingPathComponent("sample-current-aligned.fcpxmld")
        let writer = OutputWriter(hooks: OutputWriterHooks(
            beforeFinalizationLock: { try FileManager.default.createDirectory(at: collidingOutput, withIntermediateDirectories: false) }
        ))

        let result = try writer.process(input: input, settings: .templateDefaults)

        XCTAssertEqual(result.outputURL.lastPathComponent, "sample-current-aligned-2.fcpxmld")
        XCTAssertEqual(result.reportURL.lastPathComponent, "sample-current-aligned-2-report.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: collidingOutput.path))
    }

    func testFailureAfterFirstFinalMoveRollsBackOnlyOwnedOutputAndDeliversNothing() throws {
        let input = try copyFixtureBundle(named: "sample-current")
        let writer = OutputWriter(hooks: OutputWriterHooks(afterFirstFinalMove: { throw OutputWriterTestError.forced }))

        XCTAssertThrowsError(try writer.process(input: input, settings: .templateDefaults))

        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("sample-current-aligned.fcpxmld").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("sample-current-aligned-report.txt").path))
        XCTAssertEqual(try visibleSiblingNames(), [input.lastPathComponent])
    }

    func testCurrentFixtureInfoFCPXMLMatchesPinnedSHA256() throws {
        let info = try fixtureURL("sample-current").appendingPathComponent("Info.fcpxml")
        XCTAssertEqual(try hexSHA256(of: info), "158579222b8bc57cb3db4c1f731726ae165844326f259beafba2cb3dace5ab9e")
    }

    func testStaleUnlockedAdvisoryLockFileDoesNotBlockProcessing() throws {
        let input = try copyFixtureBundle(named: "sample-current")
        let lock = temporaryDirectory.appendingPathComponent(".fcpxml-aligner-finalize.lock")
        try Data("stale".utf8).write(to: lock)

        let result = try OutputWriter().process(input: input, settings: .templateDefaults)

        XCTAssertEqual(result.outputURL.lastPathComponent, "sample-current-aligned.fcpxmld")
        XCTAssertTrue(FileManager.default.fileExists(atPath: lock.path))
    }

    func testActiveAdvisoryLockRejectsThenAllowsProcessingAfterRelease() throws {
        let input = try copyFixtureBundle(named: "sample-current")
        let lock = temporaryDirectory.appendingPathComponent(".fcpxml-aligner-finalize.lock")
        let descriptor = open(lock.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)

        XCTAssertThrowsError(try OutputWriter().process(input: input, settings: .templateDefaults)) { error in
            guard case .finalizationLockUnavailable = error as? OutputWriterError else {
                return XCTFail("Expected finalizationLockUnavailable, got \(error)")
            }
        }
        XCTAssertEqual(flock(descriptor, LOCK_UN), 0)
        XCTAssertEqual(close(descriptor), 0)

        let result = try OutputWriter().process(input: input, settings: .templateDefaults)
        XCTAssertEqual(result.outputURL.lastPathComponent, "sample-current-aligned.fcpxmld")
    }

    func testBundleIntegrityHashesOnlyInfoXMLAndDetectsInventoryAndXMLChanges() throws {
        let input = try copyFixtureBundle(named: "sample-current")
        let embedded = input.appendingPathComponent("embedded-media.bin")
        try Data(repeating: 0xA5, count: 128 * 1024).write(to: embedded)
        var hashedPaths: [String] = []
        let inventoryChangingWriter = OutputWriter(hooks: OutputWriterHooks(
            observeHashedFile: { hashedPaths.append($0.lastPathComponent) },
            beforeFinalization: { try Data("new media inventory".utf8).write(to: embedded) }
        ))

        XCTAssertThrowsError(try inventoryChangingWriter.process(input: input, settings: .templateDefaults)) { error in
            guard case .sourceChanged = error as? OutputWriterError else {
                return XCTFail("Expected sourceChanged, got \(error)")
            }
        }
        XCTAssertTrue(hashedPaths.contains("Info.fcpxml"))
        XCTAssertFalse(hashedPaths.contains("embedded-media.bin"))

        let xmlInput = try copyFixtureBundle(named: "sample-current", as: "xml-change.fcpxmld")
        let info = xmlInput.appendingPathComponent("Info.fcpxml")
        let xmlChangingWriter = OutputWriter(hooks: OutputWriterHooks(
            beforeFinalization: {
                let contents = try String(contentsOf: info, encoding: .utf8)
                try (contents + " ").write(to: info, atomically: true, encoding: .utf8)
            }
        ))
        XCTAssertThrowsError(try xmlChangingWriter.process(input: xmlInput, settings: .templateDefaults)) { error in
            guard case .sourceChanged = error as? OutputWriterError else {
                return XCTFail("Expected sourceChanged, got \(error)")
            }
        }
    }

    func testPlainTextReportEscapesTabsAndC0Controls() {
        let report = ChangeReport(titles: [TitleChangeRecord(
            titleName: "name\t\u{0001}", titleText: "text\u{0002}", kind: .action,
            originalFontSize: nil, finalFontSize: nil,
            originalTitleTransform: nil, finalTitleTransform: nil,
            originalBackgroundTransform: nil, finalBackgroundTransform: nil,
            autoShrunk: false, fitsSafeWidth: true, backgroundMatched: false,
            skipReason: "why\r\n\t", changed: false
        )])
        let text = report.plainText(
            inputURL: URL(fileURLWithPath: "/input"), outputURL: URL(fileURLWithPath: "/output"),
            reportURL: URL(fileURLWithPath: "/report"), version: "1.14",
            sourceProjectNames: [], outputProjectNames: []
        )

        XCTAssertTrue(text.contains("\\t"))
        XCTAssertTrue(text.contains("\\u{0001}"))
        XCTAssertTrue(text.contains("\\u{0002}"))
        XCTAssertFalse(text.contains("\u{0001}"))
    }

    private func copyFixtureBundle(named name: String, as outputName: String? = nil) throws -> URL {
        let destination = temporaryDirectory.appendingPathComponent(outputName ?? "\(name).fcpxmld")
        try FileManager.default.copyItem(at: try fixtureURL(name), to: destination)
        return destination
    }

    private func projectUIDs(in document: FCPXMLDocument) throws -> [String] {
        try document.xmlDocument.nodes(forXPath: "//project/@uid").compactMap(\.stringValue)
    }

    private func recursiveFingerprint(of url: URL) throws -> [FileFingerprint] {
        let manager = FileManager.default
        if (try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
            return [FileFingerprint(path: url.lastPathComponent, data: try Data(contentsOf: url))]
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        let urls = try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: []).flatMap { child -> [URL] in
            if (try? child.resourceValues(forKeys: keys).isRegularFile) == true { return [child] }
            return try manager.subpathsOfDirectory(atPath: child.path).map { child.appendingPathComponent($0) }
                .filter { (try? $0.resourceValues(forKeys: keys).isRegularFile) == true }
        }.sorted { $0.path < $1.path }
        return try urls.map {
            FileFingerprint(path: $0.path.replacingOccurrences(of: url.path + "/", with: ""), data: try Data(contentsOf: $0))
        }
    }

    private func visibleSiblingNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)
            .filter { !$0.hasPrefix(".fcpxml-aligner-") }
            .sorted()
    }

    private func normalizedOutputXML(at url: URL) throws -> String {
        var xml = try String(contentsOf: url, encoding: .utf8)
        xml = xml.replacingOccurrences(of: " name=\"first-aligned\"", with: "")
        xml = xml.replacingOccurrences(of: " name=\"second-aligned\"", with: "")
        let pattern = " uid=\\\"[0-9A-Fa-f-]{36}\\\""
        return xml.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private func hexSHA256(of url: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: url))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private enum OutputWriterTestError: Error { case forced }

private struct FileFingerprint: Equatable {
    let path: String
    let data: Data
}

private func sequenceUUIDs(_ values: [String]) -> () -> UUID {
    var iterator = values.makeIterator()
    return {
        UUID(uuidString: iterator.next() ?? "00000000-0000-0000-0000-000000000099")!
    }
}
