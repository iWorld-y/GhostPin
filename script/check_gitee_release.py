"""隔离验证 Gitee Release 同步，不访问网络或真实发行版。"""

from __future__ import annotations

import hashlib
import json
import subprocess
import unittest
from pathlib import Path
from types import SimpleNamespace
from typing import Any
from unittest.mock import patch

import sync_gitee_release as sync

TAG = "v1.2.3"
COMMIT = "a" * 40
FILENAME = "GhostPin-1.2.3.dmg"
DMG = b"verified GitHub DMG"


class ReleaseSyncChecks(unittest.TestCase):
    """用内存中的远端状态检查同步与中断恢复。"""

    def setUp(self) -> None:
        self.source: dict[str, Any] = {
            "tag_name": TAG,
            "name": "GhostPin 1.2.3",
            "body": "新增功能\n修复问题",
            "draft": False,
            "prerelease": False,
            "assets": [
                {
                    "name": FILENAME,
                    "size": len(DMG),
                    "digest": f"sha256:{hashlib.sha256(DMG).hexdigest()}",
                }
            ],
        }
        self.release: dict[str, Any] | None = None
        self.attachments: dict[int, bytes] = {}
        self.calls: list[tuple[str, str]] = []
        self.tag_commit = COMMIT
        self.missing_release_returns_null = False
        self.lose_create_response = False
        self.lose_upload_response = False
        self.corrupt_upload = False
        self.github = patch.object(sync, "github_json", side_effect=self.github_json)
        self.api = patch.object(sync, "gitee_api", side_effect=self.gitee_api)
        self.process = patch.object(
            sync.subprocess, "run", side_effect=self.run_command
        )
        for mock in (self.github, self.api, self.process):
            mock.start()
            self.addCleanup(mock.stop)

    def github_json(self, path: str) -> dict[str, Any]:
        """提供固定的 GitHub 发布信息与提交。"""
        return {"sha": COMMIT} if path.startswith("commits/") else self.source

    def run_command(self, command: list[str], **kwargs: Any) -> SimpleNamespace:
        """替代标签查询和 DMG 下载。"""
        if command[:2] == ["git", "ls-remote"]:
            refs = f"{self.tag_commit}\trefs/tags/{TAG}\n" if self.tag_commit else ""
            return SimpleNamespace(stdout=refs)
        self.assertEqual(command[:3], ["gh", "release", "download"])
        (Path(command[-1]) / FILENAME).write_bytes(DMG)
        return SimpleNamespace(stdout="")

    def gitee_api(self, method: str, path: str, token: str, **kwargs: Any) -> Any:
        """记录远端写入，并允许模拟服务器已完成写入后的响应丢失。"""
        self.calls.append((method, path))
        if kwargs.get("download") is not None:
            attachment_id = int(path.split("/")[-2])
            kwargs["download"].write_bytes(self.attachments[attachment_id])
            return None
        if path == f"releases/tags/{TAG}":
            if self.release is None:
                if self.missing_release_returns_null:
                    return None
                raise sync.GiteeAPIError(method, path, 404)
            return self.release.copy()
        if (method, path) == ("POST", "releases"):
            self.release = {"id": 42, **kwargs["payload"]}
            if self.lose_create_response:
                self.lose_create_response = False
                raise subprocess.CalledProcessError(28, ["curl"])
            return self.release.copy()
        if (method, path) == ("PATCH", "releases/42"):
            assert self.release is not None
            self.release.update(kwargs["payload"])
            return self.release.copy()
        if method == "DELETE":
            del self.attachments[int(path.split("/")[-1])]
            return None
        if method == "POST":
            self.attachments[100] = (
                b"corrupt" if self.corrupt_upload else kwargs["asset"].read_bytes()
            )
            if self.lose_upload_response:
                self.lose_upload_response = False
                raise subprocess.CalledProcessError(28, ["curl"])
            return {"id": 100}
        self.assertEqual(path, "releases/42/attach_files?per_page=100")
        return [{"id": key, "name": FILENAME} for key in self.attachments]

    def test_initial_sync_and_identical_retry(self) -> None:
        self.tag_commit = ""
        sync.sync_release(TAG, "test-token")
        assert self.release is not None
        self.assertEqual(self.release["target_commitish"], COMMIT)
        self.assertEqual(self.release["body"], self.source["body"])
        self.assertEqual(self.attachments, {100: DMG})
        self.calls.clear()
        sync.sync_release(TAG, "test-token")
        self.assertTrue(all(method == "GET" for method, _ in self.calls))

    def test_initial_null_lookup_creates_release_and_identical_retry(self) -> None:
        self.missing_release_returns_null = True
        sync.sync_release(TAG, "test-token")
        assert self.release is not None
        self.assertEqual(self.release["target_commitish"], COMMIT)
        self.assertEqual(self.calls.count(("POST", "releases")), 1)
        self.assertEqual(self.attachments, {100: DMG})
        self.calls.clear()
        sync.sync_release(TAG, "test-token")
        self.assertTrue(all(method == "GET" for method, _ in self.calls))

    def test_conflicting_content_follows_github(self) -> None:
        self.release = {"id": 42, "tag_name": TAG, "name": "旧标题", "body": "旧说明"}
        self.attachments = {99: b"old DMG"}
        sync.sync_release(TAG, "test-token")
        self.assertEqual(self.attachments, {100: DMG})
        self.assertEqual(self.release["body"], self.source["body"])
        self.assertIn(("DELETE", "releases/42/attach_files/99"), self.calls)

    def test_unknown_create_result_is_reconciled_on_retry(self) -> None:
        self.lose_create_response = True
        with self.assertRaises(subprocess.CalledProcessError):
            sync.sync_release(TAG, "test-token")
        self.assertIsNotNone(self.release)
        self.assertEqual(self.attachments, {})
        sync.sync_release(TAG, "test-token")
        self.assertEqual(self.calls.count(("POST", "releases")), 1)
        self.assertEqual(self.attachments, {100: DMG})

    def test_conflicting_tag_stops_before_writes(self) -> None:
        self.tag_commit = "b" * 40
        with self.assertRaisesRegex(ValueError, "标签.*不一致"):
            sync.sync_release(TAG, "test-token")
        self.assertEqual(self.calls, [])

    def test_unknown_upload_result_is_reconciled_on_retry(self) -> None:
        self.lose_upload_response = True
        with self.assertRaises(subprocess.CalledProcessError):
            sync.sync_release(TAG, "test-token")
        self.assertEqual(self.attachments, {100: DMG})
        sync.sync_release(TAG, "test-token")
        self.assertEqual(self.calls.count(("POST", "releases/42/attach_files")), 1)

    def test_invalid_source_stops_before_writes(self) -> None:
        for field, value in (("draft", True), ("assets", [])):
            with self.subTest(field=field):
                original = self.source[field]
                self.source[field] = value
                with self.assertRaises(ValueError):
                    sync.sync_release(TAG, "test-token")
                self.source[field] = original
                self.assertEqual(self.calls, [])

    def test_github_digest_mismatch_stops_before_writes(self) -> None:
        self.source["assets"][0]["digest"] = "sha256:incorrect"
        with self.assertRaisesRegex(ValueError, "GitHub DMG 摘要"):
            sync.sync_release(TAG, "test-token")
        self.assertEqual(self.calls, [])

    def test_gitee_readback_detects_corruption(self) -> None:
        self.corrupt_upload = True
        with self.assertRaisesRegex(ValueError, "Gitee DMG 回读摘要"):
            sync.sync_release(TAG, "test-token")

    def test_permission_failure_does_not_create_release(self) -> None:
        with (
            patch.object(
                sync,
                "gitee_api",
                side_effect=sync.GiteeAPIError("GET", "releases", 403),
            ) as request,
            self.assertRaises(sync.GiteeAPIError),
        ):
            sync.sync_release(TAG, "test-token")
        self.assertEqual(request.call_count, 1)
        self.assertEqual(request.call_args.args[0], "GET")


