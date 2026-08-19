## Context

现有 GhostPin 将可复用任务行为放在 `GhostPinCore`，但 `TodoStore` 仍依赖 Apple Combine；窗口、视图、通知区域、快捷键和偏好则依赖 AppKit、SwiftUI、Carbon 与 UserDefaults。当前 Swift Package 只声明 macOS 14，因此 Windows HUD 不能直接编译或承载现有 UI。

本变更是与 macOS 应用并列的 Windows HUD MVP。它以 `specs/windows-ghost-hud/spec.md` 为行为合同，复用任务 JSON 格式和可验证规则，而不通过 Swift/C# 互操作强行共享运行时代码。Windows 首版只验证核心 HUD 链路，不承担完整 Windows 产品发布。

## Goals / Non-Goals

**Goals:**

- 建立可在 Windows 11 x64 上直接构建、测试和运行的独立 .NET solution。
- 将窗口平台逻辑、任务领域逻辑、文件存储与 WPF 视图分离，使窗口编排层不包含排序、JSON 或任务状态细节。
- 只使用公开 Win32 API 实现置顶、穿透、非激活、任务切换器隐藏、命中测试和多显示器行为。
- 用共享 JSON fixtures 和领域测试证明 Windows 投影、状态转换及兼容读取与现有 GhostPin 合同一致。
- 保持 macOS Swift Package、应用行为和构建命令不变。

**Non-Goals:**

- 不在本变更中抽取跨语言库、移除 `GhostPinCore` 的 Combine 依赖或统一 macOS/Windows UI。
- 不使用未公开虚拟桌面接口，不承诺跨虚拟桌面或独占全屏覆盖。
- 不引入 Windows CLI、提醒通知、安装器、自动更新、开机启动、全局快捷键或发布流水线。
- 不追求逐像素复刻 macOS 材质；Windows 视觉只需保持 GhostPin 品牌、信息层级与模式提示一致。

## Decisions

### 1. 独立的 Windows solution 与三层结构

在仓库根目录新增以下结构：

```text
windows/
├── GhostPin.Windows.sln
├── src/
│   ├── GhostPin.Windows.Core/
│   └── GhostPin.Windows.App/
└── tests/
    └── GhostPin.Windows.Core.Tests/
```

`GhostPin.Windows.Core` 是不依赖 WPF 的 .NET class library，包含任务 DTO、JSON codec、排序与 HUD 投影、状态推进、任务仓储和设置模型。`GhostPin.Windows.App` 是 WPF executable，包含窗口宿主、Win32 互操作、文件监听、通知区域和视图。测试项目主要覆盖 Core，并对需要 Windows 的平台服务使用窄接口替身。

选择独立 solution 而不是扩展 `Package.swift`，是因为 SwiftUI、AppKit 和 Combine 没有 Windows 对等运行时；把 Windows 项目放进 Swift target 会增加条件编译和工具链耦合，却不能复用 UI。备选方案是 Swift + WinSDK，但需要从零建设 Win32 渲染和 Swift Runtime 分发，不适合首个 HUD 验证。

### 2. 使用 .NET 10 WPF，Win32 互操作收敛在平台层

WPF 负责 XAML 布局、数据绑定、滚动列表、渐变、圆角、阴影和 180ms 模式动画；不引入第三方 UI 框架。窗口在 `SourceInitialized` 后取得 HWND，并由单一 `HudWindowHost` 调用 P/Invoke。所有常量、结构体、错误转换和 style 更新封装在 `Win32`/`HudWindowHost`，ViewModel 和领域层不得直接调用原生 API。

WinUI 3 是备选，但透明浮层仍需操作 HWND，且会增加 Windows App SDK 生命周期与部署复杂度。Electron/Avalonia 能缩短部分 UI 工作，却引入更大的运行时或额外抽象，不能降低窗口语义验证风险。

### 3. 用显式窗口样式状态机实现穿透和焦点边界

窗口固定使用无系统边框、透明背景和工具窗口身份。平台层维护两个明确状态：

```text
Passthrough
  ├── WS_EX_TOOLWINDOW
  ├── WS_EX_LAYERED
  ├── WS_EX_TRANSPARENT
  └── WS_EX_NOACTIVATE

Interactive
  ├── WS_EX_TOOLWINDOW
  └── WS_EX_LAYERED
```

