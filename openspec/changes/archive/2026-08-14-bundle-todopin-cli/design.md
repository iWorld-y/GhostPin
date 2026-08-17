## Context

动机见 proposal.md。现状约束：

- script/package_dmg.sh 的发布链：swift build -c release → 取主程序二进制（`swift build -c release --show-bin-path`）→ 组装 app bundle → codesign --force --deep → hdiutil 打 DMG
- todopin-cli 是同一 Package.swift 的 executable target，release 构建产物与主程序位于同一 bin 目录
- README 当前 MCP 注册示例指向开发期路径 .build/release/todopin-cli，发布用户无此文件
- 本次变更不涉及任何 Swift 源码

## Goals / Non-Goals

**Goals:**

- 一次 release 构建同时产出 App 与 CLI，二者同版本随 DMG 分发
- 安装后存在固定的 MCP 注册路径，README 可直接引用
- 现有签名流程无需重构即可覆盖新增二进制

**Non-Goals:**

- 不改变 MCP 协议、工具行为或 CLI 命令契约
- 不做 CLI 独立安装器、Homebrew 或其他分发渠道
- 不在 App 内实现「首次启动自动安装 CLI」逻辑
- 不动 DMG 其余内容与 HUD/通知行为

## Decisions

**D1. CLI 放 TodoPin.app/Contents/MacOS/todopin-cli**

与主二进制同级，遵循 macOS bundle 惯例（可执行文件在 MacOS/，Resources 只放资源）。
备选：放 Contents/Resources —— 拒绝，Resources 语义上不是可执行文件位置；
备选：DMG 根目录单独放 CLI —— 拒绝，需要用户手动拷贝，易错且无法随 App 一起签名。

**D2. 打包脚本复制同一 release 构建产物**

package_dmg.sh 已通过 --show-bin-path 取得主程序路径，同目录取 todopin-cli 一行 cp 完成。
备选：单独再构建一次 CLI —— 拒绝，浪费且引入版本不一致风险。

**D3. 签名流程不变**

codesign --force --deep 递归签名整个 bundle，自动覆盖新增 Mach-O；脚本末尾的
codesign --verify --deep --strict 保留作为兜底。未来启用公证时同样覆盖。

**D4. 文档路径约定**

README 注册示例只用标准安装路径 /Applications/TodoPin.app/Contents/MacOS/todopin-cli，
不提及开发期 .build 路径。非标准安装位置由用户调整（行为已写入 spec）。

**D5. 验证方式**

打包后从 bundle 内路径运行 todopin-cli mcp 做 JSON-RPC 握手（initialize → tools/list），
确认六个工具声明完整，作为打包验证的一部分。

## Risks / Trade-offs

- [用户把 App 移出 /Applications 后 MCP 配置失效] → 文档写明路径随 App 位置调整；spec 已覆盖非标准位置行为
- [发布版 CLI 与用户自建开发版 CLI 版本漂移] → bundle 内 CLI 与 App 恒为同版本；文档统一只推荐 bundle 内路径
- [codesign --deep 对 bundle 内多个 Mach-O 的行为在工具链版本间可能有差异] → 保留 codesign --verify --deep --strict 检查，发布前验证失败即中止；bundle 内现有两个 Mach-O（App + CLI），--deep 为既有写法，未来启用公证时建议改为逐项签名（sign 每个 Mach-O 后再签 bundle），避免不同工具链下的行为差异
- [DMG 体积增加约 0.5MB] → 对菜单栏应用可接受

## Migration Plan

- 已安装 v0.0.1 的用户：下载新版 DMG 覆盖安装即可获得 CLI，无数据迁移（todos.json 位置不变）
- 回滚：脚本变更独立可回退；发布前验证未通过则不产出 DMG
