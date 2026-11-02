# harmonyos/ —— 鸿蒙客户端开发守则

本目录是 `com.mafit.dshremote`（ArkTS/ArkUI，侧载分发）的 DevEco 工程。在本目录及其子目录工作时，以下规则是硬性约束。

## 1. 硬性约束

1. **零第三方运行时依赖**
   - `oh-package.json5` 的 `dependencies` 恒为 `{}`，不引入任何 ohpm 第三方 har。
   - UI 一律用系统 ArkUI 组件与自绘组件；缺的能力对照已有自绘实现补，不找库。
   - `devDependencies` 只允许模板自带的 `@ohos/hypium` 与 `@ohos/hamock`（不进 HAP）。
2. **不发明 DSH RPC**：以网关与 DSH Web 的实际行为为准；跨端契约要同步改网关。
3. **入库与隐私**：`build-profile.json5` 不入库（自动签名会把证书路径与加密密码写进去），
   仓库只保留 `build-profile.example.json5`；`local.properties`、`.signing/`、token/API key
   都不入库；令牌只存设备 `preferences`，不进日志。
4. **改完回填文档**：行为/接口变化写进 `docs/ARCHITECTURE.md`；未验证的能力不要写成已支持。
5. **一律通栏 + 直角，不要左右边距、不要圆角卡片**（用户已多次强调）
   - 适用于**所有列表页和页面内容区块**：会话 / 服务器 / 设置分组 / 侧栏 / 首页卡片 /
     服务器编辑表单 …… 内容必须横向铺满屏幕，不得对行、列表或区块用 `padding({ left, right })`、
     `margin` 留出左右边距，也不得把行/区块做成左右内嵌的圆角卡片。
   - 不要 `borderRadius` / `shadow` 卡片外壳：区块用整宽底色 + 0.5 发丝线分隔（首尾不加线）。
     弹窗、聊天气泡这类**浮层/气泡**不在此列（它们的圆角是语义的一部分）。
   - 文字缩进写在行/区块自身（通常 `padding({ left: 16 })`）；行高统一，左滑动作条与行等高、
     直角贴边。

## 2. 工程结构

- 页面：`entry/src/main/ets/pages/`（手机 `@Entry`）+ `pages/tablet/`（≥600vp 分栏）
- 组件：`components/`；数据模型：`models/`；服务：`services/`
- 共享逻辑：`common/`（I18n、导航、主题、Markdown、确认弹窗）
- 主题：颜色统一走 `models/Theme.ets` 的 `Design.*`；深色/强调色不写死 hex
- 状态：`AppState` + `AppStorage` 原语 + `@StorageLink`；`@Builder` 按值传参不建立渲染依赖，动态值用闭包
- 弹窗：用 `@CustomDialog` 自绘卡片时，`CustomDialogController` 必须带 `customStyle: true`，
  否则系统会再画一层对话框卡片，和自绘卡片叠成「重影」；投影需自己加（`Design.cardShadow`）

## 3. 构建与验证

```sh
scripts/build-hap.sh                # 仓库根
scripts/verify.sh                   # JS 语法 + 工程关键配置
```

- 产物：`entry/build/default/outputs/default/*.hap`
- 改过 `resources/base/media/` 后先删 `entry/build/default/intermediates` 再构建，避免资源 ID 错位。
- 真机行为（通知、后台、扫码、深色、弱网）不能用编译通过代替；记到 `docs/` 里要注明验证方式。
- `compatibleSdkVersion` / `targetSdkVersion` 都是 `26.0.0`；调低会需要重新核对 API 可用性。
