# Gitee 发行版同步

GitHub 是发布源。推送 `v*` 标签后，现有 GitHub Actions 流程构建并校验 DMG、创建 GitHub Release，再由 `sync-gitee` 任务同步到 `lancer_lancet/GhostPin`。

同步内容包括同名标签的 Release 标题、说明、预发布状态和 `GhostPin-<版本号>.dmg`。DMG 从已发布的 GitHub Release 下载；上传后重新下载 Gitee 附件并比较 SHA-256，确认两端内容一致。

## 配置凭据

1. 在 [Gitee 私人令牌](https://gitee.com/profile/personal_access_tokens) 页面创建具备目标仓库读写权限的令牌，勾选 `projects` 权限。
2. 在 [GitHub Actions Secrets](https://github.com/iWorld-y/GhostPin/settings/secrets/actions) 中添加仓库 Secret，名称为 `GITEE_TOKEN`，值为该令牌。

也可以在本机交互式设置，令牌不写入命令参数：

```bash
gh secret set GITEE_TOKEN --repo iWorld-y/GhostPin
```

GitHub 读取使用流程自带的 `GITHUB_TOKEN`。Gitee 同步直接接在现有发布任务之后，避免 `GITHUB_TOKEN` 创建 Release 时不会触发另一个 Release 事件工作流的问题。

## 重试与冲突处理

- 未配置 `GITEE_TOKEN` 时，同步任务明确报错；已创建的 GitHub Release 保留。
- 同步失败后，在原 GitHub Actions 运行中选择 **Re-run failed jobs**。不要重新执行已经成功的 GitHub 发布任务，该任务会拒绝重复发布。
- 重试前会重新读取 Gitee Release 和附件。相同 DMG 跳过上传，内容不同时以 GitHub 为准替换同名附件，标题和说明也按 GitHub 更新。
- Gitee 缺少标签时，创建 Release 时使用 GitHub 标签的提交 SHA；该提交需已推送到 Gitee。两端同名标签指向不同提交时停止同步，先以 GitHub 为准校正 Gitee 标签，再重试。
- 写请求超时后停止运行，不自动重发。下一次运行先读取远端状态，再补齐未完成部分。

本地隔离检查：

```bash
python3 script/check_gitee_release.py
```

接口契约参考 [Gitee 官方 SDK](https://gitee.com/sdk/gitee5j/blob/main/docs/RepositoriesApi.md)，事件触发规则参考 [GitHub GITHUB_TOKEN 文档](https://docs.github.com/en/actions/concepts/security/github_token)。
