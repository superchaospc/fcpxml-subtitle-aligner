import Foundation
import XCTest

final class PackagingTests: XCTestCase {
    func testREADMEHasPublicBadgesAndBilingualProductGuide() throws {
        let readme = try repositoryDocument(named: "README.md")

        for token in [
            "https://github.com/superchaospc/fcpxml-subtitle-aligner/releases/latest",
            "https://github.com/superchaospc/fcpxml-subtitle-aligner/actions/workflows/ci.yml/badge.svg",
            "macOS 13+", "Swift 6", "MIT", "对齐", "居中", "左右文本边距",
            "adjusts sizes", "auto-shrink", "preserves the original", "Final Cut Pro",
            "拖放", "App", "CLI", "fcpxml-aligner", ".fcpxml", ".fcpxmld",
            "不覆盖", "never overwrite", "local-only", "仅在本机"
        ] {
            XCTAssertTrue(readme.localizedCaseInsensitiveContains(token), "README is missing: \(token)")
        }
    }

    func testAllREADMEBadgeTargetsStayInsideCanonicalGitHubRepository() throws {
        let readme = try repositoryDocument(named: "README.md")
        let repositoryURL = "https://github.com/superchaospc/fcpxml-subtitle-aligner"
        let badgeLines = readme.split(separator: "\n").filter { $0.contains("[![") }
        XCTAssertEqual(badgeLines.count, 5)

        for line in badgeLines {
            let line = String(line)
            guard let targetStart = line.range(of: ")](") else {
                XCTFail("Badge has no target: \(line)")
                continue
            }
            let targetRemainder = line[targetStart.upperBound...]
            guard let targetEnd = targetRemainder.firstIndex(of: ")") else {
                XCTFail("Badge target is not closed: \(line)")
                continue
            }
            let target = String(targetRemainder[..<targetEnd])
            XCTAssertTrue(
                target.hasPrefix(repositoryURL),
                "Badge target must stay inside \(repositoryURL): \(target)"
            )
        }

        for target in [
            "\(repositoryURL)/releases/latest",
            "\(repositoryURL)/actions/workflows/ci.yml",
            "\(repositoryURL)#requirements",
            "\(repositoryURL)#source-build",
            "\(repositoryURL)/blob/main/LICENSE"
        ] {
            XCTAssertTrue(readme.contains(")](" + target + ")"), "Missing repository badge target: \(target)")
        }
    }

    func testREADMEDocumentsEveryCLIFlagJSONOutputsAndBuildPath() throws {
        let readme = try repositoryDocument(named: "README.md")

        for token in [
            "--action-size", "--ingredient-size", "--minimum-size", "--safe-width",
            "--auto-shrink", "--no-auto-shrink", "--json", "--help", "-h", "--version",
            "outputPath", "reportPath", "changedTitles", "skippedTitles",
            "输出文件", "报告文件", "source build", "swift build", "releases/latest"
        ] {
            XCTAssertTrue(readme.localizedCaseInsensitiveContains(token), "README is missing: \(token)")
        }
    }

    func testREADMEUsesArchitectureNeutralCLIPathAndDocumentsAppBuildScript() throws {
        let readme = try repositoryDocument(named: "README.md")

        XCTAssertTrue(readme.contains("swift build -c release --show-bin-path"))
        XCTAssertFalse(readme.contains(".build/arm64-apple-macosx/release/fcpxml-aligner"))
        for token in [
            "scripts/build_app.sh", "drag and drop", "FCPXML Subtitle Aligner.app",
            "outputs", "build the App", "output directory"
        ] {
            XCTAssertTrue(readme.localizedCaseInsensitiveContains(token), "README is missing: \(token)")
        }
    }

    func testREADMEDocumentsSkillPromptsUninstallPrivacyAndTroubleshooting() throws {
        let readme = try repositoryDocument(named: "README.md")

        for token in [
            "scripts/install_skill.sh", "Codex", "Claude", "fcpxml-subtitle-aligner",
            ".codex/skills", ".agents/skills", ".claude/skills", "uninstall",
            "missing font", "malformed", "no match", "字体", "格式错误", "没有匹配",
            "JSON", "privacy", "隐私", "does not upload", "不上传"
        ] {
            XCTAssertTrue(readme.localizedCaseInsensitiveContains(token), "README is missing: \(token)")
        }
    }

