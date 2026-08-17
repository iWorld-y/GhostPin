## 1. 补齐 CLI 任务字段能力

- [x] 1.1 为完整字段新增、截止日期修改与清除、部分字段保持、非法日期和非法优先级补充可隔离运行的检查
- [x] 1.2 扩展 `add` 的 `--priority`、`--due`、`--description` 参数并保持现有默认值与 JSON 输出
- [x] 1.3 扩展 `update` 的 `--priority`、`--due`、`--clear-due`、`--description` 参数，确保未提供字段保持不变
- [x] 1.4 为根命令及 list/add/doing/done/undone/update/delete/version 的 `-h`、`--help` 增加退出码 0、无需业务参数且不读写数据的行为检查
- [x] 1.5 在业务参数解析前分派命令级帮助，为每条命令输出自身用法、位置参数和选项，并在 update 帮助中列出 `--due` 与 `--clear-due`
- [x] 1.6 更新根帮助、用法文本和错误信息，并验证现有 list/doing/done/undone/delete 行为兼容

## 2. 收敛用户向 Skill

- [x] 2.1 重写 `skills/todopin-cli/SKILL.md`，所有命令固定使用 `/Applications/TodoPin.app/Contents/MacOS/todopin-cli`
- [x] 2.2 增加正式 CLI 可执行性检查、缺失安装提示、UUID 消歧和删除后复核流程
- [x] 2.3 更新 `agents/openai.yaml`，确保元数据只描述安装用户通过 CLI 管理任务
- [x] 2.4 校验 Skill 不包含协议术语、`.build`、`swift run`、`<repo-root>` 或源码开发说明

## 3. 删除协议实现与依赖

- [x] 3.1 从 `todopin-cli` 删除协议子命令、启动函数、import 和帮助文本
- [x] 3.2 从 `Package.swift` 删除 TodoPinMCP target，并让 TodoPinCLI 与 TodoPinCoreChecks 只依赖 TodoPinCore
- [x] 3.3 删除 `Sources/TodoPinMCP/` 的协议消息、服务器和工具实现
- [x] 3.4 从 TodoPinCoreChecks 删除协议测试、辅助函数、import 和检查注册，保留仍适用的 Core 行为检查

## 4. 同步当前文档

- [x] 4.1 更新 `README.md` 与 `README.en.md`，以仓库 Skill 和 App Bundle CLI 完整路径替代旧入口、配置和示例
- [x] 4.2 更新 `AGENTS.md` 的架构、测试、命令和规格说明，删除已不存在模块的当前描述
- [x] 4.3 在 CHANGELOG 新增破坏性迁移说明，同时保留既有发布历史

## 5. 验证与交付检查

- [x] 5.1 运行 `swift run TodoPinCoreChecks` 与 `swift build`，确认核心行为和 Swift Package 构建通过
- [x] 5.2 运行 `./script/build_and_run.sh --verify`，确认 App 仍可启动且文件监听链路未受影响
- [x] 5.3 运行 Skill 官方校验和静态禁词检查，确认用户向内容与完整路径契约
- [x] 5.4 打包 DMG 并确认 `TodoPin.app/Contents/MacOS/todopin-cli` 存在、可执行，截止日期修改和逐命令帮助均可用
- [x] 5.5 检查当前源码、README、AGENTS 和 Skill 不再引用已删除入口，并运行 `openspec validate remove-mcp-support --strict` 与 `git diff --check`
