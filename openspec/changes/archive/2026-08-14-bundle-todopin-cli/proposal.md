## Why

v0.0.1 的 DMG 只分发 TodoPin.app（纯展示壳），不包含 todopin-cli。TodoPin 是 Agent native 应用，新增/修改/删除任务必须通过 CLI/MCP 完成——用户安装后没有任何可用的写入口，核心功能等于未发布。README 中的 MCP 注册示例还指向开发期路径 .build/release/todopin-cli，对发布用户不可用。

## What Changes

- package_dmg.sh 打包时把 release 构建的 todopin-cli 复制进 TodoPin.app/Contents/MacOS/，与主程序一起 codesign，随 DMG 分发
- README/README.en.md 的 MCP 注册示例改为指向 app bundle 内路径（标准安装位置 /Applications/TodoPin.app/Contents/MacOS/todopin-cli），不再提及开发期 .build 路径
- todo-cli 能力新增「随应用分发」requirement：安装 TodoPin 后 todopin-cli 与 MCP server 立即可用

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- todo-cli: 新增「随应用分发」requirement——todopin-cli SHALL 随 TodoPin DMG 一起安装，位于 app bundle 内，用户安装后无需自行构建即可通过 CLI/MCP 操作任务

## Impact

- 打包脚本 script/package_dmg.sh：新增复制 CLI 步骤
- 文档 README.md、README.en.md：MCP 注册路径更新
- spec todo-cli：新增分发 requirement（archive 时并入主 spec）
- DMG 体积增加约 0.5MB（CLI 二进制）
- 无 Swift 源码、API、依赖变更；非 breaking
