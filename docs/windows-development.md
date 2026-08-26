# Windows 原生开发说明

Windows 版 GhostPin 位于 `windows-native/`，使用 Rust、`windows-rs`、Win32、Direct2D、DirectWrite 和 Windows SDK。仓库不再包含 .NET/WPF Windows 实现；macOS 代码位于 `Sources/`，两者互不依赖。

## 工具链

- Windows 11 x64
- Rust MSVC 工具链
- Visual Studio Build Tools（MSVC 链接器与 Windows SDK，仅源码构建需要）

运行发布的原生 EXE 不需要安装 .NET、Visual C++ Redistributable 或额外 DLL。

## 构建与运行

Makefile 会通过 `OS=Windows_NT` 自动选择 Windows 原生入口。在仓库根目录执行：

```powershell
make build
make test
make start
make restart
make stop
make verify
make package
```

- `make build`：使用 `windows-native/build_stage1.cmd` 构建 Rust Release EXE。
- `make test`：运行 Cargo 测试和 `ghostpin-native-core-checks`。
- `make start`：构建并启动 `GhostPin.Native.exe`。
- `make package`：生成 `dist/GhostPin-<版本号>-windows-x64.exe`。

也可以直接执行：

```powershell
windows-native\build_stage1.cmd
windows-native\test.cmd
& .\windows-native\script\package.ps1
```

`make start` 在已有 `GhostPin.Native.exe` 运行时会因文件锁返回错误；此时使用 `make restart`。

## 数据与设置

- 任务真源：`%LOCALAPPDATA%\GhostPin\todos.json`
- 原生 HUD 设置：`%LOCALAPPDATA%\GhostPin\native-settings.json`

任务文件不存在时显示空状态；文件暂时损坏时保留最后一次成功快照并记录诊断，不会覆盖源文件。状态推进通过同目录临时文件和原子替换写回。

## HUD 操作

- 默认置顶、鼠标穿透且不抢焦点；交互模式支持任务推进、背景拖动和四边四角缩放。
- 通知区域菜单提供显示/隐藏、交互模式、设置和退出。
- 设置窗口包含 HUD 与高级两页，支持透明度、范围、条数上限、置顶和可选全局快捷键。
- HUD 只显示 Todo/Doing，圆形按钮执行 `Todo → Doing → Done`；同一任务成功推进后的 500ms 内重复点击会被忽略。

## 人工验收

在 Windows 11 真机上检查穿透与焦点、交互按钮、拖动缩放、置顶、托盘生命周期、设置页、快捷键、100%/150%/200% DPI、负坐标多显示器，以及任务文件外部替换和短暂损坏恢复。

自动化检查与评估脚本位于 `windows-native/`；当前未完成的桌面人工验收记录在 `windows-native/docs/windows-native-hud-evaluation.md`。
