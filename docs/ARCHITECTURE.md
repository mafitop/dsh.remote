# 架构说明

## 一条消息的链路

```text
鸿蒙手机 App
   │  HTTP /api/*  +  WebSocket /ws（Bearer Token）
   ▼
笔记本 gateway.js  (0.0.0.0:8787)
   │  鉴权、限流、设备密钥、文件系统边界、静态控制台
   ▼
DSH Web (127.0.0.1:3080)
```

网关不解析 DSH 的 RPC 语义，只做鉴权与透明代理；除静态文件、文件传输、公告、反馈、统计、
配对等少数端点由网关自己处理外，其余 `/api/*` 与 WebSocket 原样转发。

## 鸿蒙客户端分层

```text
entry/src/main/ets/
  pages/            页面：Index(手机) / tablet(≥600vp 分栏) / Chat / Settings /
                    ServerSettingsPage(服务器列表) / ServerEditPage(新增·编辑服务器) ...
  components/       自绘组件：MarkdownView / HandoffCard / SkeletonList ...
  services/         GatewayApi(HTTP) / RealtimeService(WS+轮询) / AppState(全局状态)
                    StorageService(preferences) / FsUploadService / ScanService ...
  models/           纯数据：Theme / ServerInfo / SessionView / ChatMessage ...
  common/           I18n / AppNav / Constants / Markdown / UiFeedback ...
```

- 零第三方运行时依赖：只用系统 ArkUI 与系统 Kit（网络、通知、扫码、语音、实况窗等）。
- 状态：`AppState` 单例 + `AppStorage` 原语 + `@StorageLink`。
- 主题：颜色统一走 `models/Theme.ets` 的 `Design.*` 令牌，深色/浅色不写死 hex。
- 连接：优先 WebSocket 实时；失败降级为长轮询，两者都有退避与恢复。
- 服务器管理（0.10.10 起）：列表页只做「展示 / 显式切换 / 左滑编辑删除 / 右下角扫码 FAB」，
  手工录入独立成 `ServerEditPage`（右上角「+」进入）；目标 id 经 `AppStorage('serverEditId')`
  传递，手机 router 与平板 NavPathStack 复用同一路径（栈 param 在 builder 构建时机读不到）。
  交互映射：列表行整体不可点（防误触）；所有变更都在左滑动作条里——「设为当前 / 编辑 / 删除」
  （非当前项才出现「设为当前」）。动作条是与卡片同高的连体一条（无图标），滑开时卡片右侧
  两个圆角归零（`ListItem.swipeAction.onOffsetChange` 跟踪），与动作条拼成一条矩形。
  右侧只显示「当前」状态标签，不做成可点控件。列表按全局规则通栏（行左右无边距、直角贴边、
  行间发丝线），与「会话」列表一致。
  动作条宽度随「是否当前项」变化（非当前 3 个动作、当前 2 个），点「设为当前」后动作集变窄，
  行内容会停在旧偏移上露出空白——所以切换成功后调用 `ListScroller.closeAllSwipeActions()`
  把滑动动作收起来（0.10.16 起）。
- 展开态点会话 = 切换右栏主视图（`replacePathByName`，路由名带 `#sessionId` 以强制新建
  ChatView；系统交叉淡入、无抽屉 push、无返回按钮），不再用 `clear+push`。
- 展开态（≥600vp 分栏）不再有底部 Tab 栏：侧栏品牌行 = 左上角齿轮（设置，取代原 `◆`）
  + `Remote` 文字（点了回主页）+ 右侧两个图标按钮（文件夹＝新建工作区、气泡＝新建会话）。
- 新建工作区（0.10.10 起）：手机上不再手打目录，改为浏览「网关所在电脑」的目录——
  走 `GET /fs/list`（网关只暴露 `FS_ROOTS` 之下），进入目录后点「在此新建」；
  以 `.` 开头的目录默认隐藏（可切换显示），并保留「手动输入」兜底。
