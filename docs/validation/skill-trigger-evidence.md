# Cross-agent Skill trigger evidence

Date of fresh-agent run: 2026-08-23

This is a sanitized record of packaging and path-compatibility checks. Paths below are placeholders, not real fixtures or user directories. The observations are limited to the checks listed; they do not claim a live model trigger where one was not executed.

## Scenario matrix

| Scenario | Sanitized exact prompt | Observed result | Acceptance |
| --- | --- | --- | --- |
| Baseline without Skill | `Align the ingredient subtitles in /workspace/sample.fcpxmld.` (Skill unavailable) | No Skill was available to trigger; this is the control condition. | Baseline recorded before installation. |
| Positive `.fcpxmld` alignment | `Use the FCPXML subtitle aligner to align this .fcpxmld bundle. Set action size to 18 and ingredient size to 16; preserve the source.` | The `.fcpxmld` trigger matched with `action18` and `ingredient16`. Preflight ran before execution, including readable `Info.fcpxml` checks. The exact JSON CLI was `fcpxml-aligner --json --action-size 18 --ingredient-size 16 /workspace/sample.fcpxmld`. The result required `Structural validation: PASS`, a full source fingerprint, and absolute output/report paths. | Trigger terms, preflight ordering, JSON output verification, full inventory, and absolute outputs were all present in the packaged Skill. |
| Malformed input | `Align the subtitles in /workspace/malformed.fcpxmld and preserve the source.` | Controlled failure for malformed input; no partial output was reported as successful. | Error detail was retained and the source remained untouched. |
| Missing CLI | `Align /workspace/sample.fcpxml with the FCPXML subtitle aligner.` (CLI unavailable) | Controlled missing-binary path. The fallback was only described with explicit network authorization required before any download: pinned repository `superchaospc/fcpxml-subtitle-aligner`, tag `v1.0.0`, asset `fcpxml-aligner-v1.0.0-macos-universal.tar.gz`, companion `SHA256SUMS`, and matching SHA256 entry. No download was automatic. | Release, asset, expected filename, and SHA256 checks were required before use. |
| MP4-only input | `Align the subtitles in /workspace/video.mp4.` | Did not trigger the Skill. | The description excludes MP4-only and generic subtitle requests. |
| Canonical installation paths | `Resolve the installed FCPXML subtitle aligner Skill.` | The canonical install locations `.codex/skills/fcpxml-subtitle-aligner`, `.agents/skills/fcpxml-subtitle-aligner`, and `.claude/skills/fcpxml-subtitle-aligner` each resolved to the same Skill source. | All three canonical locations were checked for the same target and readable `SKILL.md`. |

## Explicit limitation

Claude Code CLI 2.1.215 was installed, but its reported state was `loggedIn: false` with `authMethod none`. Therefore a live Claude trigger was **NOT executed**, and **no login attempted**. Only packaging/path compatibility was validated. This record makes no stronger claim than that evidence supports.

No personal absolute paths, usernames, real fixture names, or upload steps are included. All processing and checks are local.
