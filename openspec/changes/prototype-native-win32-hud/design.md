## Context

当前 Windows 实现位于 `windows/`，以 .NET 10 WPF 承担布局、绘制和控件，以窄 Win32 平台层实现 HWND 样式、全局快捷键、多显示器与 DPI。现有自包含单文件 EXE 约 74.5 MB。`windows-native/` 中已经存在部分 C++20/Win32 原型，但该实现依赖手工管理句柄、COM、GDI 对象、回调指针和错误码；继续扩展会放大资源生命周期、异常边界和维护成本。

本变更保留已确认的窗口、数据和交互合同，但将候选实现改为稳定版 Rust 与 Microsoft `windows-rs`。C++ 源码只作为迁移期间的行为参考，不再代表本变更的完成度。行为合同见 `specs/native-win32-hud-prototype/spec.md`，动机与产品边界见 `proposal.md`。

## Goals / Non-Goals

**Goals:**

- 使用 Rust、`windows` crate 与 Windows SDK 内置能力实现可单文件分发的 x64 原生 Windows 客户端。
- 将不可避免的 Win32、COM 和回调 `unsafe` 限制在可审查的窄边界中，让领域、设置和应用编排保持安全 Rust。
- 使用带上下文的 `Result` 和稳定错误类型保留 HRESULT、Win32 错误码与失败阶段，避免静默失败或跨 FFI 展开。
- 对齐现有 WPF 版的核心 HUD、托盘、设置、快捷键和任务文件行为，而不是只制作视觉样例。
- 让领域规则、JSON 兼容、窗口样式计算和指标采集具备自动化验证入口，把真实焦点、穿透和多屏行为留给可记录的真机验收。
- Release x64 产物保持单 EXE、无额外运行时，并且不超过 10,000,000 字节。
- 在同一设备和构建配置下形成可重复的 WPF/Rust 原生体积、启动和内存对照。

**Non-Goals:**

- 不建立 C++/Rust FFI 混合实现，也不保留两个原生运行目标。
- 不共享 Swift、C# 与 Rust 的运行时代码；迁移期间保留既有 WPF 基线，不让它成为原生运行时依赖。
- 不引入 Qt、WinUI 3、Windows App SDK、WebView、第三方 UI 框架或插件体系。
- 首版不额外引入 JSON 框架；继续通过 `windows` crate 使用系统 `Windows.Data.Json`。
- 不修改 Release workflow、正式产物命名或安装方式；本地 Windows `make start` 单独指向 Rust 原生目标。
- 不扩展现有 Windows 产品范围，不实现虚拟桌面、独占全屏、CLI、提醒、安装器或自动更新；登录时启动作为 macOS 已有的客户端设置实现。

用户已确认：Windows 的 `make start` 在平台自动识别后应构建并启动 Rust 原生客户端；这只影响本地开发入口，不代表本变更立即切换 GitHub Release。

## Decisions

### 1. 在 `windows-native/` 建立 Cargo/MSVC Rust 工程

`windows-native/` 使用一个 Cargo package，包含可执行入口和按职责拆分的 Rust modules，不为一次性原型建立多 crate workspace。目标为 `x86_64-pc-windows-msvc`，使用稳定版 Rust、锁定的 `Cargo.lock`、Windows GUI subsystem、Per-Monitor V2 manifest 和 PE 资源。Cargo target 使用合法的 `ghostpin-native`/`ghostpin_native` 名称，staging 脚本再复制为既有的 `GhostPin.Native.exe`，避免把发布文件名强行作为 crate 名称。

Release profile 启用面向体积的优化、LTO、单 codegen unit、关闭调试信息和 `panic = "abort"`。仓库级 `.cargo/config.toml` 为 `x86_64-pc-windows-msvc` 设置 `target-feature=+crt-static`，并在构建后检查 PE imports，确保单 EXE 不依赖 Visual C++ Redistributable。品牌图标、manifest 和版本信息继续编译进 PE 资源。

提交 `rust-toolchain.toml` 固定经验证的 stable toolchain 版本；`build.rs` 调用开发者命令环境中的 `rc.exe` 编译 `.rc` 资源并链接到每次 `cargo build --release`，不再依赖 CMake 或手工后处理。资源编译失败必须使构建失败。

使用 Cargo 是为了统一依赖锁定、测试、格式化、lint 和 Release 构建。当前 CMake/C++ 工程在 Rust 验收完成前仅作为行为参考，最终从 `windows-native/` 移除，避免两套原生构建长期漂移。

### 2. 使用 `windows` crate 的 feature-gated typed bindings