- 通栏直角规则（0.10.10 起）同样适用于页面内容区块：首页卡片、设置分组、服务器编辑表单、
  会话/侧栏分组容器都去掉了左右留白与 `borderRadius`/`shadow`；只有弹窗与聊天气泡保留圆角。
  跨端接续条（`HandoffCard`，会话列表/侧栏顶部「接着看」）同样去掉圆角与 1.5vp 描边，
  改成整宽浅主色底 + 底部发丝线。
- 会话详情页（`ChatView`，0.10.12 起）按 Web 端对话栏对齐：**左右各 16 是唯一内容栏**
  （`List.padding`），气泡、工具行、压缩摘要/系统提示、goal/todos/统计区都落在同一条栏里，
  不再出现「白条贴到屏幕边、气泡却留一段空白」的参差。工具行/摘要条/投影区是透明扁平行 +
  0.5 发丝线（不再整宽白底）；聊天气泡保留圆角与白底，`maxWidth` 放到整栏宽，长消息的右边界
  与工具行一致（短消息仍按内容自适应）。气泡阴影换成 0.5 发丝描边。
  顶栏改成「标题行（末尾铅笔图标进重命名）+ 状态行」两行结构，去掉标题里拼接的 `✎`；右侧
  「停止/模型/待处理」统一 28vp 高胶囊（窄屏模型 chip 只显示「模型」二字，避免挤掉标题）。
  输入栏与消息区之间加整宽发丝线，输入框改浅底胶囊、发送按钮收到 42vp。
  「本轮统计」不再占消息区顶部，改为消息列表下方的**独立一行**（页面底色 + 顶部发丝线，底部
  分隔线复用输入栏的顶部发丝线），不混进输入栏的白色面；四项全展示（轮次/步数、LLM 耗时、
  输出/缓存、上下文），窄屏靠 Flex 换行；goal/todos 仍留在顶部。
  工具行单行常显、正文默认折叠，点击整行展开；思考块改为气泡内左侧 2vp 主色条 + 扁平排版，
  不再套第二层灰底圆角卡（注意：气泡是 `maxWidth` 自适应宽，子项用 `width('100%')` 会按约束
  上限测量、长文本溢出气泡外，思考块因此不设 100% 宽）。
- Markdown 排版按 Web 端令牌校准（`components/MarkdownView.ets`）：Web 正文 14px/24px（行高
  1.72）、段落间距 16px、列表缩进 18px/行距 6px、标题 21/19/18px、代码 12px/19px。客户端正文
  15vp 时取 **行高 26**、块间距 12、列表缩进 18（marker 12 + 间距 6）、标题 +7/+5/+4、代码块
  内边距 12；行高是「手机版比网页版挤」的主因——ArkUI 默认行高只有 1.3 左右。思考过程（13/21）
  与工具展开正文（11/18）同步放宽行高。
  - 行内代码：网页版是 `0.875em` + 灰底 + 0.5 描边 + 6px 圆角。ArkUI 的 `Span` 没有 padding/
    描边，只能用 `textBackgroundStyle` 画背景 + 圆角（`Design.INLINE_CODE_BG`）；胶囊会比网页版
    紧一点，但复制不失真（不往代码里塞空格）。用户气泡（彩底）用半透明白底。
  - 两级对齐：**内容栏 16**（`List.padding`）负责气泡盒子与发丝线；**文字栏 30**（16 气泡内边距
    或 16+14 行内边距）负责文字和「展开」。工具行、摘要条、投影卡的内容都内缩 14，所以工具行文字
    与气泡正文同一条左线，各处「展开」同一条右线，胶囊/发丝线的边界又都在 16。曾用负 margin 把
    思考块抵到气泡边去对齐「展开」，结果「展开」贴住气泡圆角，已回退。
  - 次级/辅助灰：会话页改用网页版色板 `Design.TEXT_SECONDARY`（#61666B / #CFD3D6）与
    `Design.TEXT_CAPTION`（#81858C / #ADB2B8），其它页面继续用 `TEXT_SUB` / `TEXT_HINT`
    （用户要求只调会话页）。
