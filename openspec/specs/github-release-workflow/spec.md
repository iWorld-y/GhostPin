# github-release-workflow Specification

## Purpose

让 GhostPin 在推送版本 tag 后由 GitHub 自动完成 macOS 构建、ad-hoc 签名、DMG 校验和 Release 发布，减少本机环境差异并保留可追溯的构建记录。

## Requirements

### Requirement: Tag 触发发布
系统 SHALL 在仓库推送匹配 `v*` 格式的版本 tag 后触发一次跨平台发布 Workflow；普通分支提交不得直接创建发布 Release，手动触发仅用于生成验证 artifacts。

#### Scenario: 推送版本 tag
- **WHEN** 用户推送 `v0.0.3` tag
- **THEN** GitHub 自动启动该 tag 对应提交的 macOS 与 Windows 发布 Workflow

#### Scenario: 普通提交不发布
- **WHEN** 用户只向 `main` 推送普通提交且未推送版本 tag
- **THEN** 发布 Workflow 不创建 DMG、Windows EXE 或 GitHub Release

#### Scenario: 手动触发不发布
- **WHEN** 用户从 GitHub Actions 手动触发发布 Workflow
- **THEN** Workflow 仅执行构建验证，不创建 GitHub Release

### Requirement: 版本号一致性
发布 Workflow MUST 在 tag 触发时校验 tag 去掉 `v` 前缀后的版本号与该 tag 提交中的 `script/VERSION` 内容完全一致；手动触发时 MUST 使用目标提交中的 `script/VERSION` 作为两个平台产物的唯一版本号来源。版本校验失败时 MUST 在创建发布产物和 GitHub Release 前终止。

#### Scenario: 版本号一致
- **WHEN** Workflow 处理 `v0.0.3` tag，且 `script/VERSION` 内容为 `0.0.3`
- **THEN** Workflow 使用 `0.0.3` 构建两个平台的产物并继续发布

#### Scenario: 版本号不一致
- **WHEN** Workflow 处理 `v0.0.3` tag，但 `script/VERSION` 内容不是 `0.0.3`
- **THEN** Workflow 失败且不创建 Release、不上传 DMG 或 Windows EXE

#### Scenario: 手动验证读取版本号
- **WHEN** 用户手动触发 Workflow，且目标提交中的 `script/VERSION` 内容为合法版本号
- **THEN** Workflow 使用该版本号命名 macOS 与 Windows Actions artifacts

### Requirement: macOS 构建与 DMG 校验
发布 Workflow SHALL 在 macOS 构建环境中运行核心行为检查、构建 GhostPin 与 `ghostpin-cli`，生成包含两者的 DMG，并验证 App 签名、Bundle 身份、CLI 路径与 DMG 完整性。

#### Scenario: 构建成功
- **WHEN** 版本号校验通过且核心检查、构建、签名和 DMG 校验均成功
- **THEN** Workflow 产出名称为 `GhostPin-<version>.dmg` 的 DMG，其中包含 `GhostPin.app/Contents/MacOS/GhostPin` 和 `GhostPin.app/Contents/MacOS/ghostpin-cli`

#### Scenario: Bundle 身份兼容
- **WHEN** Workflow 校验打包后的 `GhostPin.app`
- **THEN** App 名称和主程序为 `GhostPin`，Bundle ID 为历史兼容值 `com.oyuxi.TodoPin`

#### Scenario: 构建或校验失败
- **WHEN** 核心检查、构建、签名、命名、CLI 路径或 DMG 校验任一步骤失败
- **THEN** Workflow 失败且不创建成功状态的 GitHub Release

### Requirement: Ad-hoc 签名发布
发布 Workflow SHALL 使用 ad-hoc 签名生成可验收的 DMG，不得要求 Developer ID 证书、Apple notarization 凭据或相关 GitHub Secrets。

#### Scenario: 无 Apple 凭据构建
- **WHEN** Workflow 未配置 Apple Developer 证书和 notarization 凭据
- **THEN** 仍可完成 ad-hoc 签名、DMG 校验和 GitHub Release 发布

### Requirement: GitHub Release 发布
两个平台构建均成功后，Workflow SHALL 创建与版本 tag 对应、标题使用 `GhostPin <version>` 的 GitHub Release，并上传唯一匹配的 GhostPin DMG 与 Windows x64 单文件 EXE；任一平台失败时 MUST NOT 创建 Release。同一 tag 的重复发布 SHALL 失败并保留已有 Release，不得覆盖资产或生成不同版本名的资产。

#### Scenario: 上传 DMG
- **WHEN** `v0.0.3` 的 macOS 与 Windows 构建及校验全部成功
- **THEN** GitHub Release `v0.0.3` 标题为 `GhostPin 0.0.3`，并且仅包含 `GhostPin-0.0.3.dmg` 和 `GhostPin-0.0.3-windows-x64.exe` 两个应用资产

