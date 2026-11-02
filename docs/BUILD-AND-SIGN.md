# 构建与签名（HarmonyOS 7 / API 26）

本机已安装 DevEco Studio 26.0.0（自带 API 26 SDK、JBR、hvigor、hdc），以下命令都已按此环境验证。

## 1. 环境

```sh
export DEVECO_HOME=/Applications/DevEco-Studio.app   # 默认值，可不设
```

`scripts/build-hap.sh` 会自动设置：

- `JAVA_HOME=$DEVECO_HOME/Contents/jbr/Contents/Home`
- `DEVECO_SDK_HOME=$DEVECO_HOME/Contents/sdk`
- `PATH` 加入 DevEco 自带 Node
- `HVIGOR_USER_HOME` / `npm_config_cache` 指向项目内（避免写 `~/.hvigor`）

## 2. 构建

```sh
scripts/build-hap.sh            # release 模式
scripts/build-hap.sh debug      # debug 模式
```

产物：

```text
harmonyos/entry/build/default/outputs/default/entry-default-unsigned.hap
```

### 2.1 打上架用的 App Pack（.app）

华为应用市场（AGC）上传的是 **App Pack**，不是 HAP：

```sh
cd harmonyos
export DEVECO_HOME=/Applications/DevEco-Studio.app
export JAVA_HOME="$DEVECO_HOME/Contents/jbr/Contents/Home"
export DEVECO_SDK_HOME="$DEVECO_HOME/Contents/sdk"
export PATH="$JAVA_HOME/bin:$DEVECO_HOME/Contents/tools/node/bin:$PATH"
export HVIGOR_USER_HOME="$PWD/../.hvigor-home" npm_config_cache="$PWD/../.npm-cache"
"$DEVECO_HOME/Contents/tools/hvigor/bin/hvigorw" assembleApp --mode project \
  -p product=default -p buildMode=release --no-daemon
```

产物（`harmonyos/build/outputs/default/`）：

```text
harmonyos-default-unsigned.app    # 用发布证书再签这个
harmonyos-default-signed.app      # 若工程里配置了 signingConfig 会自动签（本机是 debug Profile）
```

**签名类型很关键**：DevEco「自动管理签名」生成的是 `"type":"debug"` 的 Profile（带设备 UDID），
AGC 会拒收；上架必须用 AGC 的**发布证书 + 发布 Profile**。签名后可用下面命令核对：

```sh
java -jar "$DEVECO_SDK_HOME/default/openharmony/toolchains/lib/hap-sign-tool.jar" \
  verify-app -inFile dist/xxx.app -outCertChain /tmp/v.cer -outProfile /tmp/v.p7b
strings /tmp/v.p7b | grep -o '"type":"[a-z]*"'   # 发布包应为 "release"
```

`scripts/sign-hap.sh` 也能签 `.app`（按扩展名决定产物名）：

```sh
scripts/sign-hap.sh harmonyos/build/outputs/default/harmonyos-default-unsigned.app
# → dist/dsh-remote-harmonyos-<version>.app
```

注意：

- `harmonyos/build-profile.json5` **不入库**：DevEco 自动签名会把证书路径和加密后的密码写进去。
  仓库里只有 `build-profile.example.json5`；`build-hap.sh` 发现本机缺该文件时会自动从模板复制。
  新克隆后如果先打开 DevEco，请先手动复制一次。
- API 26 起 `compatibleSdkVersion` 必须写成 `"26.0.0"`（带 `(26)` 会报 `api version parameter is illegal`）。
- 改过 `resources/base/media/` 里的图标后，先删**整个** `harmonyos/entry/build` 再构建，避免用到旧的合成图。
- 应用图标有两处副本，必须同时改，否则桌面图标不变：
  - `harmonyos/AppScope/resources/base/media/{background,foreground}.png` ← **桌面显示的就是这一份**
  - `harmonyos/entry/src/main/resources/base/media/{background,foreground,startIcon}.png` ← 模块/Ability 图标 + 启动页图标

  两个分层图都是 1024×1024（hvigor 打包时缩成 512），`startIcon` 为 152×152。
  背景层是纯白 `#FFFFFF`（`gen-icons.mjs` 里的 `whiteBg`）；改配色只改生成器，别手改 PNG。
