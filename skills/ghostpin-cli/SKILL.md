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
2. 修改已有任务前，使用 `list --all --json` 获取真实 UUID；用户已给出 UUID 时可直接使用。
3. 按标题定位时，若存在多个同名任务且无法消歧，列出候选并询问用户。
4. 只执行用户明确要求的操作；删除范围不明确时先询问。
5. 写操作成功后检查返回结果；删除后再次查询确认目标 UUID 已不存在。

## 常用命令

```bash
# 查询未完成任务
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli list --json

# 查询全部任务，包括已完成任务
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli list --all --json

# 新增任务
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli add "整理周报" --priority medium --due "2026-08-20T18:00:00+08:00" --description "汇总本周数据" --json

# 修改状态
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli doing <uuid> --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli done <uuid> --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli undone <uuid> --json

# 修改标题、优先级、截止日期或描述
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update <uuid> --title "整理并发送周报" --priority high --due "2026-08-21T18:00:00+08:00" --description "发送给团队" --json

# 清除截止日期或提醒
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update <uuid> --clear-due --json
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli update <uuid> --clear-reminder --json

# 删除任务
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli delete <uuid> --json
```

提醒时间和截止日期必须使用带时区的 ISO8601；自然语言时间先转换为绝对时间再传入。

标题以 `--` 开头时，把 `--json` 放在 `--` 前：

```bash
/Applications/GhostPin.app/Contents/MacOS/ghostpin-cli add --json -- "--检查参数解析"
```

命令返回非零退出码时视为失败，保留并报告错误信息，不要声称任务已处理。

## 输出

完成后简洁说明实际动作、任务标题和 UUID。查询请求直接整理结果，不展示无关原始输出。
