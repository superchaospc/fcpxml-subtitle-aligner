# Cross-Agent Skill and v1.0.0 Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish FCPXML Subtitle Aligner as a tested public Swift project with a universal macOS App, an automation CLI, one Skill usable by Codex and Claude Code, anonymized fixtures, CI, tag `v1.0.0`, and a GitHub Release.

**Architecture:** Keep `FCPXMLAlignerCore` as the single transformation engine. Add a small testable CLI target beside the existing App target, package one canonical Skill into all supported agent skill directories, and build every Release asset from the tagged monorepo. Privacy checks run in the Swift test suite and release script so real production metadata cannot be published accidentally.

**Tech Stack:** Swift 6 / SwiftPM, Foundation and AppKit, XCTest, Bash, GitHub Actions, GitHub CLI.

---

## File map

- `Package.swift`: declares the CLI product/target/test target and existing App/Core products.
- `Sources/FCPXMLAlignerCLI/CLIArguments.swift`: parses and validates CLI arguments without filesystem work.
- `Sources/FCPXMLAlignerCLI/CLIApplication.swift`: runs `OutputWriter`, formats JSON/text output, and maps failures to exit codes.
- `Sources/FCPXMLAlignerCLI/Main.swift`: process I/O adapter only.
- `Tests/FCPXMLAlignerCLITests/CLIArgumentsTests.swift`: parser/default/validation coverage.
- `Tests/FCPXMLAlignerCLITests/CLIApplicationTests.swift`: real transformation and failure-contract coverage.
- `Tests/FCPXMLAlignerCoreTests/RepositoryPrivacyTests.swift`: scans publishable source and fixtures for private metadata.
- `Tests/FCPXMLAlignerCoreTests/Fixtures/*.fcpxmld/Info.fcpxml`: anonymized structural fixtures.
- `Tests/FCPXMLAlignerCoreTests/TestSupport.swift`: neutral fixture names and helpers.
- `skills/fcpxml-subtitle-aligner/SKILL.md`: canonical cross-agent operating instructions.
- `skills/fcpxml-subtitle-aligner/agents/openai.yaml`: Codex-facing display metadata.
- `skills/fcpxml-subtitle-aligner/assets/`: small and large Skill icons.
- `scripts/install_skill.sh`: idempotent installation into Codex and Claude Code homes.
- `scripts/build_release.sh`: clean universal build, packaging, and checksums.
- `Tests/FCPXMLSubtitleAlignerAppTests/SkillPackagingTests.swift`: Skill and installer contract tests.
- `Tests/FCPXMLSubtitleAlignerAppTests/ReleasePackagingTests.swift`: release-script contract and isolated behavioral tests.
- `.github/workflows/ci.yml`: macOS Debug/Release warnings-as-errors CI.
- `.gitignore`: excludes Swift build state, Finder metadata, Xcode state, and local artifacts.
- `LICENSE`: MIT license.
- `README.md`: Chinese-first bilingual product, installation, CLI, Skill, troubleshooting, privacy, and release documentation.
- `CHANGELOG.md`: `v1.0.0` release notes source.

### Task 1: Establish repository hygiene and an enforceable privacy boundary

**Files:**
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `Tests/FCPXMLAlignerCoreTests/RepositoryPrivacyTests.swift`
- Modify: `Tests/FCPXMLAlignerCoreTests/TestSupport.swift`
- Modify: `Tests/FCPXMLAlignerCoreTests/FixtureAccessTests.swift`
- Modify: `Tests/FCPXMLAlignerCoreTests/OutputWriterTests.swift`
- Modify: `Tests/FCPXMLAlignerCoreTests/InputAndParsingTests.swift`
- Modify: `Tests/FCPXMLAlignerCoreTests/TransformerFixtureTests.swift`
- Modify: `Tests/FCPXMLSubtitleAlignerAppTests/PackagingTests.swift`
- Replace: `Tests/FCPXMLAlignerCoreTests/Fixtures/*.fcpxmld/Info.fcpxml`

- [ ] **Step 1: Write the failing repository privacy test**

```swift
import Foundation
import XCTest

final class RepositoryPrivacyTests: XCTestCase {
    func testPublishableFilesContainNoPrivateProductionMetadata() throws {
        // Enumerate every tracked regular file with `git ls-files -z`.
        // Build the known private-token set from harmless fragments at runtime,
        // then inspect raw UTF-8, UTF-16LE, UTF-16BE, and decoded bookmark bytes.
    }
}
```

