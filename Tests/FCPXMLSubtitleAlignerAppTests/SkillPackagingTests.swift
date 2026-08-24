import CryptoKit
import Foundation
import XCTest

final class SkillPackagingTests: XCTestCase {
    func testSkillInstallerCreatesThreeCanonicalLinksAndIsIdempotent() throws {
        let fixture = try makeInstallerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sourceSnapshot = try Data(contentsOf: fixture.skill)

        let first = try runInstaller(home: fixture.home, source: fixture.source)
        XCTAssertEqual(first.status, 0, first.output)
        assertInstalledLinks(home: fixture.home, source: fixture.source)

        let second = try runInstaller(home: fixture.home, source: fixture.source)
        XCTAssertEqual(second.status, 0, second.output)
        assertInstalledLinks(home: fixture.home, source: fixture.source)
        XCTAssertEqual(try Data(contentsOf: fixture.skill), sourceSnapshot)
    }

    func testSkillInstallerDefaultsToRepositorySkillSource() throws {
        let root = URL(fileURLWithPath: "/tmp/fcpxml-subtitle-aligner-skill-default-\(UUID().uuidString)")
        let home = root.appending(path: "home")
        let source = packageRoot.appending(path: "skills/fcpxml-subtitle-aligner")
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try runInstaller(arguments: ["--home", home.path])
        XCTAssertEqual(result.status, 0, result.output)
        assertInstalledLinks(home: home, source: source)
    }

    func testSkillInstallerUsesExplicitHomeWhenHOMEIsAbsent() throws {
        let fixture = try makeInstallerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "HOME")

