# Proposal

## Why

当前发布包只包含 App 和 CLI，项目维护的 `ghostpin-cli` skill 没有随版本分发，安装用户无法通过 CLI 获取或更新它。需要让 skill 与应用版本一起交付，并提供明确的覆盖更新入口，同时保护符号链接和不属于 GhostPin 的同名目录。

## What Changes

- 将完整的 `skills/ghostpin-cli/` 打包到 App 的 `Contents/Resources/skills/ghostpin-cli/`，并在 skill 根目录增加名为 `ghostpin-cli` 的空普通文件作为归属标记。
- 新增 `ghostpin-cli init`，将随包 skill 安装到当前用户的 `~/.agents/skills/ghostpin-cli/`；重复执行时整目录替换，清除旧版多余文件和本地新增文件。
- 覆盖前解析符号链接，检查最终真实目录中的归属标记，再替换真实目录并保留原链接。未标记目录、断开或循环的链接、非目录目标必须拒绝覆盖；替换失败时保留或恢复旧目录。
- 为 `init` 提供帮助和 JSON 输出，补充安装说明、隔离行为检查及发布包内容校验。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `todo-agent-skill`：增加完整 skill 随包分发、归属标记和初始化说明。
- `todo-cli`：增加 `init` 的安装、链接解析、覆盖保护、失败恢复、帮助与输出契约。
- `github-release-workflow`：要求 macOS App 和 DMG 包含与当前提交一致的完整 skill，并在发布前验证。

## Impact

- CLI 命令入口和输出位于 `Sources/GhostPinCLI/`；文件安装逻辑下沉到 `Sources/GhostPinCore/` 中的独立模块，保持命令入口只负责参数、调用和结果输出。
- 打包涉及 `script/build_and_run.sh`、`script/package_dmg.sh` 和 `.github/workflows/release.yml`；skill 文件涉及 `skills/ghostpin-cli/`。
- 验证涉及 `Tests/GhostPinCoreChecks/main.swift`、`script/check_cli.py` 和 DMG 内容检查；用户说明涉及 `README.md`、`README.en.md` 和 skill 使用说明。
- 不新增依赖，不修改任务存储或现有任务命令契约。本次只规划 macOS 的 App Bundle CLI，不增加 App 自动安装入口，也不调整 Windows 发布行为。