Add a local helper that reads the tracked regular-file inventory, scans raw bytes before exempting intentional binary icons, and decodes each bookmark payload before checking it.

- [ ] **Step 2: Run the privacy test and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RepositoryPrivacyTests
```

Expected: FAIL on the fixtures and documentation that still contain production metadata.

- [ ] **Step 3: Replace fixtures with neutral structural data and update tests**

Rename the fixture roles consistently:

```swift
func currentFixtureDocument() throws -> FCPXMLDocument {
    try FCPXMLDocument(inputDocument: InputDocument(sourceURL: fixtureURL("sample-current")))
}

func templateFixtureDocument() throws -> FCPXMLDocument {
    try FCPXMLDocument(inputDocument: InputDocument(sourceURL: fixtureURL("sample-template")))
}

func goldFixtureDocument() throws -> FCPXMLDocument {
    try FCPXMLDocument(inputDocument: InputDocument(sourceURL: fixtureURL("sample-gold")))
}
```

Use generated neutral project names (`Sample Current`, `Sample Template`, `Sample Gold`), stable synthetic UUIDs, neutral `2001-01-01` dates, and `file:///tmp/fcpxml-subtitle-aligner-fixtures/media-N.mov` references. Remove the Desktop-source comparison test; replace it with checked-in SHA-256 assertions for each anonymized XML file. Keep the structural title/background/style content needed by the existing 17-title and gold-geometry assertions.

Create `.gitignore` with at least:

```gitignore
.build/
.swiftpm/
.DS_Store
DerivedData/
dist/
outputs/
*.xcuserstate
*.xccheckout
```

Create the standard MIT license naming `2026 superchaospc`.

- [ ] **Step 4: Run privacy and existing suites and verify GREEN**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test -c debug -Xswiftc -warnings-as-errors
```

Expected: all existing tests plus `RepositoryPrivacyTests` pass with zero warnings.

- [ ] **Step 5: Commit the privacy boundary**

```bash
git add .gitignore LICENSE Tests
git commit -m "test: anonymize fixtures and guard repository privacy"
```

### Task 2: Add the CLI argument contract

**Files:**
- Modify: `Package.swift`
- Create: `Sources/FCPXMLAlignerCLI/CLIArguments.swift`
- Create: `Tests/FCPXMLAlignerCLITests/CLIArgumentsTests.swift`

- [ ] **Step 1: Declare a CLI target and write failing parser tests**

Add products and targets:

```swift
.executable(name: "fcpxml-aligner", targets: ["FCPXMLAlignerCLI"]),
// ...
.executableTarget(name: "FCPXMLAlignerCLI", dependencies: ["FCPXMLAlignerCore"]),
.testTarget(name: "FCPXMLAlignerCLITests", dependencies: ["FCPXMLAlignerCLI", "FCPXMLAlignerCore"]),
```

Define tests for this public API:

```swift
let parsed = try CLIArguments.parse([
    "input.fcpxmld", "--action-size", "18", "--ingredient-size", "16",
    "--minimum-size", "12", "--safe-width", "0.88", "--no-auto-shrink", "--json"
])
XCTAssertEqual(parsed.input.path, URL(fileURLWithPath: "input.fcpxmld").standardizedFileURL.path)
XCTAssertEqual(parsed.settings.actionBaseSize, 18)
XCTAssertEqual(parsed.settings.ingredientBaseSize, 16)
XCTAssertEqual(parsed.settings.minimumSize, 12)
XCTAssertEqual(parsed.settings.safeWidthFraction, 0.88)
XCTAssertFalse(parsed.settings.autoShrink)
XCTAssertTrue(parsed.json)
```

Also test defaults, `--auto-shrink`, `--help`, `--version`, missing input, duplicate input, unknown options, non-numeric values, non-positive sizes, `minimumSize` greater than both base sizes, and safe width outside `0.1...1.0`.

- [ ] **Step 2: Run parser tests and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CLIArgumentsTests
```

Expected: build/test failure because `CLIArguments` does not exist.

- [ ] **Step 3: Implement minimal parser**

Use this interface:

```swift
public struct CLIArguments: Equatable, Sendable {
    public enum Mode: Equatable, Sendable { case align, help, version }
    public let mode: Mode
    public let input: URL?
    public let settings: AlignmentSettings
    public let json: Bool

    public static func parse(_ arguments: [String]) throws -> CLIArguments
}

public enum CLIArgumentError: Error, LocalizedError, Equatable {
    case missingInput
    case unexpectedArgument(String)
    case missingValue(String)
    case invalidNumber(option: String, value: String)
    case invalidSettings(String)
}
```