平台调用统一使用 Microsoft `windows-rs` 提供的 `windows` crate，而不是混用 `winapi`、`windows-sys` 或手写 FFI 声明。`windows` 同时覆盖 Win32、COM 与 WinRT，适合 Direct2D、DirectWrite、WIC 和 `Windows.Data.Json`；Cargo 只启用实际使用的 API features。

若完整 `windows` crate 在实测中造成无法接受的编译或体积问题，才评估 `windows-bindgen` 生成项目专用绑定；不得在没有测量证据时预先增加绑定生成流程。`windows-window`、`windows-canvas` 和 `windows-reactor` 不作为首版运行时依赖，因为 HUD 需要自定义消息窗口、DIB DC render target 和 `UpdateLayeredWindow` 路径。

### 3. 保持 Core、Storage、Platform、Render 和 App 五个职责模块

原型采用五个窄模块：

- Core：任务模型、状态推进、HUD 投影、快捷键规则和设置校验，不包含 HWND、COM、`windows` 类型或磁盘 API。
- Storage：UTF-8 JSON 转换、原子写入、最后有效快照和目录变化通知。
- Platform：窗口类、消息循环、通知区域、热键、DPI、显示器、单实例与 WPF 进程互斥检查。
- Render：Direct2D、DirectWrite、WIC、DIB 资源与每帧绘制，不处理业务状态变化。
- App：只创建服务、转发消息、发布快照和控制生命周期。

模块先保持在单 package 内，以 `pub(crate)` 和小接口限制耦合。只有 Core 可被平台无关测试直接使用；Platform、Render 与 Storage 不向 Core 暴露原始句柄、COM 接口或裸指针。

### 4. 建立显式安全边界和资源所有权

所有 `unsafe` block 必须位于 Platform、Render、Storage 或启动边界，范围保持到单次 Windows API 调用或明确的 FFI 序列，并在不直观时说明安全前提。WndProc 和系统回调只做参数校验、消息转换与调度，不承载业务逻辑，也不得让 panic 跨越 `extern "system"` 边界。窗口状态通过 `WM_NCCREATE` 写入 `GWLP_USERDATA`，在 `WM_NCDESTROY` 清除；状态只属于创建它的 UI 线程，回调不得持有跨消息调用的 `&mut App`，也不得在可能同步重入的 API 调用期间保留可变借用。

HWND、HANDLE、HDC、HBITMAP、HICON、HMENU、热键注册、通知区域图标和线程停止信号使用按来源区分的拥有/借用窄封装，在 `Drop` 中执行与创建路径对称的释放或注销：HWND 只能由创建线程销毁，HDC 区分 `ReleaseDC`、`DeleteDC` 和 `EndPaint`，选入 DC 的 HBITMAP 必须先解除选择，shared HICON 不得 `DestroyIcon`，附着到窗口的 HMENU 仅由实际拥有者销毁。UI 资源不实现 `Send`/`Sync`，不把这些类型抽象成统一泛型句柄。COM 接口使用 `windows` crate 的引用计数类型，不手工调用 `Release`。跨线程只传递拥有所有权的数据或消息，不传递悬空指针和借用。

### 5. 使用类型化错误并保留系统诊断信息

模块公开操作返回 `Result<T, ModuleError>`；错误类型区分 JSON、路径、文件、Win32、HRESULT、热键冲突和渲染设备丢失等可处理类别，同时保留原始错误码、操作名和目标路径。不可恢复错误由 App 统一记录并有序退出，可恢复错误保留最后有效状态并继续消息循环。

错误处理不得依赖 panic、忽略返回值或只保存人类可读字符串。WndProc、线程入口和析构路径不得抛出或展开；清理失败可以记录，但不得阻断剩余资源释放。GUI subsystem 不提供可见 `stderr`，因此 App 必须把诊断写入 `%LOCALAPPDATA%\\GhostPin\\native.log`（按大小轮转并限制权限），同时调用 `OutputDebugStringW`；面向用户的启动冲突或不可恢复错误再通过 `MessageBoxW` 告知。

### 6. 通过 `Windows.Data.Json` 保持现有 JSON 契约

Storage 通过 `windows` crate 使用系统 `Windows.Data.Json` 解析和生成 JSON，外层立即转换为普通 Rust 模型，Core 不依赖 WinRT 类型。UI 线程及每个直接使用 WinRT、WIC 或 COM 的测试线程各自初始化 apartment；当前 guard 只负责当前线程的幂等初始化并保持到线程结束，不在中途调用 `RoUninitialize`，以避免 windows-rs `FactoryCache` 在同一线程重复初始化时保留失效工厂指针。相关 WinRT 对象在工作线程结束前销毁，codec/storage 的进程级测试分离，watcher 线程不持有 WinRT/COM 对象，只向 UI 消息窗口发送拥有所有权的数据。后续若要支持线程复用，必须先增加独立进程回归测试再改变该生命周期策略。

