## 1. 打包脚本

- [x] 1.1 script/package_dmg.sh 在组装 bundle 时把 release 构建的 todopin-cli 复制到 TodoPin.app/Contents/MacOS/ 并 chmod +x
- [x] 1.2 打包后检查 bundle 内 todopin-cli 存在且与主程序同为本次 release 构建

## 2. 文档

- [x] 2.1 README.md 注册 MCP Server 示例改为 /Applications/TodoPin.app/Contents/MacOS/todopin-cli，不提及开发期 .build 路径
- [x] 2.2 README.en.md 同步更新 MCP 注册说明

## 3. 端到端验证

- [x] 3.1 运行 script/package_dmg.sh 产出 DMG
- [x] 3.2 从 bundle 内路径运行 todopin-cli mcp 完成 JSON-RPC 握手（initialize → tools/list），确认六个工具声明完整
- [x] 3.3 以发布用户视角验证：仅依赖 bundle 内 CLI 完成一次 add 与 list，确认写入 ~/Library/Application Support/TodoPin/todos.json