置顶与模式分开管理：置顶切换只通过 `SetWindowPos(HWND_TOPMOST/HWND_NOTOPMOST, SWP_NOACTIVATE)` 改变 Z 序。显示穿透态窗口使用不激活路径；进入交互态时先移除 `WS_EX_TRANSPARENT` 和 `WS_EX_NOACTIVATE`，再由明确的用户操作请求激活。退出交互态时先恢复样式，再释放 HUD 焦点，刷新任务或设置透明度不得触发激活。

窗口边缘和四角的 resize 命中由 `WM_NCHITTEST` hook 返回对应 hit code；内容背景拖动使用 WPF `DragMove()`，按钮和滚动区保持普通 WPF 命中。穿透态不会收到这些输入，因此无需在每个控件重复禁用事件。

备选方案是只设置 WPF `IsHitTestVisible=false`，但它只影响 WPF 视觉树，不能保证鼠标传递到其他进程窗口；因此必须使用 HWND 扩展样式。

### 4. WPF 视觉近似 GhostPin，不依赖系统材质

HUD 根窗口保持完全透明，内容板使用圆角 Border、半透明渐变、克制阴影和品牌 PNG。卡片沿用 Doing/Todo 分区、标题、描述、优先级和截止时间层级。交互模式通过描边、亮度、卡片按钮可见性和短动画区分；穿透模式降低饱和度与透明度。

首版不依赖 Mica/Acrylic，因为系统材质与透明 layered window、点击穿透及不同 Windows 设置组合会扩大验证面。若纯 WPF 视觉无法达到可接受质量，可在后续变更中单独评估 Windows Composition，不改变当前领域和窗口状态机。

### 5. 以契约和 fixtures 共享任务行为，不做 Swift/C# 运行时桥接

C# 模型保持与现有任务 JSON 相同的字段名、UUID、ISO 8601 日期、可空字段以及小写状态/优先级值。解码时支持缺少 `status` 的旧任务：根据 `completedAt` 映射为 Todo 或 Done。未知字段忽略，已知字段写回时保持稳定命名。

HUD 投影实现为 Core 中的纯函数，输入为任务集合、当前时间、日历日边界、范围和条数上限，输出为有序任务列表。排序和截断使用与现有 `TodoStore` 相同的规则；测试使用同一组 JSON fixtures 和固定时区/时间断言结果，不把“两个实现看起来相似”当作兼容证明。

备选方案是把 Swift Core 编译为 DLL 后由 C# 调用。该方案仍需移除 Combine、设计 C ABI、分发 Swift Runtime 并处理跨语言错误和所有权，成本高于当前小型领域逻辑的显式移植。

### 6. 单一任务仓储负责加载、状态更新和原子写入

`TodoRepository` 是 Windows 任务真源的唯一读写入口，路径固定为 `%LOCALAPPDATA%\GhostPin\todos.json`。所有读写通过异步互斥串行化：

1. 加载时读取完整文件并在内存外完成解析；成功后一次性发布不可变快照。
2. 文件不存在时发布空快照；解析失败时保留最后有效快照并记录错误。
3. 状态推进前重新读取当前有效文件，按 UUID 定位任务；找不到或源文件无效时不覆盖磁盘。
4. 写入时先在同目录生成临时文件并刷新内容；目标存在时使用替换语义，目标不存在时使用同卷移动，最后清理残留临时文件。

App 层只调用 `AdvanceStatusAsync(id)`，不直接修改集合或序列化 JSON。成功写入后仓储立即发布新快照，随后到达的文件系统事件通过内容等价检查被消除，避免自身写入造成二次闪烁。

### 7. 目录级 FileSystemWatcher、500ms 防抖与完整重载

文件监听器监控任务目录而不是长期持有目标文件句柄，并处理 Created、Changed、Renamed、Deleted 和 Error。任一相关事件只触发可取消的 500ms 防抖；到期后调用仓储完整重载。监听缓冲区错误时重建 watcher 并执行一次完整重载，不尝试从事件序列恢复增量状态。

任务目录不存在时先创建目录再启动监听。刷新结果通过 WPF Dispatcher 发布，但重新读取和解析在后台执行。窗口宿主不参与数据刷新，因此刷新路径不会调用 Show、Activate 或 Z 序 API。

### 8. 设置与任务数据分离，并以显示器相对布局恢复窗口

