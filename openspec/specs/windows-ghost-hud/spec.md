# windows-ghost-hud Specification

## Purpose

定义 GhostPin 在 Windows 11 上以原生桌面 HUD 形态运行时的窗口、交互、任务投影、文件刷新和状态持久化行为，并明确首个 Windows MVP 与现有 macOS 产品之间的兼容边界。

## Requirements

### Requirement: Windows HUD 常驻入口
系统 SHALL 在 Windows 11 x64 上提供可独立启动的 GhostPin HUD，并 SHALL 在运行期间提供通知区域图标；HUD 窗口 MUST NOT 出现在任务栏或 Alt+Tab 应用切换列表中。

#### Scenario: 启动 Windows HUD
- **WHEN** 用户启动 Windows 版 GhostPin
- **THEN** 系统显示通知区域图标和 HUD，且 HUD 不出现在任务栏或 Alt+Tab 应用切换列表中

#### Scenario: 关闭 HUD 窗口
- **WHEN** 用户通过 HUD 的关闭入口隐藏窗口
- **THEN** 系统隐藏 HUD 但保留通知区域进程，用户仍可从通知区域重新显示 HUD

### Requirement: 无边框透明窗口与置顶
HUD SHALL 使用无标题栏、无系统边框且背景透明的窗口，默认 SHALL 位于普通应用窗口之上；系统 MUST 允许用户关闭或重新开启置顶，且切换窗口层级时 MUST NOT 激活 HUD。

#### Scenario: 默认显示 HUD
- **WHEN** HUD 首次显示且没有已保存偏好
- **THEN** HUD 以无边框透明外观显示在普通应用窗口之上

#### Scenario: 关闭置顶
- **WHEN** 用户关闭 HUD 置顶
- **THEN** HUD 回到普通窗口层级且不夺取当前前台应用的焦点

### Requirement: 穿透与交互模式
HUD 默认 SHALL 处于穿透模式，穿透模式下鼠标事件 MUST 传递给 HUD 下方的应用且 HUD MUST NOT 获得键盘焦点；系统 SHALL 允许用户通过通知区域切换至交互模式，交互模式下 HUD SHALL 接收鼠标输入，并 SHALL 以克制的视觉差异提示当前模式。

#### Scenario: 穿透模式点击
- **WHEN** HUD 处于穿透模式且用户点击 HUD 覆盖区域
- **THEN** 点击由 HUD 下方的应用处理，HUD 不响应且当前键盘焦点保持不变

#### Scenario: 切换到交互模式
- **WHEN** 用户从通知区域打开交互模式
- **THEN** HUD 开始接收鼠标输入、允许获得焦点，并以可察觉但克制的视觉变化表示交互状态

#### Scenario: 切回穿透模式
- **WHEN** 用户从通知区域关闭交互模式
- **THEN** HUD 停止接收鼠标输入并恢复不激活、不抢焦点的穿透状态

### Requirement: 交互态移动与调整大小
交互模式下，用户 SHALL 能够拖动 HUD 并从窗口四边及四角调整大小；穿透模式下这些窗口操作 MUST 不生效。HUD 的最小内容区域 SHALL 足以显示标题、空状态或至少一张任务卡片。

#### Scenario: 交互态拖动 HUD
- **WHEN** HUD 处于交互模式且用户拖动非控件背景区域
- **THEN** HUD 随指针移动并在拖动结束后保存新位置

#### Scenario: 交互态调整大小
- **WHEN** HUD 处于交互模式且用户拖动窗口边缘或角落
- **THEN** HUD 在不小于最小尺寸的前提下调整大小并保存新尺寸

#### Scenario: 穿透态尝试拖动
- **WHEN** HUD 处于穿透模式且用户在 HUD 上按下并移动指针
- **THEN** 下方应用接收该输入，HUD 的位置和尺寸保持不变

### Requirement: Windows 任务数据兼容
系统 SHALL 使用 `%LOCALAPPDATA%\GhostPin\todos.json` 作为 Windows 任务真源，并 MUST 兼容现有 GhostPin 任务对象的字段、`todo`、`doing`、`done` 状态值和 ISO 8601 日期表示。任务目录或文件不存在时系统 SHALL 以空列表继续运行；文件内容暂时无效时系统 MUST 保留最后一次成功加载的任务列表且不得崩溃。

#### Scenario: 读取兼容任务文件
- **WHEN** Windows 任务文件包含由现有 GhostPin JSON 契约编码的任务
- **THEN** HUD 正确读取任务标识、标题、状态、优先级、截止时间和描述

#### Scenario: 首次启动没有任务文件
- **WHEN** Windows 数据目录或任务文件尚不存在
- **THEN** HUD 显示空状态并保持运行，后续文件创建后仍可加载任务

#### Scenario: 任务文件暂时损坏
- **WHEN** 任务文件变为无法完整解析的内容
- **THEN** HUD 保留最后一次成功加载的任务列表、报告可诊断错误且不退出

