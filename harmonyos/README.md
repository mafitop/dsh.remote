# DSH Remote · 鸿蒙客户端

`com.mafit.dshremote` —— 原生 ArkTS/ArkUI 工程，面向 **HarmonyOS 7.0（API 26）**、仅手机。

- 版本：`0.8.3` / `8016`（与根 `package.json` 对齐）
- 兼容 SDK：`26.0.0`（API 26 起该字段必须用纯版本号，不能写 `7.0.0(26)`）
- 设备类型：`phone`
- 零第三方运行时依赖：`oh-package.json5` 的 `dependencies` 必须保持 `{}`

| 文档 | 内容 |
| --- | --- |
| [构建与签名](../docs/BUILD-AND-SIGN.md) | 工具链、构建、签名、安装 |
| [架构](../docs/ARCHITECTURE.md) | 分层、状态、数据落盘位置 |
| [目录守则](AGENTS.md) | 改本工程前必读 |

## 构建

在仓库根目录：

```sh
scripts/build-hap.sh
scripts/sign-hap.sh
scripts/install-hap.sh
```

或者用 DevEco Studio 打开本目录，配置自动签名后直接 Run。

`local.properties`、`build.cmd`、签名材料都是本机文件，不入库。`build-profile.json5` 同样不入库
（DevEco 自动签名会写入证书路径与加密密码），仓库只保留 `build-profile.example.json5`；
`scripts/build-hap.sh` 会自动从模板复制。
