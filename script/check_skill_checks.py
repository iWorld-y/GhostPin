"""使用临时夹具检查 skill 校验命令的成功和失败出口。"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def check_fixture(source: Path, target: Path, code: int, mutation: str) -> None:
    """执行校验命令并核对退出码。"""
    result = subprocess.run(
        [
            sys.executable,
            str(Path(__file__).with_name("check_skill.py")),
            str(source),
            str(target),
        ],
        capture_output=True,
        text=True,
        check=False,
        timeout=15,
    )
    assert result.returncode == code, (mutation, result.stdout, result.stderr)


def main() -> None:
    """验证内容、路径、类型和归属标记检查。"""
    repository = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="ghostpin-skill-validator-") as temporary:
        root = Path(temporary)
        source = root / "source"
        shutil.copytree(repository / "skills/ghostpin-cli", source, symlinks=True)
        (source / "nested/empty").mkdir(parents=True)
        (source / "nested/.hidden").write_bytes(b"helper")
        (source / "reference").symlink_to("SKILL.md")
        target = root / "target"
        mutations = (
            "valid",
            "missing",
            "extra",
            "content",
            "directory-type",
            "link-text",
            "marker-missing",
            "marker-nonempty",
            "marker-directory",
            "marker-link",
        )
        for mutation in mutations:
            shutil.copytree(source, target, symlinks=True)
            if mutation == "missing":
                (target / "agents/openai.yaml").unlink()
            elif mutation == "extra":
                (target / "old-file").touch()
            elif mutation == "content":
                (target / "nested/.hidden").write_bytes(b"changed")
            elif mutation == "directory-type":
                (target / "nested/empty").rmdir()
                (target / "nested/empty").touch()
            elif mutation == "link-text":
                (target / "reference").unlink()
                (target / "reference").symlink_to("./SKILL.md")
            elif mutation.startswith("marker-"):
                marker = target / "ghostpin-cli"
                marker.unlink()
                if mutation == "marker-nonempty":
                    marker.write_bytes(b"invalid")
                elif mutation == "marker-directory":
                    marker.mkdir()
                elif mutation == "marker-link":
                    marker.symlink_to("SKILL.md")
            check_fixture(source, target, 0 if mutation == "valid" else 1, mutation)
            shutil.rmtree(target)
        print("PASS skill 校验器隔离检查：完整目录、缺失、额外文件、内容、类型和标记")


if __name__ == "__main__":
    main()
