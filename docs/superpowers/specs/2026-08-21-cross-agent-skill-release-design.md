# FCPXML Subtitle Aligner: Cross-Agent Skill and v1.0.0 Release Design

Date: 2026-08-21
Status: Approved in conversation; pending written-spec review

## Objective

Turn the existing FCPXML Subtitle Aligner into a public, reusable GitHub project that can be operated directly by Codex and Claude Code, while retaining the macOS drag-and-drop application. Publish the first stable release as `v1.0.0` under the MIT License.

## Product boundaries

- Accept Final Cut Pro `.fcpxml` files and `.fcpxmld` bundles.
- Never overwrite or mutate the input project.
- Produce an aligned sibling project and a UTF-8 change report.
- Preserve the existing adjustable action-title size, ingredient-title size, minimum size, and auto-shrink behavior.
- Preserve the current alignment goal: center the background box and keep equal minimum left/right text padding.
- Run locally. Do not upload FCPXML, videos, fonts, or local paths to an external service.
- Publish only anonymized test fixtures. Real project names, dates, UUIDs, volume paths, and media metadata must not enter the repository or release artifacts.

## Chosen architecture

Use one repository, `superchaospc/fcpxml-subtitle-aligner`, as the source of truth for all components and versions.

### Swift components

1. `FCPXMLAlignerCore`
   - Retains parsing, matching, typography, transformation, invariant validation, safe output staging, and report generation.
   - Remains shared by the GUI and CLI.

2. `fcpxml-aligner` CLI
   - Provides a stable automation entry point for Codex, Claude Code, shell users, and tests.
   - Supports one `.fcpxml` or `.fcpxmld` input at a time.
   - Exposes action size, ingredient size, minimum size, and auto-shrink options.
   - Prints final output and report paths in a machine-readable, documented form.
   - Uses non-zero exit codes and actionable stderr messages for invalid input, missing fonts, parse failures, transform failures, or validation failures.

3. `FCPXML Subtitle Aligner.app`
   - Keeps the current Finder drag/open workflow and settings dialog.
   - Calls the same core implementation as the CLI.

### Skill component

The canonical Skill lives at `skills/fcpxml-subtitle-aligner/` and contains:

- `SKILL.md` with trigger conditions, safe workflow, command examples, error handling, and verification requirements.
- Minimal scripts or references only where they make execution more reliable than prose.
- Agent metadata required by Codex packaging conventions.

The same Skill source is installed for both agent families. The installer creates links or copies, without maintaining divergent instructions, at:

- `~/.codex/skills/fcpxml-subtitle-aligner`
- `~/.agents/skills/fcpxml-subtitle-aligner`
- `~/.claude/skills/fcpxml-subtitle-aligner`

The Skill prefers an installed `fcpxml-aligner` executable. If it is absent, it directs the agent to install the matching GitHub Release asset or build locally. It never silently substitutes a remote service.

## Agent workflow

When asked to align or normalize Final Cut Pro subtitles, the Skill directs the agent to:

1. Resolve and validate the input path and extension.
2. Confirm the input is readable and record its fingerprint.
3. Invoke `fcpxml-aligner` with explicit settings or documented defaults.
4. Verify the original fingerprint is unchanged.
5. Verify the output can be parsed and the report records the intended changes.
6. Return absolute paths to the new project and report.

Missing fonts, malformed projects, unmatched title/background pairs, and validation failures are explicit controlled outcomes. The tool must not claim success or deliver a partial project when final validation fails.

## Repository layout

```text
fcpxml-subtitle-aligner/
├── .github/workflows/ci.yml
├── Sources/
│   ├── FCPXMLAlignerCore/
│   ├── FCPXMLAlignerCLI/
│   └── FCPXMLSubtitleAlignerApp/
├── Tests/
│   ├── FCPXMLAlignerCoreTests/
│   ├── FCPXMLAlignerCLITests/
│   └── FCPXMLSubtitleAlignerAppTests/
├── skills/fcpxml-subtitle-aligner/
├── scripts/
│   ├── build_app.sh
│   ├── build_release.sh
│   └── install_skill.sh
├── docs/superpowers/specs/
├── README.md
├── LICENSE
└── Package.swift
```

