import Foundation
import XCTest

final class HistoryPrivacyAuditTests: XCTestCase {
    func testAuditRejectsSensitiveDataRetainedOnlyInHistory() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let privatePath = ["/", "Us", "ers/", "example/private.mov"].joined()

        try Data(privatePath.utf8).write(to: repository.appending(path: "metadata.txt"))
        try commitAll(in: repository, message: "add metadata")
        try Data("synthetic".utf8).write(to: repository.appending(path: "metadata.txt"))
        try commitAll(in: repository, message: "sanitize current tree")

        let result = try runAudit(in: repository)
        XCTAssertEqual(result.status, 1, result.output)
        XCTAssertTrue(result.output.contains("private-token"), result.output)
    }

    func testAuditRejectsNonNoreplyCommitIdentity() throws {
        let repository = try makeRepository(authorEmail: "person@example.com")
        defer { try? FileManager.default.removeItem(at: repository) }

        try Data("synthetic".utf8).write(to: repository.appending(path: "README.md"))
        try commitAll(in: repository, message: "initial")

        let result = try runAudit(in: repository)
        XCTAssertEqual(result.status, 1, result.output)
        XCTAssertTrue(result.output.contains("non-noreply-author-email"), result.output)
    }

    func testAuditAcceptsCleanSingleRootHistory() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }

        try Data("synthetic public fixture".utf8).write(to: repository.appending(path: "README.md"))
        try commitAll(in: repository, message: "initial")

        let result = try runAudit(in: repository)
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("PASS"), result.output)
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeRepository(
        authorEmail: String = "superchaospc@users.noreply.github.com"
    ) throws -> URL {
        let repository = URL(fileURLWithPath: "/tmp")
            .appending(path: "fcpxml-history-audit-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: false)
        XCTAssertEqual(try run("/usr/bin/git", ["init", "-q"], in: repository).status, 0)
        XCTAssertEqual(try run("/usr/bin/git", ["config", "user.name", "Fixture Author"], in: repository).status, 0)
        XCTAssertEqual(try run("/usr/bin/git", ["config", "user.email", authorEmail], in: repository).status, 0)
        return repository
    }

    private func commitAll(in repository: URL, message: String) throws {
        let add = try run("/usr/bin/git", ["add", "."], in: repository)
        XCTAssertEqual(add.status, 0, add.output)
        let commit = try run("/usr/bin/git", ["commit", "-q", "-m", message], in: repository)
        XCTAssertEqual(commit.status, 0, commit.output)
    }

    private func runAudit(in repository: URL) throws -> ProcessResult {
        try run(
            "/usr/bin/python3",
            [packageRoot.appending(path: "scripts/audit_repository_history.py").path, "--require-noreply-authors"],
            in: repository
        )
    }

    private func run(_ executable: String, _ arguments: [String], in directory: URL) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        return ProcessResult(
            status: process.terminationStatus,
            output: String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }
}

private struct ProcessResult {
    let status: Int32
    let output: String
}
