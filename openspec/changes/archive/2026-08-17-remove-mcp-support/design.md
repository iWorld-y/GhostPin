## Context

当前 `todopin-cli` 已能独立读写与 App 相同的 `todos.json`，但 Swift Package 仍包含 TodoPinMCP target，CLI 通过一个子命令依赖该 target。协议工具还提供 CLI 尚未暴露的优先级、截止时间和描述写入。与此同时，仓库内 Skill 优先选择源码构建产物，不适合只安装了 TodoPin.app 的普通用户。参见 proposal.md 与本变更的 delta specs。

## Goals / Non-Goals

**Goals:**

- 在移除协议模块前让 CLI 覆盖全部任务字段写入，避免能力倒退。
- 让每条用户命令都能在不满足业务参数的情况下独立显示准确帮助。
- 让 Skill 成为纯用户向说明，始终调用正式安装 App Bundle 内的 CLI。
- 解除 CLI、测试目标与协议 target 的构建依赖，并删除不再使用的源码和测试。
- 保持 `todos.json` 格式、现有 CLI JSON 输出和 App 文件监听行为兼容。

**Non-Goals:**

- 本阶段不安装符号链接、不修改 PATH 或环境变量。
- Skill 不发现非标准 App 安装位置，也不提供源码构建或开发运行 fallback。
- 不迁移或自动修改既有 Agent 客户端配置。
- 不改写 `openspec/changes/archive/` 和既有发布历史。

## Decisions

### 1. 先补齐 CLI 字段，再删除协议模块

扩展 `add` 支持 `--priority`、`--due`、`--description`，扩展 `update` 支持上述参数及 `--clear-due`。参数解析继续沿用现有显式 flag 模式，日期继续使用 ISO8601，优先级只接受 `high`、`medium`、`low`。更新时先读取当前任务，未提供的字段原样传回 TodoStore。

先完成和验证这些参数，再移除旧模块，可把破坏性变化限制在调用入口，而不是任务管理能力。备选方案是直接删除旧模块并接受字段能力缺失，但这不满足“Skill + CLI 替代”的目标。

### 2. 在业务参数解析前处理命令级帮助

根命令以及 `list`、`add`、`doing`、`done`、`undone`、`update`、`delete`、`version` 均接受 `-h` 与 `--help`。命令分派先识别帮助请求，再进入该命令的位置参数、选项校验或 TodoStore 初始化；因此 `todopin-cli update --help` 不需要 id，输出只描述 update 的用法和选项，以退出码 0 结束且不访问任务数据。

每条命令维护一段短小的专属帮助，根帮助只负责列出命令和全局选项。备选方案是让所有子命令重复输出根帮助，但用户仍无法直接发现 `update --due`、`--clear-due` 等命令专属参数，因此不采用。另一个备选方案是引入第三方参数解析库，但当前命令规模很小，会增加不必要依赖，也不采用。

### 3. CLI 直接依赖 TodoPinCore

删除 CLI 中的协议模块 import、子命令分支、服务器启动函数和帮助文本；从 Package.swift 删除 TodoPinMCP target，并让 TodoPinCLI 与 TodoPinCoreChecks 只依赖 TodoPinCore。CLI 的 JSON 响应结构已位于 TodoPinCLI，任务 payload 已位于 TodoPinCore，因此无需新建共享模块或迁移数据类型。

备选方案是保留空壳 target 维持构建兼容，但会留下无实际用途的模块和错误的可用性信号，因此不采用。

### 4. Skill 固定调用标准安装路径

`skills/todopin-cli/SKILL.md` 的所有命令直接使用 `/Applications/TodoPin.app/Contents/MacOS/todopin-cli`。执行前只检查该文件是否可执行；检查失败时提示用户把 TodoPin.app 安装到 `/Applications` 并停止，不尝试环境变量、PATH、符号链接、其他 App 位置或仓库构建产物。

Skill 的 frontmatter、正文和示例全部面向安装用户，并通过静态检查禁止协议术语和开发入口。固定路径牺牲非标准安装兼容性，但行为确定、不会误选工作区中的陈旧二进制，符合本阶段范围。

### 5. 发行包继续以 App Bundle 承载 CLI

保留 `package_dmg.sh` 将 release 构建的 `todopin-cli` 复制到 `TodoPin.app/Contents/MacOS/` 的机制，并以打包验证确认该文件存在、可执行且与主程序来自同一次构建。Skill 不依赖构建仓库，因此正式 DMG 是用户入口的唯一交付物。

### 6. 测试按职责收敛

从 TodoPinCoreChecks 删除协议帧、工具声明和工具调用测试；保留并扩展 TodoStore 对字段保持、状态转换和持久化的行为检查。CLI 层增加参数校验与隔离存储下的命令冒烟检查，覆盖完整字段新增、部分字段更新、修改与清除截止时间、非法日期/优先级不写入，以及每条命令的 `-h`、`--help` 无副作用行为。继续运行 `swift run TodoPinCoreChecks`、`swift build` 和 `./script/build_and_run.sh --verify`，并验证 DMG 内 CLI 路径。

## Risks / Trade-offs

- [已配置的协议客户端在升级后无法调用] → 在 README 和发布说明中明确破坏性变化，并给出 Skill + CLI 命令映射。
- [固定 `/Applications` 路径不支持移动 App] → Skill 明确提示标准安装要求；路径发现和符号链接留给后续独立变更。
- [CLI 新参数可能在部分更新时覆盖未指定字段] → 更新前读取当前任务，并为字段保持增加定向检查。
- [命令参数变化后专属帮助可能过期] → 帮助文本与解析选项放在同一 CLI 模块，并用逐命令冒烟检查覆盖关键选项。
- [删除大量协议测试降低表面覆盖数量] → 以 Core 行为检查和 CLI 端到端冒烟覆盖仍保留的用户能力，不保留已删除接口的测试。
- [历史文件仍包含旧术语] → 静态清理范围限定为当前源码、主规格、README、AGENTS 和 Skill；归档与既有发布历史保留。

## Migration Plan

1. 扩展 CLI 字段参数和逐命令帮助，验证截止日期修改、帮助无副作用与现有 JSON 契约。
2. 将 Skill 改为固定正式安装路径，补充缺失路径和消歧行为检查。
3. 删除 CLI 子命令、TodoPinMCP target、源码与对应测试，确认 Swift Package 依赖闭合。
4. 更新当前主文档和 delta 影响的规格，打包并验证 App Bundle 内 CLI。
5. 发布时把入口迁移说明列为破坏性变化；出现阻断时回退到上一发行版本，不执行数据迁移，因为存储格式未变化。