### Requirement: Windows HUD 任务投影
HUD SHALL 只展示 Todo 与 Doing 任务，并 SHALL 将 Doing 分区置于 Todo 分区上方且隐藏空分区。系统 SHALL 支持“全部未完成”和“今天新增”两种范围以及 1 至 20 的可配置条数上限；相同任务数据和时间输入在 Windows 与现有 GhostPin 中 MUST 产生一致的分区、优先级、截止时间、逾期状态及创建时间排序和截断结果。

#### Scenario: 同时存在 Doing 与 Todo
- **WHEN** 当前范围同时包含 Doing 与 Todo 任务
- **THEN** HUD 先显示 Doing 分区再显示 Todo 分区，并在各分区中应用兼容排序

#### Scenario: 今天新增范围
- **WHEN** 用户选择“今天新增”范围
- **THEN** HUD 只展示本地日历当天创建且状态为 Todo 或 Doing 的任务

#### Scenario: Doing 占满条数上限
- **WHEN** Doing 任务数量不少于配置的条数上限
- **THEN** HUD 只显示排序后的前 N 个 Doing 任务且不显示 Todo 分区

### Requirement: Windows HUD 状态推进
交互模式下，HUD 任务卡片的圆形按钮 SHALL 将 Todo 推进为 Doing，并将 Doing 推进为 Done；成功状态变化 MUST 原子写回 Windows 任务文件并立即更新投影。一次成功变化后的 500ms 内，系统 MUST 忽略同一任务的后续推进请求。

#### Scenario: Todo 推进为 Doing
- **WHEN** 用户在交互模式下点击 Todo 任务的圆形按钮
- **THEN** 系统将任务状态写为 `doing`，任务立即移动到 Doing 分区

#### Scenario: Doing 推进为 Done
- **WHEN** 用户在交互模式下点击 Doing 任务的圆形按钮且该任务不在冷却窗口内
- **THEN** 系统将任务状态写为 `done`、记录完成时间，并立即从 HUD 移除该任务

#### Scenario: 冷却窗口内重复点击
- **WHEN** 同一任务成功推进后 500ms 内再次收到推进请求
- **THEN** 系统忽略该请求且任务状态不发生第二次变化

### Requirement: 外部任务文件变化刷新
系统 SHALL 监听 Windows 任务目录中的文件创建、修改、重命名和替换，并 SHALL 在稳定变化发生后的数秒内重新读取完整任务真源。重复文件事件 MUST 合并处理；外部刷新和 HUD 自身写入 MUST NOT 激活窗口、夺取键盘焦点、清空最后一次有效列表或造成可见闪烁。

#### Scenario: 外部原子替换任务文件
- **WHEN** 外部进程通过临时文件重命名或替换 `todos.json`
- **THEN** HUD 在数秒内读取替换后的完整文件并更新任务投影

#### Scenario: 单次写入产生多个事件
- **WHEN** Windows 为同一次文件操作发出多个文件系统事件
- **THEN** 系统将相邻事件合并为稳定刷新且 HUD 不重复闪烁

#### Scenario: 刷新时其他应用保持焦点
- **WHEN** 用户正在其他应用工作且任务文件触发刷新
- **THEN** 其他应用保持前台和键盘焦点，HUD 仅更新自身内容

### Requirement: Windows HUD 偏好持久化
系统 SHALL 将 HUD 的显示状态、窗口位置与尺寸、透明度、置顶开关、穿透或交互模式、显示范围、条数上限以及已成功注册的可选全局快捷键持久化到任务文件之外的 Windows 本地设置，并 SHALL 在下次启动时恢复。首次启动 MUST 使用穿透模式、置顶开启和 0.5 至 1.0 范围内的默认透明度。

#### Scenario: 重启恢复 HUD 状态
- **WHEN** 用户修改 HUD 位置、尺寸、透明度、置顶、模式、范围或条数上限后重启应用
- **THEN** 系统恢复所有已保存且仍然有效的 HUD 偏好

#### Scenario: 首次启动使用安全默认值
- **WHEN** 应用没有可用的 Windows HUD 设置
- **THEN** HUD 以穿透、置顶和有效默认透明度启动

#### Scenario: 设置文件无效
- **WHEN** Windows HUD 设置文件无法解析或包含越界值
- **THEN** 系统对无效项使用安全默认值且任务数据不受影响

### Requirement: Windows 设置窗口
系统 SHALL 提供与 macOS 基本结构一致的独立设置窗口，并 SHALL 包含“HUD”和“高级”两个页签。HUD 页 SHALL 集中调整透明度、显示范围、条数上限和置顶开关，高级页 SHALL 配置可选全局快捷键；通知区域菜单 SHALL 只保留常驻高频操作和设置窗口入口。设置窗口 MUST 复用当前 HUD 状态，修改后 SHALL 立即更新 HUD 并持久化，且重复打开 MUST 复用同一个窗口实例。

