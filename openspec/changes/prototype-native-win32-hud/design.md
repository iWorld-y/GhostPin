## Context

当前 Windows 实现位于 `windows/`，以 .NET 10 WPF 承担布局、绘制和控件，以窄 Win32 平台层实现 HWND 样式、全局快捷键、多显示器与 DPI。任务模型、投影、原子存储和设置已下沉到独立 Core，但不能被 C++ 直接复用；现有自包含单文件 EXE 约 74.5 MB。

本实现先并行落地，避免在尚未取得体积、性能和行为证据前扰动 WPF 正式基线或发布流程；用户已确认后续 Windows 只保留原生客户端。行为合同见 `specs/native-win32-hud-prototype/spec.md`，动机与产品边界见 `proposal.md`。

## Goals / Non-Goals

**Goals:**

- 使用 Windows SDK 内置能力实现可单文件分发的 x64 原生 Windows 客户端，并把平台窗口、绘制、领域、存储和应用编排分离。
- 对齐现有 WPF 版的核心 HUD、托盘、设置、快捷键和任务文件行为，而不是只制作无法实际使用的视觉样例。
- 让领域规则、JSON 兼容、窗口样式计算和指标采集具备自动化验证入口，把真实焦点、穿透和多屏行为留给可记录的真机验收。
- 在同一设备和构建配置下形成可重复的 WPF/原生体积、启动和内存对照。

**Non-Goals:**

- 不共享 Swift、C# 与 C++ 的运行时代码；迁移期间保留既有 WPF 基线，不让它成为原生运行时依赖。
- 不引入 Qt、WinUI 3、Windows App SDK、WebView、第三方 JSON/UI 库或插件体系。
- 不修改 Release workflow、正式产物命名或安装方式；本地 Windows `make start` 单独指向原生开发目标。
- 不扩展现有 Windows 产品范围，不实现虚拟桌面、独占全屏、CLI、提醒、安装器或自动更新；登录时启动作为 macOS 已有的客户端设置实现。

用户已确认：Windows 的 `make start` 在平台自动识别后应构建并启动原生客户端；这只影响本地开发入口，不代表本变更立即切换 GitHub Release。

## Decisions

### 1. 建立并行的 CMake/MSVC C++20 工程

在 `windows-native/` 建立独立 CMake 工程，生成 `GhostPin.Native.exe`、无 UI 依赖的 Core 静态库和 Core 行为检查可执行程序。Release 使用 MSVC `/MT` 静态链接 C/C++ 运行库，品牌图标和视觉资源编译进 PE 资源，因此分发物只包含一个 EXE。

选择 CMake 是为了让 Visual Studio、Build Tools 和命令行使用同一工程定义，同时不把原型接入现有 .NET solution。备选的 `.vcxproj` 手工维护更贴近 Visual Studio，但会增加工程文件噪音；Qt、WinUI 3 和 Windows App SDK 会重新引入用户正在评估的运行时或框架负担。

### 2. 按领域、存储、平台、渲染和编排拆分职责

原型采用五个窄模块：

- Core：任务模型、状态推进、HUD 投影、快捷键规则和设置校验，不包含 HWND、COM 或磁盘 API。
- Storage：UTF-8 JSON 读取、原子写入、最后有效快照和目录变化通知。
- Platform：窗口类、消息循环、通知区域、热键、DPI、显示器、单实例与 WPF 进程互斥检查。
- Render：Direct2D/DirectWrite/WIC 资源与每帧绘制，不处理业务状态变化。
- App：只创建服务、转发消息、发布快照和控制生命周期。

这延续现有 Windows Core/App 的边界，减少比较结果被架构差异干扰。把所有逻辑塞进 `WndProc` 虽然代码起步更少，但会让 JSON、窗口消息、绘制和设置互相耦合，无法可靠测试或决定后续替换。

### 3. 使用系统 JSON API而不是自研解析器或第三方头文件

Storage 使用 Windows SDK 提供的 C++/WinRT `Windows.Data.Json` 解析和生成 JSON，外层仍转换为普通 C++ 模型，Core 不依赖 WinRT 类型。进程初始化 STA 后即可同时服务设置窗口和 JSON；Windows 11 自带所需运行时，不增加分发文件。

