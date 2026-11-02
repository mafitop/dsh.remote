# 上架素材（华为应用市场 / HarmonyOS）

给 `com.mafit.dshremote` 上架华为应用市场（AppGallery Connect，下称 AGC）时要用到的图标素材，
以及它们和包内图标的对应关系。截图、文案等非图标素材见第 4 节（尚未准备）。

## 1. 一条命令生成

```sh
node scripts/icon/gen-icons.mjs --store E      # E = 当前使用的简约平面柚子方案
```

输出（`dist/` 不入库，随时可重新生成，渲染是确定性的）：

| 文件 | 尺寸 | 用途 |
| --- | --- | --- |
| `dist/store/harmonyos-app-icon-216.png` | 216×216 | **AGC 上传用**（市场列表 / 详情页图标） |
| `dist/store/harmonyos-app-icon-512.png` | 512×512 | 备用：推广位、第三方渠道 |
| `dist/store/harmonyos-app-icon-1024.png` | 1024×1024 | 备用：直角原图，可再缩放 |

不带参数运行 `node scripts/icon/gen-icons.mjs` 会同时刷新 `dist/icon/`（候选预览）与 `dist/store/`。

## 2. 图标要求与仓库现状

| 素材 | 规格 | 仓库里的文件 |
| --- | --- | --- |
| AGC 应用图标 | 216×216 px，PNG，**直角、不透明**，不含文字 | `dist/store/harmonyos-app-icon-216.png`（27 KB） |
| 分层图前景（桌面图标主体） | 1024×1024 px，透明底，只有主体，**不可自己加圆角/内边距/外投影** | `harmonyos/AppScope/resources/base/media/foreground.png` |
| 分层图背景 | 1024×1024 px，**纯白 `#FFFFFF`**，不含主体元素 | `harmonyos/AppScope/resources/base/media/background.png` |
| 启动页图标 `startWindowIcon` | 152×152 px | `harmonyos/entry/src/main/resources/base/media/startIcon.png` |
| 分层图描述 | 前/背景引用 | `harmonyos/AppScope/resources/base/media/layered_image.json` |

要点：

- **为什么 AGC 用直角图**：圆角由华为一侧按桌面/列表样式裁切，自己切反而会和系统裁切叠加；
  透明背景同理，规范要求不透明，直接给铺满画布的成品。生成器因此对上架素材**不加遮罩**。
- **背景为纯白**：分层图背景固定 `#FFFFFF`（原先的奶油橘渐变已去掉）。主体白瓤是暖白
  （`#FFFEFB` → `#F6EDD6`），靠这圈暖白 + 右下柔和投影与纯白背景分开，缩到 32 px 仍能看出果皮。
- **简约画法**：6 瓣，瓣缝全宽 32（1024 空间，实测缩到 32 px 仍可辨），白皮厚 50，果肉平涂
  （无渐变 / 内阴影 / 高光），只有一条 0.5 透明度的极淡外描边把圆形轮廓收住。
  调瓣数或粗细改 `scripts/icon/gen-icons.mjs` 里的 `CITRUS`（`SEGS` / `PITH_RAY` / `R_RIND_IN`）。
- **前/背景各一份副本**：`AppScope/resources`（桌面显示）与 `entry/src/main/resources`（模块 / Ability / 启动页）
  必须同时更新，否则桌面图标不变。用 `--install E` 会一次写全，不要手改 PNG。
- **hvigor 打包时把 1024 缩成 512**；`startIcon` 固定 152×152。
- **市场图标必须与包内图标一致**：审核会比对两者观感。`--store` 和 `--install` 用的是
  `scripts/icon/gen-icons.mjs` 里同一个候选、同一套 SDF 场景，只是尺寸与遮罩不同，所以天然不会跑偏。
  换方案时两条命令都要跑：`--install X` + `--store X`。

## 3. 已做的合规自检

对 `dist/store/*.png` 实际解码校验过：

