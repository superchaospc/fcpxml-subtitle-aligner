import CryptoKit
import Foundation
import XCTest
import FCPXMLAlignerCLI

final class CLIApplicationTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CLIApplicationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testJSONProcessesCopiedBundleAndLeavesSourceUnchanged() throws {
        let input = try copyFixtureBundle()
        let sourceXML = input.appendingPathComponent("Info.fcpxml")
        let sourceSHA = try sha256(of: sourceXML)

        let result = CLIApplication().run(arguments: ["--json", input.path])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.hasSuffix("\n"))
        XCTAssertEqual(result.stdout.filter { $0 == "\n" }.count, 1)

        let payload = try JSONDecoder().decode(
            CLISuccessPayload.self,
            from: Data(result.stdout.utf8)
        )
        XCTAssertEqual(payload.changedTitles, 17)
        XCTAssertEqual(payload.skippedTitles, 0)
        XCTAssertTrue(payload.outputPath.hasPrefix("/"))
        XCTAssertTrue(payload.reportPath.hasPrefix("/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: payload.outputPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: payload.reportPath))
        XCTAssertEqual(try sha256(of: sourceXML), sourceSHA)

        let sortedEncoder = JSONEncoder()
        sortedEncoder.outputFormatting = [.sortedKeys]
        let expectedJSON = try XCTUnwrap(String(data: sortedEncoder.encode(payload), encoding: .utf8))
        XCTAssertEqual(result.stdout, expectedJSON + "\n")
    }

    func testHumanOutputProcessesSingleFCPXMLWithLabeledAbsolutePathsAndCounts() throws {
        let input = temporaryDirectory.appendingPathComponent("source.fcpxml")
        try FileManager.default.copyItem(at: fixtureBundle.appendingPathComponent("Info.fcpxml"), to: input)
        let sourceSHA = try sha256(of: input)

        let result = CLIApplication().run(arguments: [input.path])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("Output: \(temporaryDirectory.path)/source-aligned.fcpxml\n"))
        XCTAssertTrue(result.stdout.contains("Report: \(temporaryDirectory.path)/source-aligned-report.txt\n"))
        XCTAssertTrue(result.stdout.contains("Changed: 17\n"))
        XCTAssertTrue(result.stdout.contains("Skipped: 0\n"))
        XCTAssertEqual(try sha256(of: input), sourceSHA)
    }

    func testHelpDocumentsFlagsDefaultsAndNonOverwriteBehavior() {
        let result = CLIApplication().run(arguments: ["--help"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        for expected in [
            "--action-size", "--ingredient-size", "--minimum-size", "--safe-width",
            "--auto-shrink", "--no-auto-shrink", "--json", "--help", "-h", "--version",
            "17", "15", "13", "0.9", "does not overwrite",
        ] {
            XCTAssertTrue(result.stdout.contains(expected), "Missing help text: \(expected)")
        }
    }

    func testVersionWritesOnlyVersionToStandardOutput() {
        let result = CLIApplication().run(arguments: ["--version"])

        XCTAssertEqual(result, CLIExecutionResult(
            exitCode: 0,
            stdout: "fcpxml-aligner \(CLIApplication.version)\n",
            stderr: ""
        ))
    }

    func testUnsupportedExtensionIsInputError() throws {
        let input = temporaryDirectory.appendingPathComponent("source.xml")
        try Data("<fcpxml/>".utf8).write(to: input)

        let result = CLIApplication().run(arguments: [input.path])

        XCTAssertEqual(result.exitCode, 66)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.localizedCaseInsensitiveContains("unsupported"))
        XCTAssertTrue(result.stderr.contains(".fcpxml"))
    }

    func testMissingPathIsInputError() {
        let missing = temporaryDirectory.appendingPathComponent("missing.fcpxml")

        let result = CLIApplication().run(arguments: [missing.path])

        XCTAssertEqual(result.exitCode, 66)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.localizedCaseInsensitiveContains("does not exist"))
        XCTAssertTrue(result.stderr.contains(missing.path))
    }

    func testUnreadableFileIsInputError() throws {
        let input = temporaryDirectory.appendingPathComponent("unreadable.fcpxml")
        try Data("<fcpxml/>".utf8).write(to: input)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: input.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: input.path)
        }

        let result = CLIApplication().run(arguments: [input.path])

        XCTAssertEqual(result.exitCode, 66)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.localizedCaseInsensitiveContains("not a readable"))
    }

    func testMalformedXMLIsDataError() throws {
        let input = temporaryDirectory.appendingPathComponent("malformed.fcpxml")
        try Data("<fcpxml>".utf8).write(to: input)

        let result = CLIApplication().run(arguments: [input.path])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.localizedCaseInsensitiveContains("malformed"))
    }

    func testUnprocessableXMLIsDataError() throws {
        let input = temporaryDirectory.appendingPathComponent("no-titles.fcpxml")
        try Data("<fcpxml version=\"1.14\"><resources/><library/></fcpxml>".utf8).write(to: input)

        let result = CLIApplication().run(arguments: [input.path])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("No Basic Title"))
    }

    func testArgumentErrorUsesUsageStatusAndHelpHint() {
        let result = CLIApplication().run(arguments: ["--unknown"])

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("Unexpected argument: --unknown"))
        XCTAssertTrue(result.stderr.contains("Try 'fcpxml-aligner --help'"))
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var fixtureBundle: URL {
        packageRoot
            .appendingPathComponent("Tests/FCPXMLAlignerCoreTests/Fixtures/sample-current.fcpxmld")
    }

    private func copyFixtureBundle() throws -> URL {
        let destination = temporaryDirectory.appendingPathComponent("sample-current.fcpxmld")
        try FileManager.default.copyItem(at: fixtureBundle, to: destination)
        return destination
    }

    private func sha256(of url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