选择系统 API 可以避免自研 JSON 对转义、Unicode、数字和无效输入的高风险，也不引入 `nlohmann/json` 等第三方源码依赖。代价是 Storage 需要显式处理 UTF-8 与 `hstring` 转换，并通过 fixtures 验证与 C# codec 的兼容结果。

### 4. 以 DIB + Direct2D DC render target 输出逐像素透明窗口

HUD 使用 32 位预乘 BGRA DIB section 作为离屏表面，Direct2D DC render target 绘制卡片、渐变、圆角和图形，DirectWrite 绘制文字，完成后通过 `UpdateLayeredWindow` 把整帧提交给顶层 layered window。图片从 PE 资源经 WIC 解码；阴影和透明边缘直接绘制，不依赖 Mica/Acrylic。

普通 HWND render target 不保证 layered window 的逐像素 alpha，直接采用它可能得到黑底或整窗不透明；DirectComposition 能提供更现代的合成路径，但会扩大设备丢失、交换链和命中测试验证面。DIB 路径更适合小尺寸、低频刷新的待办 HUD，也便于截帧与像素验证。仅在数据、尺寸、DPI 或模式变化时重绘，不建立持续动画循环。

### 5. 用显式窗口状态机维持焦点与穿透语义

HUD 始终使用 `WS_EX_TOOLWINDOW | WS_EX_LAYERED` 并移除 `WS_EX_APPWINDOW`。Passthrough 状态增加 `WS_EX_TRANSPARENT | WS_EX_NOACTIVATE`；Interactive 状态移除两者。置顶只通过带 `SWP_NOACTIVATE` 的 `SetWindowPos` 独立切换，非用户操作的显示路径使用不激活语义。

`WM_NCHITTEST` 在交互态为四边四角返回 resize hit code，为背景返回 caption hit code，为任务按钮返回 client；穿透态由扩展样式把输入交给下层窗口。所有样式变更通过一个平台对象执行并读回验证，数据刷新和重绘不能调用激活或前台切换 API。

这与现有 WPF 平台层已经验证的模型一致。只在应用内部忽略鼠标消息不能保证输入到达下层应用，因此不采用。

### 6. 用原生消息窗口承载托盘、快捷键和文件刷新

应用创建一个隐藏消息窗口，统一接收通知区域回调、`WM_HOTKEY`、计时器和 Storage 发布的刷新消息。托盘使用 `Shell_NotifyIconW`，菜单命令只调用 App 编排接口；全局快捷键使用 `RegisterHotKey`/`UnregisterHotKey` 与 `MOD_NOREPEAT`，沿用 WPF 版候选校验和冲突恢复规则。

Storage 在线程中使用 `ReadDirectoryChangesW` 监听任务目录，把相关创建、修改、删除、重命名或溢出折叠为消息窗口上的 500ms 防抖计时器；计时器到期后完整重载。状态推进在写入前重读并按 UUID 定位，写入同目录临时文件、刷新文件缓冲，再用 `ReplaceFileW` 或 `MoveFileExW` 原子替换。

消息窗口避免让渲染 HWND 同时承担后台生命周期。轮询文件时间戳实现更简单，但会引入持续唤醒且对原子替换和短暂损坏的诊断较弱。

### 7. 设置窗口使用 Win32 Common Controls 并保持双页结构

设置是独立的可复用顶层 HWND，使用 Tab、Trackbar、ComboBox、Edit、Button 和静态文本构成 HUD/高级两页；浅色背景、卡片分组和品牌色通过 owner-draw 与主题 API控制。关闭设置只隐藏窗口，再次打开同步当前状态并激活同一实例。

原型设置保存在 `%LOCALAPPDATA%\GhostPin\native-settings.json`，字段与 WPF 设置含义一致但文件完全隔离。窗口位置以显示器设备名、相对工作区坐标、逻辑尺寸和保存 DPI 表示；`WM_DPICHANGED` 使用系统建议矩形，恢复时对当前工作区裁剪。

用纯 Win32 控件比手绘全部输入控件更容易获得键盘、辅助功能和系统交互语义；使用 XAML Islands 会重新引入 Windows App SDK 生命周期，不符合原型目标。

### 8. 启动时阻止双实现同时访问任务文件

