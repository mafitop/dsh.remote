# DSH Remote · 鸿蒙个人版

- `harmonyos/` —— 原生 ArkTS/ArkUI 客户端，面向 **HarmonyOS 7.0（API 26）**
- `gateway.js` + `public/` —— 笔记本端网关（单文件、零运行时依赖），负责鉴权、代理 DSH、文件传输、配对
- `packages/plugin/` —— 可选的 DSH 插件（在 DSH 里一键启停网关），通过相对路径直接复用仓库根目录的 `gateway.js` / `public/` / `hap/`，不再保留副本

## 这个分支改了什么

| 项目 | dsh.remote |
| --- | --- |
| 平台 | 仅 HarmonyOS 手机 |
| 兼容 SDK | `26.0.0`（HarmonyOS 7.0） |
| 包名 | `com.mafit.dshremote` |
| 版本 | 0.10.17（客户端与仓库对齐） |
| 设备类型 | phone |
| 更新 | 由笔记本网关分发 HAP，手机内直接下载 |
| 户外联网 | 局域网 + Tailscale 组网（见 `docs/TAILSCALE.md`） |

## 目录

```text
harmonyos/                鸿蒙客户端（ArkTS/ArkUI，DevEco 工程）
gateway.js                笔记本端网关（单文件）
gateway-stats.cjs         网关统计模块（gateway.js 依赖）
public/                   网关控制台（配对二维码 / 设备管理 / 更新分发）
packages/plugin/          DSH 插件（可选；相对路径复用根目录的 gateway.js / public / hap）
scripts/
  build-hap.sh            构建未签名 HAP
  sign-hap.sh             用本机证书签名
  install-hap.sh          通过 hdc 装到手机
  publish-hap.sh          把 HAP 发布到网关，供手机下载更新
  verify.sh               轻量校验
docs/                     构建签名、Tailscale、架构说明、上架素材
```

## 笔记本端：启动网关

```sh
node gateway.js            # 默认 0.0.0.0:8787，上游 DSH 默认 127.0.0.1:3080
```

常用环境变量：

```sh
PORT=8787
TOKEN=...                          # 不设则自动生成到 ~/.dsh-remote/token
DSH_UPSTREAM=http://127.0.0.1:3080
```

打开 `http://127.0.0.1:8787/health` 确认网关存活；控制台在 `http://127.0.0.1:8787/`，管理页在 `/admin`（生成配对二维码、看设备、改令牌）。

### DSH 版本较新时：需要会话 Cookie

DSH 0.1.2 起，Host RPC 与 WebSocket 要求浏览器会话 Cookie。网关会读取
`~/.dsh-remote/dsh-upstream.cookie`；这个文件由 **DSH 插件**在启动时自动兑换并刷新。

所以推荐在 DSH 里装上本仓库的插件（插件同时负责网关自启停）：

```sh
dsh plugin --profile web add ./packages/plugin
```

如果你只想跑独立网关，就把浏览器打开 DSH 后拿到的会话 Cookie（形如 `name=value`）
写进 `~/.dsh-remote/dsh-upstream.cookie`，网关会动态读取。

`/health` 里 `upstreamStatus: 401` 就是缺这个 Cookie；补上后应变为 200。

## 手机端：构建 → 签名 → 安装

```sh
scripts/build-hap.sh          # 产物在 harmonyos/entry/build/.../outputs/default/
scripts/sign-hap.sh           # 需要 .signing/ 里的证书，见下
scripts/install-hap.sh        # 手机用数据线连上、开 USB 调试
```

签名材料只放本机、已在 `.gitignore` 中排除：

```text
.signing/store.p12          密钥库
.signing/certificate.cer    应用签名证书
.signing/profile.p7b        设备 Profile（bundle-name 必须是 com.mafit.dshremote）
.signing/signing.env        密码与别名（模板见 scripts/sign.env.example）
```

如果你懒得自己配证书：用 DevEco Studio 打开 `harmonyos/`，登录华为账号 → Project Structure → Signing Configs → 勾选自动签名 → 直接 Run。自动签名会为该包名创建 Profile，并带上当前手机的 UDID。

> 侧载的 Profile 里必须包含你手机的 UDID；换手机或 Profile 过期需要重新生成。

详细步骤见 [`docs/BUILD-AND-SIGN.md`](docs/BUILD-AND-SIGN.md)。

## 配对

1. 手机和笔记本都加入同一个 Tailscale 网络（户外也一样）。
2. 在笔记本浏览器打开 `http://127.0.0.1:8787/admin`，用局域网或 Tailscale 地址生成配对二维码。
3. 手机 App「更多 → 主机与连接 → 扫码连接」扫码；或手动填 `http://<笔记本Tailscale IP>:8787` + 令牌。

一个服务器条目可以存多个地址，网关会自动选最快的那个；Tailscale 地址在户外同样可用。

## 更新

```sh
scripts/build-hap.sh && scripts/sign-hap.sh
scripts/publish-hap.sh        # 复制到 hap/ 并写入 public/harmonyos-update.json
```

手机 App 设置 → 检查更新，会提示从网关下载新 HAP，下载后按系统提示覆盖安装（签名证书需一致）。


## 校验

```sh
scripts/verify.sh             # JS 语法 + 鸿蒙工程关键配置 + 空白检查
node gateway.js               # 冒烟：能起来、/health 返回 ok
```
