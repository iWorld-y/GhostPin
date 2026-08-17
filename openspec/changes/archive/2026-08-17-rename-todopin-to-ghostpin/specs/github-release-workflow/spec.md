## MODIFIED Requirements

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

### Requirement: GitHub Release 发布

构建成功后，Workflow SHALL 创建与版本 tag 对应、标题使用 `GhostPin <version>` 的 GitHub Release，并上传唯一匹配的 GhostPin DMG 资产；同一 tag 的重复发布 SHALL 失败并保留已有 Release，不得生成不同版本名的资产。

#### Scenario: 上传 DMG
- **WHEN** `v0.0.3` 的构建与校验成功
- **THEN** GitHub Release `v0.0.3` 标题为 `GhostPin 0.0.3`，并包含 `GhostPin-0.0.3.dmg`

#### Scenario: 重复 tag 发布
- **WHEN** 已存在 `v0.0.3` Release 时再次触发相同 tag 的发布
- **THEN** Workflow 报告重复发布错误，不覆盖已有 Release
