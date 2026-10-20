"""在临时任务和 skill 目录中检查开发版 CLI。"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

from check_skill import skill_entries, validate_skill


def run(binary: Path, root: Path, *args: str, code: int = 0) -> object:
    """执行带 JSON 输出的命令并检查退出码。"""
    result = subprocess.run(
        [str(binary), *args, "--json"],
        env={
            **os.environ,
            "GHOSTPIN_TEST_SUPPORT_ROOT": str(root),
            "GHOSTPIN_TEST_SKILLS_ROOT": str(root / "skills"),
        },
        capture_output=True,
        text=True,
        check=False,
        timeout=15,
    )
    assert result.returncode == code, (args, result.stdout, result.stderr)
    payload: object = json.loads(result.stdout)
    if code:
        assert isinstance(payload, dict) and payload.get("ok") is False, payload
    return payload


def unchanged_failures(binary: Path, root: Path, task_file: Path) -> None:
    """非法参数或不存在的目标不得提交任务文件和备份。"""
    before = task_file.read_bytes()
    backup = task_file.with_name("todos.v1.backup.json")
    backup_before = backup.read_bytes() if backup.exists() else None
    failures: list[tuple[list[str], int]] = [
        (["add", "缺组"], 2),
        (["add", "空组", "--group", " \n "], 2),
        (["add", "缺值", "--group"], 2),
        (["list", "--group", " "], 2),
        (["update", "10000", "--group", ""], 2),
        (["update", "10000", "--due", "不是日期"], 2),
        (["add", "非法优先级", "--group", "默认", "--priority", "urgent"], 2),
        (["update", "99999", "--group", "项目"], 1),
        (["doing", "99999"], 1),
        (["delete", "99999"], 1),
    ]
    for invalid in (
        "00000000-0000-0000-0000-000000000001",
        "-1",
        "9999",
        "10000.5",
        "1e4",
        "9007199254740992",
    ):
        failures.append((["done", invalid], 2))
    for args, code in failures:
        run(binary, root, *args, code=code)
        assert task_file.read_bytes() == before, args
        assert (backup.read_bytes() if backup.exists() else None) == backup_before


def check_help(binary: Path, root: Path) -> None:
    """根命令和全部子命令的帮助不接触任务目录。"""
    commands: list[str] = [
        "init",
        "list",
        "add",
        "doing",
        "done",
        "undone",
        "update",
        "delete",
        "version",
    ]
    for command in (None, *commands):
        for flag in ("-h", "--help"):
            args = [str(binary), *([command] if command else []), flag]
            result = subprocess.run(
                args,
                env={
                    **os.environ,
                    "GHOSTPIN_TEST_SUPPORT_ROOT": str(root),
                    "GHOSTPIN_TEST_SKILLS_ROOT": str(root / "skills"),
                },
                capture_output=True,
                text=True,
                check=True,
                timeout=15,
            )
            assert "ghostpin-cli" in result.stdout
            if command is None:
                assert "ghostpin-cli init [--json]" in result.stdout
            assert not root.exists(), args


def check_init(binary: Path, root: Path, source: Path) -> None:
    """在临时 App 中验证来源定位、覆盖保护、链接、输出和隔离边界。"""
    app = root / "GhostPin.app/Contents"
    app_binary = app / "MacOS/ghostpin-cli"
    bundled = app / "Resources/skills/ghostpin-cli"
    app_binary.parent.mkdir(parents=True)
    bundled.parent.mkdir(parents=True)
    shutil.copy2(binary, app_binary)
    support_root = root / "tasks-must-not-exist"
    skills_root = root / "installed-skills"
    target = skills_root / "ghostpin-cli"
    env = {
        **os.environ,
        "GHOSTPIN_TEST_SUPPORT_ROOT": str(support_root),
        "GHOSTPIN_TEST_SKILLS_ROOT": str(skills_root),
    }

    def invoke(
        *arguments: str, code: int = 0, executable: Path = app_binary
    ) -> subprocess.CompletedProcess[str]:
        """执行隔离初始化命令，核对退出码且不触及任务目录。"""
        result = subprocess.run(
            [str(executable), "init", *arguments],
            env=env,
            cwd=root,
            capture_output=True,
            text=True,
            check=False,
            timeout=15,
        )
        assert result.returncode == code, (arguments, result.stdout, result.stderr)
        return result

    # 缺资源、目标父路径是普通文件时，帮助仍应在所有文件访问前返回。
    help_env_root = root / "help-skills"
    help_env_root.write_bytes(b"not a directory")
    env["GHOSTPIN_TEST_SKILLS_ROOT"] = str(help_env_root)
    for flag in ("-h", "--help"):
        help_result = invoke(flag)
        for text in (
            "~/.agents/skills/ghostpin-cli/",
            "符号链接",
            "归属标记",
            "--json",
        ):
            assert text in help_result.stdout
        assert help_env_root.read_bytes() == b"not a directory"
        assert not support_root.exists()
    missing = json.loads(invoke("--json", code=1).stdout)
    assert missing["ok"] is False and "error" in missing
    assert not support_root.exists()
    env["GHOSTPIN_TEST_SKILLS_ROOT"] = str(skills_root)
    for arguments in (("extra",), ("--unknown",), ("--group", "默认"), ("-q",)):
        failure = json.loads(invoke(*arguments, "--json", code=2).stdout)
        assert failure["ok"] is False
        assert not skills_root.exists() and not support_root.exists()
    shutil.copytree(source, bundled, symlinks=True)
    (bundled / "nested/empty").mkdir(parents=True)
    (bundled / "nested/.hidden").write_bytes(b"bundled helper")

    installed = json.loads(invoke("--json").stdout)
    assert installed == {"ok": True, "path": str(target.resolve())}
    validate_skill(bundled, target)
    assert not support_root.exists()
    other = skills_root / "other-skill"
    other.symlink_to("../unrelated")
    (target / "old-file").write_bytes(b"stale")
    (target / "SKILL.md").write_bytes(b"local change")
    text_result = invoke()
    assert str(target.resolve()) in text_result.stdout
    validate_skill(bundled, target)
    assert other.readlink() == Path("../unrelated")

    # 调用当前 CLI 的链接时，来源仍应来自实际二进制相邻资源。
    cli_link = root / "cli-link"
    cli_link.symlink_to("GhostPin.app/Contents/MacOS/ghostpin-cli")
    installed = json.loads(invoke("--json", executable=cli_link).stdout)
    assert installed == {"ok": True, "path": str(target.resolve())}

    real = root / "real-skill"
    target.rename(real)
    middle = root / "middle-skill"
    middle.symlink_to("real-skill")
    target.symlink_to("../middle-skill")
    installed = json.loads(invoke("--json").stdout)
    assert installed == {"ok": True, "path": str(real.resolve())}
    assert target.readlink() == Path("../middle-skill")
    assert middle.readlink() == Path("real-skill")
    validate_skill(bundled, real)
    before = skill_entries(real)
    for arguments in (("extra",), ("--unknown",)):
        failure = json.loads(invoke(*arguments, "--json", code=2).stdout)
        assert failure["ok"] is False and skill_entries(real) == before

    (real / "ghostpin-cli").unlink()
    failure = json.loads(invoke("--json", code=1).stdout)
    assert failure["ok"] is False and "归属标记" in failure["error"]
    assert (real / "SKILL.md").read_bytes() == (bundled / "SKILL.md").read_bytes()
    assert not (real / "ghostpin-cli").exists()
    assert target.readlink() == Path("../middle-skill")
    target.unlink()
    for destination in ("missing", "ghostpin-cli"):
        target.symlink_to(destination)
        failure = json.loads(invoke("--json", code=1).stdout)
        assert failure["ok"] is False and target.readlink() == Path(destination)
        target.unlink()
    target.write_bytes(b"keep this file")
    failure = json.loads(invoke("--json", code=1).stdout)
    assert failure["ok"] is False and target.read_bytes() == b"keep this file"
    target.unlink()
    shutil.copytree(bundled, target, symlinks=True)

    # 已有损坏任务也不应被 init 读取、迁移或改写。
    task = support_root / "GhostPin/todos.json"
    task.parent.mkdir(parents=True)
    task.write_bytes(b"unreadable task document")
    task.chmod(0)
    try:
        invoke("--json")
        for required in ("ghostpin-cli", "SKILL.md", "agents/openai.yaml"):
            path = bundled / required
            content = path.read_bytes()
            path.unlink()
            failure = json.loads(invoke("--json", code=1).stdout)
            assert failure["ok"] is False
            path.write_bytes(content)
            validate_skill(bundled, target)
        assert list(task.parent.iterdir()) == [task]
    finally:
        task.chmod(0o600)
    assert task.read_bytes() == b"unreadable task document"
    print("PASS init 隔离检查：来源定位、帮助、参数、完整替换、链接、归属和任务隔离")


def main() -> None:
    """验证迁移、组别、整数 ID、并发和失败保护。"""
    repository = Path(__file__).resolve().parents[1]
    binary = repository / ".build/debug/ghostpin-cli"
    with tempfile.TemporaryDirectory(prefix="ghostpin-cli-check-") as temporary:
        root = Path(temporary)
        check_help(binary, root / "help-must-not-exist")
        check_init(binary, root / "init-check", repository / "skills/ghostpin-cli")
        assert run(binary, root, "list") == []
        task_file = root / "GhostPin/todos.json"
        assert not task_file.exists()
        legacy = repository / "windows-native/tests/fixtures/tasks-groups-legacy.json"
        task_file.write_bytes(legacy.read_bytes())
        unchanged_failures(binary, root, task_file)
        migrated = run(binary, root, "list", "--all")
        assert isinstance(migrated, list) and len(migrated) == 3
        assert {item["id"] for item in migrated} == {10000, 10001, 10002}
        assert {item["group"] for item in migrated} == {"默认"}
        assert (
            task_file.with_name("todos.v1.backup.json").read_bytes()
            == legacy.read_bytes()
        )

        created = run(
            binary, root, "add", "长组任务", "--group", "  完整项目名称 Project  "
        )
        assert isinstance(created, dict) and created["ok"] is True
        item = created["item"]
        assert item["id"] == 10003 and item["group"] == "完整项目名称 Project"
        assert run(binary, root, "list", "--group", "完整项目名称 Project") == [item]
        assert run(binary, root, "list", "--group", "完整项目名称 project") == []
        fields = run(
            binary,
            root,
            "update",
            "10003",
            "--reminder",
            "2027-01-01T09:00:00+08:00",
            "--due",
            "2027-01-02T18:00:00+08:00",
            "--priority",
            "high",
            "--description",
            "保留详情",
        )
        renamed = run(binary, root, "update", "10003", "--title", "临时新标题")
        assert isinstance(fields, dict) and isinstance(renamed, dict)
        assert renamed["item"]["reminderAt"] == fields["item"]["reminderAt"]
        assert renamed["item"]["dueAt"] == fields["item"]["dueAt"]
        assert (
            renamed["item"]["priority"] == "high"
            and renamed["item"]["description"] == "保留详情"
        )
        cleared = run(
            binary,
            root,
            "update",
            "10003",
            "--title",
            "长组任务",
            "--clear-reminder",
            "--clear-due",
        )
        assert (
            isinstance(cleared, dict)
            and cleared["item"]["reminderAt"] is None
            and cleared["item"]["dueAt"] is None
        )
        for command, status in (
            ("doing", "doing"),
            ("done", "done"),
            ("undone", "todo"),
        ):
            changed = run(binary, root, command, "10003")
            assert isinstance(changed, dict) and changed["item"]["status"] == status
            assert changed["item"]["id"] == 10003
            if command == "done":
                assert (
                    run(binary, root, "list", "--group", "完整项目名称 Project") == []
                )
                completed = run(
                    binary, root, "list", "--group", "完整项目名称 Project", "--all"
                )
                assert isinstance(completed, list) and len(completed) == 1
        moved = run(binary, root, "update", "10003", "--group", "默认")
        assert isinstance(moved, dict) and moved["item"]["group"] == "默认"
        assert (
            run(binary, root, "list", "--group", "完整项目名称 Project", "--all") == []
        )
        unchanged_failures(binary, root, task_file)

        # App 使用同一个 Core 入口。先加载旧快照，再交错 CLI 写入和状态、提醒回写。
        worker = subprocess.Popen(
            [
                str(repository / ".build/debug/GhostPinCoreChecks"),
                "--app-worker",
                str(task_file.parent),
                "10003",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            deadline = time.monotonic() + 5
            while not (task_file.parent / f"ready-{worker.pid}").exists():
                assert time.monotonic() < deadline, "App 工作进程未就绪"
                time.sleep(0.01)
            run(binary, root, "update", "10003", "--group", "App 外部新组")
            run(binary, root, "add", "外部新增", "--group", "另一组")
            (task_file.parent / "go").touch()
            stdout, stderr = worker.communicate(timeout=15)
            assert worker.returncode == 0, (stdout, stderr)
        finally:
            if worker.poll() is None:
                worker.kill()
                worker.communicate()
        latest = json.loads(task_file.read_text())
        target = next(item for item in latest["items"] if item["id"] == 10003)
        assert target["group"] == "App 外部新组" and target["status"] == "doing"
        assert target["reminderSentAt"] is not None
        assert latest["nextID"] == 10005 and len(latest["items"]) == 5

        # 文本写命令返回整数行；list 文本包含完整组名。
        for args in (
            ("done", "10003"),
            ("undone", "10003"),
            ("doing", "10003"),
            ("update", "10003", "--description", "文本回执"),
        ):
            text_result = subprocess.run(
                [str(binary), *args],
                env={**os.environ, "GHOSTPIN_TEST_SUPPORT_ROOT": str(root)},
                capture_output=True,
                text=True,
                check=True,
                timeout=15,
            )
            assert text_result.stdout.strip() == "10003"
        text_list = subprocess.run(
            [str(binary), "list", "--group", "App 外部新组"],
            env={**os.environ, "GHOSTPIN_TEST_SUPPORT_ROOT": str(root)},
            capture_output=True,
            text=True,
            check=True,
            timeout=15,
        )
        assert "10003\tdoing\tApp 外部新组\t长组任务" in text_list.stdout

        processes: list[subprocess.Popen[str]] = [
            subprocess.Popen(
                [str(binary), "add", f"并发 {index}", "--group", "并发", "--json"],
                env={**os.environ, "GHOSTPIN_TEST_SUPPORT_ROOT": str(root)},
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            for index in range(8)
        ]
        ids: set[int] = set()
        for process in processes:
            stdout, stderr = process.communicate(timeout=15)
            assert process.returncode == 0, stderr
            ids.add(json.loads(stdout)["item"]["id"])
        assert ids == set(range(10005, 10013)), ids
        all_items = run(binary, root, "list", "--all")
        assert isinstance(all_items, list) and len(all_items) == 13
        for item in all_items:
            if item["id"] == 10003:
                deleted_text = subprocess.run(
                    [str(binary), "delete", "10003"],
                    env={**os.environ, "GHOSTPIN_TEST_SUPPORT_ROOT": str(root)},
                    capture_output=True,
                    text=True,
                    check=True,
                    timeout=15,
                )
                assert deleted_text.stdout.strip() == "10003"
            else:
                deleted = run(binary, root, "delete", str(item["id"]))
                assert deleted == {"ok": True, "id": item["id"]}
        assert run(binary, root, "list", "--all") == []
        continued = run(binary, root, "add", "清空后继续", "--group", "默认")
        assert isinstance(continued, dict) and continued["item"]["id"] == 10013
        document = json.loads(task_file.read_text())
        assert document["nextID"] == 10014 and document["schemaVersion"] == 2
        # 在同一隔离目录恢复原始备份并重新迁移，验证恢复字节及映射。
        current = task_file.read_bytes()
        task_file.write_bytes(task_file.with_name("todos.v1.backup.json").read_bytes())
        assert task_file.read_bytes() == legacy.read_bytes()
        assert run(binary, root, "list", "--all") == migrated
        task_file.write_bytes(current)
        print(
            "PASS CLI 隔离集成检查：帮助、失败保护、迁移、组别、状态、并发、删除与继续编号"
        )


if __name__ == "__main__":
    main()
