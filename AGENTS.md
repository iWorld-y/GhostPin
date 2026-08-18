# AGENTS.md

## 项目概述

GhostPin 是一个 **Agent native**、本地优先的 macOS 菜单栏待办应用，使用 SwiftUI、AppKit 和 Swift Package Manager。App 负责菜单栏、桌面幽灵 HUD、设置、文件监听与本地通知；任务主要由 Agent 通过随应用分发的 `ghostpin-cli` 管理。最低支持 macOS 14，全部目标使用 Swift 6 语言模式编译（`swiftLanguageModes: [.v6]`）。

## Build & Run

```bash
make help                           # 查看 Makefile 中的可用命令
make build                          # 构建全部 Swift 目标
make dev                            # 构建并启动开发版 App
make restart                        # 构建并重启开发版 App
make stop                           # 停止 GhostPin 进程
make test                           # 运行全部核心行为检查
make verify                         # 构建 App 并验证进程可启动
make logs                           # 启动 App 并跟踪统一日志
make telemetry                      # 跟踪 GhostPin subsystem 日志
make cli ARGS='list --json'         # 执行开发版 CLI；可能访问真实本地任务数据
make dmg                            # 构建并校验 DMG
```

底层入口为 `swift build`、`swift run GhostPinCoreChecks`、`./script/build_and_run.sh --verify` 和 `./script/package_dmg.sh`。构建产物写入已忽略的 `.build/`、`dist/`。

## Testing

- 测试目标是可执行程序 `GhostPinCoreChecks`，不是 XCTest；`swift test` 不是本仓库的测试入口。
- 所有用例定义在 `Tests/GhostPinCoreChecks/main.swift`，并须手动注册到文件顶部的 `checks` 数组，否则不会执行。目前没有单用例筛选器。
- 任一检查失败会输出 `FAIL` 并以退出码 1 结束。日期相关用例固定使用 GMT+8、`zh_CN` 日历，不要擅自更改。
- Core 改动至少运行 `make test`；CLI 改动运行 `make build` 并为下沉到 Core 的行为运行 `make test`；AppKit/SwiftUI、窗口或设置改动运行 `make verify`；打包改动运行 `make dmg`。

## Project Structure

- `Sources/GhostPinCore/`：Model、`TodoStore`、JSON 文件存储和日期支持；不得导入 AppKit 或 SwiftUI。
- `Sources/GhostPin/`：应用入口、`AppState`、窗口协调、菜单栏、HUD、设置、通知、文件监听和可选全局快捷键。
- `Sources/GhostPinCLI/`：`ghostpin-cli` 参数解析与输出，依赖 `GhostPinCore`。
- `Tests/GhostPinCoreChecks/`：依赖 `GhostPinCore` 的可执行行为检查，不覆盖 CLI 参数解析或 AppKit/SwiftUI 层。
- `skills/ghostpin-cli/`：已安装 App 的 Agent 操作契约。
- `script/`：开发启动、DMG 打包与发布脚本。
- `openspec/specs/`：当前正式规格；`openspec/changes/archive/`：已归档变更。
- `.github/workflows/release.yml`：`v*` tag 触发的 DMG 发布流程。

## Agent Native 与数据边界

- 处理真实 GhostPin 待办前，先读取 `skills/ghostpin-cli/SKILL.md`，并使用固定入口 `/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli`；不要直接编辑 `todos.json`，也不要用 `.build`、PATH 或 `swift run` 代替已安装 CLI。
- 修改已有任务前先用 `list --all --json` 获取真实 UUID；同名无法消歧时先询问；写后检查 JSON 和退出码，删除后再次查询确认。
- HUD 当前唯一允许的任务写交互是状态推进：`Todo → Doing → Done`（`AppState.advanceStatus`）。新增、字段编辑、重开和删除仍只能通过 CLI；不要给 App 增加这些录入 UI。
- 全局快捷键只用于切换 HUD 穿透/交互模式，默认关闭且由用户在「高级」设置中配置；不要增加其他全局快捷键。
- App 通过 `TodoFileWatcher` 监听 CLI 写入并重新加载；业务逻辑下沉到 `GhostPinCore`，`AppState` 只做服务和 UI 编排。
- 任务数据位于 `~/Library/Application Support/GhostPin/todos.json`，偏好位于 UserDefaults。首次升级可从旧 `TodoPin/todos.json` 复制数据并保留源文件，不要破坏该兼容逻辑。
- `reminderAt` 到点触发本地通知，发送后记录 `reminderSentAt`；没有周期提醒或免打扰策略。

## Code Style

- 保持现有 Swift 风格：显式类型、早返回、简短函数、最少抽象和最少注释；不要顺手格式化或重构无关代码。
- Core 中新增可复用业务逻辑，App 层只保留流程编排；新增文件和命名应匹配相邻目录。
- 仓库没有 SwiftLint、SwiftFormat 或其他 lint/formatter 配置，不要声称运行了不存在的检查。

```swift
public func ghostPinDayStart(for date: Date) -> Date {
    startOfDay(for: date)
}
```

## Change, Git & Release Workflow

- 新产品需求使用 `openspec/config.yaml` 的 `spec-driven` 流程：`opsx-propose` → `opsx-apply` → `opsx-archive`。不要把归档变更当作待实现任务。
- 仓库有 `.codegraph/`；理解或定位代码时先运行 `codegraph explore "<问题或符号>"`，再使用精确的 `rg` 补充。
- 提交信息使用中文；提交前检查 `git status --short`、暂存范围和与改动风险相称的验证结果。
- 仓库没有常规 PR/test CI；唯一 GitHub Actions 工作流由 `v*` tag 触发，运行 Core checks、构建并校验 DMG、创建 GitHub Release。
- `make release` / `script/release.sh` 会切换到 `main`、可能提交 `script/VERSION`、拉取并推送 `main`、创建并推送 tag。只有用户明确授权发布时才可运行，不能把它当作验证命令。
- 用户文档包括 `README.md`、`README.en.md`、`CHANGELOG.md` 和 `docs/`；正式行为以 `openspec/specs/` 与当前代码为准。

## Boundaries

- ✅ **Always do:** 精准改动；为行为变化添加并注册检查；按改动层级运行 `make test`、`make verify` 或 `make dmg`；保持 CLI、App 与正式规格一致。
- ⚠️ **Ask first:** 新增依赖、修改存储格式或迁移、改变公开 CLI 参数/JSON 契约、增加 App 写入口或全局快捷键、调整发布流程、执行任何发布或远程 Git 操作。
- 🚫 **Never do:** 直接修改用户的 `todos.json`；让 `GhostPinCore` 依赖 UI 框架；绕过 `skills/ghostpin-cli/SKILL.md` 操作真实任务；未经授权推送 `main`、tag 或 Release；提交密钥、证书或签名材料。
