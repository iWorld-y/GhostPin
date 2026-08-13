#!/usr/bin/env bash
# 一键发布 TodoPin:同步 main → release 构建 → 打包 DMG → 打 tag → GitHub Release。
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

# 2. 工作区必须干净,防止把未提交改动打进去
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "错误: 工作区有未提交改动,请先提交或清理" >&2
  exit 1
fi

# 3. 同步 main 最新代码(含已合并的 PR)
git checkout main
git pull origin main

# 4. 防重复发布:tag 已存在则退出
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "错误: tag $TAG 已存在,该版本已发布过" >&2
  exit 1
fi

# 5. release 构建(本机 SPM manifest 沙箱问题,需 --disable-sandbox)
swift build -c release --disable-sandbox

# 6. 打包 DMG(版本号优先取 TODO_PIN_VERSION,回退读 script/VERSION)
TODO_PIN_VERSION="$VERSION" ./script/package_dmg.sh

# 7. 校验产物
DMG_PATH="dist/TodoPin-$VERSION.dmg"
if [[ ! -f "$DMG_PATH" ]]; then
  echo "错误: DMG 未生成: $DMG_PATH" >&2
  exit 1
fi

# 8. 打 tag 并推送
git tag "$TAG"
git push origin "$TAG"

# 9. 创建 GitHub Release 并上传 DMG
gh release create "$TAG" "$DMG_PATH" \
  --repo iWorld-y/TodoPin \
  --title "TodoPin $VERSION" \
  --notes "Agent native 版 $VERSION。任务操作走 MCP,App 仅负责展示与通知。"

echo ">>> 发布完成: https://github.com/iWorld-y/TodoPin/releases/tag/$TAG"
