# Windows HUD 开发说明

Windows 版 GhostPin 位于 `windows/`，与现有 macOS Swift Package 并列。当前目标是 Windows 11 x64、.NET SDK 10.0.400 和 WPF；本变更不修改 `Sources/` 下的 macOS 代码。

## 构建与运行

Makefile 会通过 `OS=Windows_NT` 自动选择 Windows 命令；同一组目标在 macOS 上继续使用现有 Swift 与 AppKit 构建流程。在 Windows PowerShell 或 CMD 中进入仓库根目录后执行：

```powershell
make build
make test
make dev
make restart
make stop
make verify
```

Windows 默认使用 Debug 配置，可通过 `make build CONFIGURATION=Release` 等方式切换。由于当前开发网络无法稳定访问 NuGet 漏洞审计索引，Windows Makefile 默认传入 `NuGetAudit=false`；可通过 `make build NUGET_AUDIT=true` 恢复在线审计。该选项不会关闭编译期 warnings-as-errors。

Windows MVP 尚未提供 CLI、统一日志、遥测、DMG 或发布流程；在 Windows 调用对应的现有 Make 目标会给出明确错误，而不会执行 macOS 脚本。

应用项目启用 WPF、内置 WinForms `NotifyIcon` 和 Per-Monitor V2 manifest。测试项目是 MSTest；测试不依赖开发机绝对路径，fixture 会复制到测试输出目录。

## 数据与设置

- 任务真源：`%LOCALAPPDATA%\GhostPin\todos.json`
- HUD 设置：`%LOCALAPPDATA%\GhostPin\settings.json`

两个文件分开保存。应用首次启动会创建目录；任务文件不存在时显示空状态。任务文件短暂损坏时 HUD 保留最后一次成功快照并显示非阻塞诊断信息，不会用空数据覆盖磁盘。状态推进通过同目录临时文件和原子替换写回。

## HUD 操作

- 默认是置顶、鼠标穿透模式；穿透时点击会交给下层应用且不抢焦点。
- 通过通知区域菜单显示/隐藏 HUD、切换交互模式、切换置顶和退出。
- 通知区域菜单还可以选择任务范围（全部/今天）、透明度（70%/85%/92%/100%）和最多显示任务数（5/8/12/20）；选择后立即刷新并持久化。
- 交互模式下，点击任务卡片圆形按钮可执行 `Todo → Doing → Done`；同一任务成功推进后的 500ms 内重复点击会被忽略。
- 交互模式下可拖动非控件背景，窗口边缘和四角可调整大小；关闭按钮只隐藏窗口，进程和文件监听继续运行。
- HUD 只显示 Todo/Doing，支持全部未完成和今天新增范围，以及条数上限；Doing 始终位于 Todo 之上。

## 人工验收

在 Windows 11 真机上至少检查：

1. 默认穿透点击下层应用、穿透态不改变前台焦点；交互态按钮、背景拖动、四边和四角缩放。
2. 置顶切换、隐藏后从托盘恢复、任务栏和 Alt+Tab 隐藏，以及退出后托盘图标移除。
3. 100%、150%、200% DPI 和包含负坐标的双显示器：移动、重启恢复、断开显示器回退、文字清晰度与命中区域。
4. 外部创建、修改、临时文件重命名替换、短暂损坏和恢复 `todos.json`；确认数秒内稳定刷新、不闪烁、不改变其他应用焦点。

## Windows 11 x64 验证记录

2026-08-19 在 Windows 11 x64（系统内部版本 `10.0.26200.9168`）完成以下自动验证：

- .NET SDK：`10.0.400`。
- `dotnet restore windows/GhostPin.Windows.sln -p:NuGetAudit=false`：退出码 0，三个项目均还原成功。
- `dotnet build windows/GhostPin.Windows.sln --configuration Release --no-restore -p:TreatWarningsAsErrors=true`：退出码 0，0 个警告、0 个错误；App 产物目标为 `net10.0-windows/win-x64`。
- `dotnet test windows/GhostPin.Windows.sln --configuration Release --no-build`：退出码 0，27/27 通过。
- `make build CONFIGURATION=Release`：自动选择 Windows solution，退出码 0，0 个警告、0 个错误。
- `make test CONFIGURATION=Release`：自动选择 Windows 测试项目，退出码 0，27/27 通过。

本次开发期出现过的非零验证结果均已修复或明确归因：

- NuGet 直连曾因 TLS 服务索引不可达报 `NU1301`，最终默认 restore 又因漏洞审计索引不可达报 `NU1900`；进程代理没有稳定改善审计请求，关闭本次在线审计后依赖还原成功。
- solution 级传入 `--runtime win-x64` 报 `NETSDK1134`；已改为由 App 项目的 `RuntimeIdentifier` 固定 RID。
- warnings-as-errors 构建先后暴露并修复 WindowsDesktop SDK 警告、设置边界表达式、WPF/WinForms 类型歧义、DPI manifest 分析器、窗口句柄 API、WPF 父级遍历、`ReadOnlySpan` 跨 `await`、不存在的 `RadioCheck` 属性和测试项目缺失 `System.IO` 导入。
- 早期测试为 14/15，主显示器回退用例失败；补充主显示器标记和回退逻辑后，扩展测试集最终为 27/27。

## 明确不在本变更范围

Windows MVP 不提供虚拟桌面固定、独占全屏覆盖、Windows CLI、提醒通知、安装器、自动更新、开机启动或可配置全局快捷键，也不承诺 macOS 与 Windows 的运行时代码复用。这些能力需要后续独立变更。
