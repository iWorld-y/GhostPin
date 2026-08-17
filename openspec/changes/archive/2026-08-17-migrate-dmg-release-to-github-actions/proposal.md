## Why

当前 DMG 构建、签名、校验和 GitHub Release 上传都依赖开发者本机执行 `release.sh`。这使发布受本机 Swift/Xcode 工具链和 macOS 环境影响，也无法让每次 tag 发布都留下可复现的构建记录；现在需要将发布产物构建迁移到 GitHub 的 macOS Workflow。

## What Changes

- 新增由 `v*` tag 推送触发的 GitHub Workflow。
- 在固定 macOS runner 上运行核心检查、Swift release 构建、ad-hoc 签名、DMG 创建与校验。
- 校验 tag 版本与 `script/VERSION` 一致，并将 DMG 上传到对应 GitHub Release。
- 调整本地 `release.sh` 的职责：版本号变更时自动提交并推送 `script/VERSION`，创建并推送 tag；不再承担本地 DMG 构建与 Release 上传。
- 保持 ad-hoc 签名，不引入 Developer ID、Apple notarization 或相关密钥管理。

## Capabilities

### New Capabilities

- `github-release-workflow`: 通过 GitHub tag 自动执行 TodoPin macOS 构建、ad-hoc 签名、DMG 发布和版本一致性校验。

### Modified Capabilities

无。

## Impact

- 新增 `.github/workflows/` 发布工作流。
- 修改 `script/release.sh` 的本地发布职责，并复用 `script/package_dmg.sh` 的 DMG 组装、ad-hoc 签名与校验逻辑。
- GitHub Actions 需要对仓库内容具有创建 Release 所需的写权限；不需要 Apple Developer 证书或 GitHub Secrets。
- 发布从开发者本机迁移到 GitHub-hosted macOS runner，构建日志和 DMG 产物由 Workflow/Release 保存。