- 改图标请用生成器，别手改 PNG：`node scripts/icon/gen-icons.mjs --install E`
  （同形态两套质感：`E` 简约平面版＝当前使用（6 瓣、加粗白瓣缝、平涂果肉、纯白底）；`D` 串珠版。不带参数则把预览与联系表输出到 `dist/icon/`，
  同时刷新华为应用市场的上架图标 `dist/store/`）。
- 上架华为应用市场要的 216×216 直角图标用 `node scripts/icon/gen-icons.mjs --store E`，
  规格、对应关系与审核驳回点见 [`docs/STORE-ASSETS.md`](STORE-ASSETS.md)。换方案时 `--install X` 与 `--store X` 要同 X。
- 未签名 HAP 装不上真机。

## 3. 签名

### 3.1 方式 A：DevEco 自动签名（最省事）

1. 用 DevEco Studio 打开 `harmonyos/`。
2. 登录华为账号（右上角 HUAWEI ID 头像；未登录会提示 `Failed to auto generate signing, please sign in first.`）。
3. 菜单 `File → Project Structure...`（快捷键 ⌘;）→ 顶部页签 **`签名配置`**（Signing Configs）
   → 选择 **`自动管理签名`**（Automatically manage signing）→ `OK`。
   > 这个对话框是内嵌网页，第一次打开可能要等一两秒；旧的「自动生成签名」现在只是页签里的一个链接，
   > 名称已改成「自动管理签名」，按旧名字找会找不到。
4. 手机连 USB、开「开发者模式 + USB 调试」，直接 Run。

自动签名会：

- 在 AGC 里为该包名创建应用；
- 生成 `~/.ohos/config/default_*.p12/.cer/.p7b`；
- 把当前手机的 UDID 加进 Profile。

> 换手机、Profile 过期（通常 1 年）或换包名，都要重新走一次。

**常见坑**：DevEco 生成好 `signingConfigs` 后，**不一定**会在 product 里补上引用。
如果构建日志出现：

```text
WARN: No signingConfig found for product default
```

说明签名配置存在但没被使用，产物仍是 `entry-default-unsigned.hap`，安装时会报
`error: no signature file.`（错误码 9568320）。手动在 `harmonyos/build-profile.json5` 里补一行：

```json5
"products": [
  {
    "name": "default",
    "signingConfig": "default",   // 缺这行就不会签名
    ...
  }
]
```

### 3.2 方式 B：现有证书手工签名

把文件放进 `.signing/`（已 gitignore）：

```text
.signing/store.p12
.signing/certificate.cer
.signing/profile.p7b
.signing/signing.env       # 从 scripts/sign.env.example 复制
```

`signing.env`：

```sh
STORE_PASSWORD='...'
KEY_PASSWORD='...'
KEY_ALIAS='debugKey'
```

然后：

```sh
scripts/sign-hap.sh
# 产物：dist/dsh-remote-harmonyos-0.8.3.hap
```

脚本会先检查 Profile 的 `bundle-name` 是否等于 `harmonyos/AppScope/app.json5` 里的包名，
不一致会直接报错（这是最常见的“签名成功但装不上”原因）。

### 3.3 Profile 从哪里来

- **调试用**：DevEco 自动签名生成，带手机 UDID，可侧载到自己手机。
- **发布用**：AGC → 证书、Profile 管理 → 新建 Profile，选择包名与设备，下载 `.p7b`。

包名当前是 `com.mafit.dshremote`，改包名需要同步改：

```text
harmonyos/AppScope/app.json5                  bundleName
harmonyos/entry/src/main/ets/common/Constants.ets   BUNDLE_NAME
```

## 4. 安装

```sh
scripts/install-hap.sh                    # 自动取 dist/ 下最新的 HAP
scripts/install-hap.sh path/to/xxx.hap
```

等价手工命令：

```sh
hdc list targets
hdc install -r dist/dsh-remote-harmonyos-0.8.3.hap
hdc shell aa start -a EntryAbility -b com.mafit.dshremote
```

被系统拦截时，在手机上允许「安装外部来源应用 / 调试应用」。首次安装若提示签名不一致，
先卸载旧版本（同包名不同证书不能覆盖安装）。

## 5. 发布到网关（手机内更新）

```sh
scripts/publish-hap.sh
```

会把 HAP 复制到 `hap/dsh-remote-harmonyos.hap`，并写入：

- `public/harmonyos-update.json`（App 检查更新读取）
- `public/update.json`（Web 控制台兼容）

手机在设置里点「检查更新」，下载地址是 `<网关地址>/dsh-remote-harmonyos.hap`。
