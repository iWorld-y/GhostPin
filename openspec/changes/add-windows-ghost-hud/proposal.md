## Why

GhostPin 当前只能在 macOS 运行，无法验证其核心差异化体验——常驻、默认穿透且可切换交互的幽灵 HUD——在 Windows 上是否成立。先以独立的 Windows HUD MVP 验证 C# WPF 与 Win32 组合，可以在不改动现有 macOS 实现的前提下，尽早确认窗口语义、视觉表现、文件刷新和任务状态交互的可行性。

## What Changes

- 新增面向 Windows 11 x64 的 GhostPin HUD 应用，使用 .NET 10、C# WPF 与 Win32 互操作实现。
- 提供无边框透明窗口、默认置顶、默认鼠标穿透、穿透/交互模式切换、交互态拖动与调整大小，以及克制的模式视觉提示。
- 复用现有任务 JSON 契约和 HUD 行为规则，在 Windows 本地数据目录读取任务，展示 Doing/Todo 分区，并允许通过圆形按钮执行 `Todo → Doing → Done` 状态推进和 500ms 点击冷却。
- 监听 Windows 任务文件的外部创建、修改、替换与恢复，在不抢焦点、不闪烁的前提下刷新 HUD。
- 持久化 Windows HUD 的显示状态、位置尺寸、透明度、置顶开关、交互模式、显示范围和条数上限，并处理多显示器与 DPI 变化。
- 提供与 macOS 状态栏基本交互一致的 Windows 通知区域入口，用于显示/隐藏 HUD、切换交互模式、打开独立设置窗口和退出应用；通知区域使用与 macOS 状态栏相同的 `GhostPinStatusBar` 图标资源。
- 提供与 macOS 相同基本结构的双页 Windows 设置窗口：HUD 页集中调整透明度、显示范围、条数上限和置顶，高级页录制用于切换穿透/交互模式的可选全局快捷键。
- 将 HUD 与设置页从固定黑色主题改为接近 macOS 浅色材质的白、绿、黄层级，保持 GhostPin 的品牌色调与信息层级一致。
- 本变更不实现虚拟桌面固定、独占全屏覆盖、Windows CLI、通知提醒、安装器、开机启动或 macOS 代码重构。

## Capabilities

### New Capabilities

- `windows-ghost-hud`: 定义 Windows HUD MVP 的窗口行为、任务展示与状态推进、文件刷新、托盘控制、偏好持久化、多显示器及 DPI 适配边界。

### Modified Capabilities

无。

## Impact

- 在仓库中新建独立的 Windows .NET solution、WPF 应用和自动化测试，不改变现有 Swift Package 的 macOS 构建入口。
- 新增 .NET 10 与 WPF 构建依赖，并通过受控 P/Invoke 调用公开 Win32 API 管理 HWND 扩展样式、Z 序、非激活显示、命中测试和多显示器信息。
- Windows 任务数据使用 `%LOCALAPPDATA%\GhostPin\todos.json`，字段、枚举和 ISO 8601 日期格式与现有 GhostPin JSON 契约保持兼容；Windows 偏好使用独立设置文件，不写入任务文件。
- 新增 Windows 专用构建、测试和人工验收说明；现有 macOS App、CLI、任务数据路径和正式行为保持不变。
