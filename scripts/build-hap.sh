#!/usr/bin/env bash
# 构建鸿蒙 HAP（默认 release）。产物：harmonyos/entry/build/default/outputs/default/*.hap
#
#   scripts/build-hap.sh            # release
#   scripts/build-hap.sh debug      # debug
#
# 可用环境变量覆盖：DEVECO_HOME / JAVA_HOME / DEVECO_SDK_HOME / HVIGOR_USER_HOME
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVECO_HOME="${DEVECO_HOME:-/Applications/DevEco-Studio.app}"
BUILD_MODE="${1:-release}"
HVIGOR="$DEVECO_HOME/Contents/tools/hvigor/bin/hvigorw"

if [[ ! -x "$HVIGOR" ]]; then
  echo "找不到 hvigor：$HVIGOR" >&2
  echo "请安装 DevEco Studio，或用 DEVECO_HOME 指向其安装目录。" >&2
  exit 1
fi

export JAVA_HOME="${JAVA_HOME:-$DEVECO_HOME/Contents/jbr/Contents/Home}"
export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$DEVECO_HOME/Contents/sdk}"
export PATH="$JAVA_HOME/bin:$DEVECO_HOME/Contents/tools/node/bin:$PATH"
# hvigor 默认把缓存写到 ~/.hvigor；沙箱/CI 下可改到项目内。
export HVIGOR_USER_HOME="${HVIGOR_USER_HOME:-$ROOT/.hvigor-home}"
export npm_config_cache="${npm_config_cache:-$ROOT/.npm-cache}"
mkdir -p "$HVIGOR_USER_HOME" "$npm_config_cache"

# build-profile.json5 不入库（DevEco 自动签名会把证书路径与加密密码写进去）
if [[ ! -f "$ROOT/harmonyos/build-profile.json5" ]]; then
  echo "==> build-profile.json5 不存在，从 build-profile.example.json5 复制"
  cp "$ROOT/harmonyos/build-profile.example.json5" "$ROOT/harmonyos/build-profile.json5"
fi

cd "$ROOT/harmonyos"
echo "==> 构建模式：$BUILD_MODE"
"$HVIGOR" assembleHap --mode module \
  -p module=entry@default \
  -p product=default \
  -p buildMode="$BUILD_MODE" \
  --no-daemon

OUT_DIR="$ROOT/harmonyos/entry/build/default/outputs/default"
SIGNED_HAP="$(ls -t "$OUT_DIR"/*-signed.hap 2>/dev/null | head -n 1 || true)"
HAP="${SIGNED_HAP:-$(ls -t "$OUT_DIR"/*.hap 2>/dev/null | head -n 1 || true)}"
if [[ -z "$HAP" ]]; then
  echo "构建结束但没有找到 HAP，请检查上方日志。" >&2
  exit 1
fi

echo
echo "==> 产物：$HAP"
ls -lh "$HAP"
shasum -a 256 "$HAP" 2>/dev/null || sha256sum "$HAP"

if [[ -z "$SIGNED_HAP" ]]; then
  echo
  echo "!! 本次产物未签名，安装会报 'no signature file'。" >&2
  echo "   DevEco: File → Project Structure → 签名配置 → 选「自动管理签名」。" >&2
  echo "   或确认 build-profile.json5 的 products[0] 里有 \"signingConfig\": \"default\"。" >&2
else
  echo
  echo "下一步：scripts/install-hap.sh"
fi