选择系统 API可以继续复用现有跨语言 fixtures，避免在技术切换时同时更换 JSON 引擎。字段、枚举、Unicode、数字、未知字段和无效输入必须由 Rust tests 重新验证；既有 C++ 检查结果不算作 Rust 实现完成。

### 7. 以 DIB + Direct2D DC render target 输出逐像素透明窗口

HUD 使用 32 位预乘 BGRA DIB section 作为离屏表面，Direct2D DC render target 绘制卡片、渐变、圆角和图形，DirectWrite 绘制文字，完成后通过 `UpdateLayeredWindow` 把整帧提交给顶层 layered window。图片从 PE 资源经 WIC 解码；阴影和透明边缘直接绘制，不依赖 Mica、Acrylic 或交换链 UI 框架。

普通 HWND render target 不保证 layered window 的逐像素 alpha；`windows-canvas` 的 swap chain 路径也不直接满足本原型的 DIB 提交模型。DIB 路径适合小尺寸、低频刷新的待办 HUD。仅在数据、尺寸、DPI 或模式变化时重绘，不建立持续动画循环。

### 8. 用显式窗口状态机维持焦点与穿透语义

HUD 始终使用 `WS_EX_TOOLWINDOW | WS_EX_LAYERED` 并移除 `WS_EX_APPWINDOW`。Passthrough 状态增加 `WS_EX_TRANSPARENT | WS_EX_NOACTIVATE`；Interactive 状态移除两者。置顶只通过带 `SWP_NOACTIVATE` 的 `SetWindowPos` 独立切换，非用户操作的显示路径使用不激活语义。

`WM_NCHITTEST` 在交互态为四边四角返回 resize hit code，为背景返回 caption hit code，为任务按钮返回 client；穿透态由扩展样式请求下层命中。`WS_EX_TRANSPARENT`、`WS_EX_NOACTIVATE` 和 `HTTRANSPARENT` 只作为实现线索，不能被当作跨进程点击穿透的保证；必须在真机上验证目标应用收到输入、HUD 不获得焦点，失败则记录为验收门禁失败。所有样式变更通过 Platform 的安全接口执行并读回验证，数据刷新和重绘不能调用激活或前台切换 API。

### 9. 用隐藏消息窗口承载托盘、快捷键和文件刷新

应用创建一个隐藏消息窗口，统一接收通知区域回调、`WM_HOTKEY`、计时器和 Storage 发布的刷新消息。托盘使用 `Shell_NotifyIconW`；全局快捷键使用 `RegisterHotKey`、`UnregisterHotKey` 与 `MOD_NOREPEAT`。

Storage worker 使用 `ReadDirectoryChangesW` 监听任务目录，把创建、修改、删除、重命名或溢出折叠为消息窗口上的 500ms 防抖计时器；计时器到期后完整重载。OVERLAPPED、事件和通知缓冲区必须由 watcher 所有并固定到 I/O 完成；停止时先调用 `CancelIoEx`，等待完成通知后再释放缓冲区并 join。完成回调必须校验 `FILE_NOTIFY_INFORMATION` 的长度、偏移和 UTF-16 名称边界，拒绝越界数据。状态推进在写入前重读并按 UUID 定位，写入同目录临时文件、刷新文件缓冲，再用 `ReplaceFileW` 或 `MoveFileExW` 原子替换。

### 10. 设置窗口使用 Win32 Common Controls

设置是独立的可复用顶层 HWND，使用 Tab、Trackbar、ComboBox、Edit、Button 和静态文本构成 HUD/高级两页；浅色背景、卡片分组和品牌色通过 owner-draw 与主题 API 控制。关闭设置只隐藏窗口，再次打开同步当前状态并激活同一实例。

原型设置保存在 `%LOCALAPPDATA%\GhostPin\native-settings.json`，字段与 WPF 设置含义一致但文件完全隔离。窗口位置以显示器设备名、相对工作区坐标、逻辑尺寸和保存 DPI 表示；`WM_DPICHANGED` 使用系统建议矩形，恢复时对当前工作区裁剪。

### 11. 启动时阻止双实现同时访问任务文件

原型先用命名 mutex 阻止自身重复启动，再枚举当前用户会话中的 `GhostPin.Windows.App.exe`。发现 WPF 进程时，在初始化 Storage 前显示明确提示并退出；原型退出路径先停止并 join watcher、注销热键、保存设置、移除托盘图标，最后销毁窗口和 COM 资源。

不修改 WPF 版本意味着无法从两边建立共享跨进程锁，因此原型只能主动防止“WPF 已启动”顺序；人工验收也必须先确认两种进程没有并存。后续若决定替换，再由独立变更设计统一单实例和迁移。

