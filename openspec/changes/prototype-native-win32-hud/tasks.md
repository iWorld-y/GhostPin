## 1. 原生工程与工具链

- [x] 1.1 在 Windows 11 x64 开发机检查并记录 Rust MSVC、MSVC 链接器、Cargo、Windows SDK 版本；缺失工具只在获得用户授权后安装，并验证最小 windows-rs Win32 程序可编译运行
- [x] 1.2 在 `windows-native/` 创建 App、Core 和 CoreChecks 分层 Cargo 工程，启用 Rust MSVC、静态 CRT、Release 优化与 Per-Monitor V2 manifest
- [x] 1.3 将 GhostPin 同源品牌图标、版本信息和所需视觉资源编译进 PE 资源，确保构建定义和资源路径不依赖开发机绝对路径
- [x] 1.4 建立 Rust 所有权/Drop 基础封装和统一错误结果，覆盖 COM、窗口、GDI、图标、菜单、文件、线程与热键句柄的确定性释放

## 2. 任务领域与 JSON 兼容

- [x] 2.1 实现不依赖 Win32 UI 的 Rust 任务、状态、优先级、HUD 范围和设置模型，并注册 CoreChecks 可执行行为检查
- [x] 2.2 使用 `Windows.Data.Json` 实现 UTF-8 任务 codec，覆盖小写枚举、UUID、ISO 8601、可空与未知字段、缺少 `status` 的旧数据以及无效内容测试
- [x] 2.3 复用现有跨语言 fixtures 实现 Doing/Todo 投影纯函数，覆盖全部/今天范围、排序、截止与逾期、空分区、条数上限和 Done 隐藏的黄金结果
- [x] 2.4 实现 `Todo → Doing → Done` 推进、完成时间和可注入单调时钟的 500ms 冷却，测试无效状态、重复请求和任务不存在时不产生写入
- [x] 2.5 实现设置逐字段校验、快捷键候选规则和窗口 placement 纯计算，测试越界回退、显示器缺失、负坐标及不同 DPI 换算

## 3. 原生存储与文件刷新

- [x] 3.1 实现 `%LOCALAPPDATA%\GhostPin\todos.json` 与 `native-settings.json` 路径解析和目录初始化，测试设置与现有 WPF 文件完全隔离
- [x] 3.2 实现串行任务仓储、最后有效快照、推进前重读、同目录临时写入、`FlushFileBuffers` 和原子替换，测试缺失文件、损坏文件、UUID 竞争及写回兼容性
- [x] 3.3 使用 `ReadDirectoryChangesW` 实现目录级创建、修改、删除、重命名和溢出监听，通过消息窗口执行 500ms 防抖和完整重载
- [ ] 3.4 通过集成检查验证外部原子替换、重复事件合并、自身写入去重、暂时损坏后恢复，以及刷新路径不触发窗口显示或激活
- [x] 3.5 实现原型命名 mutex 和当前用户会话 WPF 进程检测，验证冲突时在初始化仓储前退出且不修改任务或设置

## 4. HWND 与 Direct2D HUD

- [x] 4.1 实现集中式 Win32 窗口类、消息循环和 Passthrough/Interactive 扩展样式计算，测试工具窗口、layered、transparent、no-activate 与 app-window 位的组合
- [x] 4.2 实现 32 位预乘 BGRA DIB、Direct2D DC render target、DirectWrite 和 WIC 资源管线，通过 `UpdateLayeredWindow` 提交逐像素透明帧并处理设备资源重建
- [x] 4.3 绘制浅色白绿黄 HUD、品牌标题、空状态、Doing/Todo 分区、任务标题/描述/优先级/截止状态、滚动裁剪和圆形推进按钮
- [x] 4.4 实现默认穿透、非激活显示、独立置顶切换、交互态按钮命中、背景拖动和四边四角缩放，确保任务刷新与重绘不调用激活或前台切换 API
- [x] 4.5 实现 Per-Monitor V2 DPI、显示器工作区、最小尺寸、跨屏建议矩形和离屏恢复，并在稳定移动或缩放后持久化逻辑位置
- [ ] 4.6 为透明边缘、浅色色阶、文字清晰度、GhostPin 图标和两种模式视觉差异建立固定截图验收基准

## 5. 托盘、设置、快捷键与应用编排

- [x] 5.1 实现只负责连接 Core、Storage、Platform 和 Render 的 App Controller，以及启动、隐藏 HUD、错误诊断和有序退出生命周期
- [x] 5.2 使用 `Shell_NotifyIconW` 和同源 GhostPin 图标实现显示/隐藏、模式切换、设置和退出菜单，保持勾选状态与 HUD 状态同步并清理退出后的托盘图标
- [x] 5.3 使用 Win32 Common Controls 实现单实例浅色设置窗口及 HUD/高级双页，接入透明度、范围、条数上限、置顶和立即持久化
- [x] 5.4 在高级页实现快捷键录制、Esc 取消、清除、`RegisterHotKey`/`UnregisterHotKey`、`MOD_NOREPEAT`、冲突回退及模式同步
- [x] 5.5 完成异常路径编排，验证 JSON、设置、渲染、托盘或平台调用失败时保留最后有效任务、输出可诊断信息并安全释放资源

## 6. 构建、验证与决策记录

- [x] 6.1 在 Windows 11 x64 运行 Cargo Release Build、cargo test 与 CoreChecks，记录完整工具版本、检查数量与所有非零退出结果
- [x] 6.2 检查 Release 目录和 PE 依赖，验证正式原型分发只需一个 x64 EXE，且不依赖 .NET、Visual C++ Redistributable、第三方 DLL 或同目录资源
- [ ] 6.3 在未安装 .NET 和 Visual C++ Redistributable 的干净 Windows 11 x64 环境启动单个 EXE，验证 HUD、托盘、退出和缺失任务文件的首次启动路径
- [ ] 6.4 人工验证默认穿透点击下层、焦点保持、任务栏/Alt+Tab 隐藏、交互按钮、拖动、八方向缩放、置顶、托盘生命周期、双页设置和全局快捷键
- [ ] 6.5 在 100%、150%、200% DPI、负坐标双显示器和显示器断开场景验证透明边缘、文字清晰度、命中区域、跨屏移动及重启恢复
- [ ] 6.6 备份测试任务文件并确认 WPF 已退出后，人工验证外部创建、修改、原子替换、短暂损坏恢复、状态推进竞争和 500ms 冷却，结束后恢复测试前数据
- [x] 6.7 实现可重复评估脚本，在同一提交、设备和 Release x64 配置下多次采集 WPF 与原生 EXE 精确字节数、发布文件数、HUD 可见启动耗时和稳定工作集
- [ ] 6.8 在 `docs/windows-native-hud-evaluation.md` 记录原始样本、环境、命令、汇总值、相对差值、人工验收结果和继续/替换/终止建议，未通过门槛时明确保留 WPF
- [x] 6.9 重新运行现有 Windows WPF 构建与测试，确认 `make build`/`make test`、Release workflow、正式 EXE 和 macOS 工程均未被原型改写，并确认开发期 `make start` 明确启动 Rust 原型
- [x] 6.10 运行 `openspec validate prototype-native-win32-hud --strict` 和全量严格校验，检查最终 diff 只包含原型、评估及明确规划范围，不提交构建产物