    func testChangelogStartsWithVersionDateAndTaskSixCapabilities() throws {
        let changelog = try repositoryDocument(named: "CHANGELOG.md")
        XCTAssertTrue(changelog.hasPrefix("## [1.0.0] - 2026-08-23"))
        for token in [
            "App", "CLI", "cross-agent Skill", "safe output transaction",
            "adjustable typography", "anonymous fixtures", "CI",
            "macOS 13+ deployment target", "macos-14 CI runner"
        ] {
            XCTAssertTrue(changelog.localizedCaseInsensitiveContains(token), "CHANGELOG is missing: \(token)")
        }
    }

    func testCIUsesPinnedMacOSRunnerLeastPermissionsStrictTestsAndUniversalArtifacts() throws {
        let workflow = try repositoryDocument(named: ".github/workflows/ci.yml")

        for token in [
            "name: CI", "push:", "pull_request:", "macos-14", "permissions:",
            "contents: read", "xcode-select --switch", "xcodebuild -version",
            "actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4",
            "swift package clean", "swift test -c debug", "swift test -c release",
            "-Xswiftc -warnings-as-errors", "--arch arm64 --arch x86_64",
            "FCPXMLSubtitleAligner", "fcpxml-aligner", "lipo", "-verify_arch arm64 x86_64",
            "quick_validate", "SKILL.md", "bash -n", "scripts/build_app.sh", "scripts/install_skill.sh",
            "xcodebuild test", "SkillPackagingTests", "SWIFT_TREAT_WARNINGS_AS_ERRORS=YES",
            "-only-testing:FCPXMLSubtitleAlignerAppTests/SkillPackagingTests"
        ] {
            XCTAssertTrue(workflow.localizedCaseInsensitiveContains(token), "CI is missing: \(token)")
        }
    }

    func testBuiltTestExecutableLocatorFindsDebugAndReleaseSiblingsFromBundleBases() throws {
        let root = URL(fileURLWithPath: "/tmp")
            .appending(path: "fcpxml-subtitle-aligner-executable-locator-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        for configuration in ["debug", "release"] {
            let products = root.appending(path: configuration)
            let executable = products.appending(path: "FCPXMLSubtitleAligner")
            let bundle = products.appending(path: "FCPXMLSubtitleAlignerPackageTests.xctest")
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            try Data().write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

            XCTAssertEqual(try BuiltTestExecutableLocator.find(from: bundle), executable)
        }
    }

    func testBuiltTestExecutableLocatorRejectsUnrecognizedProductsDirectory() throws {
        let root = URL(fileURLWithPath: "/tmp")
            .appending(path: "fcpxml-subtitle-aligner-executable-locator-\(UUID().uuidString)")
        let products = root.appending(path: "unrelated")
        let executable = products.appending(path: "FCPXMLSubtitleAligner")
        let bundle = products.appending(path: "FCPXMLSubtitleAlignerPackageTests.xctest")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        XCTAssertThrowsError(try BuiltTestExecutableLocator.find(from: bundle))
    }

    func testBuiltTestExecutableLocatorFindsActualConfigurationSibling() throws {
        let bundle = Bundle(for: PackagingTests.self).bundleURL
        let executable = try BuiltTestExecutableLocator.find(from: bundle)

        XCTAssertEqual(executable.lastPathComponent, "FCPXMLSubtitleAligner")
        XCTAssertTrue(["debug", "release"].contains(executable.deletingLastPathComponent().lastPathComponent))
    }

