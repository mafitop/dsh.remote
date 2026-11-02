#!/usr/bin/env bash
# 用本机证书签名 HAP 或 App Pack(.app)。
#
# 准备：把签名材料放进 .signing/（已在 .gitignore 中，不会入库）：
#   .signing/store.p12            # 密钥库（含私钥）
#   .signing/certificate.cer      # 应用签名证书
#   .signing/profile.p7b          # Profile（bundle-name 必须与本应用一致）
#   .signing/signing.env          # 变量（见 sign.example.env）
#
# 用法：scripts/sign-hap.sh [输入.hap|输入.app] [输出文件]
#   - 上架华为应用市场要传 .app（App Pack），且必须用**发布**证书 + **发布** Profile；
#     DevEco「自动管理签名」生成的是 debug Profile（带设备 UDID），AGC 会拒收。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGN_DIR="${SIGNING_DIR:-$ROOT/.signing}"
DEVECO_HOME="${DEVECO_HOME:-/Applications/DevEco-Studio.app}"
JAVA="${JAVA_HOME:-$DEVECO_HOME/Contents/jbr/Contents/Home}/bin/java"
SIGN_TOOL="$DEVECO_HOME/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar"

if [[ -f "$SIGN_DIR/signing.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$SIGN_DIR/signing.env"
  set +a
fi

STORE_FILE="${STORE_FILE:-$SIGN_DIR/store.p12}"
CERT_FILE="${CERT_FILE:-$SIGN_DIR/certificate.cer}"
PROFILE_FILE="${PROFILE_FILE:-$SIGN_DIR/profile.p7b}"
KEY_ALIAS="${KEY_ALIAS:-debugKey}"
SIGN_ALG="${SIGN_ALG:-SHA256withECDSA}"

missing=()
[[ -f "$STORE_FILE" ]] || missing+=("$STORE_FILE")
[[ -f "$CERT_FILE" ]] || missing+=("$CERT_FILE")
[[ -f "$PROFILE_FILE" ]] || missing+=("$PROFILE_FILE")
[[ -x "$JAVA" ]] || missing+=("java（$JAVA）")
[[ -f "$SIGN_TOOL" ]] || missing+=("hap-sign-tool.jar（$SIGN_TOOL）")
if ((${#missing[@]})); then
  printf '缺少签名材料：\n' >&2
  printf '  %s\n' "${missing[@]}" >&2
  echo "把证书放进 $SIGN_DIR，或参考 .signing/sign.example.env 配置路径。" >&2
  exit 1
fi

: "${STORE_PASSWORD:?请设置 STORE_PASSWORD（或在 .signing/signing.env 中定义）}"
: "${KEY_PASSWORD:?请设置 KEY_PASSWORD（或在 .signing/signing.env 中定义）}"

# Profile 的 bundle-name 必须与应用一致，否则装不上。
APP_BUNDLE="$(sed -n 's/.*"bundleName": *"\([^"]*\)".*/\1/p' "$ROOT/harmonyos/AppScope/app.json5" | head -n 1)"
PROFILE_BUNDLE="$(strings -a "$PROFILE_FILE" 2>/dev/null | grep -o '"bundle-name":"[^"]*"' | head -n 1 | cut -d'"' -f4 || true)"
if [[ -n "$PROFILE_BUNDLE" && "$PROFILE_BUNDLE" != "$APP_BUNDLE" ]]; then
  echo "Profile 包名与工程不一致：profile=$PROFILE_BUNDLE app=$APP_BUNDLE" >&2
  echo "请在 AGC 为该包名生成 Profile，或修改 harmonyos/AppScope/app.json5。" >&2
  exit 1
fi

INPUT="${1:-}"
if [[ -z "$INPUT" ]]; then
  INPUT="$(ls -t "$ROOT"/harmonyos/entry/build/default/outputs/default/*.hap 2>/dev/null | head -n 1 || true)"
fi
[[ -n "$INPUT" && -f "$INPUT" ]] || { echo "找不到待签名 HAP/APP，请先运行 scripts/build-hap.sh（.app 用 hvigor assembleApp）" >&2; exit 1; }

# 按输入扩展名决定默认产物名：.app（App Pack，上架用）与 .hap 都走 sign-app
EXT="${INPUT##*.}"
[[ "$EXT" == "app" ]] || EXT="hap"

VERSION="$(sed -n 's/.*"versionName": *"\([^"]*\)".*/\1/p' "$ROOT/harmonyos/AppScope/app.json5" | head -n 1)"
OUTPUT="${2:-$ROOT/dist/dsh-remote-harmonyos-${VERSION}.${EXT}}"
mkdir -p "$(dirname "$OUTPUT")"

echo "==> 签名：$INPUT"
echo "    bundle : $APP_BUNDLE"
echo "    profile: $(basename "$PROFILE_FILE")"
"$JAVA" -jar "$SIGN_TOOL" sign-app \
  -mode localSign \
  -keyAlias "$KEY_ALIAS" \
  -keyPwd "$KEY_PASSWORD" \
  -appCertFile "$CERT_FILE" \
  -profileFile "$PROFILE_FILE" \
  -profileSigned 1 \
  -inFile "$INPUT" \
  -signAlg "$SIGN_ALG" \
  -keystoreFile "$STORE_FILE" \
  -keystorePwd "$STORE_PASSWORD" \
  -outFile "$OUTPUT" \
  -compatibleVersion 26

echo
echo "==> 已签名：$OUTPUT"
ls -lh "$OUTPUT"
shasum -a 256 "$OUTPUT" 2>/dev/null || sha256sum "$OUTPUT"