## Documentation

The README will provide concise Chinese and English guidance, with Chinese first. It will include:

- What the tool changes and what it preserves.
- App, CLI, and Skill installation.
- Finder drag-and-drop usage.
- CLI examples and option reference.
- Codex and Claude Code invocation examples.
- Output naming and report behavior.
- Font and malformed-project troubleshooting.
- Uninstall instructions.
- Privacy and non-destructive guarantees.

The header will use badges for the latest GitHub Release, CI, macOS support, Swift, and MIT License. Badge targets must resolve to this repository; the CI badge is backed by a real workflow rather than a decorative static claim.

## Privacy and fixtures

All existing real-world fixture bundles are replaced before the first public commit by minimal synthetic fixtures. The replacements retain structural cases needed for layout, style, matching, rollback, and bundle/file tests, but use generic project/title/media names, generated identifiers, neutral dates, and non-personal synthetic media URLs. The corpus deliberately has 17 title cases: fifteen actions (including the `DISH UP` hero), one multi-line ingredient title, and one two-line closing. The template retains multi-run yellow/italic ingredient emphasis; the gold fixture is a generated transformed snapshot used alongside independent calibration, style, and geometry assertions.

An automated repository privacy test scans every tracked regular file, including documentation, for runtime-constructed private token fragments in raw UTF-8/UTF-16 bytes and decoded bookmark payloads. It also rejects bookmark elements in public fixtures and validates their synthetic metadata schema.

Build directories, editor state, signing artifacts, Finder metadata, and local release output are excluded by `.gitignore`.

## Test and verification strategy

Local and CI verification covers:

- Debug and Release Swift tests with warnings treated as errors.
- `.fcpxml` file and `.fcpxmld` bundle inputs.
- Centered background boxes and equal minimum left/right text padding.
- Adjustable font sizes, minimum size, and auto-shrink.
- Preservation of emphasis and supported style attributes.
- Source immutability, parseable output, invariant validation, rollback, and collision-safe naming.
- CLI parsing, exit status, stdout/stderr contract, and failure modes.
- Skill structure, metadata, command examples, and installer behavior in temporary homes.
- Fixture anonymization and absence of private paths.
- Universal `arm64` and `x86_64` architecture checks for macOS release executables.

GitHub Actions runs on macOS and executes the test suite. Release creation happens only after the same verification passes locally and on the release commit.

## Release design

The initial public version is `v1.0.0`. Its GitHub Release contains:

- `FCPXML-Subtitle-Aligner-v1.0.0-macos-universal.zip`
- `fcpxml-aligner-v1.0.0-macos-universal.tar.gz`
- `fcpxml-subtitle-aligner-skill-v1.0.0.zip`
- `SHA256SUMS`

The release notes summarize capabilities, supported macOS version, installation, local-only processing, known font requirements, and checksums. Assets are produced by a deterministic release script from a clean source tree. The Git tag and GitHub Release both use `v1.0.0`.

## GitHub publication sequence

1. Initialize local Git history and commit this approved design.
2. Implement the CLI, Skill, anonymized fixtures, documentation, CI, license, and release tooling with tests.
3. Run the complete local verification matrix and inspect packaged assets.
4. Create the public GitHub repository under `superchaospc`.
5. Push the verified default branch.
6. Confirm GitHub Actions succeeds.
7. Create and push annotated tag `v1.0.0`.
8. Create the GitHub Release and upload all verified assets and checksums.
9. Confirm badges, release links, downloadable assets, and installation instructions work from the public repository.

## Rejected alternatives

- Embedding a precompiled binary inside the Skill was rejected because binaries and instructions can drift and repository reviews become less transparent.
- Splitting the App and Skill into separate repositories was rejected because it duplicates versioning, testing, tagging, and compatibility maintenance without a current product need.

## Success criteria

The work is complete when a new user can discover the public repository, install either the App or CLI, install one shared Skill for Codex and Claude Code, safely transform an anonymized sample, verify the report, and reproduce the published checksums from the tagged source without exposing the original user's production metadata.
