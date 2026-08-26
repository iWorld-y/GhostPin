# Rust 原生 HUD 阶段评估

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
| `cargo clippy --all-targets -- -D warnings` | NOT PASS：当前非 VS Developer SSH shell 未加载 Windows SDK include，`rc.exe` 找不到 `windows.h`；未以此结果作为运行验收依据 |
| `cargo test` | PASS：9 个 library tests、4 个 Storage/watcher/message-window integration tests |
| `cargo run --bin ghostpin-native-core-checks` | PASS：3 个 CoreChecks |
| `cargo build --release` | PASS |
| `build_stage1.cmd` | Release 编译 PASS；staging 复制因已有运行中的 `GhostPin.Native.exe` 锁定目标而未覆盖，已生成独立 `GhostPin.Native.next.exe` |
| `openspec validate ... --strict` | PASS（macOS 本地 OpenSpec 校验） |

现有 WPF 回退工程复验：Windows `make build CONFIGURATION=Release` PASS（0 警告、0 错误），
`make test CONFIGURATION=Release` PASS（32 tests）。Makefile 的 Windows 默认 `start` 仍调用
`windows-native/build_stage1.cmd`，正式发布与 macOS 工程未被原型改写。

可重复采样脚本为 `script/collect_evaluation.ps1`。在交互式 Windows 会话中执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\script\collect_evaluation.ps1 `
  -NativeExe .\build-stage1\GhostPin.Native.exe `
  -WpfExe .\windows\src\GhostPin.Windows.App\bin\Release\net10.0-windows\win-x64\GhostPin.Windows.App.exe `
  -WpfPublishDir .\windows\src\GhostPin.Windows.App\bin\Release\net10.0-windows\win-x64
```

脚本固定采集 EXE 精确字节数、发布目录文件数、进程启动就绪时间和预热后的工作集；
托盘程序若没有可见 `MainWindowHandle` 会明确记录 `readyWindowDetected=false`，不能把进程创建时间
冒充 HUD 可见时间。

当前仅完成脚本语法验证，尚未在同一交互桌面采集 WPF/Rust 的多次启动、稳定工作集和相对差值原始样本，
因此 OpenSpec 任务 6.8 保持未完成。

## 体积与依赖

- `windows-native/target/release/ghostpin-native.exe`：806,400 bytes。
- `windows-native/build-stage1/GhostPin.Native.next.exe`：806,400 bytes。
- `ghostpin-native-core-checks.exe` 仅为开发检查目标；`build_stage1.cmd` 只复制 GUI 目标，正式 staging 目录只包含一个 EXE。
- `dumpbin /dependents` 仅包含 Windows 系统 DLL；未发现 `VCRUNTIME140.dll`、
  `api-ms-win-crt-*`、.NET 或第三方 DLL。
- 10,000,000 bytes 门槛：通过，约为门槛的 8.06%。

## 当前边界

SSH 非交互会话已验证 Release EXE 可构建；这不等价于交互桌面验收。
WS_EX_TRANSPARENT/HTTRANSPARENT 的跨进程穿透、焦点保持、托盘重启、设置页完整双页、快捷键录制、
DPI/多屏、干净 Windows VM/Sandbox、视觉截图基线与真实文件竞争仍是后续门禁。当前渲染已使用
windows-rs 的预乘 BGRA DIB、Direct2D DC render target、DirectWrite、WIC 图标解码和
`UpdateLayeredWindow`；图标资源编译期嵌入 EXE，不需要同目录资源文件。

结论：Rust/windows-rs 原生候选已满足单 EXE 与 10 MB 体积目标；在严格 Clippy、安全注释、
交互真机与干净环境门禁通过前，保留现有 WPF 回退，不移除旧实现。