#### Scenario: 从通知区域打开设置
- **WHEN** 用户在通知区域菜单选择“设置…”
- **THEN** 系统显示并激活单一设置窗口，窗口反映当前 HUD 透明度、显示范围、条数上限和置顶状态

#### Scenario: 修改 HUD 设置
- **WHEN** 用户在设置窗口调整任一支持的 HUD 设置
- **THEN** HUD 立即应用该值、设置写入独立设置文件，通知区域状态与设置窗口保持一致

#### Scenario: 关闭并重新打开设置
- **WHEN** 用户关闭设置窗口后再次从通知区域打开
- **THEN** 系统复用设置窗口生命周期并显示最新的当前值，不创建重复窗口

### Requirement: Windows 全局交互快捷键
系统 SHALL 允许用户在设置窗口高级页选择性启用并录制一个全局快捷键，用于切换 HUD 的穿透与交互模式。普通按键候选 MUST 至少包含 Ctrl、Alt、Shift 或 Win 中的一个修饰键，F1 至 F20 MAY 单独使用，单独修饰键 MUST NOT 成为候选，Esc SHALL 取消录制。快捷键及启用状态 MUST 仅在系统成功注册后持久化；候选被占用或注册失败时系统 MUST 保留原设置，并在原快捷键此前启用时尝试恢复注册。

#### Scenario: 首次启用并录制快捷键
- **WHEN** 用户打开全局快捷键开关但尚未设置组合
- **THEN** 系统进入待配置状态且不持久化启用状态，直至用户录制的候选成功注册

#### Scenario: 快捷键切换交互模式
- **WHEN** 已注册的全局快捷键被按下
- **THEN** 系统只在穿透与交互模式之间切换 HUD，并同步通知区域及设置状态

#### Scenario: 新候选注册冲突
- **WHEN** 用户替换已启用快捷键且新候选无法注册
- **THEN** 系统显示冲突原因、不保存新候选，并恢复此前已注册的快捷键

#### Scenario: 取消或清除快捷键
- **WHEN** 用户在录制时按 Esc 或选择清除快捷键
- **THEN** Esc 恢复录制前状态；清除操作注销快捷键、关闭启用状态并移除持久化组合

### Requirement: Windows 与 macOS 色调一致
Windows HUD SHALL 沿用 macOS HUD 的浅色白色材质、绿色与黄色半透明渐变、深色主文字和灰色次要文字层级；设置窗口 SHALL 使用浅色系统背景、白色分组内容和标准控件层级。HUD 和设置窗口 MUST NOT 默认呈现为固定黑色主题。

#### Scenario: 打开 HUD 与设置窗口
- **WHEN** 用户在默认外观下启动 Windows HUD 并打开设置窗口
- **THEN** 两个窗口呈现与 macOS GhostPin 一致方向的浅色白绿黄层级，而不是黑色面板

### Requirement: 多显示器与 DPI 适配
系统 SHALL 在 Windows Per-Monitor DPI 环境下保持 HUD 内容清晰，并 SHALL 在窗口跨越不同缩放比例的显示器时更新布局和窗口尺寸。恢复已保存窗口时，系统 MUST 检查其是否与任一当前显示器工作区相交；完全离屏的窗口 SHALL 回到当前主显示器的可见区域。

#### Scenario: 移动到不同 DPI 的显示器
- **WHEN** 用户将交互态 HUD 从一个显示器移动到缩放比例不同的显示器
- **THEN** HUD 按新显示器 DPI 重新布局且文字、图标和命中区域保持可用

#### Scenario: 恢复已断开的显示器位置
- **WHEN** 已保存位置属于当前未连接的显示器且与所有工作区均不相交
- **THEN** HUD 在主显示器可见区域内恢复，并保留合法尺寸或将其限制到可用范围

### Requirement: 通知区域控制
通知区域菜单 SHALL 提供显示或隐藏 HUD、切换交互模式、打开设置窗口和退出应用的入口，且菜单状态 SHALL 与当前 HUD 可见性及交互模式保持一致。通知区域图标 MUST 使用与 macOS 状态栏相同的 `GhostPinStatusBar` 图像资源，不得使用通用应用占位图标。

#### Scenario: 显示 GhostPin 通知区域图标
- **WHEN** Windows 版 GhostPin 创建通知区域入口
- **THEN** 通知区域显示由 `GhostPinStatusBar` 资源生成的 GhostPin 图标，而不是系统通用应用图标

#### Scenario: 从通知区域显示 HUD
- **WHEN** HUD 已隐藏且用户选择显示入口
- **THEN** HUD 以已保存的窗口状态显示且不无条件夺取其他应用焦点

#### Scenario: 从通知区域退出
- **WHEN** 用户选择退出入口
- **THEN** 系统保存待持久化设置、移除通知区域图标并结束 Windows 进程