- 悬浮胶囊与内容避让（0.10.11 起）：折叠态（<600vp）的「主页/会话/设置」是浮在页面上的
  胶囊叠层。**胶囊不占列表高度**——`Tabs` 铺满全屏，列表内容可以一直滚到屏幕底边（用户
  明确要求：内容要能触摸到屏幕底部）；避让只体现在**滚动内容末端的留白**上，滚到底时最后
  一行停在胶囊上方，不会压在胶囊下面。
  - `Design.contentBottomInset()`：手机形态 = `navReserve()`（整段胶囊预留；宽屏无胶囊时
    为 `safeBottom + 12`，让开系统手势条）。
  - 用法：`Scroll` 页（首页/设置）把它加在内容 Column 的 `padding.bottom`；`List` 页（会话）
    用 `contentEndOffset(...)`——`List.padding` 只改 List 自身尺寸，不是末端留白。
  - 胶囊几何只此一份：`Design.CAPSULE_H` + `Design.capsuleBottomOf`；`navReserve()` =
    max(96, 胶囊高 + 底距 + 16) 由它们算出，安全区一变（折叠态外屏、三键导航）就跟着长。
    底部安全区取手势指示条与系统导航栏的较大值，见 `EntryAbility`。
  - 中间滚动过程中行会从胶囊后面滑过——这是悬浮导航的预期形态；此前曾把内容区上收到胶囊
    上方（`Tabs.padding`）来彻底避免重叠，但那会吃掉列表高度、底部留一大块空白，已回退。

## 实时事件的兜底对账（0.10.13 起）

DSH 的实时链路是「订阅 + 增量事件」，**没有补发机制**：切后台、WebSocket 重连、
轮询与 WS 切换期间漏掉的 `assistant/message` 不会再送达。表现是会话页一直停在
「思考中」，最后那段正文永远不出现，必须退出再点一次会话（重拉历史）才恢复。

`ChatView` 现在在三个时机主动对账，等价于自动帮用户重进一次会话：

1. **回合结束**（`agent/status` 且 `running=false`）时，若本轮没收到过最终
   `assistant/message`（`sawAssistantMessage`），延迟 700ms 重拉最近 60 条历史；
2. **实时模式从断开切回 `ws` / `poll`**（`AppStorage('connMode')` 跳变）；
3. **回到前台**（`EntryAbility.onForeground` 递增 `AppStorage('foregroundGeneration')`）。

对账走 `loadHistory(true)`：整表替换但不强制滚到底，重复触发有 300–700ms 防抖，
已解码的图片会跳过，不会重复解码堆积。另外 `session/reasoning` 基线在
`running=false` 时直接丢弃——迟到的基线曾把已经结束的一轮重新点亮成「思考中」，
盖在已到达的正文上面。

## 数据存在哪里

手机端（`preferences`，库名 `dsh_remote`）：

| key | 内容 |
| --- | --- |
| `servers_v2` | 服务器列表（地址 / 令牌 / 分组 / `host`；`host` 由 `/health.host` 缓存，`note` 为旧字段保留兼容） |
| `active_server_id` | 当前服务器 |
| `theme` / `dark_mode` | 外观 |
| `notify_enabled` / `background_poll` | 通知与后台轮询 |
| `client_id` | 网关侧设备识别 id |

笔记本端（默认 `~/.dsh-remote/`）：

| 文件 | 内容 |
| --- | --- |
| `token` | 访问令牌（`TOKEN_FILE` 可覆盖） |
| `device-keys.json` | 独立设备密钥（`DSH_REMOTE_DEVICE_KEYS`） |
| `workbench.json` | 工作台绑定 |
| `handoff.json` | 跨设备接续 |
| `crashes.jsonl` | 崩溃日志（`DSH_REMOTE_CRASH_LOG_FILE`） |
| `stats/` | 调用统计 |

令牌与设备密钥都不会进仓库，也不应出现在日志里。

## 关键端点

