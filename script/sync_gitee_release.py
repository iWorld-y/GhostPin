"""将 GitHub 已发布的 Release 和 macOS DMG 同步到 Gitee。"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

GITHUB_REPO = "iWorld-y/GhostPin"
GITEE_REPO = "lancer_lancet/GhostPin"
GITEE_API = f"https://gitee.com/api/v5/repos/{GITEE_REPO}"


class GiteeAPIError(RuntimeError):
    """保留 Gitee HTTP 状态，区分资源不存在和请求失败。"""

    def __init__(self, method: str, path: str, status: int) -> None:
        self.status = status
        super().__init__(f"Gitee {method} {path} 失败：HTTP {status}")


def github_json(path: str) -> Any:
    """通过已认证的 gh 读取 GitHub API。"""
    result = subprocess.run(
        ["gh", "api", f"repos/{GITHUB_REPO}/{path}"],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def gitee_api(
    method: str,
    path: str,
    token: str,
    *,
    payload: dict[str, Any] | None = None,
    asset: Path | None = None,
    download: Path | None = None,
) -> Any:
    """调用 Gitee API；写入失败时停止，由下次运行重新查询远端状态。"""
    command: list[str] = [
        "curl",
        "--silent",
        "--show-error",
        "--connect-timeout",
        "15",
        "--max-time",
        "300",
        "--header",
        "@-",
        "--request",
        method,
        "--write-out",
        "\n%{http_code}",
        f"{GITEE_API}/{path}",
    ]
    if payload is not None:
        command += ["--json", json.dumps(payload, ensure_ascii=False)]
    if asset is not None:
        command += ["--form", f"file=@{asset};type=application/octet-stream"]
    if download is not None:
        command += ["--location", "--output", str(download)]
    accept = "application/octet-stream" if download is not None else "application/json"
    # Token 通过标准输入传给 curl，不写入命令参数或日志。
    result = subprocess.run(
        command,
        input=f"Authorization: Bearer {token}\nAccept: {accept}\n",
        check=True,
        capture_output=True,
        text=True,
    )
    body, status = result.stdout.rsplit("\n", 1)
    if not status.startswith("2"):
        raise GiteeAPIError(method, path, int(status))
    return json.loads(body) if body and download is None else None


def sync_release(tag: str, token: str) -> None:
    """校验源版本与标签后同步说明和 DMG，重复执行时按内容判断是否上传。"""
    if re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag) is None:
        raise ValueError("版本标签必须为 v<主版本>.<次版本>.<修订版本>")
    source: dict[str, Any] = github_json(f"releases/tags/{tag}")
    filename = f"GhostPin-{tag[1:]}.dmg"
    assets = [asset for asset in source["assets"] if asset["name"] == filename]
    if source["draft"] or source["tag_name"] != tag or len(assets) != 1:
        raise ValueError("GitHub Release 尚未发布或缺少唯一匹配的 DMG")
    commit = github_json(f"commits/{tag}")["sha"]
    refs = subprocess.run(
        [
            "git",
            "ls-remote",
            f"https://gitee.com/{GITEE_REPO}.git",
            f"refs/tags/{tag}",
            f"refs/tags/{tag}^{{}}",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    remote_refs = {
        ref: sha for sha, ref in (line.split() for line in refs.stdout.splitlines())
    }
    remote_commit = remote_refs.get(
        f"refs/tags/{tag}^{{}}", remote_refs.get(f"refs/tags/{tag}")
    )
    if remote_commit is not None and remote_commit != commit:
        raise ValueError(
            "Gitee 同名标签与 GitHub 提交不一致，请先以 GitHub 为准同步标签"
        )

    with tempfile.TemporaryDirectory(prefix="ghostpin-gitee-release-") as directory:
        dmg = Path(directory) / filename
        subprocess.run(
            [
                "gh",
                "release",
                "download",
                tag,
                "--repo",
                GITHUB_REPO,
                "--pattern",
                filename,
                "--dir",
                directory,
            ],
            check=True,
        )
        digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
        if dmg.stat().st_size != assets[0]["size"] or dmg.stat().st_size == 0:
            raise ValueError("下载的 GitHub DMG 大小不符合发布记录")
        if assets[0].get("digest") not in (None, f"sha256:{digest}"):
            raise ValueError("下载的 GitHub DMG 摘要不符合发布记录")

        payload: dict[str, Any] = {
            "tag_name": tag,
            "name": source["name"] or f"GhostPin {tag[1:]}",
            "body": source["body"] or "",
            "prerelease": source["prerelease"],
        }
        try:
            release = gitee_api("GET", f"releases/tags/{tag}", token)
        except GiteeAPIError as error:
            if error.status != 404:
                raise
            release = gitee_api(
                "POST",
                "releases",
                token,
                payload={**payload, "target_commitish": commit},
            )

        release_path = f"releases/{release['id']}"
        attachments = gitee_api(
            "GET", f"{release_path}/attach_files?per_page=100", token
        )
        matches = [asset for asset in attachments if asset["name"] == filename]
        existing = Path(directory) / "gitee.dmg"
        identical = False
        if len(matches) == 1:
            gitee_api(
                "GET",
                f"{release_path}/attach_files/{matches[0]['id']}/download",
                token,
                download=existing,
            )
            identical = hashlib.sha256(existing.read_bytes()).hexdigest() == digest
        if not identical:
            for attachment in matches:
                gitee_api(
                    "DELETE", f"{release_path}/attach_files/{attachment['id']}", token
                )
            uploaded = gitee_api(
                "POST", f"{release_path}/attach_files", token, asset=dmg
            )
            gitee_api(
                "GET",
                f"{release_path}/attach_files/{uploaded['id']}/download",
                token,
                download=existing,
            )
            if hashlib.sha256(existing.read_bytes()).hexdigest() != digest:
                raise ValueError("Gitee DMG 回读摘要与 GitHub 不一致")
        if any(release.get(key) != value for key, value in payload.items()):
            gitee_api("PATCH", release_path, token, payload=payload)
    print(f"同步完成：https://gitee.com/{GITEE_REPO}/releases/tag/{tag}")


def main() -> int:
    """读取版本标签和 CI Secret，执行同步并返回退出码。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    arguments = parser.parse_args()
    token = os.environ.get("GITEE_TOKEN", "")
    if not token:
        print("同步失败：请配置 GitHub Actions Secret GITEE_TOKEN", file=sys.stderr)
        return 1
    try:
        sync_release(arguments.tag, token)
    except (OSError, ValueError, GiteeAPIError, subprocess.CalledProcessError) as error:
        print(f"同步失败：{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
