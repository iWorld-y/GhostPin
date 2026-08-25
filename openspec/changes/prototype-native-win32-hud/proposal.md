## Why

当前 Windows 版基于 .NET 10 WPF，自包含单文件发布约 74.5 MB，明显高于 macOS DMG，且核心 HUD 仍主要依赖托管运行时。先用并行、可回退的原生实现验证 C++/Win32 + Direct2D，再将其打磨为最终唯一的 Windows 客户端，以保持 GhostPin 与 macOS 一致的交互并降低发布体积和运行时依赖。

## What Changes

- 新增面向 Windows 11 x64 的原生 HUD 原型，使用 C++20、Win32、Direct2D、DirectWrite、WIC、DWM 与 Windows SDK 自带组件，不引入第三方 UI 框架或额外运行时。
- 在独立目录和独立可执行文件中实现与当前 Windows 版一致的核心链路：透明置顶 HUD、默认穿透、交互模式、任务投影与状态推进、文件刷新、通知区域入口、浅色双页设置和可选全局快捷键。
- 复用 `%LOCALAPPDATA%\GhostPin\todos.json` 任务契约，但使用原型专属设置文件，避免覆盖现有 WPF 设置；不同时启动两种 Windows HUD 作为受支持场景。
- 增加可重复的 Release x64 构建、行为检查和包体/启动时间/空闲内存采样，形成与当前 WPF 自包含 EXE 的对照结果和保留、替换或终止原型的决策记录。
- 暂不接入 GitHub Release；Windows 开发阶段通过平台自动识别的 `make start` 构建并启动原生客户端，正式下载与发布切换另行处理。
- 不实现虚拟桌面固定、独占全屏覆盖、Windows CLI、提醒通知、安装器或自动更新；登录时启动属于与 macOS 对齐的客户端设置。

### 已确认的产品决策

- 后续 Windows 只保留原生客户端，WPF 仅作为迁移期间的回退基线。
- HUD、托盘、设置、快捷键、任务推进、文件刷新和焦点语义均以 macOS 版本为行为基准；Windows 只保留平台差异。
- 设置采用 JSON 文件；试用阶段写入 `%LOCALAPPDATA%\\GhostPin\\native-settings.json`，与旧 WPF 设置隔离。
- 视觉对齐 macOS 的浅色 GhostPin HUD，不以当前 WPF 的黑色或独立视觉为目标。

## Capabilities

### New Capabilities

- `native-win32-hud-prototype`: 定义原生 Windows HUD 原型必须覆盖的窗口、渲染、任务、设置、托盘和可量化评估行为。

### Modified Capabilities

无。

## Impact

- 新增独立的原生 Windows 工程、资源、行为检查与评估文档，不修改现有 Swift Package 和 WPF solution 的运行代码。
- Windows 开发环境需要 MSVC C++20 编译器、CMake 和 Windows 11 SDK；应用运行时仅调用系统提供的 Win32、Direct2D、DirectWrite、WIC、DWM、Shell 与注册热键 API。
- 原型将读取并在交互推进时原子写回现有 Windows 任务文件；设置写入独立文件。实施和人工验收期间不得让 WPF 与原生 HUD 同时写同一任务文件。
- 当前发布流程和用户默认下载保持不变；本变更只产出可比较的原型及决策证据，不直接切换正式 Windows 实现。
