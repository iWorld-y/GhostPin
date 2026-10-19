<p align="center">
  <img src="Sources/GhostPin/Resources/Logo/GhostPinLogo.png" width="128" height="128" alt="GhostPin 应用图标">
</p>

# GhostPin

**中文** · [English](README.en.md)

GhostPin 是一个 **Agent native** 的本地优先 macOS 菜单栏待办应用，同时提供基于 Rust/windows-rs + Win32 的 Windows 原生版本。macOS 任务由 Agent 通过随应用分发的命令行工具管理，应用本身负责展示桌面幽灵 HUD、文件监听和本地通知。纯本地存储，无云同步。macOS 最低支持 14，工具链为 Swift 6。

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
- **全局快捷键可选（默认关闭）**：默认不注册全局快捷键；可在设置「高级」页为穿透/交互切换录制一个全局快捷键。保存前做系统快捷键预检，注册失败会阻止保存；第三方软件的快捷键冲突无法完全自动检测。
- **文件监听实时刷新**：CLI 修改后，HUD 在数秒内自动刷新，无需重启 App。

## 功能

- 桌面幽灵 HUD：无边框、始终置顶、透明度可调，默认鼠标点击穿透；窗口位置、尺寸、透明度、模式与显示范围重启后自动恢复。
- HUD 统一展示所有组的任务：标题、优先级、组别、截止日期、描述、过期删除线；唯一交互是状态推进。优先级和组别标记在标题行右对齐，组名最多显示三个汉字的文本宽度，超出部分尾部省略。
- 菜单栏托盘：未完成数量徽标、显示/隐藏桌面便签、交互模式开关、设置、退出。设置包含 HUD 页与「高级」页（可选全局快捷键）。
- 本地 macOS 通知：任务提醒时间到点通知；支持登录时启动。
- ghostpin-cli 命令行工具：查询、新增、状态切换、修改、删除、JSON 输出和命令级帮助。
- 无账号系统、无云同步、无数据采集。

## 隐私模型

GhostPin 采用本地优先设计。

- 待办保存在 ~/Library/Application Support/GhostPin/todos.json。
- 偏好设置保存在 macOS UserDefaults。
- 应用除构建依赖外不联网。

任务使用包含 `schemaVersion: 2`、`nextID` 和 `items` 的文档，ID 为从 `10000` 开始的整数，所有组共享编号且删除后不复用。旧 UUID 数组首次成功访问时统一迁入 `默认`，原始字节保存在同目录的 `todos.v1.backup.json`。GhostPin 文件不存在时仍可从旧 `TodoPin/todos.json` 升级，并保留旧源文件。

升级前退出旧 App 和 CLI，同时更新应用与随包 CLI。旧程序不支持新文档，旧 UUID 不再用于任务操作。回退只恢复迁移时快照，升级后新增和修改需另外保留；详见[任务存储与升级](docs/task-storage.md)。

## 安装

从 GitHub Releases 页面按平台下载最新版本：

- macOS：`GhostPin-<版本号>.dmg`，打开后把 GhostPin.app 拖入 Applications。
- Windows 11 x64：`GhostPin-<版本号>-windows-x64.exe`，这是 Rust 原生自包含单文件，直接下载运行，无需安装 .NET、Visual C++ Redistributable 或解压。

当前 macOS 公开发布为 ad-hoc 签名，macOS 门禁可能提示“无法验证开发者”；Windows EXE 当前未配置 Authenticode 签名，Windows SmartScreen 可能显示安全提示。

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

# 按组查询，也可加 --all
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli list --group GhostPin --json

# 新增任务，必须指定组别
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli add "整理周报" --group 默认 --priority medium --due "2026-08-20T18:00:00+08:00" --description "汇总本周数据" --json

# 修改状态
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli doing <id> --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli done <id> --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli undone <id> --json

# 修改任务字段
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update <id> --group GhostPin --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update <id> --title "整理并发送周报" --priority high --due "2026-08-21T18:00:00+08:00" --description "发送给团队" --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update <id> --clear-due --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update <id> --clear-reminder --json

# 删除任务
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli delete <id> --json
```

`<id>` 必须来自真实查询结果，为十进制整数。每条任务只属于一个组，组名去掉首尾空白后精确、区分大小写地匹配；新增必须显式选择组别，允许指定 `默认`。HUD 保持统一列表，长组名完整保存在数据与 CLI 中。提醒时间和截止日期必须使用带时区的 ISO8601。命令返回非零退出码时视为失败。

## 从源码构建

macOS 环境要求：

- macOS 14 或更高
- Xcode 命令行工具
- Swift Package Manager

Windows 环境要求：

- Windows 11 x64
- Rust 1.89 或更新的 MSVC 工具链
- Visual Studio Build Tools（MSVC 与 Windows SDK，仅源码构建需要）

日常开发建议使用 Makefile：

```bash
make help                 # 查看所有常用命令
make dev                  # 构建并启动 App
make restart              # 构建并重启 App
make stop                 # 停止 App
make logs                 # 启动 App 并跟踪日志
make test                 # 运行核心行为检查
python3 script/check_cli.py # 构建后运行隔离 CLI 检查
make cli ARGS='list --json' # 执行开发版 CLI
make package              # 根据平台生成 DMG 或 Windows 单文件 EXE
```

也可以直接使用底层脚本：

```bash
swift build
swift run GhostPinCoreChecks
./script/build_and_run.sh --verify
./script/package_dmg.sh
# Windows：PowerShell
./windows-native/script/package.ps1
```

`make package` 会自动识别当前平台：macOS 生成 `GhostPin-<版本号>.dmg`，Windows 生成 `GhostPin-<版本号>-windows-x64.exe`。正式版本发布由 GitHub Actions 在 macOS 与 Windows runner 上完成；发布前只修改 script/VERSION，然后执行：

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
windows-native/              Rust/windows-rs Windows 原生 HUD、Core 与检查
script/                      应用打包与发布脚本
```

## 许可证

GhostPin 使用 MIT License，见 LICENSE。