class GiteeAPIChecks(unittest.TestCase):
    """检查 curl 契约，避免 Token 出现在参数中或隐式重发写请求。"""

    def test_http_200_null_response(self) -> None:
        with patch.object(
            sync.subprocess, "run", return_value=SimpleNamespace(stdout="null\n200")
        ):
            self.assertIsNone(
                sync.gitee_api("GET", f"releases/tags/{TAG}", "test-secret")
            )

    def test_json_request(self) -> None:
        with patch.object(
            sync.subprocess,
            "run",
            return_value=SimpleNamespace(stdout='{"id":42}\n201'),
        ) as run:
            result = sync.gitee_api(
                "POST", "releases", "test-secret", payload={"name": "版本"}
            )
        self.assertEqual(result, {"id": 42})
        command = run.call_args.args[0]
        self.assertNotIn("test-secret", " ".join(command))
        self.assertNotIn("--retry", command)
        self.assertIn(
            "Authorization: Bearer test-secret", run.call_args.kwargs["input"]
        )
        self.assertEqual(json.loads(command[-1]), {"name": "版本"})

    def test_http_failure(self) -> None:
        for status in ("401", "404", "500"):
            with (
                self.subTest(status=status),
                patch.object(
                    sync.subprocess,
                    "run",
                    return_value=SimpleNamespace(
                        stdout=f'{{"message":"error"}}\n{status}'
                    ),
                ),
                self.assertRaises(sync.GiteeAPIError) as error,
            ):
                sync.gitee_api("GET", "releases", "test-secret")
            self.assertEqual(error.exception.status, int(status))

    def test_download_requests_binary(self) -> None:
        with patch.object(
            sync.subprocess, "run", return_value=SimpleNamespace(stdout="\n200")
        ) as run:
            sync.gitee_api("GET", "download", "test-secret", download=Path("dmg"))
        self.assertIn("Accept: application/octet-stream", run.call_args.kwargs["input"])
        self.assertIn("--location", run.call_args.args[0])


if __name__ == "__main__":
    unittest.main(verbosity=2)
