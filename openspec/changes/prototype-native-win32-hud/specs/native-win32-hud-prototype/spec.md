## Purpose

定义 GhostPin 基于 Rust 与 Microsoft `windows-rs` 的原生 Windows HUD 原型，包括可启动产物、内存安全边界、错误处理、核心交互兼容性、数据安全与量化评估方式，为是否替换现有 WPF 实现提供可复现证据。

## ADDED Requirements

### Requirement: Rust 与 windows-rs 实现边界

原生原型 MUST 使用稳定版 Rust 和 Microsoft `windows-rs` 的 `windows` crate 实现 Windows API 调用，并 MUST NOT 依赖 C++ 运行时代码、托管 UI 运行时或 C++/Rust FFI 混合层。Core 和 App 编排层 MUST 只暴露安全 Rust 类型；Windows API、COM、句柄、裸指针与系统回调所需的 `unsafe` MUST 限制在 Platform、Render、Storage 或进程启动的窄边界中。

#### Scenario: 检查原生实现依赖与源码边界

- **WHEN** 审查 Release 构建依赖、Cargo features 和模块接口
- **THEN** Windows API 由锁定版本且按需启用 features 的 `windows` crate 提供，Core 不引用 HWND、COM、裸指针或 `windows` 类型，且正式原生目标不链接 C++ 对象或库

#### Scenario: Windows API 调用失败

- **WHEN** 文件、窗口、COM、热键或渲染 API 返回失败
- **THEN** 对应模块以类型化 `Result` 保留操作阶段、HRESULT 或 Win32 错误码和必要路径上下文，由 App 决定恢复或有序退出，不以 panic、静默忽略或跨 FFI 展开处理

#### Scenario: 资源离开所有权范围

- **WHEN** 窗口、句柄、GDI 对象、通知区域图标、热键注册、worker 或 COM 接口结束生命周期
- **THEN** 拥有该资源的 Rust 类型执行与创建路径对称的销毁、注销、停止或引用释放，重复清理不会产生二次释放

#### Scenario: 线程级 COM 与 WinRT 生命周期

- **WHEN** UI 线程或测试线程使用 `Windows.Data.Json`、WIC 或其他 COM/WinRT API
- **THEN** 该线程独立幂等初始化 apartment 并保持到线程结束，相关对象在工作线程结束前销毁；当前原型不在同一线程中途调用 `RoUninitialize`，codec/storage 测试按进程隔离；watcher 线程不持有 COM/WinRT 对象，只发送拥有所有权的数据或消息

#### Scenario: Cargo 资源构建链路

- **WHEN** 单独执行 `cargo build --release`
- **THEN** 合法的 Rust target 通过 `build.rs` 和 `rc.exe` 编译并链接 manifest、图标和版本资源；资源缺失或编译失败使构建失败，staging 后的文件名仍为 `GhostPin.Native.exe`

#### Scenario: 系统回调和异步 watcher 结束

- **WHEN** 窗口收到 `WM_NCCREATE`、`WM_NCDESTROY` 或 watcher 被停止
- **THEN** `GWLP_USERDATA` 仅在窗口所属 UI 线程设置和清除，回调不跨同步重入持有可变借用；watcher 先 `CancelIoEx` 并等待 I/O 完成，再释放 `OVERLAPPED`、事件和通知缓冲区，同时拒绝越界的 `FILE_NOTIFY_INFORMATION`

#### Scenario: GUI 子系统输出诊断

- **WHEN** 平台、存储或渲染操作失败
- **THEN** App 将操作阶段、Win32/HRESULT 错误码和路径写入受限的本地日志并发送 `OutputDebugStringW`；启动冲突或不可恢复错误另外通过 `MessageBoxW` 告知，不依赖不可见的 `stderr`

### Requirement: 无托管运行时的单文件原型

系统 SHALL 产出一个可直接启动且不超过 10,000,000 字节的 Windows 11 x64 Rust 原生 `.exe`，运行时 MUST NOT 要求安装 .NET、Visual C++ Redistributable、第三方 UI 框架或与 EXE 同目录的动态库及资源文件。

#### Scenario: 在干净的 Windows 11 x64 环境启动

- **WHEN** 用户把 Release 原型 EXE 复制到仅包含 Windows 系统组件且未安装 .NET 或 Visual C++ Redistributable 的 Windows 11 x64 账户并启动
- **THEN** 系统显示 GhostPin 通知区域图标和 HUD，EXE 精确大小不超过 10,000,000 字节，且不会因缺少额外运行时或同目录文件而失败

### Requirement: 与 WPF 实现隔离运行

原生原型 SHALL 使用独立的进程身份和设置文件，并 MUST NOT 覆盖现有 WPF 设置。原生原型检测到 WPF GhostPin 正在运行时 MUST 拒绝进入任务读写生命周期，并 SHALL 给出可诊断提示。

#### Scenario: WPF GhostPin 已经运行

- **WHEN** 用户在现有 WPF GhostPin 仍在运行时启动原生原型
- **THEN** 原生原型提示用户先退出 WPF 版本并结束自身，且不修改任务文件或任一版本的设置

