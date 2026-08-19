## Why

GhostPin 的发布流程目前只在 macOS 构建并上传 DMG，Windows HUD 即使已经可用，用户仍无法从 GitHub Release 直接取得可运行程序。需要把 Windows 构建纳入同一条可追溯的发布链路，并提供无需安装 .NET、无需解压的单文件 EXE。

## What Changes

- 将 GitHub Actions 发布流程拆分为 macOS 与 Windows 独立构建任务；只有两端检查和打包全部成功后，才创建同一个 GitHub Release。
- macOS 继续产出 `GhostPin-<version>.dmg`；Windows 产出自包含、单文件、x64 的 `GhostPin-<version>-windows-x64.exe`，用户可直接下载运行。
- 增加手动触发的跨平台构建验证：生成并保留 Actions artifacts，但不创建 GitHub Release，便于在推送版本 tag 前验收。
- 让现有 `make package` 根据运行平台选择 DMG 或 Windows 单文件 EXE 打包，不要求使用者记忆新的平台专用入口。
- Windows EXE 继续使用现有 GhostPin 图标，并写入与 `script/VERSION` 一致的版本元数据；本变更不引入 Authenticode 签名、MSIX/安装器或自动更新。
- macOS 维持现有 Apple Silicon、ad-hoc 签名和未公证的发布边界；本变更不新增 Intel/universal DMG 或 Apple 发布凭据。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `github-release-workflow`: 将仅发布 macOS DMG 的行为扩展为可手动验证、tag 触发且同时发布 macOS DMG 与 Windows 单文件 EXE 的跨平台流程。

## Impact

- 修改 `.github/workflows/release.yml` 的触发条件、任务结构、构建产物传递和 Release 创建步骤。
- 新增 Windows PowerShell 打包脚本，并调整根目录 `Makefile` 的平台识别和 `package` 编排；macOS 现有 DMG 脚本继续复用。
- Windows 构建依赖 .NET 10 Windows Desktop SDK 和 `win-x64` 自包含运行时包；首次本地发布可能需要联网还原运行时包。
- 更新发布脚本提示和用户文档中的跨平台产物说明，不改变任务 JSON、CLI 或 HUD 交互契约。
- 实现将按用户授权直接落在仓库默认分支 `main`；现有未提交的 `script/VERSION` 与文档改动不属于本变更。
