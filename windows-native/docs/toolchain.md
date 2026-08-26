# Windows 原生 Rust 工具链记录

记录日期：2026-08-25
目标：Windows 11 x64 / Release / MSVC 静态 CRT

## Rust + windows-rs 阶段记录

| 组件 | 版本或路径 | 结果 |
| --- | --- | --- |
| rustup | 1.29.0 | 用户授权后通过 WinGet 安装 |
| rustc | 1.98.0 (88d9e12ae) | `x86_64-pc-windows-msvc`，已固定到 `rust-toolchain.toml` |
| Cargo | 1.98.0 | 已生成并提交 `Cargo.lock` |
| windows crate | 0.61.3 | 仅启用 Win32、Direct2D/DirectWrite/WIC、COM、WinRT JSON、Shell 等 features |
| MSVC | 14.29.30133 | VS 2019 BuildTools x64 Developer 环境 |
| Windows SDK | 10.0.19041.0 | `rc.exe` 与系统 API 可用 |

Rust Release 使用 `opt-level=z`、LTO、单 codegen unit、`panic=abort` 和符号剥离；`build.rs` 通过 `rc.exe` 编译现有 GhostPin 图标、manifest 与版本资源。GUI target 为 `ghostpin-native`，Release 文件当前约 805,376 字节，staging 时再复制为 `GhostPin.Native.next.exe`（正式目标被运行中的旧进程锁定时使用）。

Windows Runtime apartment 是线程级资源。UI 或测试线程独立持有 `RuntimeApartment`；watcher 线程不持有 WinRT/COM 对象。非交互 SSH 只用于构建和自动化检查，不能证明托盘、焦点、穿透或全局快捷键验收；这些行为需要交互桌面计划任务或人工验收。


## Rust / windows-rs 实施记录

Rust 目标已切换为稳定版 MSVC 工具链：rustup 1.29.0、rustc/Cargo 1.98.0、目标
`x86_64-pc-windows-msvc`、`windows` crate 0.61.3、MSVC 14.29.30133、Windows SDK
10.0.19041.0。`windows-native/rust-toolchain.toml` 固定工具链；`build.rs` 使用
`rc.exe` 编译同源 `.rc`、manifest 和图标资源。仓库级与 `windows-native/.cargo/`
配置均为 MSVC 目标启用 `target-feature=+crt-static`，避免 VC/UCRT DLL 运行时依赖。

最终验证命令为 `cargo fmt --check`、`cargo clippy --all-targets -- -D warnings`、
`cargo test` 与 `cargo build --release`；单元测试 9 项通过，Storage/watcher/message-window 集成测试 4 项通过；
`cargo run --bin ghostpin-native-core-checks` 的 3 个 CoreChecks 通过。
当前严格 Clippy 在非 VS Developer SSH shell 中因 `rc.exe` 未加载 Windows SDK include、找不到
`windows.h` 未通过，不把它误记为运行时验收通过。
Release EXE `ghostpin-native.exe` 与 staging 后的 `GhostPin.Native.next.exe` 当前约为 806,400 字节，
`dumpbin /dependents` 仅列出 Windows 系统 DLL，没有 `VCRUNTIME140.dll` 或 `api-ms-win-crt-*`。
`ghostpin-native-core-checks.exe` 仅供开发验证，`build_stage1.cmd` 使用 `--bin ghostpin-native`
并只复制 GUI EXE 到 staging 目录。
非交互 SSH 只验证构建、启动存活和进程清理；透明穿透、焦点、托盘、DPI 与多屏仍需交互桌面
或干净 VM/Sandbox 门禁。
