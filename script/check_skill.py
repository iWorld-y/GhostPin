"""校验源 skill 与 App 中 skill 的全部路径、文件类型和内容。"""

from __future__ import annotations

import argparse
import os
import stat
import sys
from pathlib import Path


def skill_entries(directory: Path) -> dict[str, tuple[str, bytes | str | None]]:
    """读取完整目录并检查必需文件，不跟随目录内符号链接。"""
    if not stat.S_ISDIR(directory.lstat().st_mode):
        raise ValueError(f"skill 必须是普通目录: {directory}")
    for relative in ("SKILL.md", "agents/openai.yaml", "ghostpin-cli"):
        file = directory / relative
        if not stat.S_ISREG(file.lstat().st_mode):
            raise ValueError(f"skill 必需文件不是普通文件: {file}")
    if not stat.S_ISDIR((directory / "agents").lstat().st_mode):
        raise ValueError(f"agents 必须是普通目录: {directory / 'agents'}")
    if (directory / "ghostpin-cli").stat().st_size:
        raise ValueError(f"归属标记必须为空普通文件: {directory / 'ghostpin-cli'}")

    entries: dict[str, tuple[str, bytes | str | None]] = {}

    def visit(parent: Path) -> None:
        """记录文件字节、空目录和链接文本。"""
        for file in sorted(parent.iterdir()):
            relative = file.relative_to(directory).as_posix()
            mode = file.lstat().st_mode
            if stat.S_ISDIR(mode):
                entries[relative] = ("directory", None)
                visit(file)
            elif stat.S_ISREG(mode):
                entries[relative] = ("file", file.read_bytes())
            elif stat.S_ISLNK(mode):
                entries[relative] = ("symlink", os.readlink(file))
            else:
                raise ValueError(f"skill 包含不支持的文件类型: {file}")

    visit(directory)
    return entries


def validate_skill(source: Path, installed: Path) -> None:
    """比较完整 skill，任一路径、类型或内容不一致时抛出错误。"""
    expected = skill_entries(source)
    actual = skill_entries(installed)
    if expected != actual:
        paths = sorted(
            path
            for path in expected.keys() | actual.keys()
            if expected.get(path) != actual.get(path)
        )
        raise ValueError(f"skill 目录不一致: {', '.join(paths)}")


def main() -> int:
    """校验命令行指定的源目录和分发目录。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("installed", type=Path)
    arguments = parser.parse_args()
    try:
        validate_skill(arguments.source, arguments.installed)
    except (OSError, ValueError) as error:
        print(f"skill 校验失败: {error}", file=sys.stderr)
        return 1
    print(f"PASS skill 完整目录校验: {arguments.installed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