#### Scenario: Windows 构建失败
- **WHEN** macOS DMG 构建成功但 Windows 检查或 EXE 打包失败
- **THEN** Workflow 失败且不创建 GitHub Release

#### Scenario: macOS 构建失败
- **WHEN** Windows EXE 构建成功但 macOS 检查或 DMG 打包失败
- **THEN** Workflow 失败且不创建 GitHub Release

#### Scenario: 重复 tag 发布
- **WHEN** 已存在 `v0.0.3` Release 时再次触发相同 tag 的发布
- **THEN** Workflow 报告重复发布错误，不覆盖已有 Release 或资产

### Requirement: 本地版本准备
本地发布脚本 SHALL 在工作区仅有 `script/VERSION` 改动时自动提交该文件并推送 `main`，随后创建并推送版本 tag；存在其它工作区改动时 MUST 在提交或推送前失败。

#### Scenario: 自动提交版本号
- **WHEN** 用户仅修改 `script/VERSION` 并执行发布脚本
- **THEN** 脚本提交版本号、推送 `main`，并继续推送对应版本 tag 以触发 Workflow

#### Scenario: 其它改动阻止发布
- **WHEN** 用户除 `script/VERSION` 外还修改或新增任意文件并执行发布脚本
- **THEN** 脚本失败，不提交版本号、不推送 `main`、不推送版本 tag

### Requirement: 手动跨平台构建验证
发布 Workflow SHALL 支持从 GitHub Actions 手动触发 macOS 与 Windows 的完整检查和打包，并将两个平台的包保存为可下载的 Actions artifacts；手动运行 MUST NOT 创建或修改 GitHub Release。

#### Scenario: Tag 前手动验证成功
- **WHEN** 用户在任意目标提交上手动触发发布 Workflow，且两个平台的检查和打包均成功
- **THEN** Workflow 成功并提供该提交对应的 DMG 与 Windows x64 EXE Actions artifacts

#### Scenario: 手动验证不发布
- **WHEN** 用户手动触发发布 Workflow
- **THEN** Workflow 不创建 GitHub Release，也不修改已有 GitHub Release

#### Scenario: 任一平台验证失败
- **WHEN** 手动运行中的 macOS 或 Windows 任一检查、构建或打包步骤失败
- **THEN** Workflow 以失败结束，且失败的平台不提供成功打包的 Actions artifact

### Requirement: Windows 自包含单文件构建
发布 Workflow SHALL 在 Windows x64 构建环境中运行 Windows 自动化测试并生成名称为 `GhostPin-<version>-windows-x64.exe` 的自包含单文件应用；该文件 MUST 在未预装 .NET Runtime 的 Windows 11 x64 环境中无需解压即可启动，并 MUST 保留 GhostPin 应用图标和与 `script/VERSION` 一致的产品版本元数据。

#### Scenario: Windows 构建成功
- **WHEN** Windows 自动化测试、发布和产物校验均成功
- **THEN** Workflow 产出唯一的 `GhostPin-<version>-windows-x64.exe`，且用户可直接下载并运行

#### Scenario: Windows 测试或打包失败
- **WHEN** Windows 自动化测试、单文件发布、命名、图标或版本校验任一步骤失败
- **THEN** Windows 构建任务失败，且不得将不完整文件作为成功产物发布

### Requirement: Windows 无签名凭据发布
发布 Workflow SHALL 能够在未配置 Windows Authenticode 证书或相关 GitHub Secrets 时生成并发布 Windows EXE；该产物不得被描述为已经过 Windows 代码签名。

#### Scenario: 无 Windows 签名凭据构建
- **WHEN** Workflow 未配置 Authenticode 证书和时间戳服务凭据
- **THEN** 仍可完成 Windows EXE 构建、校验和 GitHub Release 发布

### Requirement: 平台感知的本地打包
仓库 SHALL 提供同一个 `make package` 入口：在 macOS 生成并校验 DMG，在 Windows 生成并校验自包含单文件 EXE；在不支持的平台上 MUST 给出明确错误且不得伪造成功产物。

#### Scenario: macOS 本地打包
- **WHEN** 用户在受支持的 macOS 环境执行 `make package`
- **THEN** 系统调用 macOS 打包流程并生成 `GhostPin-<version>.dmg`

#### Scenario: Windows 本地打包
- **WHEN** 用户在受支持的 Windows x64 环境执行 `make package`
- **THEN** 系统调用 Windows 打包流程并生成 `GhostPin-<version>-windows-x64.exe`

#### Scenario: 不支持的平台
- **WHEN** 用户在未提供打包实现的平台执行 `make package`
- **THEN** 命令以非零状态退出并说明该平台不受支持
