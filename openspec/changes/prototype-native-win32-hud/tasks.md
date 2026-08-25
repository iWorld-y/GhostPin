## 1. Rust 工程、工具链与安全边界

- [x] 1.1 在 Windows 11 x64 开发机检查并记录稳定版 `rustc`、Cargo、`x86_64-pc-windows-msvc` target、MSVC linker 和 Windows SDK 版本；缺失工具只在获得用户授权后安装，并验证最小 `windows` crate Win32 程序可编译运行
- [x] 1.2 在 `windows-native/` 建立单 package Cargo 工程，使用合法的 `ghostpin-native`/`ghostpin_native` target，分离 library modules、GUI binary 和 tests，启用 Windows GUI subsystem 与 Per-Monitor V2 manifest，确保路径不依赖开发机绝对目录
- [x] 1.3 引入锁定版本的 Microsoft `windows` crate，只启用 Win32、COM、WinRT JSON、Direct2D、DirectWrite 和 WIC 所需 features；提交 `Cargo.lock` 并记录依赖用途与许可证
- [x] 1.4 配置 Release x64 的体积优化、LTO、单 codegen unit、`panic = "abort"`、静态 CRT 和无调试信息产物，保留可审查的开发 profile
- [x] 1.5 提交 `rust-toolchain.toml` 固定已验证的 stable 版本，并通过 `build.rs` 调用 `rc.exe` 将 GhostPin 同源品牌图标、manifest 和版本信息编译进 PE 资源；单独 `cargo build --release` 缺少资源时必须失败，确保 Release 目录不需要同目录图片、manifest 或配置资源
- [ ] 1.6 建立拥有所有权的 HWND、HANDLE、GDI、菜单、图标、热键、通知区域和 worker 封装，以及类型化模块错误；明确 `WM_NCCREATE`/`WM_NCDESTROY` 的 `GWLP_USERDATA` 生命周期、UI 线程亲和和同步重入约束，限制并说明每个非直观 `unsafe` 边界，禁止 panic 跨越 `extern "system"` 回调

## 2. Rust 任务领域与 JSON 兼容

- [x] 2.1 实现不依赖 `windows` crate 或 Win32 类型的 Rust 任务、状态、优先级、HUD 范围和设置模型，并注册平台无关 tests
- [x] 2.2 通过 `windows` crate 的 `Windows.Data.Json` 实现 UTF-8 任务 codec，覆盖小写枚举、UUID、ISO 8601、可空与未知字段、缺少 `status` 的旧数据以及无效内容
- [ ] 2.3 复用现有跨语言 fixtures 实现 Doing/Todo 投影纯函数，覆盖全部/今天范围、排序、截止与逾期、空分区、条数上限和 Done 隐藏的黄金结果
- [ ] 2.4 实现 `Todo → Doing → Done` 推进、完成时间和可注入单调时钟的 500ms 冷却，测试无效状态、重复请求、任务不存在及写入失败时不留下错误状态
- [ ] 2.5 实现设置逐字段校验、快捷键候选规则和窗口 placement 纯计算，测试非法枚举、NaN/Inf、极端坐标、显示器缺失、负坐标及不同 DPI 换算

## 3. Rust 存储与文件刷新

- [x] 3.1 通过系统 API 实现 `%LOCALAPPDATA%\GhostPin\todos.json` 与 `native-settings.json` 路径解析和目录初始化，测试设置与现有 WPF 文件完全隔离
- [x] 3.2 实现串行任务仓储、最后有效快照、推进前重读、同目录临时写入、`FlushFileBuffers` 和原子替换；错误保留路径、操作和 Win32 错误码
- [ ] 3.3 使用 `ReadDirectoryChangesW` 实现可停止并 join 的目录 watcher，固定拥有 `OVERLAPPED`、事件和通知缓冲区直到 I/O 完成；停止先 `CancelIoEx` 再等待完成后释放，校验 `FILE_NOTIFY_INFORMATION` 边界，覆盖创建、修改、删除、重命名和溢出，通过消息窗口执行 500ms 防抖和完整重载
- [ ] 3.4 通过 Rust 集成检查验证外部原子替换、重复事件合并、自身写入去重、暂时损坏后恢复、UUID 竞争，以及刷新路径不触发窗口显示或激活
- [ ] 3.5 实现原型命名 mutex 和当前用户会话 WPF 进程检测，验证冲突时在初始化仓储前退出且不修改任务或设置

## 4. HWND 与 Direct2D HUD

- [x] 4.1 使用 `windows` crate 实现集中式窗口类、隐藏消息窗口、消息循环和 Passthrough/Interactive 扩展样式计算，测试 toolwindow、layered、transparent、no-activate 与 app-window 位组合，并将 `WS_EX_TRANSPARENT`/`HTTRANSPARENT` 明确为需真机验证的请求而非跨进程保证
- [ ] 4.2 实现 32 位预乘 BGRA DIB、Direct2D DC render target、DirectWrite 和 WIC 资源管线，通过 `UpdateLayeredWindow` 提交逐像素透明帧并处理设备资源重建
- [ ] 4.3 绘制浅色白绿黄 HUD、品牌标题、空状态、Doing/Todo 分区、任务标题、描述、优先级、截止状态、滚动裁剪和圆形推进按钮
- [ ] 4.4 实现默认穿透、非激活显示、独立置顶切换、交互态按钮命中、背景拖动和四边四角缩放；在真实下层应用验证输入确实到达且 HUD 不获焦点，失败记录为验收门禁失败；确保任务刷新与重绘不调用激活或前台切换 API
- [ ] 4.5 实现 Per-Monitor V2 DPI、显示器工作区、最小尺寸、跨屏建议矩形和离屏恢复，并在稳定移动或缩放后持久化逻辑位置
- [ ] 4.6 为透明边缘、浅色色阶、文字清晰度、GhostPin 图标和两种模式视觉差异建立固定截图验收基准

