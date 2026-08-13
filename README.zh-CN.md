<p align="center">
  <img src="Sources/TodoPin/Resources/Logo/TodoPinLogo.png" width="128" height="128" alt="TodoPin app icon">
</p>

# TodoPin

**English** · [中文](README.zh-CN.md)

TodoPin 是一款本地优先的 macOS 菜单栏待办应用，支持用文本快速捕获任务，也支持可选的本地语音转写。它可以在桌面保留轻量便签、从待办文本中解析提醒时间，并持续提醒直到任务完成。

应用专为个人、单用户、本地工作流设计。待办以 JSON 文件形式存储在 Mac 上。语音转写可借助一个小型 whisper.cpp 模型在本地运行，未安装语音模型时手动输入依然可用。

## 功能特性

- 菜单栏待办面板，快速捕获和管理任务。
- 桌面便签，保持可见但不占用工作区。
- 文本快速录入，自动解析提醒时间。
- 可选的本地语音录入，由 whisper.cpp 驱动。
- 文本快速录入与语音录入使用独立的全局快捷键。
- 可编辑待办标题与提醒时间。
- 完成、删除，以及未完成事项的每小时提醒。
- 本地 macOS 通知。
- 支持开机自启。
- 无账号系统、无云同步、无数据分析。

## 隐私模型

TodoPin 从设计上就是本地优先的。

- 待办保存在本机 `~/Library/Application Support/TodoPin/todos.json`。
- 每日摘要数据保存在本机 `~/Library/Application Support/TodoPin/summaries.json`。
- 偏好设置使用 macOS `UserDefaults` 保存。
- 音频在本机采集并转写。
- 应用不会上传待办或音频用于识别。
- 只有当你从设置中显式下载可选语音模型，或从源码构建依赖时，应用才会访问网络。

## 安装

从 GitHub Releases 页面下载最新的 `TodoPin.dmg`，打开后把 `TodoPin.app` 拖入 Applications。

当前公开发行版为 ad-hoc 签名。macOS Gatekeeper 可能提示"未验证的开发者"警告。若要正式分发，请使用 Developer ID 证书构建并对 DMG 进行公证。

## 默认快捷键

- 文本快速录入：`Option + Space`
- 语音录入：`F8`

快捷键可在设置中修改。文本快速录入会打开一个紧凑输入面板。语音录入只显示一个小型桌面录制浮层，并在转写完成后自动保存待办。

## 语音模型

语音输入是可选的。TodoPin 使用 whisper.cpp 及默认模型：

- `ggml-base-q5_1.bin`
- SHA-256：`422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898`

模型文件有意不提交到 git。

可通过以下任一方式安装模型：

1. 打开 TodoPin 设置，点击模型下载按钮。
2. 或运行：

```bash
./script/fetch_models.sh
```

应用下载的模型存放在：

```text
~/Library/Application Support/TodoPin/Models/ggml-base-q5_1.bin
```

未安装语音模型时，手动输入待办依然可用。

## 从源码构建

环境要求：

- macOS 14 或更高版本
- Xcode 命令行工具
- Swift Package Manager

构建：

```bash
swift build
```

运行核心检查：

```bash
swift run TodoPinCoreChecks
```

创建并验证本地 `.app` 包：

```bash
./script/build_and_run.sh --verify
```

创建发布版 DMG：

```bash
./script/package_dmg.sh
```

默认情况下，发布版 DMG 不捆绑语音模型，用户可稍后在设置中下载。

将模型捆绑进本地构建：

```bash
TODO_PIN_INCLUDE_MODEL=1 ./script/package_dmg.sh
```

## 签名与分发

打包脚本默认支持 ad-hoc 签名。

使用 Developer ID 证书进行公开分发：

```bash
TODO_PIN_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./script/package_dmg.sh
```

本仓库尚未自动化公证流程。

## 仓库结构

```text
Sources/TodoPin/             macOS SwiftUI 应用
Sources/TodoPinCore/         本地待办、提醒、解析与存储逻辑
Sources/TodoPin/Resources/   应用图标、Logo 与可选模型目录
Tests/TodoPinCoreChecks/     可执行核心行为检查
script/                      模型下载、应用打包与 DMG 打包脚本
```

## 许可证

TodoPin 以 MIT 许可证发布。参见 [LICENSE](LICENSE)。
