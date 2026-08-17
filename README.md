<p align="center">
  <img src="Sources/GhostPin/Resources/Logo/GhostPinLogo.png" width="128" height="128" alt="GhostPin 应用图标">
</p>

# GhostPin

**中文** · [English](README.en.md)

GhostPin 是一个 **Agent native** 的本地优先 macOS 菜单栏待办应用（SwiftUI + Swift Package Manager）：任务由 Agent 通过随应用分发的命令行工具管理，应用本身负责展示桌面幽灵 HUD、文件监听和本地通知。纯本地存储，无云同步。最低支持 macOS 14，工具链为 Swift 6。

## 设计理念：Agent Native

GhostPin 是 Agent 的本地任务面板。Agent 通过命令行读取和修改任务，App 只负责展示与通知。

```text
用户 ──自然语言指令──▶ Agent ──ghostpin-cli──▶ todos.json
                                                   │ 文件监听
                                                   ▼
                                      幽灵 HUD / 本地通知 / 菜单栏托盘
```

- **写操作通过 CLI**：UI 上唯一的写入口是 HUD 上的「勾选完成」；新增、编辑、删除、状态、优先级、截止日期和描述通过 CLI 完成。
- **时间由 Agent 转换**：提醒时间和截止日期使用带时区的 ISO8601，应用不解析自然语言时间。
- **无全局快捷键**：不注册全局快捷键，HUD 的穿透/交互切换由托盘开关控制。
- **文件监听实时刷新**：CLI 修改后，HUD 在数秒内自动刷新，无需重启 App。

## 功能

- 桌面幽灵 HUD：无边框、始终置顶、透明度可调，默认鼠标点击穿透；窗口位置、尺寸、透明度、模式与显示范围重启后自动恢复。
- HUD 只读展示：标题、优先级、截止日期、描述、过期删除线；唯一交互是勾选完成。
- 菜单栏托盘：未完成数量徽标、显示/隐藏桌面便签、交互模式开关、设置、退出。
- 本地 macOS 通知：任务提醒时间到点通知；支持登录时启动。
- ghostpin-cli 命令行工具：查询、新增、状态切换、修改、删除、JSON 输出和命令级帮助。
- 无账号系统、无云同步、无数据采集。

## 隐私模型

GhostPin 采用本地优先设计。

- 待办保存在 ~/Library/Application Support/GhostPin/todos.json。
- 偏好设置保存在 macOS UserDefaults。
- 应用除构建依赖外不联网。

从旧版本升级时，首次访问会把 `~/Library/Application Support/TodoPin/todos.json` 复制到 GhostPin 目录并保留旧文件；之后只使用 GhostPin 文件。升级前请退出旧 App，回退时先备份两个目录中的任务文件并手动选择要恢复的版本。

## 安装

从 GitHub Releases 页面下载最新的 GhostPin-<版本号>.dmg，打开后把 GhostPin.app 拖入 Applications。

当前公开发布为 ad-hoc 签名，macOS 门禁可能提示“无法验证开发者”。

## 命令行工具

ghostpin-cli 随应用安装在 App Bundle 内。用户向 Skill 使用固定完整路径：

/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli

所有命令都支持 -h 和 --help。需要确认参数时，可先执行：

```bash
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli --help
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update --help
```

常用命令：

```bash
# 查询未完成任务
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli list --json

# 查询全部任务
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli list --all --json

# 新增任务
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli add "整理周报" --priority medium --due "2026-08-20T18:00:00+08:00" --description "汇总本周数据" --json

# 修改状态
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli doing <id> --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli done <id> --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli undone <id> --json

# 修改任务字段
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update <id> --title "整理并发送周报" --priority high --due "2026-08-21T18:00:00+08:00" --description "发送给团队" --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update <id> --clear-due --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update <id> --clear-reminder --json

# 删除任务
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli delete <id> --json
```

提醒时间和截止日期必须使用带时区的 ISO8601。命令返回非零退出码时视为失败。

## 从源码构建

环境要求：

- macOS 14 或更高
- Xcode 命令行工具
- Swift Package Manager

日常开发建议使用 Makefile：

```bash
make help                 # 查看所有常用命令
make dev                  # 构建并启动 App
make restart              # 构建并重启 App
make stop                 # 停止 App
make logs                 # 启动 App 并跟踪日志
make test                 # 运行核心行为检查
make cli ARGS='list --json' # 执行开发版 CLI
```

也可以直接使用底层脚本：

```bash
swift build
swift run GhostPinCoreChecks
./script/build_and_run.sh --verify
./script/package_dmg.sh
```

正式版本发布由 GitHub Actions 在 macOS runner 上完成。发布前只修改 script/VERSION，然后执行：

```bash
bash script/release.sh
```

使用 Developer ID 证书公开发布：

```bash
GHOST_PIN_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./script/package_dmg.sh
```

## 仓库结构

```text
Sources/GhostPin/             macOS SwiftUI 应用
Sources/GhostPinCore/         待办、提醒、解析与存储的核心逻辑
Sources/GhostPinCLI/          ghostpin-cli 命令行工具
Sources/GhostPin/Resources/   应用图标与 Logo
Tests/GhostPinCoreChecks/     可执行核心行为检查
script/                      应用打包与 DMG 脚本
```

## 许可证

GhostPin 使用 MIT License，见 LICENSE。
