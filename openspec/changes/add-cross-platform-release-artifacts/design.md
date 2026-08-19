## Context

参见 [proposal.md](proposal.md) 的动机。当前 `.github/workflows/release.yml` 只有一个 `macos-15` job：校验 tag 与 `script/VERSION`、运行 Swift 核心检查、调用现有 DMG 脚本并直接创建 Release。Windows WPF 项目以 .NET 10、`net10.0-windows` 和 `win-x64` 构建，但尚无发布脚本、单文件属性或 CI job。

根目录 `Makefile` 已按平台编排 `build`、`test` 等入口，`package` 当前仅指向 macOS DMG。Windows 首次执行自包含发布需要下载对应运行时包；开发机上的普通 framework-dependent 构建不能替代该发布验证。

## Goals / Non-Goals

**Goals:**

- 将版本解析、两个平台构建和 Release 创建分层，确保 Release job 只消费已经验收的不可变产物。
- 让本地与 CI 复用同一套平台打包脚本和产物命名规则。
- 让 Windows 发布物成为无需解压、无需预装 .NET Runtime 的一个可执行文件。
- 保留 tag 发布语义，同时提供不会误发 Release 的手动预检入口。

**Non-Goals:**

- 不改变 GhostPin 的任务数据、HUD 行为或平台 UI。
- 不加入 Windows 安装器、MSIX、自动更新、Authenticode 签名或 SmartScreen 绕过方案。
- 不改变 macOS 的架构、ad-hoc 签名、公证和 DMG 布局。
- 不把两个平台合并到同一个压缩包，也不发布 framework-dependent Windows 版本。

## Decisions

### 1. Workflow 使用元数据、双平台构建、发布四段式结构

增加一个轻量元数据 job，统一从 `script/VERSION` 读取版本并在 tag 触发时校验 tag；随后 `build-macos` 和 `build-windows` 并行运行，分别上传 Actions artifact。最终 `release` job 同时依赖两个构建 job，下载并校验两个产物后，通过一次 Release 创建命令上传它们。

这样可以避免两个平台并发修改同一个 Release，也能保证任一平台失败时发布 job 根本不会运行。备选方案是在单个 job 中顺序构建，但 GitHub hosted runner 不能在一次 job 中切换操作系统，且会失去并行构建和平台隔离。

### 2. `workflow_dispatch` 复用构建图但跳过 Release

发布工作流同时监听 `workflow_dispatch`。手动运行与 tag 运行使用相同的元数据、测试、打包和 artifact 上传步骤；`release` job 仅在 `push` 的 `v*` tag 事件下执行。手动运行以所选提交中的 `script/VERSION` 命名产物。

备选方案是新建独立验证 workflow，但会复制关键步骤并产生两套易漂移的发布逻辑。单工作流通过条件化最后一个 job 即可保持一致性。

### 3. Windows 使用不裁剪的 self-contained single-file 发布

Windows 打包脚本通过 `dotnet publish` 指定 `win-x64`、self-contained、single-file、原生库自解压和单文件压缩，并显式关闭 trimming 与调试符号输出。WPF 对裁剪并不安全，关闭 trimming 用体积换取运行可靠性；原生组件可能在启动时解压到系统临时目录，但对用户仍表现为只需下载和启动一个 EXE。

脚本从 `script/VERSION` 读取版本，传入程序集、文件和产品版本元数据，在隔离的暂存目录发布，再将唯一可运行文件复制为 `dist/GhostPin-<version>-windows-x64.exe`。项目引用一个仓库内固定的 `.ico` 资源，避免 CI 临时转换图标造成不一致。

备选方案包括 framework-dependent 单文件、ZIP 和 MSIX。前者要求用户预装正确的 .NET Runtime，ZIP 仍需解压，MSIX 引入证书和安装生命周期，均不符合本次直接下载 EXE 的目标。

### 4. 平台差异下沉到脚本，Makefile 只负责选择

保留 `make package` 作为唯一公共打包入口。Makefile 根据 Windows 的 `OS=Windows_NT` 或 macOS 的 `uname` 选择 `script/package_windows.ps1` 或现有 `script/package_dmg.sh`；Windows 脚本承载 publish 参数、文件命名和产物校验，避免把 PowerShell 业务逻辑塞入 Makefile。

`make dmg` 继续作为现有 macOS 专用兼容入口，不把无意义的 DMG 命令映射成 Windows 打包。备选方案是增加 `package-windows` 公共目标，但会违背已有的跨平台统一命令约定。

### 5. CI 对产物做结构与启动双重校验

macOS job 保留当前 Core checks、Bundle、签名、CLI 路径与 DMG 校验。Windows job 运行 solution tests，执行发布脚本，确认 `dist` 中只有期望名称的 EXE，并启动该文件、确认进程存活后正常终止。发布 job 再次校验下载后的文件名和数量，防止 artifact 目录结构或通配符变化导致误传。

Windows 启动检查只能证明应用在 hosted runner 上可启动，不能替代 HUD、托盘和快捷键的人工验收；这些 UI 行为仍由 Windows HUD 变更的验收任务覆盖。

## Risks / Trade-offs

- [Windows 自包含 EXE 体积明显大于 framework-dependent 构建] → 开启单文件压缩，但不启用可能破坏 WPF 的 trimming。
- [首次本地 publish 需要联网下载 `win-x64` 运行时包，开发机网络可能失败] → CI 明确安装 .NET 10 SDK；本地脚本保留清晰的 restore/publish 错误，不用普通 build 冒充发布成功。
- [未签名 EXE 可能触发 SmartScreen 警告] → 在发布说明中明确未签名边界，未来取得证书后再独立设计签名流程。
- [单文件原生库可能在运行时写入临时目录] → 使用 .NET 官方单文件机制，不承诺零临时文件，只承诺分发物为单个 EXE。
- [两个平台的 Actions artifacts 会增加存储占用] → 使用有限保留期；GitHub Release 仍只保留最终两个应用资产。
- [Release 创建期间发生网络故障可能留下不完整草稿或 Release] → 创建前严格核对两个文件，并以一次命令同时上传；失败时不自动覆盖或重试已有 Release，由维护者检查后人工处理。

## Migration Plan

1. 在 `main` 上加入 Windows 图标/版本元数据、打包脚本、Makefile 分发和四段式工作流。
2. 分别在 macOS 与 Windows 开发机执行现有测试、平台构建和 `make package`，核对文件名、文件数量与启动行为。
3. 推送代码后先使用 `workflow_dispatch` 验证 hosted runners 的两个 Actions artifacts，不创建 Release。
4. 下一次正常版本发布继续由现有发布脚本推送 `v*` tag；新工作流在双平台成功后创建同一个 Release。

本变更不涉及用户数据迁移。若手动验证失败，可回滚 workflow、Makefile、Windows 打包脚本和图标元数据，不影响既有已发布版本；若某平台在 tag 构建中失败，不会创建新 Release。