Start from `AlignmentSettings.templateDefaults`, consume one token at a time, validate the complete settings using the same range rules as the App form, and return absolute standardized input URLs.

- [ ] **Step 4: Run parser tests and verify GREEN**

Run the Step 2 command. Expected: all `CLIArgumentsTests` pass.

- [ ] **Step 5: Commit CLI parsing**

```bash
git add Package.swift Sources/FCPXMLAlignerCLI/CLIArguments.swift Tests/FCPXMLAlignerCLITests/CLIArgumentsTests.swift
git commit -m "feat: add CLI argument contract"
```

### Task 3: Add testable CLI execution and machine-readable output

**Files:**
- Create: `Sources/FCPXMLAlignerCLI/CLIApplication.swift`
- Create: `Sources/FCPXMLAlignerCLI/Main.swift`
- Create: `Tests/FCPXMLAlignerCLITests/CLIApplicationTests.swift`

- [ ] **Step 1: Write failing application tests**

Test a copied anonymized `.fcpxmld` fixture with:

```swift
let result = CLIApplication().run(arguments: [input.path, "--json"])
XCTAssertEqual(result.exitCode, 0)
let payload = try JSONDecoder().decode(CLISuccessPayload.self, from: Data(result.stdout.utf8))
XCTAssertTrue(FileManager.default.fileExists(atPath: payload.outputPath))
XCTAssertTrue(FileManager.default.fileExists(atPath: payload.reportPath))
XCTAssertEqual(try sha256(input), originalHash)
```

Add tests for `.fcpxml`, help, version `1.0.0`, invalid extension, missing path, malformed XML, and human-readable output. Assert failures use non-zero exit status, empty stdout, and actionable stderr.

- [ ] **Step 2: Run execution tests and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter CLIApplicationTests
```

Expected: build/test failure because `CLIApplication` and payloads do not exist.

- [ ] **Step 3: Implement the application layer**

Use these contracts:

```swift
public struct CLIExecutionResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

public struct CLISuccessPayload: Codable, Equatable, Sendable {
    public let outputPath: String
    public let reportPath: String
    public let changedTitles: Int
    public let skippedTitles: Int
}

public struct CLIApplication {
    public static let version = "1.0.0"
    public func run(arguments: [String]) -> CLIExecutionResult
}
```

For align mode, call `OutputWriter().process(input:settings:)`, serialize `CLISuccessPayload` with sorted JSON keys when `--json` is set, and otherwise print labeled absolute paths and change totals. Map argument errors to exit `64`, unreadable/invalid input to `66`, transform/validation failures to `65`, and success/help/version to `0`.

Keep `Main.swift` to:

```swift
import Darwin
import Foundation

let result = CLIApplication().run(arguments: Array(CommandLine.arguments.dropFirst()))
if !result.stdout.isEmpty { FileHandle.standardOutput.write(Data(result.stdout.utf8)) }
if !result.stderr.isEmpty { FileHandle.standardError.write(Data(result.stderr.utf8)) }
exit(result.exitCode)
```

- [ ] **Step 4: Run CLI and full tests and verify GREEN**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test -c debug -Xswiftc -warnings-as-errors
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run fcpxml-aligner --help
```

Expected: tests pass and help documents every supported flag and non-overwrite behavior.

- [ ] **Step 5: Commit the CLI**

```bash
git add Sources/FCPXMLAlignerCLI Tests/FCPXMLAlignerCLITests
git commit -m "feat: add automation CLI"
```

### Task 4: Create and test the canonical cross-agent Skill

**Files:**
- Create: `skills/fcpxml-subtitle-aligner/SKILL.md`
- Create: `skills/fcpxml-subtitle-aligner/agents/openai.yaml`
- Create: `skills/fcpxml-subtitle-aligner/assets/icon-400.png`
- Create: `skills/fcpxml-subtitle-aligner/assets/logo.svg`
- Create: `Tests/FCPXMLSubtitleAlignerAppTests/SkillPackagingTests.swift`

- [ ] **Step 1: Write failing Skill structure and content tests**

Assert the Skill:

```swift
XCTAssertTrue(skill.contains("name: fcpxml-subtitle-aligner"))
XCTAssertTrue(skill.contains("description:"))
XCTAssertTrue(skill.contains("fcpxml-aligner"))
XCTAssertTrue(skill.contains("--json"))
XCTAssertTrue(skill.contains("Never overwrite"))
XCTAssertTrue(skill.contains("verify"))
XCTAssertTrue(skill.contains("Never include local production metadata"))
```

Parse `agents/openai.yaml` as text and assert quoted string values, `display_name`, a 25–64 character `short_description`, icons that exist, `brand_color`, and a `default_prompt` that explicitly includes `$fcpxml-subtitle-aligner`.

- [ ] **Step 2: Run Skill tests and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SkillPackagingTests
```

Expected: FAIL because the Skill directory does not exist.

- [ ] **Step 3: Scaffold and author the Skill**

Use the skill-creator scaffold when available, then keep frontmatter limited to:

```yaml
---
name: fcpxml-subtitle-aligner
description: Use when a user wants to align, center, resize, or normalize Final Cut Pro title and ingredient subtitles in an .fcpxml file or .fcpxmld bundle while preserving the original project.
---
```

The body must instruct the agent to locate the input, fingerprint it, run `fcpxml-aligner <path> --json` with explicit optional sizing flags, verify the input hash remains unchanged, parse the JSON, confirm output/report existence, and return absolute paths. Include controlled handling for missing executable, invalid XML, missing fonts, and validation errors. Do not repeat README-level background or include user-specific examples.

Create `openai.yaml`:

```yaml
interface:
  display_name: "FCPXML Subtitle Aligner"
  short_description: "Align Final Cut Pro subtitles safely and consistently"
  icon_small: "./assets/icon-400.png"
  icon_large: "./assets/logo.svg"
  brand_color: "#7A1F0E"
  default_prompt: "Use $fcpxml-subtitle-aligner to align this Final Cut Pro subtitle project without modifying the original."
```

- [ ] **Step 4: Run Skill tests and verify GREEN**

Run the Step 2 command. Expected: all Skill packaging tests pass.

- [ ] **Step 5: Commit the Skill**

```bash
git add skills Tests/FCPXMLSubtitleAlignerAppTests/SkillPackagingTests.swift
git commit -m "feat: add Codex and Claude Code skill"
```

### Task 5: Add an idempotent multi-agent Skill installer

**Files:**
- Create: `scripts/install_skill.sh`
- Modify: `Tests/FCPXMLSubtitleAlignerAppTests/SkillPackagingTests.swift`

- [ ] **Step 1: Write failing isolated-home installer tests**

Run the script with an explicit test-only home and assert all destinations resolve to the canonical Skill:

```swift
let result = try run("/bin/bash", [
    script.path, "--source", skill.path, "--home", temporaryHome.path
])
XCTAssertEqual(result.status, 0, result.output)
for relative in [
    ".codex/skills/fcpxml-subtitle-aligner",
    ".agents/skills/fcpxml-subtitle-aligner",
    ".claude/skills/fcpxml-subtitle-aligner"
] {
    XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryHome.appending(path: relative).appending(path: "SKILL.md").path))
}
```

Test a second run, replacement of a tool-owned link, and refusal to replace an unrelated existing directory.

- [ ] **Step 2: Run installer tests and verify RED**

Run the Skill test command. Expected: FAIL because `install_skill.sh` is absent.

- [ ] **Step 3: Implement safe installation**

The Bash script uses `set -euo pipefail`, resolves the source directory, validates `SKILL.md`, creates each parent directory, and installs a relative or absolute symlink only when the destination is absent or already points to this source. It must fail without modifying an unrelated occupied destination. `--home` is a documented test/install override and never defaults to an unresolved variable; the normal default is `${HOME:?}` read-only.

- [ ] **Step 4: Run installer tests twice and verify GREEN**

Run the Step 2 command twice. Expected: both runs pass, demonstrating idempotence.

- [ ] **Step 5: Commit the installer**

```bash
git add scripts/install_skill.sh Tests/FCPXMLSubtitleAlignerAppTests/SkillPackagingTests.swift
git commit -m "feat: install skill for Codex and Claude Code"
```

### Task 6: Add public documentation, changelog, and CI

**Files:**
- Create: `README.md`
- Create: `CHANGELOG.md`
- Create: `.github/workflows/ci.yml`
- Modify: `Tests/FCPXMLSubtitleAlignerAppTests/PackagingTests.swift`

- [ ] **Step 1: Write failing documentation and CI contract tests**

Assert README badges reference `superchaospc/fcpxml-subtitle-aligner`, README documents App/CLI/Skill installation, both supported extensions, non-overwrite behavior, CLI flags, uninstall, privacy, and troubleshooting. Assert CI contains `runs-on: macos-14`, Debug and Release test commands, and `-warnings-as-errors`.

- [ ] **Step 2: Run packaging tests and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PackagingTests
```