Windows 偏好写入 `%LOCALAPPDATA%\GhostPin\settings.json`，任务文件中不增加 UI 字段。设置包含：可见性、模式、透明度、置顶、范围、条数上限，以及窗口所在显示器标识、相对工作区位置、逻辑宽高和保存时 DPI。

进程通过 manifest 声明 Per-Monitor V2。保存时将物理窗口矩形换算为相对当前显示器工作区的逻辑布局；恢复时优先匹配显示器标识，找不到则使用主显示器，并将位置与尺寸限制在工作区和最小尺寸内。`WM_DPICHANGED` 到达时采用系统建议矩形并刷新布局，再保存新的稳定状态。

设置读取采用逐字段校验：透明度限制在 0.5 至 1.0，条数上限限制为正数，未知或越界值回退默认值。设置损坏不得影响任务仓储。

### 9. 通知区域是唯一的常驻控制面

应用启动后创建一个 HUD 窗口和一个通知区域图标。通知区域菜单通过 `HudController` 调用显示/隐藏、模式切换和退出；菜单文本与勾选状态由同一应用状态生成。可使用 .NET 自带的 WinForms `NotifyIcon` 作为 Shell 通知区域的薄封装，避免为菜单生命周期编写额外 P/Invoke，且不引入第三方依赖。

隐藏 HUD 只调用 Hide 并保存可见性，进程继续监听任务文件。退出路径按“停止 watcher → 保存设置 → 移除通知区域图标 → 关闭窗口和 Dispatcher”的顺序执行。

### 10. 自动化验证聚焦领域与可分离平台策略

使用 MSTest 与 `Microsoft.NET.Test.Sdk` 建立 Windows Core 测试，覆盖：

- JSON 兼容、旧状态映射、未知字段和无效文件保留；
- Doing/Todo 排序、今天范围、条数上限和 Done 消失；
- Todo/Doing 状态推进、完成时间与 500ms 冷却；
- 原子写入后的内容以及自身事件内容去重；
- 设置校验、显示器缺失回退和 DPI 换算的纯计算部分。

HWND 样式、真实鼠标穿透、前台焦点、Alt+Tab 隐藏、拖动缩放和跨 DPI 显示器行为需要在 Windows 11 真机人工验收。平台层保留可读取当前 style/placement 的诊断接口，使验收结果可记录，而不为首版引入脆弱的桌面 UI 自动化。

## Risks / Trade-offs

- **[WPF 透明窗口渲染或阴影性能不足]** → 首版控制窗口尺寸、模糊半径和动画范围；先以行为正确为门槛，视觉升级另立变更。
- **[动态切换扩展样式后焦点或 Z 序状态不一致]** → 所有 style 变化集中在单一状态机，切换后读取实际 style 并在真机矩阵中验证。
- **[FileSystemWatcher 重复事件或缓冲区溢出]** → 目录级监听、500ms 防抖、错误后重建，并始终把磁盘完整文件作为真源。
- **[外部写入与 HUD 状态推进竞争]** → 仓储串行化自身操作、推进前重读最新有效文件、原子替换；没有可用源文件时拒绝覆盖。
- **[两个语言实现的排序或日期边界漂移]** → 使用固定时间、时区和共享 fixtures 的黄金结果测试，并将兼容规则集中在 Core 纯函数。
- **[多显示器物理像素与 WPF 逻辑单位混淆]** → 所有转换集中在 WindowPlacementService，保存显示器标识和 DPI，并用 100%、150%、200% 真机组合验收。
- **[Windows 项目增加仓库维护成本]** → 保持独立 solution、无第三方 UI 库、不修改 macOS target，并在 MVP 结论不成立时可整目录回滚。

## Migration Plan

1. 以新增目录方式引入 Windows solution、Core、App、Tests 和共享 fixtures，不修改现有 macOS 数据或二进制。
2. 在 Windows 11 x64 环境运行 `dotnet restore`、`dotnet build` 和 `dotnet test`，再按规格执行窗口、焦点、多屏与 DPI 人工验收。
3. MVP 仅以开发构建运行；是否增加安装器、签名、CLI 和发布流程由后续独立变更决定。
4. 若验证失败，删除新增 Windows 目录和 Windows 专用文档即可回滚；`%LOCALAPPDATA%\GhostPin` 中的测试数据由验证人员确认后手动保留或删除，macOS 安装与数据不受影响。
