## ADDED Requirements

### Requirement: 随应用分发

todopin-cli SHALL 随 TodoPin 的 DMG 一起分发并安装：安装完成后，TodoPin.app 的 Contents/MacOS/ 目录内存在可执行的 todopin-cli，与主程序出自同一次 release 构建，用户无需另行构建即可通过 CLI 与 MCP server 操作任务。

#### Scenario: 全新安装后 CLI 立即可用

- **WHEN** 用户从 DMG 将 TodoPin.app 安装到 /Applications 且从未构建过源码
- **THEN** /Applications/TodoPin.app/Contents/MacOS/todopin-cli 存在且可执行，以 mcp 子命令启动时 MCP server 正常握手

#### Scenario: App 未运行时 CLI 独立工作

- **WHEN** TodoPin App 未运行且用户执行 bundle 内的 todopin-cli add
- **THEN** 任务写入 ~/Library/Application Support/TodoPin/todos.json，与 App 共用同一存储

#### Scenario: CLI 与主程序版本一致

- **WHEN** 用户安装某一版本的 TodoPin DMG
- **THEN** bundle 内 todopin-cli 与该版本主程序出自同一次 release 构建，行为与发行说明一致

#### Scenario: 非标准安装位置

- **WHEN** 用户将 TodoPin.app 安装到 /Applications 以外的位置
- **THEN** todopin-cli 仍随 bundle 一起存在，MCP 注册路径随之指向新位置
