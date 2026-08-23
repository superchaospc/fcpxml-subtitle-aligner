## [1.0.0] - 2026-08-23

- App：提供 Final Cut Pro `.fcpxml` / `.fcpxmld` 拖放处理与保留原文件的图形流程。
- CLI：支持完整的字号、安全宽度、自动缩小、JSON 输出和可预测的 sibling output/report 命名。
- cross-agent Skill：提供 Codex、agents 和 Claude 的本地安装链接及安全的输入预检流程。
- safe output transaction：使用隔离暂存、校验和回滚，避免覆盖源文件或发布半成品。
- adjustable typography：支持动作/食材字号、最小字号和自动缩小设置。
- anonymous fixtures：测试 fixture 不含个人路径、项目名或用户数据。
- macOS 13+ deployment target：Package and App 的最低部署目标为 macOS 13；CI 使用 macos-14 CI runner。
- CI：在 macOS 13+ 目标上执行 Debug/Release 严格编译、universal 构建和 Skill/脚本校验。
