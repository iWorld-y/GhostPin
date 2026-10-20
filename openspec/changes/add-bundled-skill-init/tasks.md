# Tasks

## 1. 安装模块与目录替换

- [x] 1.1 在 Core 中新增接收显式来源和安装路径的独立 skill 安装模块，实现来源校验及首次安装，并在 `checks` 中注册临时目录检查；验证完整来源可安装，缺少标记、`SKILL.md` 或 `agents/openai.yaml` 时拒绝操作且目标不变。
- [x] 1.2 实现真实目标解析和覆盖归属检查，补充绝对链接、相对链接、多级链接、父目录链接、断链、循环、普通文件及无效标记检查；运行 `make test`，确认原链接文本保留且未标记的真实目录不被修改。
- [x] 1.3 实现同级临时副本、整目录替换和失败恢复，补充旧文件清理、重复执行、其他 skill 保留及复制、提交、恢复失败的注入检查；运行 `make test`，确认恢复失败时保留旧副本并返回其绝对路径。

## 2. CLI 入口与使用说明

- [x] 2.1 接入 `init` 分发、实际可执行文件相邻资源定位、帮助优先处理及文本和 JSON 输出，沿用参数错误 2、运行错误 1 的退出码；运行 `make build`，验证根帮助包含 `init`，`init -h` 和 `init --help` 在资源缺失时仍成功且无安装副作用。
- [x] 2.2 增加仅 Debug 生效的 `GHOSTPIN_TEST_SKILLS_ROOT`，在 `script/check_cli.py` 中构造临时 App 和安装目录，覆盖文本与 JSON 成功、拒绝覆盖、无效参数、资源缺失及任务目录不变；运行 `python3 script/check_cli.py`，并对修改的 Python 文件执行 Ruff 格式化和 Lint，确认 Release 不读取该隔离变量。
- [x] 2.3 更新 `README.md`、`README.en.md` 和 skill 使用说明，写明安装与升级后的完整 `init` 命令、真实目录覆盖、归属拒绝及旧目录迁移方式；核对中英文行为一致，skill 中全部命令使用正式完整路径且没有被正式规格禁止的开发入口或术语。

## 3. Skill 标记与 App 打包

- [x] 3.1 在 `skills/ghostpin-cli/` 新增名为 `ghostpin-cli` 的空普通文件；验证标记不是链接或目录、文件大小为 0，且原有 `SKILL.md` 与 `agents/openai.yaml` 均保留。
- [x] 3.2 修改开发和 Release 的 App 组装脚本，在签名前复制完整 skill 目录到 `Contents/Resources/skills/ghostpin-cli/`；运行 `make verify`，确认开发 App 可启动且随包 skill 与源目录的全部相对路径、文件类型和内容一致。
- [x] 3.3 提供可供本地和 Workflow 复用的 skill 完整目录校验入口，并以临时夹具验证缺少文件、额外旧文件及错误标记均校验失败；运行 `make dmg`，只读挂载并核对完整目录及签名，若修改或新增 Python 文件则执行 Ruff 格式化和 Lint。

## 4. 发布校验与整体验收

- [x] 4.1 在 macOS 发布 Workflow 中校验构建 App 和只读挂载 DMG 的完整 skill，并执行随包 CLI 的 `init --help`；本地复现新增校验命令并检查退出码，确认任一步骤失败均阻止发布且不触发真实 skill 安装。
- [x] 4.2 在最终实现上完成 `make build`、`make test`、`python3 script/check_cli.py`、`make verify` 和 `make dmg` 的整体检查，复用仍适用的已完成验证结果；记录实际命令、退出码和验收边界，确认各项检查未对本机真实安装路径执行 `init`、未访问真实待办。
- [x] 4.3 运行 `openspec validate add-bundled-skill-init --strict`，回读实现与三个增量规格，确认所有任务仅在对应行为和验证均完成后勾选。