Expected: FAIL because README, changelog, and CI are absent.

- [ ] **Step 3: Write the public files**

README badge set:

```markdown
[![Release](https://img.shields.io/github/v/release/superchaospc/fcpxml-subtitle-aligner)](https://github.com/superchaospc/fcpxml-subtitle-aligner/releases/latest)
[![CI](https://github.com/superchaospc/fcpxml-subtitle-aligner/actions/workflows/ci.yml/badge.svg)](https://github.com/superchaospc/fcpxml-subtitle-aligner/actions/workflows/ci.yml)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138)
[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
```

CI checks out source, selects Xcode, runs clean Debug and Release Swift tests with warnings-as-errors, builds universal App and CLI artifacts, and verifies both architectures with `lipo`.

`CHANGELOG.md` starts with `## [1.0.0] - 2026-08-21` and lists the App, CLI, cross-agent Skill, safe output transaction, adjustable typography, anonymous fixtures, and CI.

- [ ] **Step 4: Run packaging and privacy tests and verify GREEN**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'PackagingTests|RepositoryPrivacyTests'
```

Expected: documentation, CI, and privacy tests pass.

- [ ] **Step 5: Commit public documentation and CI**

```bash
git add README.md CHANGELOG.md .github Tests/FCPXMLSubtitleAlignerAppTests/PackagingTests.swift
git commit -m "docs: add public guide and CI badges"
```

### Task 7: Build deterministic universal release assets

**Files:**
- Create: `scripts/build_release.sh`
- Modify: `scripts/build_app.sh`
- Create: `Tests/FCPXMLSubtitleAlignerAppTests/ReleasePackagingTests.swift`

- [ ] **Step 1: Write failing isolated release packaging tests**

Assert `build_release.sh --version v1.0.0 --output-dir <temporary>` rejects invalid versions and occupied unowned output, then produces exactly:

```text
FCPXML-Subtitle-Aligner-v1.0.0-macos-universal.zip
fcpxml-aligner-v1.0.0-macos-universal.tar.gz
fcpxml-subtitle-aligner-skill-v1.0.0.zip
SHA256SUMS
```

Verify checksums with `shasum -a 256 -c SHA256SUMS`, inspect App/CLI archives, and run `lipo -verify_arch arm64 x86_64` on both executables.

- [ ] **Step 2: Run release packaging tests and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ReleasePackagingTests
```

Expected: FAIL because `build_release.sh` does not exist.

- [ ] **Step 3: Implement release packaging**

The script validates `^v[0-9]+\.[0-9]+\.[0-9]+$`, creates an owned `mktemp -d` workspace under the requested output parent, runs clean Release builds for `arm64` and `x86_64`, uses `lipo -create` for the CLI when SwiftPM does not emit one fat binary, delegates App bundle assembly/signing to the existing safe packaging logic, archives with `ditto`/`tar`, creates the Skill archive with the Skill directory as its root, writes sorted SHA-256 lines, verifies every archive/checksum, then publishes the complete asset set into an empty destination. A trap removes only the inode-owned workspace.

Expose a release-output option in `build_app.sh` only if its canonical destination is the release script's owned workspace; preserve all existing refusal and rollback behavior.

