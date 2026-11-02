# dsh-remote-plugin

DSH Remote 的 DSH bundle 插件：提供「更多 → 手机连接」入口、浏览器管理控制台及受用户启停意图约束的内置网关。

## 安装与连接

```sh
dsh plugin --profile web add ../packages/plugin
dsh plugin --profile web list --depth 0
```

示例针对 Web profile；自定义 profile 使用实际名称。DSH Desktop 从自身插件管理入口安装，完整退出并重开。Web 安装完成后完整重启 DSH Web，Ctrl+F5，从左侧导航「更多 → 手机连接（DSH Remote）」进入浏览器配对页。首次加载会提示入口位置；选择「开始连接」或「稍后」后不再重复提示。旧宿主缺少该菜单扩展点时，入口保留在左下角。

在主机访问 `http://127.0.0.1:8787/health`，然后在插件连接向导或管理控制台显示连接二维码。手机通过「更多 → 主机与连接 → 扫码连接」配对；HAP 下载码只用于安装。手动连接填 `http://电脑局域网IP:8787` 与令牌，不能填手机 localhost。固定版本使用 `@<已发布版本>`，`@next` 与 `@latest` 的指向需另行查询。

## 当前能力与限制

- 快速状态、完整管理控制台、Doctor、自启/自愈与明确停止意图。
- Bearer token、可选独立设备密钥、短时 WS ticket。
- mux/host 下行、独立长轮询、弱网设置与历史缓存。
- 文件多根、分块续传、校验、预览/下载与图片附件。
- 当前主机插件管理与可选上下文/费用洞察。
- 手机导航：会话、文件、更多；Web 端固定使用「草原孤塔」一套配色，不提供主题切换（无皮肤包、无选择器）。
- 手机端八步新手引导；完成或整体跳过后移除首页入口，在「更多 → 偏好与维护 → 新手引导」重新学习。
- rc.9 补充冷会话恢复与错误归属修复、发送结果诊断、文件上传与分支恢复验证；具体范围见候选版说明。
- 鸿蒙 HAP 在已有构建产物时随包分发（`hap/` 目录），通知与后台需设备权限。
- Windows Desktop 控制是实验能力，需可信实例证据；管理页不再提供 Windows 登录自启入口。
- 本分支只发布鸿蒙（HarmonyOS）客户端，不包含其他移动平台。
- 已移除旧移动平台相关入口；通知测试位于高级通知选项。
- macOS 可通过插件使用同一网关源码；主发布 CI 已配置 Apple Silicon 独立网关构建、ad-hoc 签名和启动冒烟，未做 Apple 公证。

## 配置与排查

插件端口优先级：`DSH_REMOTE_GATEWAY_PORT` → `~/.dsh-remote/gateway-port` → 8787。监听地址优先级：`DSH_REMOTE_GATEWAY_HOST` → `HOST` → gateway-host 文件 → `0.0.0.0`。插件从当前 DSH 实例传入上游。

令牌默认 `~/.dsh-remote/token`；`DSH_REMOTE_AUTOSTART=0` 禁用自动管理。文件授权、工作区及 Windows 默认根存在边界，详见完整配置参考。

本机拒绝连接先检查实际 profile、完整重启与端口；上游 degraded 检查 DSH；手机不可达检查网络和防火墙；401 重新配对；升级界面旧先强刷。插件内嵌管理页使用 DSH 登录边界，独立管理页使用 Remote 主令牌。不要把 transient 网关当成固定可 restart 的 systemd 服务。

配对二维码包含凭证，不公开；跨网络优先 Tailscale。主令牌、设备令牌与 DSH 上游 Cookie 不混用。

## License

MIT
