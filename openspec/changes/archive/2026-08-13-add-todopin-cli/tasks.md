## 1. Package 与 Core 语义

- [x] 1.1 `Package.swift` 新增可执行产品 `todopin-cli` 与 target `TodoPinCLI`（依赖 `TodoPinCore`）
- [x] 1.2 `TodoStore.load()` 增加内容比较语义：解码排序后与当前 items 相等则不赋值；文件缺失且列表非空时清空
- [x] 1.3 `TodoPinCoreChecks` 新增 checks：外部写入后 load 反映变化、内容不变时 load 不触发 objectWillChange、文件缺失时 load 清空；`swift run TodoPinCoreChecks` 全绿

## 2. CLI 骨架与参数解析

- [x] 2.1 `Sources/TodoPinCLI/main.swift`：子命令分发（list/add/done/undone/update/delete）、`--help`/`--version`、退出码约定（0 成功 / 1 运行错 / 2 用法错）
- [x] 2.2 参数解析器：`--flag value` 成对解析、位置参数收集、`add` 标题按剩余参数空格连接
- [x] 2.3 输出结构：文本模式（stderr 错误 / stdout 结果）与 JSON 模式（`{"ok":true,...}` / `{"ok":false,"error":...}`，日期 ISO8601）

## 3. CLI 命令实现

- [x] 3.1 `list`：默认未完成按创建时间倒序，`--all` 含已完成；文本与 JSON 两种输出
- [x] 3.2 `add <title> [--reminder <ISO8601>]`：日期解析失败报用法错误且不写数据
- [x] 3.3 `done <id>` / `undone <id>`：id 大小写归一解析，不存在报运行错误
- [x] 3.4 `update <id> [--title] [--reminder] [--clear-reminder]`：至少一项否则用法错误；单项修改保留另一字段
- [x] 3.5 `delete <id>`：删除成功输出 `{"ok":true,"id":...}`

## 4. App 文件监听与刷新

- [x] 4.1 `Sources/TodoPin/Services/TodoFileWatcher.swift`：目录级 DispatchSource（O_EVTONLY）+ 主队列回调 + 0.5s debounce + cancel/close 清理
- [x] 4.2 `AppState` 装配：`start()` 启动 watcher 并回调 `todoStore.load()`，`stop()` 停止；加载错误仅上报 `lastErrorMessage`
- [x] 4.3 自身写入零抖动验证：App 内勾选完成不出现重载闪烁

## 5. 验证与收尾

- [x] 5.1 `swift build` 通过
- [x] 5.2 `swift run TodoPinCoreChecks` 全绿
- [x] 5.3 `./script/build_and_run.sh --verify` 通过
- [x] 5.4 手动验收：App 运行时 `todopin-cli add` 后 HUD 秒级出现新任务；`todopin-cli done` 后消失；全程不抢焦点；退出 App 后 CLI 仍可独立读写；`todopin-cli list --json` 输出可被脚本消费
