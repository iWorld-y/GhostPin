## Context

当前 `script/release.sh` 在开发者本机完成 release 构建、调用 `script/package_dmg.sh` 生成 DMG，并使用本机 `gh` 上传 Release。`script/package_dmg.sh` 已经封装了 Swift release 构建、App 与 `todopin-cli` 打包、ad-hoc/可选签名和 `hdiutil` 校验。仓库目前没有 GitHub Workflow。

## Goals / Non-Goals

**Goals:**

- 以推送 `v*` tag 作为唯一自动发布入口。
- 将构建、DMG 生成、签名校验和 Release 上传迁移到 GitHub-hosted macOS runner。
- 保持 ad-hoc 签名，不引入 Apple 账号凭据和证书 Secret。
- 确保 tag、`script/VERSION`、DMG 文件名和 Release 资产一致。
- 让本地脚本只负责版本提交、推送 main 和推送 tag。

**Non-Goals:**

- 不实现 Developer ID 签名、Apple notarization 或 App Store 发布。
- 不改变 TodoPin App、CLI、MCP 的运行时业务行为。
- 不新增 Linux/Windows 构建矩阵。

## Decisions

### 1. 使用 tag push 触发，而不是手动输入版本号

选择 `push.tags: ["v*"]` 作为触发条件。版本由 Git 提交和 tag 固定，Workflow 可以从 tag 对应提交读取 `script/VERSION`，避免手动输入版本与代码版本漂移。手动 workflow dispatch 可作为未来的诊断入口，但不作为正式发布入口。

### 2. 使用固定 macOS runner

选择固定的 `macos-15` runner 标签，不使用 `macos-latest`，降低 GitHub 更换默认 macOS/Xcode 版本导致发布结果变化的风险。Workflow 启动时记录 macOS、Xcode、Swift 版本，便于排查构建差异。

### 3. 复用 package_dmg.sh，避免复制打包逻辑

Workflow 先运行核心行为检查，再通过 `TODO_PIN_VERSION` 传入 tag 版本并调用 `script/package_dmg.sh`。该脚本负责 release 构建、App/CLI bundle 组装、ad-hoc 签名、签名验证、DMG 创建和 DMG 验证；本地 `release.sh` 不再重复构建或上传 Release。

### 4. 使用 GitHub 内置 Token 创建 Release

Workflow 声明最小的 `contents: write` 权限，通过 GitHub 内置 Token 创建 tag 对应 Release 并上传 DMG，不引入个人 PAT。重复 tag/Release 由发布步骤显式失败，避免覆盖已有资产。

### 5. 版本提交先于 tag 推送

本地 `release.sh` 在确认只有 `script/VERSION` 改动后，切换到 `main`，提交并推送版本号，再创建并推送 tag。这样 tag 指向的提交天然包含对应版本号，Workflow 的一致性校验有稳定输入。其它本地改动在此之前阻止流程。

## Risks / Trade-offs

- [GitHub runner 镜像变化] → 固定 `macos-15`，并在日志中输出工具链版本；升级 runner 时单独验证。
- [ad-hoc 签名触发 Gatekeeper 警告] → 在 Release 说明中明确这是 ad-hoc 构建；未来以独立变更增加 Developer ID/notarization。
- [推送 main 或 tag 的网络/权限失败] → 版本提交、rebase、main 推送和 tag 推送均使用失败即停止；在创建 tag 前不开始远程 Release 发布。
- [重复触发相同 tag] → 创建 Release 时检测已有 Release，重复发布失败而不覆盖既有资产。
- [package_dmg.sh 当前会自行执行 release build] → Workflow 不额外执行第二次 release build；只在它之前运行核心检查，减少重复编译。

## Migration Plan

1. 新增 tag 触发的 macOS Workflow，并先在测试 tag 上验证构建、DMG 校验和 Release 资产。
2. 调整 `script/release.sh`，移除本地 DMG 构建和 `gh release create`，保留版本提交、main 推送和 tag 推送。
3. 发布一个正式版本，确认 Workflow 生成的 DMG 可下载、App 与 bundle 内 CLI 均可运行。
4. 回滚时删除或禁用 Workflow，并恢复本地 `release.sh` 的构建/上传步骤；已有 tag 和 Release 不自动删除。
