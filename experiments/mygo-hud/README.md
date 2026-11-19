# GhostPin MyGo HUD

用 MyGo 原生 UI 验证 GhostPin 的 macOS 幽灵 HUD。应用包和进程名为 `GhostPin MyGo HUD`，bundle ID 为 `dev.ghostpin.experiment.mygo-hud`。菜单栏入口为「MyGo HUD」。任务和窗口控制状态每次启动时初始化，保存在内存中。

## 构建与启动

在有桌面会话的 macOS 14 或更高版本上，从仓库根目录运行以下命令。模块固定使用 MyGo 提交 `400ba3b17c3ec60ef9b0604e26aa4cdcf2a2ff2d`，Go 可以通过公共模块代理解析它。已安装兼容工具链时可直接使用，以下命令固定使用本次验证的 Go 1.27.3。

```sh
cd experiments/mygo-hud
export GOTOOLCHAIN=go1.27.3
export GOPROXY=https://proxy.golang.org,direct

go test ./...
go build ./...
CGO_ENABLED=0 go run github.com/egoist/mygo/cmd/mygo@v0.10.1-0.20261118142248-400ba3b17c3e \
  build -platform darwin/universal -skip-dmg .

app="dist/darwin-universal/GhostPin MyGo HUD.app"
open -n "$app"
```

`go build ./...` 生成当前平台的 `mygo-hud` 可执行文件。上面的 MyGo 构建命令另外生成带独立身份的 macOS 通用应用包，桌面验收使用该应用包。启动时先配置托盘和隐藏窗口，再以穿透、置顶、跨 Space 开启的初始设置显示 HUD。

- 从「MyGo HUD」切换显示、交互模式、置顶和跨 Space 显示。显示 HUD 时沿用上一次隐藏前的模式、位置和尺寸。
- 进入交互模式后，点击「开始」或「完成」，也可用 Tab 选择按钮并按空格。拖动 HUD 标题区域移动窗口，拖动窗口边缘调整大小。
- 选择「退出 MyGo HUD」结束原型。再次启动时恢复演示任务和初始窗口状态。

## 窗口对照

默认测试普通无边框窗口，切回穿透时调用同一窗口的 `Hide()` 和 `ShowInactive()`，待在 macOS 上确认原应用能否继续接收键盘输入。退出当前实例后，可分别用以下参数复测。每次只运行一个实例，方便辨认正在测试的配置。

```sh
# 普通窗口，比较 Blur() 的焦点和层级
open -n "$app" --args -focus-release blur
# 非激活 Panel，仍使用 Hide() 和 ShowInactive()
open -n "$app" --args -panel
# 非激活 Panel，比较 Blur()
open -n "$app" --args -panel -focus-release blur
```

验收环境、复现步骤与记录见 [桌面验收](VERIFICATION.md)。
