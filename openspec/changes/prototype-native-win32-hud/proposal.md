## Why

现有 Windows HUD 已经验证了产品交互，但基于 .NET 10 WPF 的实现带来较大的运行时与维护负担。现在将 Windows 实现收敛为 Rust/windows-rs + Win32 + Direct2D 原生版本，在保持 GhostPin 基本交互一致的同时降低发布体积和运行时依赖。

## What Changes

- 新增面向 Windows 11 x64 的原生 HUD 原型，使用 Rust MSVC 工具链、windows-rs、Win32、Direct2D、DirectWrite、WIC、DWM 与 Windows SDK 自带组件，不引入第三方 UI 框架或额外运行时。
- 在独立目录和独立可执行文件中实现与当前 Windows 版一致的核心链路：透明置顶 HUD、默认穿透、交互模式、任务投影与状态推进、文件刷新、通知区域入口、浅色双页设置和可选全局快捷键。
- 复用 `%LOCALAPPDATA%\GhostPin\todos.json` 任务契约，并使用原生专属设置文件 `native-settings.json`。
- 增加可重复的 Release x64 构建、行为检查和包体/启动时间/空闲内存采样，形成原生实现的可复现决策记录。
- 移除旧 Windows WPF 工程及其 .NET 打包入口；Windows `make build`、`make test`、`make start`、`make package` 和 GitHub Release 均使用 Rust 原生实现。
- 不实现虚拟桌面固定、独占全屏覆盖、Windows CLI、提醒通知、安装器、自动更新或开机启动。

## Capabilities

### New Capabilities

- `native-win32-hud-prototype`: 定义原生 Windows HUD 原型必须覆盖的窗口、渲染、任务、设置、托盘和可量化评估行为。

### Modified Capabilities

无。

## Impact

- 新增独立的原生 Windows 工程、资源、行为检查与评估文档，不修改现有 Swift Package 和 macOS 行为。
- Windows 开发环境需要 Rust MSVC 工具链、MSVC 链接器和 Windows 11 SDK；应用运行时通过 windows-rs 调用系统提供的 Win32、Direct2D、DirectWrite、WIC、DWM、Shell 与注册热键 API。
- 原生实现读取并在交互推进时原子写回现有 Windows 任务文件；设置写入独立文件。
- macOS 发布流程保持不变；Windows 发布流程切换为原生单文件 EXE，用户默认下载不再包含 WPF 产物。
