#!/usr/bin/env bash
# 把已签名 HAP 发布到本机网关，让手机可以直接从笔记本下载安装/更新。
#
#   scripts/publish-hap.sh [hap路径]
#
# 产物：
#   hap/dsh-remote-harmonyos.hap       网关路由 /dsh-remote-harmonyos.hap
#   public/harmonyos-update.json       手机「检查更新」读取的版本信息
#   public/update.json                 兼容 Web 控制台
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HAP="${1:-}"
if [[ -z "$HAP" ]]; then
  HAP="$(ls -t "$ROOT"/dist/*.hap 2>/dev/null | head -n 1 || true)"
fi
if [[ -z "$HAP" ]]; then
  HAP="$(ls -t "$ROOT"/harmonyos/entry/build/default/outputs/default/*-signed.hap 2>/dev/null | head -n 1 || true)"
fi
[[ -n "$HAP" && -f "$HAP" ]] || { echo "没有可发布的 HAP：先运行 scripts/build-hap.sh + scripts/sign-hap.sh" >&2; exit 1; }

VERSION="$(sed -n 's/.*"versionName": *"\([^"]*\)".*/\1/p' "$ROOT/harmonyos/AppScope/app.json5" | head -n 1)"
SHA="$(shasum -a 256 "$HAP" | awk '{print $1}')"
RELEASED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "$ROOT/hap"
cp "$HAP" "$ROOT/hap/dsh-remote-harmonyos.hap"

write_update_json() {
  cat > "$1" <<JSON
{
  "version": "$VERSION",
  "hapUrl": "dsh-remote-harmonyos.hap",
  "sha256": "$SHA",
  "notes": "本机自用构建（HarmonyOS 7 / API 26），由笔记本网关分发。",
  "releasedAt": "$RELEASED_AT"
}
JSON
}

write_update_json "$ROOT/public/harmonyos-update.json"
write_update_json "$ROOT/public/update.json"


echo "==> 已发布到网关："
echo "    hap/dsh-remote-harmonyos.hap  ($(du -h "$HAP" | cut -f1))"
echo "    public/harmonyos-update.json  (version $VERSION)"
echo "    sha256 $SHA"
echo

# 手机可直接点开的下载地址（Tailscale 优先，其次局域网）
TS_BIN="$(command -v tailscale 2>/dev/null || true)"
if [[ -z "$TS_BIN" && -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]]; then
  TS_BIN=/Applications/Tailscale.app/Contents/MacOS/Tailscale
fi
TS_IP=""
if [[ -n "$TS_BIN" ]]; then
  TS_IP="$("$TS_BIN" ip -4 2>/dev/null | head -n 1)"
fi
if [[ -z "$TS_IP" ]]; then
  TS_IP="$(ifconfig 2>/dev/null | awk '/inet 100\./{print $2; exit}')"
fi
LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
PORT="${DSH_REMOTE_GATEWAY_PORT:-8787}"
echo "下载地址（手机浏览器直接打开，会自动下载）："
if [[ -n "$TS_IP" ]]; then
  echo "  Tailscale: http://$TS_IP:$PORT/dsh-remote-harmonyos.hap?v=$VERSION"
fi
if [[ -n "$LAN_IP" ]]; then
  echo "  局域网:    http://$LAN_IP:$PORT/dsh-remote-harmonyos.hap?v=$VERSION"
fi
echo
echo "也可以：App → 设置 → 检查更新，两种方式装的是同一个包。"
echo "覆盖安装要求版本号递增（当前 versionCode 见 harmonyos/AppScope/app.json5）。"