#### Scenario: 单独启动原生原型

- **WHEN** WPF GhostPin 未运行且用户启动原生原型
- **THEN** 原生原型读取 `%LOCALAPPDATA%\GhostPin\todos.json`，并只从原型专属设置文件恢复 HUD 偏好

### Requirement: 原生 HUD 窗口语义

原生 HUD SHALL 是无系统边框、背景逐像素透明且不出现在任务栏或 Alt+Tab 中的工具窗口。HUD 默认 SHALL 置顶并处于穿透模式；穿透模式下输入 MUST 交给下层应用且 HUD MUST NOT 抢占焦点，交互模式下 SHALL 支持任务按钮、拖动与八方向缩放。

#### Scenario: 默认穿透显示

- **WHEN** 原生原型首次启动且没有可用设置
- **THEN** HUD 置顶显示、鼠标点击到达下层应用、当前前台应用保持焦点，且 HUD 不出现在任务栏或 Alt+Tab 中

#### Scenario: 切换到交互模式

- **WHEN** 用户从通知区域或已注册的全局快捷键切换为交互模式
- **THEN** HUD 开始接收鼠标输入，任务按钮、背景拖动和四边四角缩放可用，并以克制的视觉变化提示模式

#### Scenario: 关闭置顶

- **WHEN** 用户在设置中关闭置顶
- **THEN** HUD 回到普通窗口层级且不无条件激活自身或夺取其他应用焦点

### Requirement: HUD 视觉与品牌一致

原生 HUD SHALL 呈现与 macOS 和当前 Windows 版一致方向的浅色白、绿、黄层级、深色主文字和灰色次要文字，并 SHALL 在不同 DPI 下保持文字和图标清晰。通知区域 MUST 使用 `GhostPinStatusBar` 同源图形，不得使用系统通用占位图标。

#### Scenario: 查看默认 HUD 和通知区域

- **WHEN** 用户在默认外观和 100%、150% 或 200% 缩放下启动原型
- **THEN** HUD 显示清晰的浅色 GhostPin 层级，通知区域显示 GhostPin 品牌图标，透明边缘没有不透明矩形底色

### Requirement: 任务契约与投影兼容

原生原型 SHALL 兼容现有 Windows GhostPin 任务 JSON 的字段、小写枚举、UUID、ISO 8601 日期、未知字段和缺少 `status` 的旧数据映射。相同任务、当前时间、时区、范围和条数上限输入 MUST 产生与当前 Windows HUD 一致的 Doing/Todo 分区、排序、截止与逾期状态和截断结果。

#### Scenario: 加载兼容任务文件

- **WHEN** 任务文件包含 Todo、Doing、Done、可空字段、未知字段和缺少 `status` 的旧任务
- **THEN** HUD 只投影有效的 Todo 与 Doing 任务，按兼容规则显示字段，并忽略不影响已知契约的未知字段

#### Scenario: 文件暂时无效

- **WHEN** 任务文件在外部写入期间暂时无法完整解析
- **THEN** HUD 保留最后一次成功加载的任务列表、报告可诊断错误且不覆盖源文件

### Requirement: 交互状态推进与原子写回

交互模式下，任务圆形按钮 SHALL 执行 `Todo → Doing → Done`，成功推进 MUST 原子写回 `%LOCALAPPDATA%\GhostPin\todos.json` 并立即刷新 HUD。同一任务成功推进后的 500ms 内，系统 MUST 忽略再次推进。

#### Scenario: 推进 Todo 任务

- **WHEN** 用户在交互模式点击 Todo 任务的推进按钮
- **THEN** 系统把任务原子写为 `doing`，任务立即进入 Doing 分区且其他任务字段保持兼容

#### Scenario: 完成 Doing 任务

- **WHEN** 用户点击 Doing 任务的推进按钮且任务不在冷却期
- **THEN** 系统把任务原子写为 `done`、记录完成时间并立即从 HUD 隐藏

#### Scenario: 外部写入与推进竞争

- **WHEN** 任务在 HUD 展示后被外部进程修改或删除
- **THEN** 原型在推进前重读最新有效文件，按 UUID 应用变更；无法安全定位或解析时拒绝覆盖磁盘

### Requirement: 外部文件变化实时刷新

原生原型 SHALL 监听任务目录中的创建、修改、重命名、替换、删除及监听错误，并 SHALL 合并短时间内的重复事件后完整重载任务文件。刷新 MUST NOT 显示窗口、切换 Z 序、激活 HUD 或清空最后有效列表。

#### Scenario: 外部原子替换任务文件

- **WHEN** 外部进程以临时文件重命名或替换 `todos.json`
- **THEN** HUD 在数秒内显示替换后的完整投影且不抢占其他应用焦点

#### Scenario: 单次写入产生重复事件

- **WHEN** Windows 为同一次文件操作发出多个相邻通知
- **THEN** 原型将其合并为一次稳定重载，HUD 不重复闪烁

#### Scenario: watcher 停止和损坏通知

