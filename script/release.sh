#!/usr/bin/env bash
# 一键发布 GhostPin:提交版本号 → 同步 main → 推送 tag → 触发 GitHub Actions 发布。
# 用法: 先手动修改 script/VERSION 为最新版本号,然后执行 `bash script/release.sh`。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# 1. 读取版本号
VERSION="$(cat script/VERSION | tr -d '[:space:]')"
if [[ -z "$VERSION" ]]; then
  echo "错误: script/VERSION 为空,请先填写版本号" >&2
  exit 1
fi
TAG="v$VERSION"
echo ">>> 发布版本: $VERSION (tag: $TAG)"

# 2. 工作区必须干净,但允许 script/VERSION 作为本次发布的版本输入
dirty_paths=()
version_file_dirty=false
while IFS= read -r status_line; do
  [[ -z "$status_line" ]] && continue
  path="${status_line:3}"
  dirty_paths+=("$path")
  if [[ "$path" == "script/VERSION" ]]; then
    version_file_dirty=true
  fi
done < <(git status --porcelain=v1 --untracked-files=all)

unexpected_dirty_paths=()
for path in "${dirty_paths[@]}"; do
  if [[ "$path" != "script/VERSION" ]]; then
    unexpected_dirty_paths+=("$path")
  fi
done

if ((${#unexpected_dirty_paths[@]} > 0)); then
  echo "错误: 工作区有未提交改动,仅允许 script/VERSION 作为发布版本输入:" >&2
  printf '  %s\n' "${unexpected_dirty_paths[@]}" >&2
  exit 1
fi

if ((${#dirty_paths[@]} > 0)); then
  echo ">>> 检测到仅 script/VERSION 改动,将自动提交并推送版本号"
fi

# 3. 防重复发布:本地或远程 tag 已存在则退出
if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "错误: tag $TAG 已存在,该版本已发布过" >&2
  exit 1
fi

remote_tags="$(git ls-remote --tags origin "refs/tags/$TAG")" || {
  echo "错误: 无法查询远程 tag,已停止发布" >&2
  exit 1
}
if [[ -n "$remote_tags" ]]; then
  echo "错误: 远程 tag $TAG 已存在,该版本已发布过" >&2
  exit 1
fi

# 4. 同步 main 最新代码(含已合并的 PR)
git checkout main
if [[ "$version_file_dirty" == true ]]; then
  git add script/VERSION
  git commit -m "发布版本 ${VERSION}"
  git pull --rebase origin main
  git push origin main
else
  git pull origin main
fi

# 5. 打 tag 并推送,由 GitHub Actions 负责构建 DMG 和创建 Release
git tag "$TAG"
git push origin "$TAG"

echo ">>> 已推送 tag: $TAG"
echo ">>> GitHub Actions 将自动构建 DMG 并创建 Release"