| 端点 | 说明 |
| --- | --- |
| `session.delete`（`POST /api/session.delete`） | 上游 DSH 没有该 RPC，由网关自己实现：按存储布局把 `<DSH_HOME>/sessions/<ws>/session-<id>` 移入 `~/.dsh-remote/trash/`；运行中的会话拒绝删除 |
| `GET /health` | 存活检查（无需鉴权）；含 `host`（`os.hostname()`）与 `platform`，App 用来在 IP 旁标出主机名 |
| `GET /announcements.json` | 公告；本分支默认只读本地 `public/announcements.json` |
| `POST /feedback` | 反馈；本分支默认关闭（503），需配置 `DSH_REMOTE_FEEDBACK_URL` |
| `GET /harmonyos-update.json` | 鸿蒙版更新信息（`scripts/publish-hap.sh` 写入） |
| `GET /dsh-remote-harmonyos.hap` | HAP 下载（从 `hap/` 目录） |
| `GET /admin` | 管理控制台：配对二维码、设备、令牌 |
| `/api/*` `/ws` | 透明转发到 DSH |

## 统计回填：v3 会话文件是多帧 zstd（0.10.13 起）

DSH v3 把会话写成 `session.v3.jsonl.zstd`，**每次追加一个独立的 zstd 帧**（多帧拼接）。
Node 的 `zlib.createZstdDecompress` / `zstdDecompressSync` 只解第一帧，第二帧直接报
`ZSTD_error_prefix_unknown`；而 readline 会把流错误吞掉、安静结束，于是
`gateway-stats.cjs` 的回填扫描每个文件只读到第一行（会话头，没有 `seq`），
日志照样打「0 个新事件」、不报错——表现就是 App 上「近 7 日 Token 用量」永远是 0。

处理：

- 解压优先用系统 `zstd -dc`（支持多帧）；没有 CLI 时退回 zlib，但先用文件里的魔数
  判断是否多帧，多帧文件显式抛 `zstd-multiframe-needs-cli`，不再静默统计成 0；
- 解析时跳过半截 JSON 行（会话正在写入的末行），游标停在上一条完整事件，
  活动会话不会整文件判失败；
- App 侧 Token 数字补了 `B` 单位（7 天累计含 `cacheRead`，常见到十亿量级）。

价格表 `PRICES`（元 / 百万 tokens，高峰价，空闲时段半价）按 DeepSeek 官方
《模型 & 价格》2026-11-02 版更新：`deepseek-flash` 命中 0.04 / 未命中 2 / 输出 8，
`deepseek-v4-pro` 命中 0.30 / 未命中 9 / 输出 27；旧名 `deepseek-v4-flash`、
`deepseek-v4-flash-vision-exp` 已下线，请求由 V4.1-Flash 承接并按 Flash 价格计费，
表里也按同一价挂上。模型 id 查找做了小写归一 + 别名（`deepseek-v41-flash` 等）。
费用是**按天文件里的 token 桶实时重算**的（`pricedBucket`），改价后历史日期会自动按新价
重新计算，不需要迁移。已知偏差：没有中国法定节假日日历，节假日会被当成工作日高峰计价，
费用会略微偏高。

## 兼容性：DSH 0.1.x 没有 `session/projections`

上游网关在加载「当前没有实时跟随」的会话历史时，会先去 DSH 的
`session/projections` 取 durable 游标。DSH 0.1.x（如 `0.1.5-rc.2`）没有这个路由，
请求返回 404，于是 `session.history` 报：

```text
upstream-incompatible / DSH history cursor unavailable
```

本分支在 `gateway.js` 的 `session.history` 分支加了兜底：当
`session/projections` 返回 404/405/501（即 `modernResponseNeedsLegacyFallback`）时，
改用 `session/list` 里已经带上的 `projections.asOfSeq` 作为 `session/page` 的
`throughSeq`。该值只用作一次性翻页边界，不会被当作实时流游标。

DSH 升级到带 `session/projections` 的版本后，这个兜底不会触发，行为与上游一致。

## 安全边界

- 默认监听 `0.0.0.0:8787`，但没有 Token 一律 401；推荐只在 Tailscale 网内使用。
- 文件传输限定在 `~` 与 `DSH_REMOTE_FS_ROOT` 声明的根内，路径穿越会被拒绝。
- 配对二维码包含令牌，别截图外发。
- 侧载 App 的证书/Profile 只留在本机 `.signing/`，不要提交。
