# 任务分组与递增 ID 验证记录

变更：`add-task-groups-and-sequential-ids`。规划文档已先以 `d52bb12` 提交，实现在本地分支 `feat-task-groups-and-sequential-ids`。本文的自动检查均使用隔离数据。之后按用户授权完成升级前备份和开发版预览，回读核对任务总数、整数 ID、默认组及业务字段；正式安装包未替换。

## 已执行检查

| 命令或检查 | 实际结果 |
| --- | --- |
| `make build` | 退出码 0，Debug App、CLI 和 Core checks 构建通过 |
| `make test` | 退出码 0，41 项已注册 Core 检查全部通过 |
| `python3 script/check_cli.py` | 退出码 0，隔离 CLI 集成检查通过 |
| `make verify` | 退出码 0，隔离 App 启动通过，验证进程与临时目录已清理 |
| `swift build -c release` | 退出码 0，原始 Release 命令构建通过 |
| `.build/release/GhostPinCoreChecks` | 退出码 0，Release 下 41 项 Core 检查全部通过 |
| Debug / Release 字符串检查 | Debug App、CLI 包含 `GHOSTPIN_TEST_SUPPORT_ROOT`；两份 Release 产物均不包含 |
| `ruff check script/check_cli.py`、`ruff format --check script/check_cli.py` | 退出码 0 |
| `cargo fmt --manifest-path windows-native/Cargo.toml -- --check` | 退出码 0 |
| `rustc --edition=2024 --test windows-native/src/core.rs` 及生成的检查程序 | macOS 上 4 项可移植 Core 检查通过，包含整数 ID 校验与 500ms 冷却 |
| `openspec validate add-task-groups-and-sequential-ids --strict` | 退出码 0 |

Core 每项检查使用系统临时目录中的 `GhostPinChecks-<UUID>`，通过显式 URL 注入；CLI 使用 `ghostpin-cli-check-<随机值>`，通过 Debug 环境入口传入；App 验证使用 `ghostpin-verify.<随机值>`。检查结束后均清理夹具，不读取真实任务文件。Release 检查使用显式临时文件路径，不依赖 Debug 环境入口。

首次 Release 提权编译曾因自动审批服务容量不足未执行。临时缓存目录内的受限编译随后通过，用户授权后又执行原始 `swift build -c release` 并通过；上表记录的是实际完成结果。

## 行为覆盖

- 分组：新增显式指定组别，拒绝缺失或空白组名，去除首尾空白，精确区分大小写，完整长组名、组内查询与 `--all` 组合、未知组空列表、换组保留 ID。
- 编号：从 `10000` 开始跨组递增，重启、删除最大编号和删除全部任务后继续编号；两个同步启动的 Core 进程及 8 个 CLI 进程不重复编号、不丢任务。
- 迁移：三态任务、创建时间相同的 UUID 排序、空数组、旧字段缺省值、逐字节备份、重复加载、备份冲突、备份后提交失败与重试。
- 存储保护：未知版本、重复或非法 ID、空组别、非法计数器不覆盖原文件；失败提交不发布内存状态；TodoPin 源文件不变，GhostPin 文件优先；失败参数或目标不存在不先迁移。
- 交错写入：CLI 换组和新增后，持有旧快照的内部 App 工作进程通过实际 Core 入口推进状态并记录提醒，回读保留最新组别、新任务和下一编号；删除目标不会被旧快照恢复。
- CLI 契约：JSON 数组及成功、失败外层结构，整数 ID 和完整组别，状态、update、delete 文本回执；根命令与全部子命令两种帮助均不创建任务目录。
- HUD：跨组统一投影，保留 Doing 聚焦、状态分区、排序、计数、日期范围和条数上限。未增加分组筛选或编辑入口。
- 文档：新文档示例由 Core 解码并校验；同一隔离目录中恢复原始备份，核对字节并重新迁移得到相同映射。

## macOS 标记预览

使用临时原生 `NSApplication` / `NSHostingView` 预览程序，直接读取并编译当前 `DesktopNoteCardView` 源码，连接已构建的 Core；预览不初始化 AppState、不读取任务文件或改写 App 偏好。预览窗口退出后关闭。

已目视核对 300、360 宽度下的短标题、多行标题、`默认`、三个汉字组名、超长中文组名和超长英文组名。优先级位于组别左侧，标记整体固定在卡片内容右边缘；省略号位于三汉字文本宽度内，标题使用剩余空间。优先级颜色、过期删除线、红色截止日期和描述位置保持正确。组名在 CLI 与存储中仍为完整值。

![300 宽度原生卡片预览](images/macos-task-groups-300.png)

![360 宽度原生卡片预览](images/macos-task-groups-360.png)

以上为原生卡片布局预览；`make verify` 另行验证完整 App 可启动，不代表已完成用户的真实待办升级或整机人工验收。

## Windows 待验收

Windows 模型、编解码、事务存储、状态推进和标记源码已同步，并补充共享夹具与存储检查。以下验证尚未通过，相关任务保持未勾选：

- 本机只有 `aarch64-apple-darwin` Rust 目标，没有 Windows MSVC 目标或 Windows 执行环境。
- `cargo check --offline --manifest-path windows-native/Cargo.toml --target x86_64-pc-windows-msvc` 退出码 101：缺少缓存依赖 `proc-macro2 v1.0.107`。该结果不代表 Windows 源码编译通过。
- 尚未运行 Windows 原生构建、`windows-native\test.cmd`、WinRT JSON / 文件锁存储用例，无法确认 Rust 与 Swift 的运行结果一致。
- 尚无 Windows 卡片截图、缩放与点击命中验收证据。需要在 Windows 11 上核对不同宽度下的三汉字省略和右对齐，并执行仓库既有人工验收。

用户已完成 macOS 开发版预览验收，并于 2026-10-19 明确要求同步规格、归档和合并。按该授权归档，5 项包含 Windows 验证的任务保留未完成标记；归档不代表 Windows 原生构建或视觉验收已通过。