### 12. 将体积门槛和行为验收分开记录

PowerShell 评估脚本在同一提交和设备分别完成 WPF 自包含 Release publish 与 Rust `cargo build --release`，记录 EXE 精确字节数、发布目录文件数、PE imports、`rustc`、Cargo、`windows` crate、MSVC 和 Windows SDK 版本。原生 EXE 必须不超过 10,000,000 字节，PDB、测试程序和构建缓存不计入分发体积。

每个实现冷启动多次，以对应进程出现可见 HUD 作为就绪点，记录中位启动耗时，并在稳定等待后采集工作集。自动化检查覆盖 JSON fixtures、投影、状态推进、冷却、设置校验、安全窗口样式计算和离屏恢复；真实透明、焦点、穿透、托盘、双页设置、热键、DPI 与多屏用固定清单人工验收。

### 13. 交互与设置以 macOS 为基准

Rust 原生 Windows 客户端不再设计一套独立产品交互。HUD 的默认穿透、交互模式、用户主动切换时的焦点处理、任务状态推进、设置页结构、登录时启动和快捷键录制均以 macOS 现有行为为基准；Windows 仅替换窗口、绘制、托盘和输入的系统实现。虚拟桌面固定暂不实现。默认透明度为 `1.0`，初始尺寸为 `360×460`，最小尺寸为 `300×280`。

## Risks / Trade-offs

- **[Rust 不能自动消除 Win32 FFI 风险]** → 集中 `unsafe`、封装资源所有权、禁止原始句柄进入 Core，并用 lint、测试和审阅检查每个边界。
- **[WndProc 或系统回调 panic 导致进程终止]** → 回调只转换消息和调用不 panic 的窄接口；所有可预期失败通过 `Result` 返回并由 App 处理。
- **[`windows` crate API 或 feature 变化]** → 锁定 `Cargo.lock`、记录工具链版本、只启用所需 features，并把升级作为独立可验证改动。
- **[静态 CRT、Rust 标准库或绑定使体积超过 10 MB]** → 启用 LTO 和体积 profile，检查 PE sections/imports；只有实测需要时才评估 `windows-bindgen`，不使用压缩壳掩盖体积。
- **[DIB 全帧提交在大窗口或高 DPI 下消耗 CPU]** → 只在状态变化时重绘，限制 HUD 合法尺寸，并在 100%、150%、200% DPI 下记录重绘与空闲表现。
- **[DirectWrite/WIC 或设备资源丢失导致黑底、锯齿或空白]** → 集中设备资源并实现可恢复错误类型，提交失败后重建 render target，加入透明边缘截图验收。
- **[系统 JSON API 与 C# 序列化细节漂移]** → 使用当前跨语言 fixtures 和固定时间/时区黄金结果；解析失败保留最后有效快照，写入前必须重读成功。
- **[纯 Win32 设置页视觉与可访问性打磨成本高]** → 先保持信息结构、键盘可用性和浅色层级一致，不追求逐像素复刻。
- **[WPF 在原型启动后才被用户启动，仍可能并存]** → 验收前显式检查进程，Rust 原型写入保持原子且推进前重读；若决定产品化，再增加共享跨进程锁。
- **[C++ 与 Rust 原型长期并存导致行为漂移]** → C++ 只作迁移参考，Rust 验收通过后在本变更内移除被替代的 CMake/C++ 目标和源码。

## Migration Plan

1. 在 Windows 11 x64 确认 Rust stable、Cargo、MSVC linker 和 Windows SDK，只在 `windows-native/` 建立 Rust 候选；WPF 和 macOS 工程保持不变。
2. 先移植 Core、JSON、设置、placement 和仓储，通过既有 fixtures 重建 Rust 行为证据，再进入 HWND 与渲染实现。
3. 实现 Platform、Render 和 App 后，在 Windows 真机验证穿透、焦点、DPI、多屏、托盘、设置、快捷键和文件竞争。
4. Rust Release 通过自动化、人工验收、单 EXE 依赖检查和 10,000,000 字节门槛后，移除当前 CMake/C++ 原型源码与构建入口；WPF 仍保留为回退基线。若任一门禁失败，则保留 CMake/C++ 和 WPF 默认入口，Rust 只作为候选并保留评估证据。
5. 在同一 Windows 设备重新构建 WPF 基线与 Rust 原生 Release，生成评估记录并给出继续、替换或终止建议。
6. 原型失败时保留 WPF 设置、默认命令和发布产物，停止使用 Rust 候选；任务文件如被验收推进，使用验收前备份恢复。
7. 原型通过时仍不自动迁移正式发布；另立 OpenSpec 变更处理设置迁移、发布命名、签名与 WPF 退场。
