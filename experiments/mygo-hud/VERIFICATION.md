# MyGo HUD 验收记录

## 已执行的检查

环境为 Linux x86_64（Ubuntu，内核 7.0.0-43-generic），Go 1.27.3，MyGo `v0.10.1-0.20261118142248-400ba3b17c3e`（提交 `400ba3b17c3ec60ef9b0604e26aa4cdcf2a2ff2d`）。本次没有可交互的 macOS 会话，macOS 版本与显示器配置无实测记录。

| 命令或检查 | 结果 |
| --- | --- |
| `go test ./...` | 通过。覆盖任务推进与移除、夹具重置、模式透明度、负坐标命中，以及原生 UI 无头环境下的键鼠推进和穿透模式禁用任务输入。 |
| `go build ./...` | 通过。生成 Linux x86_64 可执行文件。 |
| `go test -race ./...`、`go vet ./...` 和 `gofmt -l *.go` | 通过，Go 文件格式无需调整。 |
| README 中的 MyGo 通用包构建命令 | 通过。生成 `dist/darwin-universal/GhostPin MyGo HUD.app`，`file` 确认 Mach-O 同时包含 arm64 与 x86_64。 |
| `go version -m` 与应用包 `Info.plist` | 核对到 Go 1.27.3、固定的 MyGo 版本、独立的 `GhostPin MyGo HUD` 可执行文件和 `dev.ghostpin.experiment.mygo-hud` bundle ID、`LSUIElement = true` 及 `LSMinimumSystemVersion = 14.0`。正式 GhostPin 的 bundle ID 为 `com.oyuxi.TodoPin`。 |

首次解析提交时，环境默认的 `goproxy.cn` 返回 404。切换到 `https://proxy.golang.org,direct` 后解析和构建成功，采用原计划的提交。

## macOS 桌面复测

先在 macOS 14 验证，再用可用的较新 macOS 重跑。每轮记录 `sw_vers`、Go 版本、MyGo 版本、窗口与交还焦点的参数，以及每块显示器的分辨率、缩放、相对位置和「显示器具有单独的空间」设置。可把副屏布局放在主屏左方或上方，以覆盖负坐标。测试透明度、层级和 Space 时，把指针先移出 HUD 窗口再查看窗口是否可见。

| 场景 | 操作与判定 | macOS 14 / 较新 macOS |
| --- | --- | --- |
| 启动、显示与退出 | 启动后确认菜单栏有「MyGo HUD」，没有 Dock 图标。进入交互后移动、缩放并推进一个任务。隐藏后再次显示，核对模式、任务、位置与尺寸。退出后确认托盘和 HUD 消失，GhostPin 仍可运行。重启后检查原始演示任务及初始模式。 | 未实测 / 未实测 |
| 隔离运行 | 原型保持运行时，在 GhostPin 根目录执行 `make verify`。核对正式版从隔离任务目录启动以及两个进程同时存在，正式版校验退出后原型继续运行。再次确认原型显示内置夹具。 | 未实测 / 未实测 |
| 穿透、层级和原应用输入 | 在 TextEdit 打开一份临时文稿，把编辑区域放在 HUD 后面。编辑时从托盘隐藏后再显示穿透 HUD，菜单闭合后直接打字。指针移入 HUD 并点击下方文稿，再移出，重复三次。检查移入时完全隐身、点击可达、移出恢复。在原位置关闭置顶、用普通窗口覆盖，再开启置顶，观察 HUD 回到前方。 | 未实测 / 未实测 |
| 指针已在范围内 | 将指针停在 HUD 矩形内，通过系统的菜单栏键盘导航从托盘显示已隐藏的 HUD，随后复测从「交互模式」切回穿透。确认两种情况下窗口均先隐身，移出后恢复。如果系统没启用状态菜单键盘导航，先在系统键盘快捷键中启用。 | 未实测 / 未实测 |
| 交互与焦点交还 | 记录 TextEdit 中现有插入点，从托盘显式进入交互。用鼠标把一项 Todo 推进到 Doing，用 Tab 聚焦动作按钮并按空格将其移除。关闭「交互模式」后立即键入，检查可在同一插入点继续输入且 HUD 仍可见。对照 README 的普通窗口和 Panel 参数，记录切回时的闪烁、遮挡及焦点落点。 | 未实测 / 未实测 |
| 跨 Space 开关 | 在桌面 A 显示 HUD，切到桌面 B 和另一个应用的系统全屏 Space。回到 A 关闭跨 Space，分别重访两个目标 Space。再回到 A 开启跨 Space 并重访。期望两次开启时均可见，关闭时留在 A。普通窗口与 Panel 各测一轮。 | 未实测 / 未实测 |
| 双屏与命中 | 在交互模式拖动标题把窗口移到副屏，拖动边缘缩放，然后用鼠标和键盘操作任务。切回穿透，确认只在副屏窗口的新边界内隐身和穿透，移动到原位置保持可见。复测负坐标布局。 | 未实测 / 未实测 |

## 框架线索与迁移条件

- 指针隐身使用 `Screen.CursorScreenPoint()` 和 `Window.Bounds()`。两者的 Darwin 实现在同一桌面坐标系内，均以主屏左上角为原点。显示和模式切换时同步判定，显示且处于穿透模式时每 30 ms 采样，仅当目标透明度变化时调用 `SetOpacity`。MyGo 的 `TestPanelHoverWhileInactive` 仅覆盖可见并接收鼠标事件的后台 Panel，穿透且透明度为零仍需桌面验证。
- 普通窗口的 `Focus()` 会激活原型应用，`Blur()` 在 Darwin 上调用 `orderBack:`。公开 API 中缺少供原型定位并重新激活上一个外部应用的入口。原型比较 `Blur()` 和同一窗口的 `Hide()`、`ShowInactive()` 组合。是否交还原编辑器、是否闪烁及窗口次序的结果，以上表的「交互与焦点交还」为复现步骤。
- 普通窗口禁用自身全屏后，`SetVisibleOnAllWorkspaces(true/false)` 会切换全屏辅助标记，MyGo 的 `TestVisibleOnAllWorkspacesWithoutFullScreen` 覆盖了标记切换。非激活 Panel 创建时自带全屏辅助标记，`SetVisibleOnAllWorkspaces(false)` 会清除跨 Space 标记，但该路径保留全屏辅助标记。按上表的「跨 Space 开关」复测，确认标记差异是否导致关闭后仍出现在其他应用的全屏 Space。

进入正式迁移前，需要在同一种窗口配置上完成焦点往返、穿透隐身、置顶和跨 Space 复测，并通过双屏交互与隔离运行验收。若普通窗口无法稳定交还焦点，需确认 MyGo 能否提供明确的非激活键盘焦点交还接口。若 Panel 关闭跨 Space 后仍出现在其他应用的全屏 Space，需 MyGo 提供可撤销的全屏辅助行为。这两项的桌面表现仍待复测。