- [ ] **Step 4: Run release tests and inspect assets**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ReleasePackagingTests
scripts/build_release.sh --version v1.0.0 --output-dir dist/v1.0.0
shasum -a 256 -c dist/v1.0.0/SHA256SUMS
```

Expected: tests pass, four assets exist, and every checksum reports `OK`.

- [ ] **Step 5: Commit release tooling**

```bash
git add scripts Tests/FCPXMLSubtitleAlignerAppTests/ReleasePackagingTests.swift
git commit -m "build: package universal v1 release assets"
```

### Task 8: Validate Skill triggering and close instruction gaps

**Files:**
- Modify if required: `skills/fcpxml-subtitle-aligner/SKILL.md`
- Modify if required: `skills/fcpxml-subtitle-aligner/agents/openai.yaml`
- Modify if required: `Tests/FCPXMLSubtitleAlignerAppTests/SkillPackagingTests.swift`

- [ ] **Step 1: Run independent baseline trigger scenarios without relying on the Skill**

Use fresh subagents for at least these prompts: direct `.fcpxmld` alignment, adjustable font sizes, malformed input, missing CLI, and a nearby non-trigger request such as editing an MP4 without FCPXML. Record whether each agent invokes the Skill and follows source-preservation checks.

- [ ] **Step 2: Run the same scenarios with the Skill available**

Expected: applicable prompts trigger the Skill and use CLI/verification; the MP4-only request does not trigger it; failure cases stop with actionable guidance.

- [ ] **Step 3: Add failing regression tests for any observed gap**

For each gap, first encode the missing phrase, command, or safety requirement in `SkillPackagingTests`, run it to see RED, then minimally revise `SKILL.md` or metadata.

- [ ] **Step 4: Re-run Skill tests and scenarios**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SkillPackagingTests
```

Expected: tests pass and all positive/negative scenarios behave as designed.

- [ ] **Step 5: Commit Skill hardening if changed**

```bash
git add skills Tests/FCPXMLSubtitleAlignerAppTests/SkillPackagingTests.swift
git commit -m "test: harden cross-agent skill triggers"
```

### Task 9: Perform the complete release verification

**Files:**
- Modify only when a test-first regression fix is required.

- [ ] **Step 1: Confirm a clean tracked tree and scan publishable content**

Run:

```bash
git status --short
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RepositoryPrivacyTests
```

Expected: no uncommitted tracked changes and no production metadata in the tracked tree.

- [ ] **Step 2: Run clean Debug and Release tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift package clean
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test -c debug -Xswiftc -warnings-as-errors
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift package clean
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test -c release -Xswiftc -warnings-as-errors
```

Expected: every test passes with zero warnings.

- [ ] **Step 3: Build and smoke-test final assets**

```bash
scripts/build_release.sh --version v1.0.0 --output-dir dist/v1.0.0
shasum -a 256 -c dist/v1.0.0/SHA256SUMS
```

Extract the CLI into a temporary directory, run `--version`, `--help`, and a real anonymized fixture with `--json`; reparse the resulting output and verify the source SHA is unchanged.

- [ ] **Step 4: Commit any final release-only metadata**

```bash
git add -A
git commit -m "chore: prepare v1.0.0 release"
```

Skip this commit if the tree is already clean.

### Task 10: Create the public GitHub repository, tag, and Release

**Files:**
- No source changes expected.

- [ ] **Step 1: Reconfirm authentication and repository name availability**

```bash
gh auth status
gh repo view superchaospc/fcpxml-subtitle-aligner
```

Expected: authentication succeeds; repository lookup returns not found before creation.

- [ ] **Step 2: Create and push the public repository**

```bash
gh repo create superchaospc/fcpxml-subtitle-aligner --public --source=. --remote=origin --push --description "Align and resize Final Cut Pro subtitles safely via macOS App, CLI, Codex, and Claude Code."
```

Expected: `origin` points to the new repository and `main` is pushed.

- [ ] **Step 3: Confirm GitHub Actions succeeds**

```bash
gh run list --workflow ci.yml --limit 1
gh run watch --exit-status
```

Expected: the release commit's CI run completes successfully.

- [ ] **Step 4: Create and push the annotated release tag**

```bash
git tag -a v1.0.0 -m "FCPXML Subtitle Aligner v1.0.0"
git push origin v1.0.0
```

Expected: local and remote tag resolve to the verified release commit.

- [ ] **Step 5: Create the GitHub Release with verified assets**

```bash
gh release create v1.0.0 dist/v1.0.0/* \
  --repo superchaospc/fcpxml-subtitle-aligner \
  --title "FCPXML Subtitle Aligner v1.0.0" \
  --notes-file CHANGELOG.md \
  --verify-tag
```

Expected: a published, non-draft Release containing exactly the four planned assets.

- [ ] **Step 6: Verify the public handoff**

```bash
gh repo view superchaospc/fcpxml-subtitle-aligner --web=false
gh release view v1.0.0 --repo superchaospc/fcpxml-subtitle-aligner
```

Open the README and badge targets, download the Skill and CLI archives to a temporary directory, verify `SHA256SUMS`, and run the documented install command. Report the repository URL, Release URL, tag, test totals, and asset names to the user.