原型先用命名 mutex 阻止自身重复启动，再枚举当前用户会话中的 `GhostPin.Windows.App.exe`。发现 WPF 进程时，在初始化 Storage 前显示明确提示并退出；原型退出路径先停止 watcher、注销热键、保存设置、移除托盘图标，最后销毁窗口和 COM 资源。

不修改 WPF 版本意味着无法从两边建立共享跨进程锁，因此原型只能主动防止“WPF 已启动”顺序；人工验收也必须先确认两种进程没有并存。后续若决定替换，再由独立变更设计统一单实例和迁移。

### 9. 指标采集与行为验收分开记录

PowerShell 评估脚本在同一提交和设备分别完成 WPF 自包含 Release publish 与原生 Release build，记录 EXE 精确字节数和发布目录文件数；每个实现冷启动多次，以对应进程出现可见 HUD 作为就绪点，记录中位启动耗时，并在稳定等待后采集工作集。原始样本和汇总写入 `docs/windows-native-hud-evaluation.md`，同时记录 SDK、编译器、Windows 版本和命令。

自动化检查覆盖 JSON fixtures、投影、状态推进、冷却、设置校验、窗口样式计算和离屏恢复纯逻辑。真实透明、焦点、点击穿透、托盘、双页设置、热键、DPI 与多屏用固定清单人工验收。是否切换正式实现只依据评估记录，不在本变更中自动修改发布配置。

### 10. 交互与设置以 macOS 为基准

原生 Windows 客户端不再设计一套独立的产品交互。HUD 的默认穿透、交互模式、用户主动切换时的焦点处理、任务状态推进、设置页结构、登录时启动和快捷键录制均以 macOS 现有行为为基准；Windows 仅替换窗口、绘制、托盘和输入的系统实现。虚拟桌面固定按用户决定暂不实现。默认透明度为 `1.0`，初始尺寸为 `360×460`，最小尺寸为 `300×280`。设置序列化为 UTF-8 JSON，试用阶段文件名为 `native-settings.json`，完成 WPF 退场时再单独处理旧设置迁移。

## Risks / Trade-offs

- **[DIB 全帧提交在大窗口或高 DPI 下消耗 CPU]** → 只在状态变化时重绘，限制 HUD 合法尺寸，并在 100%、150%、200% DPI 下记录重绘与空闲表现。
- **[DirectWrite/WIC 或设备资源丢失导致黑底、锯齿或空白]** → 将设备相关资源集中管理，提交失败后重建 render target，并加入带透明边缘的截图验收。
- **[系统 JSON API 与 C# 序列化细节漂移]** → 使用当前跨语言 fixtures 和固定时间/时区黄金结果；解析失败保留最后有效快照，写入前必须重读成功。
- **[纯 Win32 设置页视觉与可访问性打磨成本高]** → 先保持信息结构、键盘可用性和浅色层级一致，不追求逐像素复刻；视觉升级不得改变设置契约。
- **[WPF 在原型启动后才被用户启动，仍可能并存]** → 验收前显式检查进程，原型写入保持原子且推进前重读；若决定产品化，再增加两个实现共享的跨进程锁。
- **[静态 CRT 或系统投影仍使体积收益不及预期]** → 保留精确字节与依赖证据；若原生 EXE 不小于 WPF 基线，原型按规格不得替换正式实现。
- **[C++ 手工资源生命周期引入崩溃或句柄泄漏]** → 使用 RAII 封装 COM、GDI、图标、菜单、文件和注册资源，退出后验证进程句柄与托盘图标均清理。

## Migration Plan

1. 先安装或确认 MSVC C++、CMake 与 Windows SDK，仅在 `windows-native/` 构建原型；现有 WPF 和 macOS 工程保持不变。
2. 使用 fixtures 和原型专属设置完成自动化检查，再在 Windows 11 x64 真机按固定清单验收；验收真实任务前备份 `todos.json` 并确保 WPF 已退出。
3. 在同一 Windows 设备重新构建 WPF 基线与原生 Release，生成评估记录并给出继续、替换或终止建议。
4. 原型失败时只删除原生构建产物并停止使用候选 EXE，WPF 设置、默认命令和发布产物无需回滚；任务文件如被验收推进，使用验收前备份恢复。
5. 原型通过时仍不自动迁移；另立 OpenSpec 变更处理默认构建、设置迁移、发布命名、签名与 WPF 退场。
