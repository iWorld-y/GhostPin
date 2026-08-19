## 1. Windows 单文件打包

- [x] 1.1 从现有 GhostPin 图标资源生成并提交 Windows `.ico`，在 WPF 项目中配置应用图标和可由打包脚本覆盖的版本元数据
- [x] 1.2 新增 Windows PowerShell 打包脚本：读取并校验 `script/VERSION`，执行不裁剪的 `win-x64` self-contained single-file publish，并只输出 `dist/GhostPin-<version>-windows-x64.exe`
- [x] 1.3 在 Windows 打包脚本中校验产物名称、文件数量、PE 可执行文件、图标和产品版本，任一检查失败时清理不完整产物并返回非零状态
- [x] 1.4 调整根目录 `Makefile`，使现有 `make package` 在 macOS 调用 DMG 脚本、在 Windows 调用 PowerShell 脚本，并为其它平台返回明确错误

## 2. 跨平台 GitHub Actions

- [x] 2.1 为发布 Workflow 增加 `workflow_dispatch`，并新增统一读取 `script/VERSION`、校验 tag 与输出发布元数据的 job
- [x] 2.2 将现有 macOS 检查和 DMG 打包迁入独立 job，保持 Bundle、签名、CLI 路径及 DMG 校验，并上传唯一 DMG Actions artifact
- [x] 2.3 新增 Windows job，配置 .NET 10，运行 Windows 测试与单文件打包，执行 EXE 启动冒烟检查，并上传唯一 EXE Actions artifact
- [x] 2.4 新增仅限 `v*` tag 的发布 job，使其同时依赖两个平台、校验下载后的文件名和数量，并在同一个 GitHub Release 中一次上传 DMG 与 EXE
- [x] 2.5 为 Actions artifacts 设置有限保留期，并确保手动运行无论成功或失败都不会创建或修改 GitHub Release

## 3. 发布说明与开发文档

- [x] 3.1 更新 `script/release.sh` 的提示，说明 tag 将由 Actions 构建并发布 macOS DMG 与 Windows x64 EXE
- [x] 3.2 更新中英文 README 的构建和下载说明，记录统一的 `make package`、两个 Release 文件名、Windows 无需 .NET/解压以及当前未签名边界

## 4. 验证

- [x] 4.1 在 macOS 运行核心检查和 `make package`，验证现有 DMG 名称、Bundle、签名、CLI 路径与挂载完整性未回归
- [x] 4.2 在 Windows 11 x64 运行 solution 测试和 `make package`，确认 dist 只有一个目标 EXE，并验证版本、图标以及启动/退出行为
- [x] 4.3 校验 Workflow YAML、Shell/PowerShell 脚本语法、`make help` 输出与 `git diff --check`，并运行 `openspec validate --all --strict`
- [ ] 4.4 代码进入远端 `main` 后手动运行一次 `workflow_dispatch`，确认两个 Actions artifacts 均可下载且没有创建 GitHub Release
