# Tasks

## 1. 验证隐身检测前提

- [x] 1.1 在真实 App 上实测指针检测机制（外部移动光标 + 探针记录）。结论：`.onHover` 在穿透模式下正常工作，既有 `isGhostFading` 分支一直是活的（实测到 `boardOpacity=0.4`）；全局鼠标监听无收益；窗口 `alphaValue=0` 不会杀死 hover 检测。验证：已完成，结论见 `design.md` 的「实测结论」。
- [x] 1.2 按 1.1 结论重写 `design.md` 决策 1/2 与风险项，把推断转为实测事实，并据此废弃全局监听方案。验证：已完成，`design.md` 不再包含未经验证的前提。

## 2. Core 层分流投影

- [x] 2.1 在 `Sources/GhostPinCore` 中实现「有 Doing 时只显示 Doing」的投影：返回 Doing / Todo 两组及各自计数；条数上限只作用于实际渲染的集合（聚焦 Doing 时截断 Doing，否则先保留 Doing 再补 Todo）。验证：新增检查断言聚焦开关开启且存在 Doing 时 Todo 组为空、关闭时两组同时非空。
- [x] 2.2 在 `Tests/GhostPinCoreChecks/main.swift` 注册新用例，覆盖：开关开启且有 Doing、开启且无 Doing、关闭时恢复同时展示、上限只作用于实际渲染集合、Doing 计数与 Todo 计数相互独立。验证：`make test` 全部通过，且新用例已加入文件顶部 `checks` 数组（未注册的用例不会执行）。
- [x] 2.3 确认既有 Doing 优先排序与条数上限用例在关闭分流时行为不变。验证：`make test` 中已有的 `hudItems` 相关检查仍全部通过。

## 3. 新增显示偏好

- [x] 3.1 在 `Sources/GhostPin/App/AppPreferences.swift` 新增「有 Doing 时只显示 Doing」布尔偏好，默认开启，沿用现有 `@Published + didSet` 与 `Keys` 枚举写法，确保键缺失时按开启处理、用户显式关闭能持久化。验证：`make build` 通过，并在 `make dev` 中修改后重启确认取值恢复。
- [x] 3.2 在 `Sources/GhostPin/Views/SettingsView.swift` 的 HUD 页新增该开关并接入偏好。验证：`make verify` 通过，设置页可切换该开关且重启后状态保持。

## 4. HUD 分区渲染与计数

- [x] 4.1 让 `Sources/GhostPin/Views/DesktopNotesBoardView.swift` 改为消费 Core 的分区投影结果，聚焦开启且存在 Doing 时不渲染 Todo 卡片与 Todo 区域标题。验证：`make verify` 通过；在 App 中构造 1 条 Doing + 多条 Todo，确认只显示 Doing。
- [x] 4.2 头部改为分别展示 Doing 计数与 Todo 计数，替换单一「N 个未完成」；聚焦隐藏 Todo 卡片时 Todo 计数仍可见。验证：`make verify` 通过，头部显示两个独立计数且与卡片数一致。
- [ ] 4.3 用 CLI 将一条 Todo 改为 Doing（`make cli ARGS='doing <id>'`）触发自动刷新，确认卡片重新分流且两个计数同步更新。验证：数秒内 HUD 计数变化正确，Doing 变为可见集合。

## 5. 穿透模式指针隐身

- [x] 5.1 指针检测沿用既有 SwiftUI `.onHover`（实测已可靠工作），不新增监听或定时器。验证：已在 1.1 实测确认，无需额外实现。
- [x] 5.2 让 `updateHUD()` 与 hover 变化共用同一个「按当前模式与指针状态计算目标透明度」的取值来源，穿透模式指针在窗口内时窗口 `alphaValue` 为 0，交互模式恒为 `hudOpacity`，不覆写偏好。验证：`make verify` 通过；交互模式移动鼠标不隐身，穿透模式移入完全不可见、移出恢复为设置值。
- [x] 5.3 实现收敛为**只由窗口层承担隐身**：`DesktopNotesBoardView` 不再归零视图不透明度，`isGhostFading` 与其 `isHovering` 状态一并移除，视图只把 hover 转告协调器。理由：乘积已为 0 时视图层再降无视觉收益，且多一个可能抑制追踪事件的风险点。验证：`make verify` 通过，`grep` 确认两个标识符均无残留。
- [ ] 5.4 复测隐身不写回偏好、且完全透明后仍可恢复：指针移入致隐身时设置中的 HUD 透明度不变，指针移出后 HUD 恢复显示且可再次隐身。验证：连续移入/移出多轮，`make dev` 中观察设置值与显示状态均正确。

## 6. 集成验证

- [x] 6.1 运行 `make test` 与 `make verify`，确认 Core 检查与 App 启动验证均通过。验证：两条命令退出码为 0。
- [ ] 6.2 端到端实测两组行为组合：交互模式调整窗口位置与透明度、切回穿透模式、指针移入/移出、CLI 增删 Doing 与 Todo 任务，确认分区、计数与隐身互不干扰。验证：逐条对照 `specs/` 下三份 delta 的场景，记录实测结果。
- [x] 6.3 在本次改动的记录中显式标注 Windows 侧未同步（`windows-native/src/core.rs` 投影与 `openspec/specs/windows-ghost-hud/spec.md` 跨平台一致性条款与实际行为的偏差）。验证：偏差有明确书面记录，且未静默修改 Windows 规格。
