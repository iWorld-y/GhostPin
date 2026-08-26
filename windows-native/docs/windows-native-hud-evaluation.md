# Rust 原生 HUD 评估记录

记录日期：2026-08-25

## 构建环境

- Windows 11 x64 开发机，通过已建立的 SSH 控制连接执行。
- rustc/Cargo 1.98.0，目标 `x86_64-pc-windows-msvc`。
- Microsoft `windows` crate 0.61.3。
- MSVC 14.29.30133，Windows SDK 10.0.19041.0。
- `rust-toolchain.toml` 固定 Rust 版本；`.cargo/config.toml` 为目标启用静态 CRT。

## 自动化结果

| 检查 | 结果 |
| --- | --- |
| `cargo fmt --check` | PASS |
| `cargo test` | PASS：9 个 library tests、4 个 Storage/watcher/message-window integration tests |
| `cargo run --bin ghostpin-native-core-checks` | PASS：3 个 CoreChecks |
| `cargo build --release` | PASS |
| `build_stage1.cmd` | Release 编译 PASS；已有运行中的 `GhostPin.Native.exe` 时复制阶段会报告文件锁 |
| `openspec validate ... --strict` | PASS（macOS 本地 OpenSpec 校验） |

Windows Makefile 入口已全部切换到 Rust 原生实现：`make build` 构建 Release，`make test` 运行 Cargo
测试与 CoreChecks，`make start` 启动 `GhostPin.Native.exe`，`make package` 生成单文件发布物。

## 可重复采样

脚本为 `windows-native/script/collect_evaluation.ps1`，只采集原生 EXE：

```powershell
powershell -ExecutionPolicy Bypass -File .\windows-native\script\collect_evaluation.ps1 `
  -NativeExe .\windows-native\build-stage1\GhostPin.Native.exe
```

脚本记录 EXE 精确字节数、构建目录文件数、进程启动就绪时间和预热后的工作集；托盘程序若没有可见
`MainWindowHandle` 会明确记录 `readyWindowDetected=false`，不能把进程创建时间冒充 HUD 可见时间。

## 体积与依赖

- `windows-native/target/release/ghostpin-native.exe`：806,400 bytes。
- `windows-native/build-stage1/GhostPin.Native.exe`：806,400 bytes。
- `ghostpin-native-core-checks.exe` 仅为开发检查目标；正式 staging 目录只包含一个 GUI EXE。
- `dumpbin /dependents` 仅包含 Windows 系统 DLL；未发现 `VCRUNTIME140.dll`、`api-ms-win-crt-*`、.NET 或第三方 DLL。
- 10,000,000 bytes 门槛：通过，约为门槛的 8.06%。

## 当前边界

SSH 非交互会话已验证 Release EXE 可构建；这不等价于交互桌面验收。透明穿透、焦点保持、托盘重启、
设置页完整双页、快捷键录制、DPI/多屏、干净 Windows VM/Sandbox、视觉截图基线与真实文件竞争仍需
交互桌面验证。当前渲染已使用 windows-rs 的预乘 BGRA DIB、Direct2D DC render target、DirectWrite、
WIC 图标解码和 `UpdateLayeredWindow`；图标资源编译期嵌入 EXE，不需要同目录资源文件。

结论：Rust/windows-rs 原生实现已满足单 EXE 与 10 MB 体积目标；后续工作集中在交互桌面、DPI/多屏和
干净环境门禁，不再维护另一套 Windows UI 实现。
