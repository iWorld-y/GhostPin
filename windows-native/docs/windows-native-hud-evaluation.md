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
| `cargo clippy --all-targets -- -D warnings` | PASS |
| `cargo test` | PASS：7 个 library tests、1 个 Storage integration test |
| `cargo build --release` | PASS |
| `build_stage1.cmd` | PASS：staging 为 `GhostPin.Native.exe` |
| `openspec validate ... --strict` | PASS（macOS 本地 OpenSpec 校验） |

## 体积与依赖

- `windows-native/target/release/ghostpin-native.exe`：524,288 bytes。
- `windows-native/build-stage1/GhostPin.Native.exe`：524,288 bytes。
- `dumpbin /dependents` 仅包含 Windows 系统 DLL；未发现 `VCRUNTIME140.dll`、
  `api-ms-win-crt-*`、.NET 或第三方 DLL。
- 10,000,000 bytes 门槛：通过，约为门槛的 5.24%。

## 当前边界

SSH 非交互会话已验证 staging EXE 可启动并保持运行 2 秒后可清理；这不等价于交互桌面验收。
WS_EX_TRANSPARENT/HTTRANSPARENT 的跨进程穿透、焦点保持、托盘、设置页、快捷键、DPI/多屏、
干净 Windows VM/Sandbox 与真实文件竞争仍是后续门禁。当前渲染基线已使用 windows-rs、DIB、
GDI 文字和 `UpdateLayeredWindow`；Direct2D/DirectWrite/WIC 完整管线及其视觉基准仍待实现。

结论：Rust/windows-rs 原生候选已满足单 EXE 与 10 MB 体积目标，并可作为默认开发入口；在
交互真机与干净环境门禁通过前，保留现有 C++/WPF 回退，不移除旧实现。
