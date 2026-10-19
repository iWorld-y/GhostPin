---
name: ghostpin-cli
description: 通过已安装的 GhostPin 应用命令行查询和管理本地待办。Use when the user asks to list, search, create, start, complete, reopen, update, or delete GhostPin tasks.
---

# GhostPin CLI

只通过已安装应用内的命令行操作 GhostPin 待办，不直接编辑任务文件。

## 固定入口

始终使用以下完整路径：

`/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli`

执行前可查询总帮助：

```bash
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli --help
```

如果该文件不存在或不可执行，停止操作并提示用户将 GhostPin.app 安装到 `/Applications`。

## 命令帮助

每条命令都支持 `-h` 和 `--help`。需要确认参数时，先执行对应命令的帮助：

```bash
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli list --help
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli add --help
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli doing --help
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli done --help
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli undone --help
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update --help
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli delete --help
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli version --help
```

## 执行流程

1. 查询和写入都优先使用 `--json`，同时检查退出码和 JSON 内容。
2. 修改已有任务前，使用 `list --all --json` 获取真实整数 ID；明确组别时可加 `--group <组名>`。用户已给出当前整数 ID 时可直接使用，不使用旧 UUID、列表序号或推测编号。
3. 按标题定位时，若存在多个同名任务且无法消歧，列出候选的整数 ID、组别和标题并询问用户。
4. 只执行用户明确要求的操作；删除范围不明确时先询问。
5. 写操作成功后检查退出码、整数 ID、组别和修改字段；删除后再次全量查询确认目标 ID 已不存在。
6. 每条任务只属于一个组。新增必须显式传 `--group`；用户或既有明确上下文没有确定组别时，先询问，不自动选择 `默认`。组名去掉首尾空白后区分大小写，长组名完整保存。

## 常用命令

```bash
# 查询未完成任务
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli list --json

# 查询全部任务，包括已完成任务
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli list --all --json

# 查询指定组，包括已完成任务
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli list --group GhostPin --all --json

# 用户明确选择“默认”组后新增
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli add "整理周报" --group 默认 --priority medium --due "2026-08-20T18:00:00+08:00" --description "汇总本周数据" --json

# 以下 ID 仅为示例，执行时使用真实查询结果
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli doing 10000 --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli done 10000 --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli undone 10000 --json

# 换组，ID 保持不变
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update 10000 --group GhostPin --json

# 修改标题、优先级、截止日期或描述
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update 10000 --title "整理并发送周报" --priority high --due "2026-08-21T18:00:00+08:00" --description "发送给团队" --json

# 清除截止日期或提醒
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update 10000 --clear-due --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update 10000 --clear-reminder --json

# 删除任务
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli delete 10000 --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli list --all --json
```

提醒时间和截止日期必须使用带时区的 ISO8601；自然语言时间先转换为绝对时间再传入。

标题以 `--` 开头时，把 `--json` 放在 `--` 前：

```bash
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli add --group 默认 --json -- "--检查参数解析"
```

命令返回非零退出码时视为失败，保留并报告错误信息，不要声称任务已处理。

## 输出

完成后简洁说明实际动作、任务标题、整数 ID 和组别。新增成功结果中的 `item.id` 必须是整数，`item.group` 必须与请求组别一致。查询请求直接整理结果，不展示无关原始输出。
