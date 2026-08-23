# FCPXML Subtitle Aligner

[![Latest Release](https://img.shields.io/github/v/release/superchaospc/fcpxml-subtitle-aligner?display_name=tag&sort=semver)](https://github.com/superchaospc/fcpxml-subtitle-aligner/releases/latest)
[![CI](https://github.com/superchaospc/fcpxml-subtitle-aligner/actions/workflows/ci.yml/badge.svg)](https://github.com/superchaospc/fcpxml-subtitle-aligner/actions/workflows/ci.yml)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111827)](https://github.com/superchaospc/fcpxml-subtitle-aligner#requirements)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138)](https://github.com/superchaospc/fcpxml-subtitle-aligner#source-build)
[![License: MIT](https://img.shields.io/badge/License-MIT-2ea44f)](https://github.com/superchaospc/fcpxml-subtitle-aligner/blob/main/LICENSE)

面向 Final Cut Pro 导出文件的本地字幕对齐工具。它把每个 Basic Title 的背景居中，并让文字左右文本边距的最小安全值相等；同时按设定调整动作字幕、食材字幕的字号，必要时自动缩小文字。原始导出文件永远保留，不覆盖源文件。

This local-first tool aligns Final Cut Pro title subtitles with their custom backgrounds, equalizes the minimum left/right text margins, and adjusts sizes and auto-shrink behavior. It preserves the original export; never overwrite the source.

## 功能与要求

- 支持 `.fcpxml` 文件和 `.fcpxmld` bundle（bundle 内须有 `Info.fcpxml`）。
- macOS 13+、Swift 6；输入应来自 Final Cut Pro 的 XML 导出。
- 图形 App：打开 App 后，将一个 `.fcpxml` 或 `.fcpxmld` 拖入窗口即可处理；输出在输入旁边生成。
- 命令行和 Skill 均仅在本机读取、处理和写入文件，不上传项目或字幕内容。

## App

从 [Latest Release](https://github.com/superchaospc/fcpxml-subtitle-aligner/releases/latest) 下载并打开 App，把 Final Cut Pro 导出的 `.fcpxml` 或 `.fcpxmld` 拖放到 App 上。App 会在同目录生成新的输出文件和报告文件，并保留原文件；它不会覆盖源文件。若需要从源码构建，请参见 [source build](https://github.com/superchaospc/fcpxml-subtitle-aligner#source-build)。

从源码构建拖放 App（build the App）：

```sh
bash scripts/build_app.sh
```

脚本需要完整 Xcode，会构建并校验 universal App；默认输出目录是仓库上一级的 `outputs/FCPXML Subtitle Aligner.app`（即 `../outputs/` 下的 `FCPXML Subtitle Aligner.app`）。

### 当前发布包的签名与首次打开

当前 release 是 **ad-hoc（临时签名）且 unnotarized（未经公证）** 的 developer build，不是带 Developer ID 的受信任发布包。Gatekeeper 首次阻止时，请只为这个 App 使用系统的明确确认：在 Finder 中 **右键** App 并选择“打开”，再确认“打开”；若仍被阻止，请到“**系统设置** → 隐私与安全性”，为该 App 选择“仍要打开”，然后重新打开它。不要关闭 Gatekeeper；不要用会影响其他文件的绕过命令。

This current release is an **ad-hoc signed, unnotarized developer build**, not a Developer ID-trusted distribution. If Gatekeeper blocks its first launch, use the per-app system workflow: **Right-click** the App in Finder, choose **Open**, then confirm Open. If it remains blocked, go to **System Settings** → Privacy & Security, choose Open Anyway for this App, and open it again. Do not disable Gatekeeper or use a blanket workaround that affects other files.

## CLI

### 安装

Release 提供 universal macOS 二进制；下载后把 `fcpxml-aligner` 放入 `PATH`。也可以从源码构建：

```sh
swift build -c release --product fcpxml-aligner
bin_dir="$(swift build -c release --show-bin-path)"
install -m 755 "$bin_dir/fcpxml-aligner" /usr/local/bin/fcpxml-aligner
```

不同 SwiftPM 架构的构建目录可能不同；始终使用 `swift build -c release --show-bin-path` 返回的 bin directory，不要硬编码架构路径。

### 使用

```sh
fcpxml-aligner [options] <input.fcpxml|input.fcpxmld>
```

输入路径可以是文件或 bundle。CLI 会在旁边选择未占用的输出文件名：第一次为 `<name>-aligned.fcpxml` 或 `<name>-aligned.fcpxmld`，报告为 `<name>-aligned-report.txt`；如果名称已存在，会依次使用 `-aligned-2` 等。它不会覆盖输入或已有输出（never overwrite）。

可用选项：

| 选项 | 说明 |
| --- | --- |
| `--action-size <points>` | 动作标题基础字号，默认 `17` |
| `--ingredient-size <points>` | 食材标题基础字号，默认 `15` |
| `--minimum-size <points>` | 自动缩小的最小字号，默认 `13` |
| `--safe-width <fraction>` | 安全宽度比例，范围 `0.1...1.0`，默认 `0.9` |
| `--auto-shrink` | 开启自动缩小（默认） |
| `--no-auto-shrink` | 关闭自动缩小 |
| `--json` | 只输出一个 JSON result object |
| `--help`, `-h` | 显示帮助 |
| `--version` | 显示版本 |

例如：

```sh
fcpxml-aligner --json --action-size 18 --ingredient-size 15 \
  --minimum-size 12 --safe-width 0.9 --auto-shrink project.fcpxml
```

JSON 输出包含绝对路径和计数，字段为 `outputPath`、`reportPath`、`changedTitles`、`skippedTitles`。报告成功时会包含 `Structural validation: PASS`。如需脚本集成，先解析 JSON，再检查输出和报告确实存在。

## Codex / Claude Skill

安装脚本会把同一个 Skill 安全地链接到 Codex、通用 agents 和 Claude 的标准目录：

```sh
bash scripts/install_skill.sh
# 或指定安装位置
bash scripts/install_skill.sh --home "$HOME" --source skills/fcpxml-subtitle-aligner
```

在 Codex 中可以这样提示：

> 使用 `$fcpxml-subtitle-aligner` 处理这个 Final Cut Pro `.fcpxmld`，不要覆盖原文件，并返回输出和报告路径。

在 Claude Code 中可以这样提示：

> Use the `fcpxml-subtitle-aligner` skill to align this `.fcpxml`; keep the source unchanged and report the generated output.

Skill 支持 `.fcpxml` 和 `.fcpxmld`，会先检查路径、可读性、bundle 的 `Info.fcpxml` 和源指纹，再运行 CLI。网络不可用时不会自动下载；任何失败都应保留未修改的源文件。

卸载（uninstall）时只删除以下三个符号链接（不要删除源 Skill 目录）：

```sh
rm "$HOME/.codex/skills/fcpxml-subtitle-aligner"
rm "$HOME/.agents/skills/fcpxml-subtitle-aligner"
rm "$HOME/.claude/skills/fcpxml-subtitle-aligner"
```

## 故障排查

- **missing font / 找不到字体**：在 Final Cut Pro 或系统中安装导出 XML 引用的字体后重试；不要用替代字体静默继续。
- **malformed XML / XML 格式错误**：重新从 Final Cut Pro 导出，确认 `.fcpxml` 是完整文件，或 `.fcpxmld/Info.fcpxml` 存在且可读。
- **no match / 没有匹配标题**：确认项目使用 Basic Title 和对应的 Custom background，并检查字幕类型、名称及时间线内容。
- **输出已存在**：工具会选择新的 sibling 名称，不会覆盖已有文件；检查 `<name>-aligned*` 和报告文件。
- **验证失败**：查看报告中的 validation detail，保留原文件并修复输入后重新运行。

## 隐私与许可证

Privacy is local-only（隐私仅在本机）: this project does not upload files; all processing happens on your Mac. 请勿在 issue、日志或 prompt 中粘贴含个人信息的项目路径。代码以 [MIT License](https://github.com/superchaospc/fcpxml-subtitle-aligner/blob/main/LICENSE) 发布。

## Source build

源码和测试位于 [GitHub repository](https://github.com/superchaospc/fcpxml-subtitle-aligner)。在 macOS 13+ 上运行：

```sh
swift build -c release
swift test -c debug
```

发布版本请查看 [Release/latest](https://github.com/superchaospc/fcpxml-subtitle-aligner/releases/latest)。

## English

### Requirements

FCPXML Subtitle Aligner requires macOS 13 or later and Swift 6 for source builds. Export XML from Final Cut Pro. Both a `.fcpxml` file and a `.fcpxmld` bundle are supported; a bundle must contain a readable `Info.fcpxml`.

### App workflow

Download the [latest Release](https://github.com/superchaospc/fcpxml-subtitle-aligner/releases/latest), open the app, and drag and drop a Final Cut Pro `.fcpxml` or `.fcpxmld` onto it. The App writes a new output file and report next to the input, keeps the original unchanged, and never overwrites an existing artifact.

To build the drag-and-drop App from source, run `bash scripts/build_app.sh`. With full Xcode installed, it builds and validates the universal bundle at `../outputs/FCPXML Subtitle Aligner.app`, the default output directory relative to the repository.

### CLI install, build, and use

The Release includes a universal macOS CLI. Put `fcpxml-aligner` on your `PATH`, or build it from the [source](https://github.com/superchaospc/fcpxml-subtitle-aligner#source-build):

```sh
swift build -c release --product fcpxml-aligner
install -m 755 "$(swift build -c release --show-bin-path)/fcpxml-aligner" /usr/local/bin/fcpxml-aligner
```

Run `fcpxml-aligner [options] <input.fcpxml|input.fcpxmld>`. It creates unused sibling names such as `<name>-aligned.fcpxml` or `<name>-aligned.fcpxmld`, plus `<name>-aligned-report.txt`; existing outputs are never overwritten.

All CLI flags:

| Flag | Purpose |
| --- | --- |
| `--action-size <points>` | Base size for action titles; default `17` |
| `--ingredient-size <points>` | Base size for ingredient titles; default `15` |
| `--minimum-size <points>` | Smallest auto-shrink size; default `13` |
| `--safe-width <fraction>` | Safe-width fraction from `0.1` to `1.0`; default `0.9` |
| `--auto-shrink` | Enable automatic shrinking (default) |
| `--no-auto-shrink` | Disable automatic shrinking |
| `--json` | Emit one JSON result object |
| `--help`, `-h` | Print help |
| `--version` | Print the version |

With `--json`, stdout contains `outputPath`, `reportPath`, `changedTitles`, and `skippedTitles`. The paths are absolute; verify that both artifacts exist and that the report contains `Structural validation: PASS` before treating a run as successful.

### Codex and Claude Skill

Install the cross-agent Skill locally with `scripts/install_skill.sh`:

```sh
bash scripts/install_skill.sh
bash scripts/install_skill.sh --home "$HOME" --source skills/fcpxml-subtitle-aligner
```

Codex prompt:

> Use `$fcpxml-subtitle-aligner` to align this Final Cut Pro `.fcpxmld`; keep the source unchanged and return the output and report paths.

Claude prompt:

> Use the `fcpxml-subtitle-aligner` skill to align this `.fcpxml`; preserve the source, validate the result, and report the generated files.

The Skill preflights readable `.fcpxml` files and `.fcpxmld` bundles, fingerprints the source, and runs the CLI locally. To uninstall, remove only these three links:

```sh
rm "$HOME/.codex/skills/fcpxml-subtitle-aligner"
rm "$HOME/.agents/skills/fcpxml-subtitle-aligner"
rm "$HOME/.claude/skills/fcpxml-subtitle-aligner"
```

### Privacy and troubleshooting

Privacy is local-only: the project does not upload files or send project data elsewhere. For a **missing font**, install the font referenced by the Final Cut Pro export and retry. For **malformed XML**, export again and check that a bundle contains `Info.fcpxml`. For **no matching titles**, confirm that the timeline uses Basic Title subtitles with their Custom backgrounds. A validation failure is not a successful output; keep the untouched source, read the report detail, and correct the input.
