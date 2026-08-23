import Foundation
import XCTest

final class ReleasePackagingTests: XCTestCase {
    func testReleaseScriptExistsAndDeclaresPublicInterface() throws {
        let script = packageRoot.appending(path: "scripts/build_release.sh")
        guard FileManager.default.fileExists(atPath: script.path) else {
            return XCTFail("Release packaging requires scripts/build_release.sh")
        }

        let contents = try String(contentsOf: script, encoding: .utf8)
        XCTAssertTrue(contents.contains("--version"))
        XCTAssertTrue(contents.contains("--output-dir"))
        XCTAssertTrue(contents.contains("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
    }

    func testReleaseScriptRejectsInvalidVersionWithoutCreatingItsOutput() throws {
        let output = releaseOutput(named: "invalid-version")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try runRelease(arguments: [
            "--version", "1.0.0",
            "--output-dir", output.path,
        ])

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(result.output.contains("version"), result.output)
    }

    func testReleaseScriptRejectsVersionThatDiffersFromProductMetadata() throws {
        let output = releaseOutput(named: "version-mismatch")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try runRelease(arguments: [
            "--version", "v1.0.1",
            "--output-dir", output.path,
        ])

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(result.output.contains("version mismatch"), result.output)
    }

    func testReleaseVersionGateChecksCLIAppSkillAndChangelog() throws {
        let script = try String(
            contentsOf: packageRoot.appending(path: "scripts/check_release_version.sh"),
            encoding: .utf8
        )

        for token in [
            "CLIApplication.swift", "CFBundleShortVersionString", "SKILL.md",
            "CHANGELOG.md", "version mismatch"
        ] {
            XCTAssertTrue(script.contains(token), "Version gate is missing: \(token)")
        }
    }

    func testTestOnlyOptionsRejectExternalOutputBeforeMakingParents() throws {
        let root = URL(fileURLWithPath: "/tmp")
            .appending(path: "fcpxml-subtitle-aligner-release-external-parent-\(UUID().uuidString)")
        let output = root.appending(path: "nested/release")
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = try testExecutable()

        let result = try runRelease(arguments: [
            "--version", "v1.0.0",
            "--output-dir", output.path,
            "--test-prebuilt-app-binary", executable.path,
            "--test-prebuilt-cli-binary", executable.path,
            "--test-skip-fat-verification",
        ])

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path), result.output)
        XCTAssertTrue(result.output.contains("test-only"), result.output)
    }