## 5. 托盘、设置、快捷键与应用编排

- [ ] 5.1 实现只连接 Core、Storage、Platform 和 Render 的安全 Rust App Controller，以及启动、隐藏 HUD、写入受限本地日志、`OutputDebugStringW`/`MessageBoxW` 错误诊断和有序退出生命周期
- [ ] 5.2 使用 `Shell_NotifyIconW` 和同源 GhostPin 图标实现显示或隐藏、模式切换、设置和退出菜单，保持勾选状态与 HUD 状态同步并清理退出后的托盘图标
- [ ] 5.3 使用 Win32 Common Controls 实现单实例浅色设置窗口及 HUD/高级双页，接入透明度、范围、条数上限、置顶和立即持久化
- [ ] 5.4 在高级页实现快捷键录制、Esc 取消、清除、`RegisterHotKey`、`UnregisterHotKey`、`MOD_NOREPEAT`、冲突回退及模式同步
- [ ] 5.5 实现当前用户范围的登录时启动注册，与设置 JSON 原子同步，并覆盖注册成功、撤销、外部变化和失败回滚
- [ ] 5.6 完成异常路径与资源清理编排，验证 JSON、设置、渲染、托盘、热键、watcher 或平台调用失败时保留最后有效状态、输出错误码和操作上下文并继续安全清理；确认 GUI subsystem 不依赖 `stderr`
- [ ] 5.7 将根目录 Windows `make start`、开发说明和工具链文档切换到 Cargo/Rust 原生目标；macOS 入口和正式 WPF 发布保持不变

## 6. 构建、验证与决策记录

- [x] 6.1 在 Windows 11 x64 运行 `cargo fmt --check`、`cargo clippy --all-targets -- -D warnings`、`cargo test` 和 `cargo build --release`，记录工具版本、检查数量与所有非零退出结果
- [ ] 6.2 检查 `cargo tree`、启用 features、许可证和源码中的 `unsafe` 位置，确认没有未批准依赖、重复 Windows bindings、C++ 链接对象或越过模块边界的原始句柄
- [x] 6.3 检查 Release 目录、EXE 精确字节数和 PE imports，验证分发只有一个不超过 10,000,000 字节的 x64 EXE，且不依赖 .NET、Visual C++ Redistributable、第三方 DLL 或同目录资源
- [ ] 6.4 在另行准备且未安装 .NET 和 Visual C++ Redistributable 的干净 Windows 11 x64 VM 或 Windows Sandbox 启动单个 EXE，验证 HUD、托盘、退出和缺失任务文件的首次启动路径；SSH 开发机只用于构建，不将其视为干净环境
- [ ] 6.5 在当前用户交互桌面或计划任务入口（不使用非交互 SSH 进程）人工验证默认穿透点击下层且目标应用实际收到输入、焦点保持、任务栏/Alt+Tab 隐藏、交互按钮、拖动、八方向缩放、置顶、托盘生命周期、双页设置和全局快捷键；穿透失败则阻断原型通过
- [ ] 6.6 在 100%、150%、200% DPI、负坐标双显示器和显示器断开场景验证透明边缘、文字清晰度、命中区域、跨屏移动及重启恢复
- [ ] 6.7 备份测试任务文件并确认 WPF 已退出后，人工验证外部创建、修改、原子替换、短暂损坏恢复、状态推进竞争和 500ms 冷却，结束后恢复测试前数据
- [ ] 6.8 实现可重复评估脚本，在同一提交、设备和 Release x64 配置下多次采集 WPF 与 Rust 原生 EXE 精确字节数、发布文件数、PE imports、HUD 可见启动耗时和稳定工作集
- [x] 6.9 在 `docs/windows-native-hud-evaluation.md` 记录原始样本、环境、`rustc`、Cargo、`windows` crate、MSVC、Windows SDK 版本、命令、汇总值、相对差值、10,000,000 字节门槛、人工验收结果和继续或终止建议
- [ ] 6.10 仅在 Rust 原型通过自动化、真机和体积验收后，移除被替代的 `windows-native/` CMake/C++ 源码、检查程序和构建入口，确认只保留一个 Rust 原生运行目标；若任一门禁失败则保留 CMake/C++，不切换默认入口
- [ ] 6.11 重新运行现有 Windows WPF 构建与测试，确认 WPF 回退基线、Release workflow、正式 EXE 和 macOS 工程均未被原型改写；门禁通过时验证 Windows `make start` 启动 Rust 原生客户端，失败时验证其仍启动 WPF 回退并保留评估证据
- [ ] 6.12 运行 `openspec validate prototype-native-win32-hud --strict` 和全量严格校验，检查最终 diff 只包含 Rust 原型、评估、C++ 原型退场及明确规划范围，不提交构建产物
