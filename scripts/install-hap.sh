#!/usr/bin/env bash
# 把已签名 HAP 装到鸿蒙手机。需要：手机开启「开发者模式 + USB 调试」，用数据线连接。
#
#   scripts/install-hap.sh [hap路径]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVECO_HOME="${DEVECO_HOME:-/Applications/DevEco-Studio.app}"
HDC="${HDC:-$DEVECO_HOME/Contents/sdk/default/openharmony/toolchains/hdc}"
BUNDLE="$(sed -n 's/.*"bundleName": *"\([^"]*\)".*/\1/p' "$ROOT/harmonyos/AppScope/app.json5" | head -n 1)"

[[ -x "$HDC" ]] || { echo "找不到 hdc：$HDC" >&2; exit 1; }

HAP="${1:-}"
if [[ -z "$HAP" ]]; then
  # 优先 dist/（手工签名产物），其次 DevEco/hvigor 产出的 signed HAP
  HAP="$(ls -t "$ROOT"/dist/*.hap 2>/dev/null | head -n 1 || true)"
fi
if [[ -z "$HAP" ]]; then
  HAP="$(ls -t "$ROOT"/harmonyos/entry/build/default/outputs/default/*-signed.hap 2>/dev/null | head -n 1 || true)"
fi
[[ -n "$HAP" && -f "$HAP" ]] || {
  echo "没有可安装的已签名 HAP。" >&2
  echo "  自动签名：scripts/build-hap.sh（需 build-profile.json5 里 product 引用 signingConfig）" >&2
  echo "  手工签名：scripts/sign-hap.sh（需 .signing/ 证书）" >&2
  exit 1
}

echo "==> 已连接设备："
"$HDC" list targets || true
echo
echo "==> 安装：$HAP"
"$HDC" install -r "$HAP"

echo
echo "==> 启动 $BUNDLE"
"$HDC" shell aa start -a EntryAbility -b "$BUNDLE"

echo
echo "提示：首次启动若被系统拦截，请在手机上允许「安装外部来源应用 / 调试应用」。"
