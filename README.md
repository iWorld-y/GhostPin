<p align="center">
  <img src="Sources/TodoPin/Resources/Logo/TodoPinLogo.png" width="128" height="128" alt="TodoPin 应用图标">
</p>

# TodoPin

**中文** · [English](README.en.md)

TodoPin 是一个本地优先的 macOS 菜单栏待办应用（SwiftUI + Swift Package Manager），支持文本快速录入、可选本地语音识别（whisper.cpp）、桌面幽灵 HUD 与本地通知。纯本地存储，无云同步。最低支持 macOS 14，工具链为 Swift 6（包声明 `swiftLanguageModes: [.v5]`）。

## 功能

- 菜单栏待办面板，快速捕捉与管理任务。
- 桌面幽灵 HUD：无边框、始终置顶、透明度可调，默认鼠标点击穿透不打扰工作，按 `⌥⌘T` 在穿透/交互模式间切换；窗口位置、尺寸、透明度、模式与显示范围重启后自动恢复。
- 文本快速录入，自动解析中文提醒时间（如"明天 9 点"）。
- 可选本地语音录入，基于 whisper.cpp 离线转写。
- 编辑标题与提醒时间、完成、删除；未完成任务每小时提醒，直到完成。
- 本地 macOS 通知；支持登录时启动。
- `todopin-cli` 命令行工具（list / add / done / undone / update / delete，`--json` 输出），供脚本与 Agent 调用。
- MCP Server（`todopin-cli mcp`），OpenCode、Codex 等 Agent 可直接管理 TodoPin。
- 无账号系统、无云同步、无数据采集。

## 隐私模型

TodoPin 采用本地优先设计。

- 待办保存在 `~/Library/Application Support/TodoPin/todos.json`。
- 每日汇总保存在 `~/Library/Application Support/TodoPin/summaries.json`。
- 偏好设置保存在 macOS `UserDefaults`。
- 音频在本机采集与转写，不上传待办或录音。
- 仅当你从设置中显式下载可选语音模型，或从源码构建依赖时，应用才会联网。

## 安装

从 GitHub Releases 页面下载最新 `TodoPin.dmg`，打开后把 `TodoPin.app` 拖入 Applications。

当前公开发布为 ad-hoc 签名，macOS 门禁可能提示"无法验证开发者"。生产分发请使用 Developer ID 证书签名并公证 DMG。

## 默认快捷键

- 文本快速录入：`Option + Space`
- 语音录入：`F8`
- HUD 穿透/交互切换：`Option + Command + T`

快捷键可在设置中修改。文本快捷键打开轻量输入面板；语音快捷键只显示桌面录音动画，转写成功后自动保存待办。

## 语音模型

语音输入是可选的。TodoPin 使用 whisper.cpp，默认模型：

- `ggml-base-q5_1.bin`
- SHA-256: `422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898`

模型文件刻意不提交进 git。

安装模型有两种方式：

1. 打开 TodoPin 设置，点击模型下载按钮。
2. 或运行：

```bash
./script/fetch_models.sh
```

应用内下载的模型存放于：

```text
~/Library/Application Support/TodoPin/Models/ggml-base-q5_1.bin
```

即使没有语音模型，手动输入依然可用。

## 命令行工具

构建后 `todopin-cli` 随仓库提供，供脚本与 Agent 使用：

```bash
todopin-cli list                      # 列出未完成任务
todopin-cli add "修复 Redis 问题"      # 新增任务
todopin-cli add "开会" --reminder "2026-08-14T09:00:00+08:00"
todopin-cli done <id>                 # 标记完成
todopin-cli undone <id>               # 恢复未完成
todopin-cli update <id> --title "..." # 修改任务
todopin-cli delete <id>               # 删除任务
todopin-cli list --json               # JSON 输出（Agent 友好）
todopin-cli mcp                       # 以 MCP Server 模式运行
```

App 运行时通过文件监听自动刷新：CLI 或 MCP 的修改会秒级反映到 HUD。

## 注册 MCP Server（OpenCode 等）

在 `~/.config/opencode/opencode.json` 的 `mcp` 段添加（路径指向已构建的 `todopin-cli` 二进制，如 release 构建）：

```json
{
  "mcp": {
    "todopin": {
      "type": "local",
      "command": ["/path/to/TodoPin/.build/release/todopin-cli", "mcp"],
      "enabled": true
    }
  }
}
```

重启 OpenCode 后即可使用 `list_tasks`、`create_task`、`update_task`、`complete_task`、`uncomplete_task`、`delete_task` 六个工具。Codex、Claude Code 等客户端同样以 stdio 方式注册该命令即可。

## 从源码构建

环境要求：

- macOS 14 或更高
- Xcode 命令行工具
- Swift Package Manager

构建：

```bash
swift build
```

运行核心行为检查：

```bash
swift run TodoPinCoreChecks
```

创建并验证本地 `.app` 包：

```bash
./script/build_and_run.sh --verify
```

创建发布 DMG：

```bash
./script/package_dmg.sh
```

默认情况下发布 DMG 不包含语音模型，用户之后可在设置中下载。

构建带模型的本地包：

```bash
TODO_PIN_INCLUDE_MODEL=1 ./script/package_dmg.sh
```

## 签名与分发

打包脚本默认使用 ad-hoc 签名。

使用 Developer ID 证书公开发布：

```bash
TODO_PIN_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./script/package_dmg.sh
```

公证流程暂未自动化。

## 仓库结构

```text
Sources/TodoPin/             macOS SwiftUI 应用
Sources/TodoPinCore/         待办、提醒、解析与存储的核心逻辑
Sources/TodoPinCLI/          todopin-cli 命令行工具
Sources/TodoPinMCP/          MCP 服务器协议与工具实现
Sources/TodoPin/Resources/   应用图标、Logo 与可选模型目录
Tests/TodoPinCoreChecks/     可执行核心行为检查
script/                      模型下载、应用打包与 DMG 脚本
```

## 许可证

TodoPin 使用 MIT License，见 [LICENSE](LICENSE)。