- **WHEN** 应用退出或 `ReadDirectoryChangesW` 返回溢出、损坏长度或取消结果
- **THEN** 原型取消并等待 watcher 的异步 I/O 后再释放资源；损坏通知只触发一次完整重载或错误诊断，不得越界读取、释放悬空缓冲区或清空最后有效列表

### Requirement: 交互态与穿透态的真机门禁

原型 SHALL 通过集中式状态机切换交互态和穿透态，并 SHALL 读回验证窗口扩展样式；`WS_EX_TRANSPARENT`、`WS_EX_NOACTIVATE` 和 `HTTRANSPARENT` MUST NOT 被当作跨进程点击穿透的充分保证。

#### Scenario: 穿透态验收

- **WHEN** HUD 处于默认穿透态且用户点击下层应用
- **THEN** 下层目标应用实际收到输入，HUD 不获得焦点且不改变前台窗口；若真机验证失败，该构建被标记为验收失败而不是静默宣称支持

### Requirement: 通知区域与双页设置基本一致

通知区域 SHALL 提供显示或隐藏 HUD、切换交互模式、打开设置和退出入口。设置窗口 SHALL 包含“HUD”和“高级”两个页签：HUD 页调整透明度、显示范围、条数上限、置顶和登录时启动，高级页录制或清除唯一的可选全局交互快捷键。设置修改 SHALL 立即应用并持久化，重复打开 MUST 复用同一窗口实例。

#### Scenario: 打开并修改 HUD 设置

- **WHEN** 用户从通知区域打开设置并修改透明度、范围、条数上限或置顶
- **THEN** 单一设置窗口反映当前值，HUD 立即更新，原型专属设置文件保存合法值

#### Scenario: 录制全局快捷键

- **WHEN** 用户在高级页录制包含有效修饰键的普通键或单独的 F1 至 F20，并且系统成功注册
- **THEN** 原型保存并启用该组合，按下时只切换 HUD 穿透与交互模式

#### Scenario: 快捷键冲突

- **WHEN** 新候选无法注册
- **THEN** 原型不保存候选、显示冲突原因，并在原组合此前启用时恢复原组合

### Requirement: 多显示器与偏好恢复

原生原型 SHALL 以 Per-Monitor DPI 感知方式保存并恢复 HUD 的可见性、位置、尺寸、透明度、置顶、模式、范围和条数上限。已保存显示器缺失或窗口完全离屏时，HUD MUST 回到当前主显示器的可见工作区。

#### Scenario: 跨不同 DPI 显示器移动

- **WHEN** 用户把交互态 HUD 移到缩放比例不同的显示器
- **THEN** HUD 按新 DPI 重新布局，文字、图标和命中区域保持可用，随后保存新位置和尺寸

#### Scenario: 已保存显示器断开

- **WHEN** 原型恢复的窗口位置不与任何当前显示器工作区相交
- **THEN** HUD 在主显示器可见区域内恢复，并将尺寸限制在合法范围

### Requirement: 可复现的原型评估

系统 SHALL 用同一提交、Release x64 配置和同一 Windows 设备记录 Rust 原生原型与当前 WPF 自包含版本的 EXE 精确字节数、发布文件数量、PE imports、HUD 可见启动耗时和稳定后的工作集内存，并 SHALL 记录 `rustc`、Cargo、`windows` crate、MSVC、Windows SDK 版本及核心行为人工验收结果。评估结果 MUST 明确原生方案相对 WPF 的差值、10,000,000 字节门槛、失败项和继续、替换或终止建议。

#### Scenario: 生成对照结果

- **WHEN** 两个实现均完成 Release 构建并在相同设备完成规定次数的采样
- **THEN** 仓库中的评估记录包含原始数据、采样命令、环境、汇总值、相对差值和可复现步骤

#### Scenario: 原型未通过决策门槛

- **WHEN** 任一核心窗口、数据安全、错误处理或设置交互验收失败，原生单文件 EXE 超过 10,000,000 字节，或原生单文件 EXE 不小于 WPF 自包含 EXE
- **THEN** 当前 WPF 实现和发布流程保持不变，评估记录明确失败原因且不得把原型切换为正式 Windows 产物

### Requirement: 原型不进入正式发布

本变更期间，GitHub Release SHALL 继续使用现有 WPF 产物，原生实现 MUST NOT 替换正式下载或改变 macOS 工程。Windows 本地开发入口 SHALL 通过平台自动识别的 `make start` 构建并启动原生实现；WPF 项目在迁移期间作为回退基线保留，正式退场 SHALL 通过后续独立变更决定。

#### Scenario: 原型通过所有门禁

- **WHEN** 原生原型、测试和评估记录完成且所有自动化、真机和体积门禁通过
- **THEN** 当前 Windows 发布仍产出既有 WPF EXE，Windows 本地 `make start` 可启动原生实现，macOS 构建与 DMG 不变

#### Scenario: 原型门禁失败

- **WHEN** 任一自动化、真机或体积门禁失败
- **THEN** `make start` 保持 WPF 默认入口，CMake/C++ 原型不删除，评估证据保留且 Rust 候选不进入正式发布
