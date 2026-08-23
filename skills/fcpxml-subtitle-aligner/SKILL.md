---
name: fcpxml-subtitle-aligner
description: Use when you need to align, center, resize, or normalize Final Cut Pro title or ingredient subtitles in .fcpxml or .fcpxmld files while preserving original source files.
---

# FCPXML Subtitle Aligner

Align title and ingredient subtitles with the local `fcpxml-aligner` CLI. Always produce a new output and report while preserving the input.

## Workflow

1. Locate the CLI with `command -v fcpxml-aligner`. If unavailable and this repository is available, run the local build `swift build -c release --product fcpxml-aligner` and use the resulting executable. When invoked outside the repository, resolve the caller-supplied repository root and check its repo-local `.build/<triple>/<configuration>/fcpxml-aligner` path (for example, `.build/arm64-apple-macosx/release/fcpxml-aligner`); never hardcode a user path. If no local binary is available, use the pinned GitHub Release fallback only when network access and download are explicitly authorized: canonical repository `https://github.com/superchaospc/fcpxml-subtitle-aligner`, tag `v1.0.0`, exact asset `fcpxml-aligner-v1.0.0-macos-universal.tar.gz`, and exact companion `https://github.com/superchaospc/fcpxml-subtitle-aligner/releases/download/v1.0.0/SHA256SUMS`. Require the matching expected filename entry in SHA256SUMS; abort if the release, asset, entry, or checksum is unavailable or mismatched. Extract in a temporary directory and use only the expected fcpxml-aligner binary. Do not execute downloads automatically unless agent or user scope permits. A missing binary is a controlled error.

2. Run a strict preflight before fingerprint and before executing the CLI. Resolve the input to an absolute path, require that it exists and is readable, and require an extension exactly `.fcpxml` or `.fcpxmld`. A .fcpxml is a file and must be readable; a .fcpxmld is a directory and must be readable, and Info.fcpxml exists and is readable. Verify the readable Info.fcpxml file before continuing. Reject every other shape before hashing or execution. For a valid bundle, record a sorted inventory of relative paths and byte sizes; do not treat the bundle as only an opaque directory.

3. Capture a source fingerprint before processing. For a `.fcpxml` file, keep its single SHA-256 digest. For a `.fcpxmld` bundle, fingerprint every regular file, not only `Info.fcpxml`: record each file's normalized relative path, byte size, and SHA-256 digest in deterministic sorted relative-path order. Use a filename-safe local enumeration such as `find "$input" -type f -print0 | sort -z` and consume it with `xargs -0` or a NUL-delimited `while` loop; never split a pathname on whitespace or newlines. Keep the full per-file digest inventory so later verification detects added, removed, renamed, or modified files. Confirm the source remains unchanged afterward.

4. Never overwrite the source. Run the CLI with an absolute input and JSON output, including only the explicitly requested optional switches:

   ```text
   fcpxml-aligner --json [--action-size N] [--ingredient-size N] [--minimum-size N] [--safe-width R] [--auto-shrink|--no-auto-shrink] /absolute/input.fcpxml
   ```

5. Parse the single JSON object from stdout. Require a successful exit status, absolute `outputPath` and `reportPath`, and existing output/report files. Verify the report contains the exact line `Structural validation: PASS`, records success, and recheck the complete source fingerprint: for `.fcpxml`, the single file digest; for `.fcpxmld`, the full sorted per-file path/size/digest inventory covering each regular file. Abort success if any inventory entry differs or if a file was added, removed, renamed, or modified.

6. Return the absolute output and report paths, plus the reported changed/skipped counts. Keep processing local and do not send project files elsewhere or include user-specific paths in examples.

## Controlled errors

Stop with a clear actionable error for a missing binary, unsupported or invalid XML, missing font, or validation failure. Do not publish partial output as successful; retain the untouched source and include stderr or the validation detail in the response.
