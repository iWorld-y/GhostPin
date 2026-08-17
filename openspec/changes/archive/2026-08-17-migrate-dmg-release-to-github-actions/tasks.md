## 1. GitHub Workflow 基础

- [x] 1.1 新增版本 tag 触发的 macOS GitHub Workflow，限制触发模式为 `v*`，并声明创建 Release 所需的 `contents: write` 权限
- [x] 1.2 固定使用 `macos-15` runner，输出 macOS、Xcode 与 Swift 工具链版本，便于定位构建环境变化

## 2. 发布前校验与构建

- [x] 2.1 在构建前读取 `script/VERSION`，校验去掉 `v` 前缀后的 tag 与版本文件完全一致；不一致时立即失败
- [x] 2.2 在 Workflow 中运行 `swift run TodoPinCoreChecks`，确保核心行为检查通过后再继续打包
- [x] 2.3 调用现有 `script/package_dmg.sh` 生成包含 TodoPin 与 `todopin-cli` 的 DMG，并传入 tag 对应的版本号
- [x] 2.4 校验 `.app` 的 ad-hoc 签名、DMG 内应用内容与 DMG 镜像完整性；任一校验失败时不得进入发布步骤

## 3. GitHub Release 发布

- [x] 3.1 使用 GitHub 内置 Token 创建与 tag 同名的 Release，并上传本次生成的精确版本 DMG
- [x] 3.2 明确处理已存在 tag 或 Release 的失败路径，禁止覆盖已有发布物
- [x] 3.3 确认 Workflow 不依赖 Developer ID、notarization 或 Apple Developer 凭据

## 4. 本地版本发布脚本

- [x] 4.1 调整 `script/release.sh`：仅允许 `script/VERSION` 作为未提交改动，并在发布前自动提交版本号
- [x] 4.2 让脚本先同步并推送 `main` 上的版本提交，再创建并推送对应的 `v<版本号>` tag
- [x] 4.3 移除脚本中的本地 DMG 构建、`gh release create` 与本地 Release 上传步骤，保留版本/tag 前置校验
- [x] 4.4 确保存在其它工作区改动、版本推送失败或 tag 推送失败时在相应步骤停止，不产生不完整发布

## 5. 文档与验收

- [x] 5.1 更新 README 或发布文档，说明修改 `script/VERSION` 后执行 `script/release.sh` 的自动提交、推 tag 与 GitHub Actions 发布流程
- [x] 5.2 执行 shell 语法检查、核心检查、Workflow 静态校验及 DMG 打包验证
- [x] 5.3 使用测试 tag 完成一次端到端发布验收，确认 GitHub Release 中的 DMG 可下载且版本号一致
