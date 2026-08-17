## 1. 前置变更与基线

- [x] 1.1 完成并归档 `remove-mcp-support`，确认 CLI 截止日期修改、逐命令帮助、Skill 用户入口和主规格已收敛，且期间不发布中间版本
- [x] 1.2 在前置变更归档后的代码上运行核心检查与构建，记录 GhostPin 改名前的可用基线

## 2. 数据迁移与系统身份兼容

- [x] 2.1 在隔离的 Application Support 根目录下增加全新安装、仅旧文件、新旧文件并存、旧文件损坏和迁移竞争的行为检查
- [x] 2.2 在 Core 的存储路径逻辑中将 GhostPin 设为默认目录，并实现验证旧 JSON、临时文件发布、不覆盖并发目标和保留旧文件的一次性迁移
- [x] 2.3 让 App 与 CLI 共用迁移后的 Core 路径解析，切换文件监听与临时 fallback 到 GhostPin，迁移失败时不得静默打开空数据
- [x] 2.4 保留 `com.oyuxi.TodoPin` Bundle ID，并在登录启动服务中根据既有偏好协调 GhostPin App 的 `SMAppService.mainApp` 状态
- [x] 2.5 增加偏好保持、登录启动选择和 App/CLI 读取同一 GhostPin 文件的定向检查

## 3. Swift Package 与应用品牌改名

- [x] 3.1 将 Package、App/Core/CLI/Checks products、targets、源码目录和 import 统一重命名为 GhostPin 对应名称
- [x] 3.2 将 App 入口、Logo 类型与资源文件、JSON 编码扩展、日历辅助方法和测试临时目录中的品牌前缀改为 GhostPin
- [x] 3.3 将 HUD、菜单、通知标题与通知标识中的当前产品名称改为 GhostPin，并保留 Todo 领域模型名称与数据字段不变
- [x] 3.4 运行 `swift build` 与 `swift run GhostPinCoreChecks`，确认目录移动、资源复制和模块依赖完整

## 4. CLI 与 Agent Skill 切换

- [x] 4.1 将公开可执行文件、根帮助、逐命令帮助、版本输出和错误示例从 `todopin-cli` 改为 `ghostpin-cli`，不生成旧命令兼容别名
- [x] 4.2 将仓库 Skill 重命名为 `skills/ghostpin-cli/`，同步 frontmatter 与 `agents/openai.yaml`，所有命令固定调用 `/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli`
- [x] 4.3 在隔离数据目录中执行 `ghostpin-cli` 的截止日期修改/清除、list/add/doing/done/undone/update/delete、JSON 输出和所有命令 `-h`/`--help` 冒烟检查，并确认帮助无数据副作用且旧可执行名称未被构建或打包

## 5. 打包与发布链路改名

- [x] 5.1 更新本地构建和 DMG 脚本，生成 `GhostPin.app`、`GhostPin`、`ghostpin-cli` 与 `GhostPin-<version>.dmg`，同时保留兼容 Bundle ID
- [x] 5.2 将发行环境变量改为 `GHOST_PIN_VERSION` 与 `GHOST_PIN_SIGN_IDENTITY`，更新脚本提示且不继续读取旧环境变量
- [x] 5.3 更新 GitHub Actions 的核心检查、App/CLI/DMG 路径、Info.plist 验收、Release 标题和上传资产名称
- [x] 5.4 打包 DMG 并验证签名、Bundle ID、App 名称、两个可执行文件、挂载内容和 DMG 名称全部符合 GhostPin 契约

## 6. 当前文档与迁移说明

- [x] 6.1 更新 `README.md` 与 `README.en.md` 的产品介绍、安装、CLI 完整路径、命令示例、数据目录、构建命令和项目结构
- [x] 6.2 更新 `AGENTS.md` 的项目名称、架构目录、常用命令、测试目标、存储路径和 Skill 入口
- [x] 6.3 在 CHANGELOG 新增破坏性更名、旧 App 清理、数据迁移和回退说明，不改写既有 TodoPin 发布记录
- [x] 6.4 检查当前主规格与本变更 delta 的 GhostPin 名称一致，并保留归档 OpenSpec 中的历史名称

## 7. 最终验证与交付

- [x] 7.1 运行 `swift run GhostPinCoreChecks`、`swift build` 和 `./script/build_and_run.sh --verify`
- [x] 7.2 验证旧数据首次迁移、GhostPin 后续独立写入、HUD 文件监听刷新以及旧文件不被修改
- [x] 7.3 对当前源码、文件名、脚本、README、AGENTS、Skill、主规格和新增发布说明执行旧品牌白名单扫描，仅允许兼容 Bundle ID 与迁移常量保留旧名
- [x] 7.4 运行 `openspec validate rename-todopin-to-ghostpin --strict` 与 `git diff --check`，确认规划契约、实现改动和格式检查通过
- [x] 7.5 在交付说明中列出仓库外的 GitHub 仓库改名、本地目录改名与 CodeGraph 索引刷新，未经用户另行授权不得自动执行
