# 户外使用：Tailscale 组网

局域网直连只在家里有效。出门后手机与笔记本不在同一网络，最省心的方案是 Tailscale：
两端各装一个客户端，自动建立点对点连接，不暴露公网端口。

## 1. 安装

- 笔记本（macOS）：`brew install --cask tailscale`，登录同一账号。
- 鸿蒙手机：在应用市场/官网安装 Tailscale，登录**同一个账号**。
  （Tailscale 官方没有鸿蒙原生客户端时，系统浏览器打开 tailscale.com 的网页控制台不能替代客户端。
  手机装不了 Tailscale 时，就在同一 Wi-Fi 下用局域网地址；本分支只支持局域网与 Tailscale 组网，
  不接入公网中转。）

## 2. 拿到笔记本的 Tailscale 地址

```sh
tailscale ip -4
# 100.x.y.z
```

也可以给设备起个固定名字，用 MagicDNS：

```sh
tailscale status
# 例如：macbook  100.101.102.103  macOS  ...
```

## 3. 网关监听

```sh
node gateway.js
# 默认 0.0.0.0:8787，Tailscale 地址上也能访问
```

验证（在手机浏览器打开）：

```text
http://100.x.y.z:8787/health
```

返回 ok 即可。注意：**不要**把网关直接暴露到公网；Tailscale 已经够用。

## 4. 配对

笔记本上：

```sh
open http://127.0.0.1:8787/admin
```

在配对区域选择 Tailscale 地址（或用 `DSH_REMOTE_ADVERTISE_HOSTS` 额外声明主机名），
生成二维码，手机 App 扫码。

或手动添加服务器：

```text
地址：http://100.x.y.z:8787
令牌：~/.dsh-remote/token 里的内容（或管理页显示的值）
```

## 5. 多地址与自动选优

同一条服务器记录可以存多个地址（例如家里 `192.168.1.10:8787` + Tailscale `100.x.y.z:8787`）。
App 会探测并选择可达且最快的地址，回家自动走局域网，出门自动走 Tailscale。

## 6. 常见问题

| 现象 | 处理 |
| --- | --- |
| 手机打不开 `/health` | 确认 Tailscale 两端都在线（`tailscale status`）、网关在跑、防火墙放行 8787 |
| 能打开但 App 连不上 | 令牌不匹配；重新扫码或从管理页复制令牌 |
| 户外时快时慢 | Tailscale 在打洞失败时会走 DERP 中继，仍可用但延迟高；保持两端在线即可 |
| 手机休眠后收不到通知 | 系统限制；App 设置里开「后台轮询」并允许通知 |
