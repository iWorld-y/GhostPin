<p align="center">
  <img src="Sources/TodoPin/Resources/Logo/TodoPinLogo.png" width="128" height="128" alt="TodoPin 应用图标">
</p>

# TodoPin

**中文** · [English](README.en.md)

TodoPin 是一个**Agent native** 的本地优先 macOS 菜单栏待办应用（SwiftUI + Swift Package Manager）：任务的新增、修改、删除一律通过 MCP 由 Agent 完成，应用本身只负责展示（桌面幽灵 HUD）与本地通知。纯本地存储，无云同步。最低支持 macOS 14，工具链为 Swift 6（包声明 `swiftLanguageModes: [.v5]`）。

## 设计理念：Agent Native

TodoPin 的定位是**「Agent 的任务面板」**：操作入口全部收敛到 MCP Server，App 退化为纯展示壳。

```
用户 ──自然语言指令──▶  Agent ──create/update/complete──▶  MCP Server
                                                               │ 读写
                                                               ▼
                                                         todos.json
                                                               │ 文件监听(秒级)
                                               ┌───────────────┼──────────────┐
                                          ┌────▼────┐    ┌─────▼────┐   ┌─────▼────┐
                                          │ 幽灵 HUD │    │ 本地通知  │   │ 菜单栏托盘 │
                                          │  (展示)  │    │(定时提醒) │   │(开关/退出)│
                                          └─────────┘    └──────────┘   └──────────┘
```

- **写操作只走 MCP**：UI 上唯一的写入口是 HUD 上的「勾选完成」；新增、编辑、删除、改优先级/截止/描述全部通过 MCP 工具完成。
- **Agent 解析自然语言**：提醒时间等自然语言表达由 Agent（LLM）解析后以 ISO8601 传入，应用不做时间解析。
- **无全局快捷键**：不注册任何全局快捷键（避免与其他软件冲突），HUD 的穿透/交互切换由托盘开关控制。
- **文件监听实时刷新**：Agent 通过 MCP/CLI 修改后，HUD 秒级反映，无需重启。

## 功能

- 桌面幽灵 HUD：无边框、始终置顶、透明度可调，默认鼠标点击穿透不打扰工作；穿透/交互模式由托盘「交互模式」开关切换；窗口位置、尺寸、透明度、模式与显示范围重启后自动恢复。
- HUD 只读展示：标题、优先级、截止时间、描述、过期删除线；唯一交互是勾选完成。
- 菜单栏托盘：未完成数量徽标、显示/隐藏桌面便签、交互模式开关、设置、退出。
- 本地 macOS 通知：任务提醒时间到点通知；支持登录时启动。
- `todopin-cli` 命令行工具（list / add / done / undone / update / delete，`--json` 输出），供脚本与 Agent 调用。
- MCP Server（`todopin-cli mcp`），Agent 可直接管理 TodoPin。
- 无账号系统、无云同步、无数据采集。

## 隐私模型

TodoPin 采用本地优先设计。

- 待办保存在 `~/Library/Application Support/TodoPin/todos.json`。
- 偏好设置保存在 macOS `UserDefaults`。
- 应用除构建依赖外不联网。

## 安装

从 GitHub Releases 页面下载最新 `TodoPin.dmg`，打开后把 `TodoPin.app` 拖入 Applications。

当前公开发布为 ad-hoc 签名，macOS 门禁可能提示"无法验证开发者"。

## 注册 MCP Server

在 Agent 的 MCP 配置中按 stdio 方式注册（`todopin-cli` 随应用安装，位于 app bundle 内）：

```json
{
  "mcp": {
    "todopin": {
      "type": "local",
      "command": ["/Applications/TodoPin.app/Contents/MacOS/todopin-cli", "mcp"],
      "enabled": true
    }
  }
}
```

重启 Agent 后即可使用 `list_tasks`、`create_task`、`update_task`、`complete_task`、`uncomplete_task`、`delete_task` 六个工具。其他支持 MCP 的 Agent 客户端以同样的 stdio 方式注册即可。

## 命令行工具

`todopin-cli` 随应用安装在 app bundle 内（`/Applications/TodoPin.app/Contents/MacOS/todopin-cli`），供脚本与 Agent 使用。该目录不在 $PATH 中，可先将它加入 PATH，或在示例中改用完整路径：

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
Sources/TodoPin/Resources/   应用图标与 Logo
Tests/TodoPinCoreChecks/     可执行核心行为检查
script/                      应用打包与 DMG 脚本
```

## 许可证

TodoPin 使用 MIT License，见 [LICENSE](LICENSE)。
