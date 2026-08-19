## 1. Windows 工程骨架

- [x] 1.1 在 `windows/` 创建 .NET 10 solution、`GhostPin.Windows.Core` class library、`GhostPin.Windows.App` WPF executable 和 `GhostPin.Windows.Core.Tests` MSTest 项目，并建立单向项目依赖
- [x] 1.2 配置 Windows App 为 `win-x64`、启用 WPF 与内置 WinForms 通知区域支持，加入 Per-Monitor V2 manifest，并以 warnings-as-errors 完成一次 `dotnet build`
- [x] 1.3 将 GhostPin 品牌 PNG 和跨语言 JSON fixtures 纳入 Windows 项目，验证资源复制路径与测试读取路径不依赖开发机绝对目录

## 2. 任务领域兼容

- [x] 2.1 实现 C# 任务、状态、优先级和 HUD 范围模型及 JSON codec，覆盖小写枚举、ISO 8601、可空字段、未知字段和缺少 `status` 的旧数据映射测试
- [x] 2.2 实现纯函数 HUD 投影，覆盖 Doing 优先分区、空分区隐藏、全部/今天范围、优先级与截止时间排序、逾期规则、条数上限和 Done 消失的黄金结果测试
- [x] 2.3 实现按 UUID 的 `Todo → Doing → Done` 推进与可注入单调时钟的 500ms 冷却，测试完成时间写入、冷却内忽略和无效状态不写入

## 3. Windows 存储与实时刷新

- [x] 3.1 实现 `%LOCALAPPDATA%\GhostPin` 路径解析、任务文件与设置文件分离，以及缺失目录自动创建，并使用临时目录测试路径和初始化行为
- [x] 3.2 实现串行化的 `TodoRepository` 完整加载、最后有效快照、推进前重读和同目录原子替换，测试文件缺失、解析失败、UUID 不存在及写入后 JSON 兼容性
- [x] 3.3 实现目录级 `FileSystemWatcher`，处理创建、修改、重命名、删除和 Error，加入可取消的 500ms 防抖、错误后重建及完整重载
- [x] 3.4 通过集成测试验证外部临时文件替换、重复事件合并和 HUD 自身原子写入不会重复发布等价任务快照
- [x] 3.5 实现 Windows 设置逐字段校验和安全默认值，测试透明度、条数上限、模式、置顶、可见性及损坏设置与任务数据隔离

## 4. HWND 窗口平台层

- [x] 4.1 在独立 Win32 互操作模块中声明所需常量、结构体和 P/Invoke，并实现可测试的 Passthrough/Interactive 扩展样式计算
- [x] 4.2 实现 `HudWindowHost`，在 HWND 初始化后应用工具窗口、layered window、`WS_EX_TRANSPARENT`、`WS_EX_NOACTIVATE` 和 `SetWindowPos`，并确保置顶切换使用不激活路径
- [x] 4.3 实现穿透/交互状态切换顺序和实际 style 诊断读取，确保数据刷新与透明度变化不调用 Show、Activate 或前台切换 API
- [x] 4.4 处理 `WM_NCHITTEST` 的四边与四角 resize，并在 WPF 非控件背景接入交互态 `DragMove()`，验证按钮和滚动区域仍保持普通命中
- [x] 4.5 实现 Per-Monitor V2 窗口 placement 服务，保存显示器标识、相对工作区布局、逻辑尺寸和 DPI，并测试显示器缺失、负坐标、越界限制与建议矩形换算

## 5. WPF HUD 与应用编排

- [x] 5.1 实现只负责编排仓储、监听器、设置、窗口宿主和通知区域的 `HudController`，确保排序、JSON 和 Win32 细节分别留在 Core 与平台模块
- [x] 5.2 实现透明无边框 `HudWindow`、品牌标题、空状态、Doing/Todo 滚动分区、半透明渐变、圆角卡片、阴影和交互模式短动画
- [x] 5.3 实现任务卡片标题、描述、优先级、截止/逾期表现和圆形推进按钮，并将推进成功、失败与冷却状态正确反映到 ViewModel
- [x] 5.4 实现通知区域图标及显示/隐藏、交互模式和退出菜单，使菜单状态与 HUD 状态双向一致，隐藏窗口后保持进程与文件监听运行
- [x] 5.5 实现启动与退出生命周期：加载设置和任务、恢复安全窗口位置、以保存模式显示且不无条件抢焦点，以及按顺序停止监听、保存设置、移除图标和关闭 Dispatcher
- [x] 5.6 为任务文件无效、设置回退和平台调用失败提供可诊断日志或非阻塞错误状态，验证错误不会关闭 HUD 或覆盖最后有效任务数据
- [x] 5.7 新增单实例 WPF 设置窗口，将透明度、显示范围、条数上限和置顶从通知区域菜单移入窗口，并确保修改立即应用和持久化
- [x] 5.8 将通知区域菜单收敛为与 macOS 状态栏一致的基本入口，并使用 `GhostPinStatusBar` 同源资源生成通知区域图标和正确管理图标生命周期
- [x] 5.9 将 HUD 与设置窗口改为接近 macOS 的浅色白绿黄层级，并将设置窗口调整为 HUD/高级双页结构
- [x] 5.10 在高级页实现全局快捷键录制、校验、冲突恢复、持久化及 `RegisterHotKey` 模式切换

## 6. 验证与文档

- [x] 6.1 在 Windows 11 x64 上运行 `dotnet restore`、`dotnet build` 和 `dotnet test`，记录 .NET SDK 版本、测试数量和所有非零退出结果
- [ ] 6.2 人工验证默认穿透点击下层应用、穿透态不抢焦点、交互态按钮/拖动/八方向缩放、置顶开关、任务栏与 Alt+Tab 隐藏以及托盘生命周期
- [ ] 6.3 在 100%、150%、200% DPI 和含负坐标的双显示器组合验证移动、重启恢复、显示器断开回退、文字清晰度和命中区域
- [ ] 6.4 人工验证外部创建、修改、原子替换、短暂损坏和恢复 `todos.json` 时 HUD 在数秒内稳定更新、不闪烁且不改变其他应用焦点
- [x] 6.5 新增 Windows 开发说明，记录构建运行命令、数据与设置路径、HUD 操作、人工验收步骤，以及虚拟桌面、独占全屏、CLI、通知、安装器和开机启动不在本变更范围
- [x] 6.6 运行 `openspec validate --all --strict --json`、检查 Windows 与 macOS 文档边界，并确认最终 diff 仅包含本变更规划和后续明确实现范围
- [x] 6.7 让仓库现有 Makefile 目标自动识别 macOS 与 Windows，在 Windows 下复用 `build`、`test`、`dev`、`restart`、`stop` 和 `verify`，并对 MVP 未支持的目标给出明确错误
- [x] 6.8 更新 Windows 开发说明并在 Windows 11 x64 上重新运行 Makefile Release 构建、测试和 OpenSpec 严格校验，记录设置窗口与同源通知区域图标的人工验收入口
- [x] 6.9 在 Windows 11 x64 上重新运行 Release 构建与 32 项测试，并启动验证浅色 HUD、双页设置和全局快捷键初始化链路
