#!/usr/bin/env bash
# 轻量校验：JS 语法 + 关键配置存在 + 空白检查。改动 gateway/public/harmonyos 后先跑这个。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
fail=0

check_js() {
  local f="$1"
  node --check "$f" >/dev/null 2>&1 || { echo "语法错误：$f" >&2; fail=1; }
}

echo "==> JS 语法"
while IFS= read -r -d '' f; do check_js "$f"; done < <(
  find gateway.js gateway-stats.cjs public packages/plugin \
    -type f \( -name '*.js' -o -name '*.cjs' -o -name '*.mjs' \) \
    -not -path '*/node_modules/*' -print0
)

echo "==> 鸿蒙工程关键配置"
for f in harmonyos/AppScope/app.json5 harmonyos/build-profile.json5 \
         harmonyos/entry/src/main/module.json5 harmonyos/oh-package.json5; do
  [[ -f "$f" ]] || { echo "缺少文件：$f" >&2; fail=1; }
done

BUNDLE="$(sed -n 's/.*"bundleName": *"\([^"]*\)".*/\1/p' harmonyos/AppScope/app.json5 | head -n 1)"
VERSION="$(sed -n 's/.*"versionName": *"\([^"]*\)".*/\1/p' harmonyos/AppScope/app.json5 | head -n 1)"
echo "    bundle=$BUNDLE version=$VERSION"
[[ -n "$BUNDLE" && -n "$VERSION" ]] || { echo "app.json5 缺少 bundleName/versionName" >&2; fail=1; }

echo "==> 插件运行时依赖"
for f in packages/plugin/index.mjs packages/plugin/package.json; do
  [[ -f "$f" ]] || { echo "缺少文件：$f" >&2; fail=1; }
done
# 插件通过相对路径直接复用仓库根目录的网关/网页/安装包，不应再保留副本或符号链接。
for dup in packages/plugin/gateway.cjs packages/plugin/gateway-stats.cjs packages/plugin/public packages/plugin/hap; do
  [[ -e "$dup" || -L "$dup" ]] && echo "提示：$dup 不应存在（插件直接复用根目录文件）" >&2
done

if git rev-parse --git-dir >/dev/null 2>&1; then
  echo "==> git 空白检查"
  git diff --check || fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "校验失败" >&2
  exit 1
fi
echo "校验通过"