- 三个尺寸 alpha 恒为 `255`（无半透明 / 透明像素，四角也是纯白底而非透明）；
- 四角无手工圆角，边缘像素为背景色，系统裁切后才是圆角；
- 主体（白皮外圈）直径占画布 **87.5%**，中心偏移 < 1 px：既不小气，也不会被系统圆角啃掉；
- 缩到 72 px / 32 px（市场列表的最小显示尺寸）仍能辨认出柚子瓣（瓣缝全宽 32/1024）。

复现校验（零依赖，纯 Node 解 PNG）：

```sh
node -e '
const fs=require("fs"),zlib=require("zlib");
const b=fs.readFileSync("dist/store/harmonyos-app-icon-216.png");
let o=8,w,h,idat=[];
while(o<b.length){const n=b.readUInt32BE(o),t=b.toString("latin1",o+4,o+8),d=b.subarray(o+8,o+8+n);
 if(t==="IHDR"){w=d.readUInt32BE(0);h=d.readUInt32BE(4);}else if(t==="IDAT")idat.push(d);o+=12+n;}
const raw=zlib.inflateSync(Buffer.concat(idat)),s=w*4;
let min=255;for(let y=0;y<h;y++)for(let x=0;x<w;x++)min=Math.min(min,raw[y*(s+1)+1+x*4+3]);
console.log(w+"x"+h+" 最小 alpha="+min+(w===216&&h===216&&min===255?" ✓":" ✗"));'
```

## 4. 还没准备的素材（上架必需）

图标之外，AGC 提交前还需要：

- **手机截图**：至少 3 张，建议 1080×2340 或 2340×1080（以 AGC 上传页当次提示为准）。
  `dist/ui/*.jpg` 是 1264×1848 的网页/预览器截图，长宽比不对，**不能**直接当手机截图上传，
  需要真机截图或按 AGC 尺寸重出。
- **应用介绍**（中文，约 50–8000 字）、**隐私政策 URL**（可公网访问）、内容分级、应用分类。
- **软件包**：release 签名后的 `.app`，见 [`docs/BUILD-AND-SIGN.md`](BUILD-AND-SIGN.md)。
- 包名 `com.mafit.dshremote`、应用名称、图标三者与 AGC 创建的应用信息一致。

## 5. 上架流程里与图标相关的几步

1. AGC →「我的应用」→ 新建 **HarmonyOS 应用**，包名填 `com.mafit.dshremote`。
2. 「版本信息」上传 `.app`，系统会解析出版本号 / API 等级 / 包内图标。
3. 「素材」页按需上传 `harmonyos-app-icon-216.png`；若图标是自动解析的，确认预览与这张一致。
4. 补齐截图与文案后提交审核（通常 3–7 个工作日）。

## 6. 常见驳回点

| 现象 | 处理 |
| --- | --- |
| 「应用图标不符合 UX 设计规范，尺寸 1024×1024」 | 包内 `foreground`/`background` 必须是 1024×1024，用 `--install` 重出 |
| 「图标尺寸不符」 | AGC 上传的那张必须正好 216×216（`--store` 输出的就是） |
| 市场上看到的图标和桌面/包里不一样 | 两条命令跑的不是同一个候选：`--install X` 与 `--store X` 要同 X |
| 前景图被要求「不要加圆角」 | 前景图保持透明底直角，圆角交给系统；生成器不会加遮罩 |
| 截图数量 / 尺寸不符 | 至少 3 张，尺寸随 AGC 当次提示（常见 1080×2340） |

## 7. 参考

- [素材规范（AGC）](https://developer.huawei.com/consumer/cn/doc/doccenter-submission/agc-help-app-visual-asset-spec-0000002277607976)
- [应用图标配置与开发](https://developer.huawei.com/consumer/cn/doc/doccenter-feature-dev/bpta-app-icon-configuration)
- [图标尺寸 1024×1024 规范 FAQ](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-appgallery-4)