    func testInfoPlistDeclaresAppIdentityAndDocumentTypes() throws {
        let plist = try propertyList(at: packageRoot.appending(path: "Resources/Info.plist"))

        XCTAssertEqual(plist["CFBundleName"] as? String, "FCPXML Subtitle Aligner")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "FCPXML Subtitle Aligner")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "local.codex.fcpxml-subtitle-aligner")
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "1.0.0")
        XCTAssertEqual(plist["CFBundleVersion"] as? String, "1")
        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "APPL")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "FCPXMLSubtitleAligner")
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "13.0")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)

        let documentTypes = try XCTUnwrap(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        XCTAssertEqual(documentTypes.count, 2)
        XCTAssertTrue(documentTypes.contains { type in
            type["CFBundleTypeRole"] as? String == "Editor"
                && (type["CFBundleTypeExtensions"] as? [String])?.contains("fcpxml") == true
        })
        XCTAssertTrue(documentTypes.contains { type in
            type["CFBundleTypeRole"] as? String == "Editor"
                && (type["CFBundleTypeExtensions"] as? [String])?.contains("fcpxmld") == true
                && type["LSTypeIsPackage"] as? Bool == true
        })

        let exported = try XCTUnwrap(plist["UTExportedTypeDeclarations"] as? [[String: Any]])
        XCTAssertTrue(exported.contains { declaration in
            declaration["UTTypeIdentifier"] as? String == "local.codex.fcpxml-subtitle-aligner.fcpxmld"
                && (declaration["UTTypeConformsTo"] as? [String])?.contains("com.apple.package") == true
                && (((declaration["UTTypeTagSpecification"] as? [String: Any])?["public.filename-extension"] as? [String])?.contains("fcpxmld") == true)
        })
    }

    func testCISelectsSwiftSixCapableXcodeAndAssertsToolchain() throws {
        let workflow = try repositoryDocument(named: ".github/workflows/ci.yml")

        XCTAssertTrue(workflow.contains("/Applications/Xcode_16.2.app/Contents/Developer"))
        XCTAssertTrue(workflow.contains("swift --version"))
        XCTAssertTrue(workflow.contains("grep -Eq 'Swift version 6\\.'"))
        XCTAssertFalse(workflow.contains("--switch /Applications/Xcode.app/Contents/Developer"))
    }

    func testBuildScriptUsesOwnedStagingSigningAndValidation() throws {
        let scriptURL = packageRoot.appending(path: "scripts/build_app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains(".fcpxml-subtitle-aligner-owner"))
        XCTAssertTrue(script.contains("mktemp -d"))
        XCTAssertTrue(script.contains("codesign --force --sign -"))
        XCTAssertTrue(script.contains("codesign --verify --deep --strict"))
        XCTAssertTrue(script.contains("plutil -lint"))
        XCTAssertTrue(script.contains("developer_dir=\"${DEVELOPER_DIR:-}\""))
        XCTAssertTrue(script.contains("/Applications/Xcode_16.2.app/Contents/Developer"))
        XCTAssertTrue(script.contains("Swift version 6"))
        XCTAssertFalse(script.contains("export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer"))
    }

    func testBuildScriptBuildsAndVerifiesUniversalExecutable() throws {
        let script = try String(contentsOf: packageRoot.appending(path: "scripts/build_app.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("swift build -c release --arch arm64 --arch x86_64"))
        XCTAssertTrue(script.contains("lipo \"$binary\" -verify_arch arm64 x86_64"))
    }

    func testBuildScriptBehaviorallyPackagesOnlyIntoIsolatedTestLocations() throws {
        let scriptURL = packageRoot.appending(path: "scripts/build_app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        guard script.contains("--test-output-parent"), script.contains("--test-inject-publish-failure") else {
            XCTFail("The build script must expose validated test-only output and failure-injection options.")
            return
        }

        let testIdentifier = UUID().uuidString
        let freshParent = try makeOutputParent(named: "\(testIdentifier)-fresh")
        let unownedParent = try makeOutputParent(named: "\(testIdentifier)-unowned")
        let symlinkParent = try makeOutputParent(named: "\(testIdentifier)-symlink")
        let rollbackParent = try makeOutputParent(named: "\(testIdentifier)-rollback")
        defer {
            for parent in [freshParent, unownedParent, symlinkParent, rollbackParent] {
                try? FileManager.default.removeItem(at: parent)
            }
        }

        let binary = try builtTestExecutable()
        let fixture = packageRoot.appending(path: "Tests/FCPXMLAlignerCoreTests/Fixtures/sample-template.fcpxmld/Info.fcpxml")
        let originalFixtureHash = try sha256(of: fixture)

        let fresh = try runScript(outputParent: freshParent, binary: binary)
        XCTAssertEqual(fresh.status, 0, fresh.output)
        let freshApp = appURL(in: freshParent)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: freshApp.appending(path: "Contents/MacOS/FCPXMLSubtitleAligner").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshApp.appending(path: "Contents/Resources/.fcpxml-subtitle-aligner-owner").path))
        XCTAssertNoThrow(try propertyList(at: freshApp.appending(path: "Contents/Info.plist")))
        let signature = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", freshApp.path])
        XCTAssertEqual(signature.status, 0, signature.output)

        let unownedApp = appURL(in: unownedParent)
        try FileManager.default.createDirectory(at: unownedApp, withIntermediateDirectories: false)
        let unownedSentinel = unownedApp.appending(path: "sentinel")
        try Data("unowned".utf8).write(to: unownedSentinel)
        let unowned = try runScript(outputParent: unownedParent, binary: binary)
        XCTAssertNotEqual(unowned.status, 0)
        XCTAssertEqual(try Data(contentsOf: unownedSentinel), Data("unowned".utf8))

        let symlinkApp = appURL(in: symlinkParent)
        try FileManager.default.createSymbolicLink(atPath: symlinkApp.path, withDestinationPath: "/nonexistent/fcpxml-subtitle-aligner")
        let symlink = try runScript(outputParent: symlinkParent, binary: binary)
        XCTAssertNotEqual(symlink.status, 0)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: symlinkApp.path), "/nonexistent/fcpxml-subtitle-aligner")

        let replacementSentinel = freshApp.appending(path: "Contents/Resources/prior-owned-sentinel")
        try Data("owned".utf8).write(to: replacementSentinel)
        let replacement = try runScript(outputParent: freshParent, binary: binary)
        XCTAssertEqual(replacement.status, 0, replacement.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: replacementSentinel.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshApp.path))
        XCTAssertFalse(try hasResidualPublicationDirectories(in: freshParent))

        let rollbackBuild = try runScript(outputParent: rollbackParent, binary: binary)
        XCTAssertEqual(rollbackBuild.status, 0, rollbackBuild.output)
        let rollbackApp = appURL(in: rollbackParent)
        let rollbackSentinel = rollbackApp.appending(path: "Contents/Resources/prior-owned-sentinel")
        try Data("restore me".utf8).write(to: rollbackSentinel)
        let originalInfoHash = try sha256(of: rollbackApp.appending(path: "Contents/Info.plist"))
        let injectedFailure = try runScript(outputParent: rollbackParent, binary: binary, injectPublishFailure: true)
        XCTAssertNotEqual(injectedFailure.status, 0)
        XCTAssertEqual(try Data(contentsOf: rollbackSentinel), Data("restore me".utf8))
        XCTAssertEqual(try sha256(of: rollbackApp.appending(path: "Contents/Info.plist")), originalInfoHash)
        XCTAssertFalse(try hasResidualPublicationDirectories(in: rollbackParent))
        XCTAssertEqual(try sha256(of: fixture), originalFixtureHash)
    }

    func testTestOutputPathCannotEscapeCanonicalTemporaryRoot() throws {
        let scriptURL = packageRoot.appending(path: "scripts/build_app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        guard script.contains("canonical_test_output_parent") else {
            XCTFail("The script must canonicalize test output paths before invoking test packaging.")
            return
        }

        let identifier = UUID().uuidString
        let permittedParent = try makeOutputParent(named: "\(identifier)-permitted")
        let externalParent = URL(fileURLWithPath: "/tmp/fcpxml-subtitle-aligner-external-\(identifier)")
        try FileManager.default.createDirectory(at: externalParent, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: permittedParent)
            try? FileManager.default.removeItem(at: externalParent)
        }
        let sentinel = externalParent.appending(path: "sentinel")
        try Data("external".utf8).write(to: sentinel)
        let nested = permittedParent.appending(path: "nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        let binary = try builtTestExecutable()
        let traversalPath = nested.path + "/../../" + externalParent.lastPathComponent

        let traversal = try runScript(outputParentPath: traversalPath, binary: binary)
        XCTAssertNotEqual(traversal.status, 0)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("external".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: appURL(in: externalParent).path))
        XCTAssertFalse(try hasResidualPublicationDirectories(in: externalParent))

        let allowedLookingLink = permittedParent.appending(path: "fcpxml-subtitle-aligner-packaging-test.link")
        try FileManager.default.createSymbolicLink(atPath: allowedLookingLink.path, withDestinationPath: externalParent.path)
        let symlinkEscape = try runScript(outputParentPath: allowedLookingLink.path, binary: binary)
        XCTAssertNotEqual(symlinkEscape.status, 0)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: allowedLookingLink.path), externalParent.path)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("external".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: appURL(in: externalParent).path))
        XCTAssertFalse(try hasResidualPublicationDirectories(in: externalParent))
    }

    func testReplacementRacePreservesIntruderAndDoesNotPublish() throws {
        let scriptURL = packageRoot.appending(path: "scripts/build_app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        guard script.contains("--test-inject-destination-replacement-before-backup-move") else {
            XCTFail("The script must expose a narrowly gated replacement-race test hook.")
            return
        }

        let parent = try makeOutputParent(named: "\(UUID().uuidString)-replacement-race")
        defer { try? FileManager.default.removeItem(at: parent) }
        let binary = try builtTestExecutable()
        let initialBuild = try runScript(outputParent: parent, binary: binary)
        XCTAssertEqual(initialBuild.status, 0, initialBuild.output)

        let existingApp = appURL(in: parent)
        let priorOwnedSentinel = existingApp.appending(path: "Contents/Resources/prior-owned-sentinel")
        try Data("prior owned output".utf8).write(to: priorOwnedSentinel)

        let racedBuild = try runScript(
            outputParent: parent,
            binary: binary,
            injectDestinationReplacementBeforeBackupMove: true
        )

        XCTAssertNotEqual(racedBuild.status, 0)
        XCTAssertFalse(racedBuild.output.contains("Built \(existingApp.path)"))
        XCTAssertEqual(try Data(contentsOf: priorOwnedSentinel), Data("prior owned output".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingApp.appending(path: "Contents/Resources/.fcpxml-subtitle-aligner-owner").path))
        XCTAssertFalse(try hasResidualStageDirectories(in: parent))

        let recoveryDirectories = try publicationDirectories(in: parent, prefix: ".fcpxml-subtitle-aligner-backup.")
        XCTAssertEqual(recoveryDirectories.count, 1, racedBuild.output)
        let intruderSentinel = recoveryDirectories[0]
            .appending(path: "FCPXML Subtitle Aligner.app")
            .appending(path: ".fcpxml-subtitle-aligner-race-intruder")
        XCTAssertEqual(try Data(contentsOf: intruderSentinel), Data("simulated intruder".utf8))
        XCTAssertTrue(racedBuild.output.contains(recoveryDirectories[0].path))
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func repositoryDocument(named path: String) throws -> String {
        let url = packageRoot.appending(path: path)
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("Missing repository document: \(path)")
            return ""
        }
        return contents
    }

    private func propertyList(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let value = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(value as? [String: Any])
    }

    private func builtTestExecutable() throws -> URL {
        try BuiltTestExecutableLocator.find(from: Bundle(for: PackagingTests.self).bundleURL)
    }

    private func makeOutputParent(named name: String) throws -> URL {
        let parent = URL(fileURLWithPath: "/tmp")
            .appending(path: "fcpxml-subtitle-aligner-packaging-test.\(name)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        return parent
    }

    private func appURL(in parent: URL) -> URL {
        parent.appending(path: "FCPXML Subtitle Aligner.app")
    }

    private func hasResidualPublicationDirectories(in parent: URL) throws -> Bool {
        let names = try FileManager.default.contentsOfDirectory(atPath: parent.path)
        return names.contains { $0.hasPrefix(".fcpxml-subtitle-aligner-stage.") || $0.hasPrefix(".fcpxml-subtitle-aligner-backup.") }
    }

    private func hasResidualStageDirectories(in parent: URL) throws -> Bool {
        try !publicationDirectories(in: parent, prefix: ".fcpxml-subtitle-aligner-stage.").isEmpty
    }

    private func publicationDirectories(in parent: URL, prefix: String) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
    }

    private func sha256(of url: URL) throws -> String {
        let result = try run("/usr/bin/shasum", ["-a", "256", url.path])
        XCTAssertEqual(result.status, 0, result.output)
        return result.output.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
    }

    private func runScript(
        outputParent: URL,
        binary: URL,
        injectPublishFailure: Bool = false,
        injectDestinationReplacementBeforeBackupMove: Bool = false
    ) throws -> ProcessResult {
        try runScript(
            outputParentPath: outputParent.path,
            binary: binary,
            injectPublishFailure: injectPublishFailure,
            injectDestinationReplacementBeforeBackupMove: injectDestinationReplacementBeforeBackupMove
        )
    }

    private func runScript(
        outputParentPath: String,
        binary: URL,
        injectPublishFailure: Bool = false,
        injectDestinationReplacementBeforeBackupMove: Bool = false
    ) throws -> ProcessResult {
        var arguments = [
            "--test-output-parent", outputParentPath,
            "--test-prebuilt-binary", binary.path,
        ]
        if injectPublishFailure { arguments.append("--test-inject-publish-failure") }
        if injectDestinationReplacementBeforeBackupMove {
            arguments.append("--test-inject-destination-replacement-before-backup-move")
        }
        return try run(packageRoot.appending(path: "scripts/build_app.sh").path, arguments, currentDirectory: packageRoot)
    }

    private func run(_ executable: String, _ arguments: [String], currentDirectory: URL? = nil) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        return ProcessResult(status: process.terminationStatus, output: String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}

private struct ProcessResult {
    let status: Int32
    let output: String
}

private enum BuiltTestExecutableLocator {
    private enum BuildConfiguration: String {
        case debug
        case release
    }

    private static let executableName = "FCPXMLSubtitleAligner"
    private static let maximumAncestorSteps = 4

    static func find(from testBundleURL: URL) throws -> URL {
        var candidateDirectory = testBundleURL.deletingLastPathComponent()
        for _ in 0...maximumAncestorSteps {
            if BuildConfiguration(rawValue: candidateDirectory.lastPathComponent) != nil {
                let executable = candidateDirectory.appending(path: executableName)
                guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                return executable
            }
            candidateDirectory.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