    func testReleaseScriptRefusesOccupiedOutputWithoutChangingSentinel() throws {
        let output = releaseOutput(named: "occupied")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: output) }
        let sentinel = output.appending(path: "sentinel")
        try Data("do not replace".utf8).write(to: sentinel)

        let result = try runFastRelease(output: output)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("do not replace".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), ["sentinel"])
    }

    func testFastReleaseProducesExactlyVerifiedAssetsWithRequiredArchiveRoots() throws {
        let output = releaseOutput(named: "assets")
        let extraction = releaseOutput(named: "archive-extraction")
        defer {
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: extraction)
        }
        let sourceSkill = packageRoot.appending(path: "skills/fcpxml-subtitle-aligner/SKILL.md")
        let sourceSkillSnapshot = try Data(contentsOf: sourceSkill)

        let result = try runFastRelease(output: output)
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertEqual(try Data(contentsOf: sourceSkill), sourceSkillSnapshot)

        let appArchive = "FCPXML-Subtitle-Aligner-v1.0.0-macos-universal.zip"
        let cliArchive = "fcpxml-aligner-v1.0.0-macos-universal.tar.gz"
        let skillArchive = "fcpxml-subtitle-aligner-skill-v1.0.0.zip"
        let expectedAssets = [appArchive, cliArchive, skillArchive, "SHA256SUMS"]
        let inventory = try FileManager.default.contentsOfDirectory(atPath: output.path).sorted()
        XCTAssertEqual(inventory, expectedAssets.sorted())
        for name in expectedAssets {
            let values = try output.appending(path: name).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            XCTAssertEqual(values.isRegularFile, true, "Expected regular file: \(name)")
            XCTAssertNotEqual(values.isSymbolicLink, true, "Release asset must not be a symlink: \(name)")
        }

        let appListing = try archiveListing(with: "/usr/bin/unzip", arguments: ["-Z1", output.appending(path: appArchive).path])
        XCTAssertTrue(appListing.contains("FCPXML Subtitle Aligner.app/Contents/MacOS/FCPXMLSubtitleAligner"), appListing.joined(separator: "\n"))
        assertArchiveEntries(appListing, rootedAt: "FCPXML Subtitle Aligner.app")

        let cliListing = try archiveListing(with: "/usr/bin/tar", arguments: ["-tzf", output.appending(path: cliArchive).path])
        XCTAssertEqual(cliListing, ["fcpxml-aligner"])

        let skillListing = try archiveListing(with: "/usr/bin/unzip", arguments: ["-Z1", output.appending(path: skillArchive).path])
        for path in [
            "fcpxml-subtitle-aligner/SKILL.md",
            "fcpxml-subtitle-aligner/agents/openai.yaml",
            "fcpxml-subtitle-aligner/assets/logo.svg",
            "fcpxml-subtitle-aligner/assets/icon-400.png",
        ] {
            XCTAssertTrue(skillListing.contains(path), "Skill archive is missing: \(path)")
        }
        assertArchiveEntries(skillListing, rootedAt: "fcpxml-subtitle-aligner")

        let checksum = try run("/usr/bin/shasum", ["-a", "256", "-c", "SHA256SUMS"], currentDirectory: output)
        XCTAssertEqual(checksum.status, 0, checksum.output)
        let checksumNames = try String(contentsOf: output.appending(path: "SHA256SUMS"), encoding: .utf8)
            .split(separator: "\n")
            .compactMap { line -> String? in
                let line = String(line)
                guard let separator = line.range(of: "  ") else { return nil }
                return String(line[separator.upperBound...])
            }
        XCTAssertEqual(checksumNames, [appArchive, cliArchive, skillArchive])

        try FileManager.default.createDirectory(at: extraction, withIntermediateDirectories: false)
        let appExtract = try run("/usr/bin/ditto", ["-x", "-k", output.appending(path: appArchive).path, extraction.path])
        XCTAssertEqual(appExtract.status, 0, appExtract.output)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: extraction
            .appending(path: "FCPXML Subtitle Aligner.app/Contents/MacOS/FCPXMLSubtitleAligner").path))

        let cliExtract = try run("/usr/bin/tar", ["-xzf", output.appending(path: cliArchive).path, "-C", extraction.path])
        XCTAssertEqual(cliExtract.status, 0, cliExtract.output)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: extraction.appending(path: "fcpxml-aligner").path))
    }

    func testSkillArchiveContainsOnlyCommittedAllowlistedFilesAndIgnoresUntrackedSentinel() throws {
        let output = releaseOutput(named: "skill-allowlist")
        let skillRoot = packageRoot.appending(path: "skills/fcpxml-subtitle-aligner")
        let sentinel = skillRoot.appending(path: ".release-packaging-sentinel-\(UUID().uuidString)")
        let sentinelData = Data("untracked sentinel".utf8)
        defer {
            try? FileManager.default.removeItem(at: output)
            if (try? Data(contentsOf: sentinel)) == sentinelData {
                try? FileManager.default.removeItem(at: sentinel)
            }
        }
        try sentinelData.write(to: sentinel)

        let result = try runFastRelease(output: output)
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertEqual(try Data(contentsOf: sentinel), sentinelData)

        let listing = try archiveListing(
            with: "/usr/bin/unzip",
            arguments: ["-Z1", output.appending(path: "fcpxml-subtitle-aligner-skill-v1.0.0.zip").path]
        )
        XCTAssertEqual(
            Set(listing),
            Set([
                "fcpxml-subtitle-aligner/",
                "fcpxml-subtitle-aligner/SKILL.md",
                "fcpxml-subtitle-aligner/agents/",
                "fcpxml-subtitle-aligner/agents/openai.yaml",
                "fcpxml-subtitle-aligner/assets/",
                "fcpxml-subtitle-aligner/assets/icon-400.png",
                "fcpxml-subtitle-aligner/assets/logo.svg",
            ])
        )
        XCTAssertFalse(listing.contains(sentinel.lastPathComponent))
    }

    func testCLIArchiveOmitsLocalOwnershipMetadata() throws {
        let output = releaseOutput(named: "tar-metadata")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try runFastRelease(output: output)
        XCTAssertEqual(result.status, 0, result.output)
        let listing = try run(
            "/usr/bin/tar",
            ["-tvzf", output.appending(path: "fcpxml-aligner-v1.0.0-macos-universal.tar.gz").path]
        )
        XCTAssertEqual(listing.status, 0, listing.output)
        let user = try run("/usr/bin/id", ["-un"])
        let group = try run("/usr/bin/id", ["-gn"])
        XCTAssertEqual(user.status, 0, user.output)
        XCTAssertEqual(group.status, 0, group.output)
        XCTAssertFalse(listing.output.contains(user.output.trimmingCharacters(in: .whitespacesAndNewlines)), listing.output)
        XCTAssertFalse(listing.output.contains(group.output.trimmingCharacters(in: .whitespacesAndNewlines)), listing.output)
    }

    func testReleaseDocumentationLabelsAdHocSigningAndSafeGatekeeperWorkflow() throws {
        let readme = try String(contentsOf: packageRoot.appending(path: "README.md"), encoding: .utf8)
        let releaseScript = try String(contentsOf: packageRoot.appending(path: "scripts/build_release.sh"), encoding: .utf8)

        for token in [
            "ad-hoc", "unnotarized", "Gatekeeper", "Right-click", "Open", "System Settings",
            "临时签名", "未经公证", "右键", "打开", "系统设置",
        ] {
            XCTAssertTrue(readme.localizedCaseInsensitiveContains(token), "README is missing release safety guidance: \(token)")
        }
        XCTAssertTrue(releaseScript.contains("ad-hoc signed, unnotarized developer build"))
        XCTAssertTrue(releaseScript.contains("Signature=adhoc"))
        XCTAssertTrue(releaseScript.contains("git archive --format=zip"))
        XCTAssertTrue(releaseScript.contains("--numeric-owner"))
        XCTAssertTrue(readme.localizedCaseInsensitiveContains("Do not disable Gatekeeper"))
        XCTAssertFalse(readme.localizedCaseInsensitiveContains("disable Gatekeeper to"))
        XCTAssertFalse(readme.localizedCaseInsensitiveContains("xattr"))
    }

    func testInjectedReleaseFailureCleansOwnedWorkspaceWithoutPublishing() throws {
        let output = releaseOutput(named: "cleanup")
        defer { try? FileManager.default.removeItem(at: output) }
        let packageSnapshot = try Data(contentsOf: packageRoot.appending(path: "Package.swift"))

        let result = try runFastRelease(output: output, injectPostStageFailure: true)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try Data(contentsOf: packageRoot.appending(path: "Package.swift")), packageSnapshot)
        let temporaryEntries = try FileManager.default.contentsOfDirectory(atPath: "/tmp")
            .filter { $0.hasPrefix(".fcpxml-subtitle-aligner-release-stage.") }
        XCTAssertTrue(temporaryEntries.isEmpty, "Residual release workspaces: \(temporaryEntries)")
    }

    func testStaticReleaseChecksRequireRealUniversalBuildLipoSigningAndNarrowTestGates() throws {
        let releaseScript = try String(contentsOf: packageRoot.appending(path: "scripts/build_release.sh"), encoding: .utf8)
        let appScript = try String(contentsOf: packageRoot.appending(path: "scripts/build_app.sh"), encoding: .utf8)

        for token in [
            "developer_dir=\"${DEVELOPER_DIR:-}\"", "/Applications/Xcode_16.2.app/Contents/Developer",
            "Swift version 6", "swift package clean",
            "swift build -c release --arch arm64 --arch x86_64 --product fcpxml-aligner",
            "lipo \"$app_binary\" -verify_arch arm64 x86_64",
            "lipo \"$cli_binary\" -verify_arch arm64 x86_64",
            "ditto -c -k --keepParent --norsrc", "COPYFILE_DISABLE=1",
            "shasum -a 256 -c SHA256SUMS", "git -C \"$source_root\" status --porcelain --untracked-files=no",
            "fcpxml-subtitle-aligner-release-test.", "--test-prebuilt-app-binary",
            "--test-skip-fat-verification", "mktemp -d \"$output_parent/.fcpxml-subtitle-aligner-release-stage.",
            "mv \"$workspace\" \"$output_dir\"",
        ] {
            XCTAssertTrue(releaseScript.contains(token), "Release script is missing: \(token)")
        }
        for token in [
            "--release-stage-parent", ".fcpxml-subtitle-aligner-release-stage-owner",
            "lipo \"$binary\" -verify_arch arm64 x86_64",
            "codesign --force --sign - --timestamp=none", "codesign --verify --deep --strict",
        ] {
            XCTAssertTrue(appScript.contains(token), "App builder is missing: \(token)")
        }
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func releaseOutput(named name: String) -> URL {
        URL(fileURLWithPath: "/tmp")
            .appending(path: "fcpxml-subtitle-aligner-release-test.\(name)-\(UUID().uuidString)")
    }

    private func testExecutable() throws -> URL {
        var candidate = Bundle(for: ReleasePackagingTests.self).bundleURL.deletingLastPathComponent()
        for _ in 0...4 {
            if ["debug", "release"].contains(candidate.lastPathComponent) {
                let executable = candidate.appending(path: "FCPXMLSubtitleAligner")
                if FileManager.default.isExecutableFile(atPath: executable.path) {
                    return executable
                }
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func runFastRelease(output: URL, injectPostStageFailure: Bool = false) throws -> ReleaseProcessResult {
        let executable = try testExecutable()
        var arguments = [
            "--version", "v1.0.0",
            "--output-dir", output.path,
            "--test-prebuilt-app-binary", executable.path,
            "--test-prebuilt-cli-binary", executable.path,
            "--test-skip-fat-verification",
        ]
        if injectPostStageFailure {
            arguments.append("--test-inject-post-stage-failure")
        }
        return try runRelease(arguments: arguments)
    }

    private func runRelease(arguments: [String]) throws -> ReleaseProcessResult {
        try run("/bin/bash", [packageRoot.appending(path: "scripts/build_release.sh").path] + arguments, currentDirectory: packageRoot)
    }

    private func archiveListing(with executable: String, arguments: [String]) throws -> [String] {
        let result = try run(executable, arguments)
        XCTAssertEqual(result.status, 0, result.output)
        return result.output.split(separator: "\n").map(String.init)
    }

    private func assertArchiveEntries(_ entries: [String], rootedAt root: String) {
        XCTAssertFalse(entries.isEmpty)
        for entry in entries {
            XCTAssertTrue(entry == root || entry.hasPrefix(root + "/"), "Unexpected archive entry: \(entry)")
            XCTAssertFalse(entry.hasPrefix("__MACOSX/") || entry.contains("/._"), "AppleDouble junk: \(entry)")
        }
    }

    private func run(_ executable: String, _ arguments: [String], currentDirectory: URL? = nil) throws -> ReleaseProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        return ReleaseProcessResult(
            status: process.terminationStatus,
            output: String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }
}

private struct ReleaseProcessResult {
    let status: Int32
    let output: String
}
