# github-release-workflow Specification

## Purpose

让 TodoPin 在推送版本 tag 后由 GitHub 自动完成 macOS 构建、ad-hoc 签名、DMG 校验和 Release 发布，减少本机环境差异并保留可追溯的构建记录。

## Requirements

### Requirement: Tag 触发发布

系统 SHALL 在仓库推送匹配 `v*` 格式的版本 tag 后触发一次发布 Workflow；普通分支提交不得直接创建发布 Release。

#### Scenario: 推送版本 tag

- **WHEN** 用户推送 `v0.0.3` tag
- **THEN** GitHub 自动启动该 tag 对应提交的发布 Workflow

#### Scenario: 普通提交不发布

- **WHEN** 用户只向 `main` 推送普通提交且未推送版本 tag
- **THEN** 发布 Workflow 不创建 DMG 或 GitHub Release

### Requirement: 版本号一致性

发布 Workflow MUST 校验 tag 去掉 `v` 前缀后的版本号与该 tag 提交中的 `script/VERSION` 内容完全一致；校验失败时 MUST 在构建和创建 Release 前终止。

#### Scenario: 版本号一致

- **WHEN** Workflow 处理 `v0.0.3` tag，且 `script/VERSION` 内容为 `0.0.3`
- **THEN** Workflow 继续执行构建和发布

#### Scenario: 版本号不一致

- **WHEN** Workflow 处理 `v0.0.3` tag，但 `script/VERSION` 内容不是 `0.0.3`
- **THEN** Workflow 失败且不创建 Release、不上传 DMG

### Requirement: macOS 构建与 DMG 校验

发布 Workflow SHALL 在 macOS 构建环境中运行核心行为检查、构建 TodoPin 与 `todopin-cli`，生成包含两者的 DMG，并验证 App 签名与 DMG 完整性。

#### Scenario: 构建成功

- **WHEN** 版本号校验通过且核心检查、构建、签名和 DMG 校验均成功
- **THEN** Workflow 产出名称为 `TodoPin-<version>.dmg` 的 DMG

#### Scenario: 构建或校验失败

- **WHEN** 核心检查、构建、签名或 DMG 校验任一步骤失败
- **THEN** Workflow 失败且不创建成功状态的 GitHub Release

### Requirement: Ad-hoc 签名发布

发布 Workflow SHALL 使用 ad-hoc 签名生成可验收的 DMG，不得要求 Developer ID 证书、Apple notarization 凭据或相关 GitHub Secrets。

#### Scenario: 无 Apple 凭据构建

- **WHEN** Workflow 未配置 Apple Developer 证书和 notarization 凭据
- **THEN** 仍可完成 ad-hoc 签名、DMG 校验和 GitHub Release 发布

### Requirement: GitHub Release 发布

构建成功后，Workflow SHALL 创建与版本 tag 对应的 GitHub Release，并上传唯一匹配的 DMG 资产；同一 tag 的重复发布 SHALL 失败并保留已有 Release，不得生成不同版本名的资产。

#### Scenario: 上传 DMG

- **WHEN** `v0.0.3` 的构建与校验成功
- **THEN** GitHub Release `v0.0.3` 包含 `TodoPin-0.0.3.dmg`

#### Scenario: 重复 tag 发布

- **WHEN** 已存在 `v0.0.3` Release 时再次触发相同 tag 的发布
- **THEN** Workflow 报告重复发布错误，不覆盖已有 Release

### Requirement: 本地版本准备

本地发布脚本 SHALL 在工作区仅有 `script/VERSION` 改动时自动提交该文件并推送 `main`，随后创建并推送版本 tag；存在其它工作区改动时 MUST 在提交或推送前失败。

#### Scenario: 自动提交版本号

- **WHEN** 用户仅修改 `script/VERSION` 并执行发布脚本
- **THEN** 脚本提交版本号、推送 `main`，并继续推送对应版本 tag 以触发 Workflow

#### Scenario: 其它改动阻止发布

- **WHEN** 用户除 `script/VERSION` 外还修改或新增任意文件并执行发布脚本
- **THEN** 脚本失败，不提交版本号、不推送 `main`、不推送版本 tag