        let result = try runInstaller(
            arguments: ["--home", fixture.home.path, "--source", fixture.source.path],
            environment: environment
        )
        XCTAssertEqual(result.status, 0, result.output)
        assertInstalledLinks(home: fixture.home, source: fixture.source)
    }

    func testSkillInstallerRejectsHomeParentTraversalWithoutTouchingSource() throws {
        let fixture = try makeInstallerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sourceSnapshot = try Data(contentsOf: fixture.skill)
        let traversalHome = fixture.root.appending(path: "missing/../source")

        let result = try runInstaller(home: traversalHome, source: fixture.source)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertEqual(try Data(contentsOf: fixture.skill), sourceSnapshot)
        for relativePath in [".codex", ".agents", ".claude"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.appending(path: relativePath).path))
        }
    }

    func testSkillInstallerRejectsHomeCurrentDirectoryTraversalWithoutTouchingSource() throws {
        let fixture = try makeInstallerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sourceSnapshot = try Data(contentsOf: fixture.skill)
        let traversalHome = fixture.root.appending(path: "missing/./source")

        let result = try runInstaller(home: traversalHome, source: fixture.source)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertEqual(try Data(contentsOf: fixture.skill), sourceSnapshot)
        for relativePath in [".codex", ".agents", ".claude"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.appending(path: relativePath).path))
        }
    }

    func testSkillInstallerRejectsExplicitEmptyHomeWithoutUsingRealHOME() throws {
        let fixture = try makeInstallerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let realHome = fixture.root.appending(path: "real-home")
        try FileManager.default.createDirectory(at: realHome, withIntermediateDirectories: true)
        let sentinel = realHome.appending(path: "sentinel")
        try Data("real-home-sentinel".utf8).write(to: sentinel)
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = realHome.path

        let result = try runInstaller(
            arguments: ["--home", "", "--source", fixture.source.path],
            environment: environment
        )
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("real-home-sentinel".utf8))
        for relativePath in [".codex", ".agents", ".claude"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: realHome.appending(path: relativePath).path))
        }
    }

    func testSkillInstallerNormalizesEquivalentSameSourceSymlink() throws {
        let fixture = try makeInstallerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let initial = try runInstaller(home: fixture.home, source: fixture.source)
        XCTAssertEqual(initial.status, 0, initial.output)

        let destination = fixture.home.appending(path: ".claude/skills/fcpxml-subtitle-aligner")
        try FileManager.default.removeItem(at: destination)
        let equivalentTarget = fixture.source.path + "/../" + fixture.source.lastPathComponent
        try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: equivalentTarget)

        let rerun = try runInstaller(home: fixture.home, source: fixture.source)
        XCTAssertEqual(rerun.status, 0, rerun.output)
        let normalizedTarget = try XCTUnwrap(
            try FileManager.default.destinationOfSymbolicLink(atPath: destination.path)
        )
        XCTAssertEqual(
            normalizedDirectoryPath(URL(fileURLWithPath: normalizedTarget).resolvingSymlinksInPath()),
            normalizedDirectoryPath(fixture.source.resolvingSymlinksInPath())
        )
        assertInstalledLinks(home: fixture.home, source: fixture.source)
    }

    func testSkillInstallerLeavesExistingSameSourceSymlinksUntouched() throws {
        let fixture = try makeInstallerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let initial = try runInstaller(home: fixture.home, source: fixture.source)
        XCTAssertEqual(initial.status, 0, initial.output)
        let destination = fixture.home.appending(path: ".codex/skills/fcpxml-subtitle-aligner")
        let initialInode = try inode(of: destination)

        let rerun = try runInstaller(home: fixture.home, source: fixture.source)
        XCTAssertEqual(rerun.status, 0, rerun.output)
        XCTAssertEqual(try inode(of: destination), initialInode)
        assertInstalledLinks(home: fixture.home, source: fixture.source)
    }

    func testSkillInstallerRefusesOccupiedDestinationsWithoutChangingAnything() throws {
        let fixture = try makeInstallerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let fileDestination = fixture.home.appending(path: ".codex/skills/fcpxml-subtitle-aligner")
        let directoryDestination = fixture.home.appending(path: ".agents/skills/fcpxml-subtitle-aligner")
        let symlinkDestination = fixture.home.appending(path: ".claude/skills/fcpxml-subtitle-aligner")
        try FileManager.default.createDirectory(at: fileDestination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directoryDestination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: symlinkDestination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let fileSentinel = Data("regular-file-sentinel".utf8)
        try fileSentinel.write(to: fileDestination)
        let directorySentinel = directoryDestination.appending(path: "sentinel")
        try FileManager.default.createDirectory(at: directoryDestination, withIntermediateDirectories: false)
        try Data("directory-sentinel".utf8).write(to: directorySentinel)
        let unrelatedTarget = fixture.root.appending(path: "unrelated-target")
        try FileManager.default.createDirectory(at: unrelatedTarget, withIntermediateDirectories: false)
        let unrelatedTargetSentinel = unrelatedTarget.appending(path: "sentinel")
        try Data("symlink-target-sentinel".utf8).write(to: unrelatedTargetSentinel)
        try FileManager.default.createSymbolicLink(atPath: symlinkDestination.path, withDestinationPath: unrelatedTarget.path)

        let sourceSnapshot = try Data(contentsOf: fixture.skill)
        let result = try runInstaller(home: fixture.home, source: fixture.source)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertEqual(try Data(contentsOf: fileDestination), fileSentinel)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directorySentinel.path))
        XCTAssertEqual(try Data(contentsOf: directorySentinel), Data("directory-sentinel".utf8))
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: symlinkDestination.path),
            unrelatedTarget.path
        )
        XCTAssertEqual(try Data(contentsOf: unrelatedTargetSentinel), Data("symlink-target-sentinel".utf8))
        XCTAssertEqual(try Data(contentsOf: fixture.skill), sourceSnapshot)
    }

    func testSkillInstallerPreflightsAllDestinationsBeforeCreatingAnyParents() throws {
        let fixture = try makeInstallerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let agentsDirectory = fixture.home.appending(path: ".agents")
        let blockedSkills = agentsDirectory.appending(path: "skills")
        try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
        try Data("blocked-parent".utf8).write(to: blockedSkills)

        let result = try runInstaller(home: fixture.home, source: fixture.source)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.home.appending(path: ".codex").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.home.appending(path: ".claude").path))
        XCTAssertEqual(try Data(contentsOf: blockedSkills), Data("blocked-parent".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.home.appending(path: ".agents/skills/fcpxml-subtitle-aligner").path))
    }

    func testSkillInstallerRejectsSymlinkAncestorWithoutFollowingIt() throws {
        let fixture = try makeInstallerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let external = fixture.root.appending(path: "external")
        let externalSentinel = external.appending(path: "sentinel")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try Data("external-sentinel".utf8).write(to: externalSentinel)
        let codex = fixture.home.appending(path: ".codex")
        try FileManager.default.createDirectory(at: fixture.home, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: codex.path, withDestinationPath: external.path)

        let result = try runInstaller(home: fixture.home, source: fixture.source)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertEqual(try Data(contentsOf: externalSentinel), Data("external-sentinel".utf8))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: codex.path), external.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.home.appending(path: ".agents").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.home.appending(path: ".claude").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: external.appending(path: "skills").path))
    }

    func testSkillHasExactFrontmatterAndRichFCPXMLTriggerDescription() throws {
        let skill = try readSkill()
        let frontmatter = try XCTUnwrap(frontmatter(in: skill))
        XCTAssertEqual(frontmatter.keys.sorted(), ["description", "name"])
        XCTAssertEqual(frontmatter["name"], "fcpxml-subtitle-aligner")

        let description = try XCTUnwrap(frontmatter["description"])
        XCTAssertTrue(description.hasPrefix("Use when"))
        for token in [
            "align", "center", "resize", "normalize", "Final Cut Pro",
            "title", "ingredient", "subtitle", ".fcpxml", ".fcpxmld",
            "preserving original"
        ] {
            XCTAssertTrue(description.localizedCaseInsensitiveContains(token), "Missing trigger token: \(token)")
        }
        XCTAssertTrue(description.localizedCaseInsensitiveContains("Final Cut Pro"))
        XCTAssertTrue(
            description.localizedCaseInsensitiveContains(".fcpxml")
                || description.localizedCaseInsensitiveContains(".fcpxmld")
        )
        XCTAssertTrue(
            ["align", "center", "resize", "normalize"].contains {
                description.localizedCaseInsensitiveContains($0)
            }
        )
        XCTAssertFalse(description.localizedCaseInsensitiveContains("mp4"))
        XCTAssertFalse(description.localizedCaseInsensitiveContains("generic subtitle"))
    }

    func testSkillDocumentsSafeCLIWorkflowAndControlledErrors() throws {
        let skill = try readSkill()
        let body = try XCTUnwrap(body(afterFrontmatterIn: skill))

        for token in [
            "fcpxml-aligner", "--json", "sha256", "Info.fcpxml", "inventory",
            "never overwrite", "source fingerprint", "unchanged", "output", "report", "success",
            "missing binary", "invalid XML", "missing font", "validation failure",
            "absolute", "Structural validation: PASS", "GitHub Release", "universal", "macOS", "checksum",
            "matching", ".build", "do not execute downloads automatically",
            "superchaospc/fcpxml-subtitle-aligner", "v1.0.0",
            "fcpxml-aligner-v1.0.0-macos-universal.tar.gz", "SHA256SUMS",
            "expected filename", "abort", "expected fcpxml-aligner binary"
        ] {
            XCTAssertTrue(body.localizedCaseInsensitiveContains(token), "Missing workflow safeguard: \(token)")
        }
        XCTAssertFalse(skill.contains("/Users"), "Skill must not contain user-specific absolute paths.")
        XCTAssertFalse(skill.localizedCaseInsensitiveContains("upload"), "Skill must not instruct remote uploads.")
    }

    func testSkillLocatesNativeAndUniversalSwiftBuildProductsWithoutHardcodedUserPaths() throws {
        let skill = try readSkill()
        let body = try XCTUnwrap(body(afterFrontmatterIn: skill))

        for token in [
            "swift build -c release --show-bin-path",
            "swift build -c release --arch arm64 --arch x86_64 --show-bin-path",
            ".build/apple/Products/Release/fcpxml-aligner",
            "executable",
        ] {
            XCTAssertTrue(body.contains(token), "Missing build-product discovery rule: \(token)")
        }
        XCTAssertFalse(skill.contains("/Users"), "Skill must not hardcode a user path.")
    }

    func testSkillRequiresStrictReadableInputPreflightBeforeFingerprintAndExecution() throws {
        let body = try XCTUnwrap(body(afterFrontmatterIn: readSkill()))
        for token in [
            "preflight", "exists", "readable", "extension exactly", ".fcpxml is a file",
            ".fcpxmld is a directory", "Info.fcpxml exists", "readable Info.fcpxml", "before fingerprint",
            "before executing"
        ] {
            XCTAssertTrue(body.localizedCaseInsensitiveContains(token), "Missing preflight rule: \(token)")
        }

        let preflight = try XCTUnwrap(body.range(of: "preflight"))
        let fingerprint = try XCTUnwrap(body.range(of: "fingerprint"))
        let execution = try XCTUnwrap(body.range(of: "Run the CLI"))
        XCTAssertLessThan(preflight.lowerBound, fingerprint.lowerBound)
        XCTAssertLessThan(fingerprint.lowerBound, execution.lowerBound)
    }

    func testSkillFingerprintsEveryRegularBundleFileInDeterministicFilenameSafeOrder() throws {
        let body = try XCTUnwrap(body(afterFrontmatterIn: readSkill()))
        for token in [
            "every regular file", "relative path", "deterministic", "sorted",
            "find", "-print0", "sort -z", "xargs -0", "per-file", "digest"
        ] {
            XCTAssertTrue(body.localizedCaseInsensitiveContains(token), "Missing full bundle fingerprint rule: \(token)")
        }
    }

    func testSkillOutputVerificationRechecksFullPerFileDigestInventory() throws {
        let body = try XCTUnwrap(body(afterFrontmatterIn: readSkill()))
        for token in [
            "recheck", "full", "per-file", "digest inventory", "each regular file",
            "added", "removed", "renamed", "modified"
        ] {
            XCTAssertTrue(body.localizedCaseInsensitiveContains(token), "Missing output inventory verification rule: \(token)")
        }
    }

    func testSkillTriggerEvidenceDocumentsFreshAgentScenarioMatrix() throws {
        let evidence = try String(
            contentsOf: packageRoot.appending(path: "docs/validation/skill-trigger-evidence.md"),
            encoding: .utf8
        )
        for token in [
            "2026-08-23", "baseline without Skill", ".fcpxmld", "action18", "ingredient16",
            "preflight", "exact JSON CLI", "Structural validation: PASS", "full source fingerprint",
            "absolute outputs", "malformed input", "controlled fail", "no partial", "missing CLI",
            "pinned repo", "tag", "asset", "SHA256", "network authorization", "MP4-only",
            "did not trigger", "canonical install locations", "same Skill", "Claude Code CLI 2.1.215",
            "loggedIn: false", "authMethod none", "NOT executed", "no login attempted",
            "packaging/path compatibility"
        ] {
            XCTAssertTrue(evidence.localizedCaseInsensitiveContains(token), "Missing evidence scenario detail: \(token)")
        }
        XCTAssertFalse(evidence.contains("/Us" + "ers/"), "Evidence must not contain personal absolute paths.")
        XCTAssertFalse(evidence.contains("/home/"), "Evidence must not contain personal absolute paths.")
        XCTAssertFalse(evidence.localizedCaseInsensitiveContains("wei" + "chaoshen"), "Evidence must not contain usernames.")
    }

    func testOpenAIInterfaceUsesQuotedStringsAndSkillDefaults() throws {
        let yaml = try String(contentsOf: packageRoot.appending(path: "skills/fcpxml-subtitle-aligner/agents/openai.yaml"), encoding: .utf8)

        XCTAssertTrue(yaml.contains("display_name:"))
        XCTAssertTrue(yaml.contains("short_description:"))
        XCTAssertTrue(yaml.contains("icon_small:"))
        XCTAssertTrue(yaml.contains("icon_large:"))
        XCTAssertTrue(yaml.contains("brand_color: \"#7A1F0E\""))
        XCTAssertTrue(yaml.contains("default_prompt:"))
        XCTAssertTrue(yaml.contains("$fcpxml-subtitle-aligner"))
        for key in ["display_name", "short_description", "icon_small", "icon_large", "brand_color", "default_prompt"] {
            let line = try XCTUnwrap(yaml.split(separator: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("\(key):") })
            XCTAssertTrue(line.contains("\""), "\(key) must be a quoted YAML string")
        }

        let shortDescription = try XCTUnwrap(yaml.split(separator: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("short_description:") })
        let value = shortDescription.drop(while: { $0 != "\"" }).dropFirst().dropLast()
        XCTAssertTrue((25...64).contains(value.count), "short_description must be 25–64 characters")
    }

    func testSkillAssetsAreDeterministicAndReferenced() throws {
        let assets = packageRoot.appending(path: "skills/fcpxml-subtitle-aligner/assets")
        let logo = assets.appending(path: "logo.svg")
        let icon = assets.appending(path: "icon-400.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: logo.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: icon.path))

        let svg = try String(contentsOf: logo, encoding: .utf8)
        XCTAssertTrue(svg.contains("#7A1F0E"))
        XCTAssertTrue(svg.contains("viewBox"))
        let iconData = try Data(contentsOf: icon)
        XCTAssertEqual(iconData.prefix(8), Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
        let dimensions = pngDimensions(iconData)
        XCTAssertEqual(dimensions.width, 400)
        XCTAssertEqual(dimensions.height, 400)
        XCTAssertEqual(try sha256(of: logo), "a8c2167c6163d09f91ffc7066b043caa5abad8d779397cba8924c3874c5fba99")
        XCTAssertEqual(try sha256(of: icon), "6551ce9c5e99e58746e5996b8aba2a2b9591c56dce9ccb2aecbd3c722f1e24d0")

        let yaml = try String(contentsOf: packageRoot.appending(path: "skills/fcpxml-subtitle-aligner/agents/openai.yaml"), encoding: .utf8)
        XCTAssertTrue(yaml.contains("assets/logo.svg"))
        XCTAssertTrue(yaml.contains("assets/icon-400.png"))
    }

    private func readSkill() throws -> String {
        try String(contentsOf: packageRoot.appending(path: "skills/fcpxml-subtitle-aligner/SKILL.md"), encoding: .utf8)
    }

    private func frontmatter(in skill: String) -> [String: String]? {
        guard skill.hasPrefix("---\n"), let end = skill.range(of: "\n---\n", range: skill.index(skill.startIndex, offsetBy: 4)..<skill.endIndex) else {
            return nil
        }
        let raw = String(skill[skill.index(skill.startIndex, offsetBy: 4)..<end.lowerBound])
        var values: [String: String] = [:]
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            let unquoted = value.first == "\"" && value.last == "\""
            values[parts[0].trimmingCharacters(in: .whitespaces)] = unquoted
                ? String(value.dropFirst().dropLast())
                : value
        }
        return values
    }

    private func body(afterFrontmatterIn skill: String) -> String? {
        guard let range = skill.range(of: "\n---\n") else { return nil }
        return String(skill[range.upperBound...])
    }

    private func pngDimensions(_ data: Data) -> (width: Int, height: Int) {
        guard data.count >= 24,
              data[12] == 0x49, data[13] == 0x48, data[14] == 0x44, data[15] == 0x52
        else { return (0, 0) }
        let width = data[16..<20].reduce(0) { ($0 << 8) | Int($1) }
        let height = data[20..<24].reduce(0) { ($0 << 8) | Int($1) }
        return (width, height)
    }

    private func sha256(of url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private struct InstallerFixture {
        let root: URL
        let home: URL
        let source: URL
        let skill: URL
    }

    private func makeInstallerFixture() throws -> InstallerFixture {
        let root = URL(fileURLWithPath: "/tmp/fcpxml-subtitle-aligner-skill-installer-\(UUID().uuidString)")
        let home = root.appending(path: "home")
        let source = root.appending(path: "source")
        let skill = source.appending(path: "SKILL.md")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("---\nname: fixture\n---\nfixture skill\n".utf8).write(to: skill)
        return InstallerFixture(root: root, home: home, source: source, skill: skill)
    }

    private func runInstaller(home: URL, source: URL) throws -> ProcessResult {
        try runInstaller(arguments: ["--home", home.path, "--source", source.path])
    }

    private func runInstaller(arguments: [String], environment: [String: String]? = nil) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [packageRoot.appending(path: "scripts/install_skill.sh").path] + arguments
        process.currentDirectoryURL = packageRoot
        if let environment {
            process.environment = environment
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        return ProcessResult(status: process.terminationStatus, output: output)
    }

    private func assertInstalledLinks(home: URL, source: URL, file: StaticString = #filePath, line: UInt = #line) {
        let canonicalSource = source.resolvingSymlinksInPath().standardizedFileURL
        for relativePath in [
            ".codex/skills/fcpxml-subtitle-aligner",
            ".agents/skills/fcpxml-subtitle-aligner",
            ".claude/skills/fcpxml-subtitle-aligner"
        ] {
            let destination = home.appending(path: relativePath)
            XCTAssertEqual(
                destination.resolvingSymlinksInPath().standardizedFileURL,
                canonicalSource,
                file: file,
                line: line
            )
            let linkTarget = try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)
            let resolvedTarget = linkTarget.map {
                normalizedDirectoryPath(URL(fileURLWithPath: $0).resolvingSymlinksInPath())
            }
            XCTAssertEqual(
                resolvedTarget,
                normalizedDirectoryPath(canonicalSource),
                file: file,
                line: line
            )
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: destination.appending(path: "SKILL.md").path),
                file: file,
                line: line
            )
        }
    }

    private func normalizedDirectoryPath(_ url: URL) -> String {
        let path = url.path
        guard path != "/" else { return path }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func inode(of url: URL) throws -> NSNumber {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.systemFileNumber] as? NSNumber)
    }

    private struct ProcessResult {
        let status: Int32
        let output: String
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
