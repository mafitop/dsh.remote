import { AppNav } from '../common/AppNav'
import { AppState } from '../services/AppState'
import { Theme, Design } from '../models/Theme'
import { I18n } from '../common/I18n'
import { StatsDay } from '../models/StatsDay'

/**
 * 主页：连接状态、用量概览、当前服务器。
 *
 * 版式（0.10.19 起，遵循「通栏直角」规则）：
 * - 顶部标题 + 36vp 刷新按钮（与「会话」页右上角图标按钮同款）
 * - 分组：连接（无标签）/ 概览 / 当前服务器
 *   组标签 13vp 次级色；组内整宽白底 + 0.5 发丝线，组间靠标签留白呼吸
 * - 连接通道一行四列（手机/宽屏一致），状态点 + 标签 + 状态值同一栏
 * - 只有真正可点的行才给按压反馈：浅底高亮（通栏行用缩放会露出页面底色）
 * - 不在主页重复显示会话列表（宽屏侧栏已有；折叠态去「会话」Tab 看），保持状态页职责
 *
 * 数据全部来自 AppState（health / stats），没有新增 RPC。
 */
@Component
export struct HomePage {
  @StorageLink('appState') appState: AppState = AppState.instance
  /** 深浅判定（AppState 写入）；变更驱动整页刷新 */
  @StorageLink('uiDark') uiDark: boolean = false
  /** 当前主题 id 原语（AppState 写入）；主题切换驱动整页刷新 */
  @StorageLink('uiTheme') uiTheme: string = 'deep-space'
  /** 刷新图标旋转角（每次点击 +360，motionCurve 补间） */
  @State spin: number = 0
  /** 按压中的交互行 key（浅底高亮） */
  @State pressedRow: string = ''

  aboutToAppear(): void {
    this.refreshAll()
  }

  private refreshAll(): void {
    this.appState.refreshHealth()
    this.appState.refreshStats()
  }

  private pageBg(): string {
    return Theme.bgOf(Theme.get(this.uiTheme), this.uiDark)
  }

  private accent(): string {
    return Theme.accentOf(Theme.get(this.uiTheme), this.uiDark)
  }

  private pressRow(key: string): void {
    this.pressedRow = key
  }

  private releaseRow(): void {
    this.pressedRow = ''
  }

  private rowBg(key: string): string {
    return this.pressedRow === key ? Design.FILL_LIGHT(this.uiDark) : Design.SURFACE(this.uiDark)
  }

  build() {
    Column() {
      Row() {
        Row() {
          Text(I18n.t('主页', 'Home'))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(Design.TEXT_MAIN(this.uiDark))
          Blank()
          // 刷新：36vp 圆形图标按钮，与会话页右上角按钮同一规格
          Row() {
            Image($r('app.media.ic_refresh'))
              .width(20)
              .height(20)
              .fillColor(this.accent())
              .rotate({ angle: this.spin })
              .animation({ curve: Design.motionCurve })
          }
          .width(36)
          .height(36)
          .justifyContent(FlexAlign.Center)
          // 页面底是浅灰：#F4F5F7 的浅底按钮几乎看不见，改用白面（深色下是 #1C1C1E）
          .backgroundColor(Design.SURFACE(this.uiDark))
          .border({ width: 0.5, color: Design.borderHair(this.uiDark) })
          .borderRadius(Design.RADIUS_PILL)
          .accessibilityText(I18n.t('刷新', 'Refresh'))
          .onClick(() => {
            this.spin += 360
            this.refreshAll()
          })
        }
        .width('100%')
        .constraintSize({ maxWidth: 720 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: Design.PAD_PAGE, right: Design.PAD_PAGE, top: 16 + Design.safeTop(), bottom: 10 })

      Scroll() {
        Row() {
          Column() {
            this.connectionSection()
            if (this.appState.server !== null) {
              this.sectionLabel(I18n.t('概览', 'Overview'))
              this.overviewSection()
            }
            this.sectionLabel(I18n.t('当前服务器', 'Current server'))
            this.serverSection()
          }
          .width('100%')
          // 通栏：左右不留边距，文字缩进写在行/区块自身（16）
          .padding({ top: 2, bottom: Design.contentBottomInset() })
          .constraintSize({ maxWidth: 720 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Top)
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBg())
  }

  /** 组标签：小号次级文字，与块内文字左缘对齐 */
  @Builder
  sectionLabel(text: string) {
    Text(text)
      .fontSize(13)
      .fontColor(Design.TEXT_SUB(this.uiDark))
      .padding({ left: Design.PAD_PAGE, right: Design.PAD_PAGE })
      .margin({ top: 14, bottom: 6 })
      .width('100%')
  }

  /** 组内分隔线：通栏白底 + 0.5 发丝线，左缩进与文字对齐 */
  @Builder
  hairline(indent: number, vMargin: number) {
    Divider()
      // FILL_LIGHT 在白底上几乎不可见；发丝线统一用 8% 黑/10% 白，撑起区块结构
      .color(Design.borderHair(this.uiDark))
      .strokeWidth(0.5)
      .margin({ left: indent, top: vMargin, bottom: vMargin })
  }

  // ------------------------------------------------------------------
  // 连接状态
  // ------------------------------------------------------------------

  private modeColor(): string {
    const m = this.appState.mode
    if (m === 'ws') {
      return Design.SUCCESS
    }
    if (m === 'poll') {
      return Design.WARNING
    }
    if (m === 'connecting') {
      return this.accent()
    }
    if (m === 'error') {
      return Design.DANGER
    }
    return Design.TEXT_HINT(this.uiDark)
  }

  private modeLabel(): string {
    const m = this.appState.mode
    if (m === 'ws') {
      return I18n.t('实时已连接', 'Realtime connected')
    }
    if (m === 'poll') {
      return I18n.t('轮询模式', 'Polling mode')
    }
    if (m === 'connecting') {
      return I18n.t('连接中', 'Connecting')
    }
    if (m === 'error') {
      return I18n.t('连接错误', 'Connection error')
    }
    return I18n.t('未连接', 'Not connected')
  }

  @Builder
  connectionSection() {
    Column() {
      Row({ space: 8 }) {
        Circle({ width: 10, height: 10 }).fill(this.modeColor())
        Text(this.modeLabel())
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(Design.TEXT_MAIN(this.uiDark))
        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.appState.health !== null) {
        this.hairline(Design.PAD_CARD, 12)
        Row() {
          this.healthCell(I18n.t('网关', 'Gateway'), this.appState.health?.ok ? I18n.t('正常', 'OK') : I18n.t('异常', 'Error'),
            this.appState.health?.ok ? Design.SUCCESS : Design.DANGER)
          this.healthCell(I18n.t('上游', 'Upstream'), this.appState.health?.upstreamOk ? I18n.t('正常', 'OK') : I18n.t('降级', 'Degraded'),
            this.appState.health?.upstreamOk ? Design.SUCCESS : Design.WARNING)
          this.healthCell('mux', this.appState.health?.eventsMux ? I18n.t('在线', 'Up') : I18n.t('离线', 'Down'),
            this.appState.health?.eventsMux ? Design.SUCCESS : Design.TEXT_HINT(this.uiDark))
          this.healthCell('host', this.appState.health?.eventsHost ? I18n.t('在线', 'Up') : I18n.t('离线', 'Down'),
            this.appState.health?.eventsHost ? Design.SUCCESS : Design.TEXT_HINT(this.uiDark))
        }
        .width('100%')
      } else if (this.appState.server === null) {
        Text(I18n.t('尚未配置服务器；在下方「当前服务器」中扫码配对后开始使用',
          'No server configured. Pair one under Current server below.'))
          .fontSize(12)
          .lineHeight(18)
          .fontColor(Design.TEXT_HINT(this.uiDark))
          .width('100%')
          .margin({ top: 6 })
      } else {
        Row({ space: 12 }) {
          Text(this.appState.lastError.length > 0 ? this.appState.lastError : I18n.t('正在获取网关状态…', 'Fetching gateway status…'))
            .fontSize(12)
            .lineHeight(18)
            .fontColor(this.appState.lastError.length > 0 ? Design.DANGER : Design.TEXT_HINT(this.uiDark))
            .layoutWeight(1)
          Text(I18n.t('重试', 'Retry'))
            .fontSize(13)
            .fontColor(this.accent())
            .onClick(() => {
              this.refreshAll()
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding(Design.PAD_CARD)
    .backgroundColor(Design.SURFACE(this.uiDark))
    .alignItems(HorizontalAlign.Start)
  }

  /** 通道小格：状态点 + 11vp 标签 + 14vp 状态值，等宽铺满一行 */
  @Builder
  healthCell(label: string, value: string, color: string) {
    Row({ space: 7 }) {
      Circle({ width: 6, height: 6 }).fill(color)
      Column({ space: 1 }) {
        Text(label)
          .fontSize(11)
          .fontColor(Design.TEXT_HINT(this.uiDark))
        Text(value)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(color)
      }
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .alignItems(VerticalAlign.Center)
  }

  // ------------------------------------------------------------------
  // 概览：Token 用量 + 待处理
  // ------------------------------------------------------------------

  @Builder
  overviewSection() {
    Column() {
      Column({ space: 6 }) {
        Row() {
          Text(I18n.t('近 7 日 Token 用量', 'Token usage, last 7 days'))
            .fontSize(13)
            .fontColor(Design.TEXT_SUB(this.uiDark))
          Blank()
          if (this.costText().length > 0) {
            Text(this.costText())
              .fontSize(12)
              .fontColor(Design.TEXT_HINT(this.uiDark))
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row() {
          Text() {
            Span(this.tokenValue())
              .fontSize(34)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.accent())
            Span(this.tokenUnit())
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.accent())
          }
          Blank()
          if (this.appState.statsDays.length > 0) {
            this.sparkline()
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)

        Text(this.tokenBreakdown())
          .fontSize(12)
          .fontColor(Design.TEXT_HINT(this.uiDark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')
      .padding({ left: Design.PAD_CARD, right: Design.PAD_CARD, top: 14, bottom: 14 })
      .alignItems(HorizontalAlign.Start)

      this.hairline(Design.PAD_CARD, 0)
      this.pendingRow()
    }
    .width('100%')
    .backgroundColor(Design.SURFACE(this.uiDark))
  }

  /** 7 日迷你柱状图：柱高按当日 Tokens 归一化，最新一天用实色 */
  @Builder
  sparkline() {
    Row({ space: 4 }) {
      ForEach(this.appState.statsDays, (d: StatsDay, index: number) => {
        Row()
          .width(6)
          .height(this.sparkHeight(d))
          .borderRadius(3)
          .backgroundColor(index === this.appState.statsDays.length - 1
            ? this.accent()
            : Design.withAlpha(this.accent(), '66'))
      }, (d: StatsDay) => d.date)
    }
    .height(32)
    .alignItems(VerticalAlign.Bottom)
  }

  private sparkMax(): number {
    let max: number = 0
    for (const d of this.appState.statsDays) {
      const t = d.tokens()
      if (t > max) {
        max = t
      }
    }
    return max
  }

  private sparkHeight(d: StatsDay): number {
    const max = this.sparkMax()
    if (max <= 0) {
      return 3
    }
    const h = Math.round(d.tokens() / max * 30)
    return h < 3 ? 3 : h
  }

  private tokenValue(): string {
    const n = this.appState.totalTokens7d
    if (this.appState.statsDays.length === 0 &&
      (this.appState.statsLoading || this.appState.statsText.length > 0)) {
      return '—'
    }
    if (n >= 1000000000) {
      return (n / 1000000000).toFixed(2)
    }
    if (n >= 1000000) {
      return (n / 1000000).toFixed(1)
    }
    if (n >= 1000) {
      return (n / 1000).toFixed(1)
    }
    return Math.round(n).toString()
  }

  private tokenUnit(): string {
    const n = this.appState.totalTokens7d
    if (this.appState.statsDays.length === 0 &&
      (this.appState.statsLoading || this.appState.statsText.length > 0)) {
      return ''
    }
    if (n >= 1000000000) {
      return 'B'
    }
    if (n >= 1000000) {
      return 'M'
    }
    if (n >= 1000) {
      return 'K'
    }
    return ''
  }

  private compact(n: number): string {
    if (n >= 1000000000) {
      return (n / 1000000000).toFixed(2) + 'B'
    }
    if (n >= 1000000) {
      return (n / 1000000).toFixed(1) + 'M'
    }
    if (n >= 1000) {
      return (n / 1000).toFixed(1) + 'K'
    }
    return Math.round(n).toString()
  }

  /** 费用估算：网关按天实时重算的 peak + off 费用（元） */
  private costText(): string {
    let cost: number = 0
    for (const d of this.appState.statsDays) {
      cost += d.totalCost()
    }
    if (cost <= 0) {
      return ''
    }
    if (cost < 0.01) {
      return I18n.t('≈ ¥ < 0.01', '≈ ¥ < 0.01')
    }
    return '≈ ¥ ' + cost.toFixed(cost >= 100 ? 1 : 2)
  }

  /** 明细：输入 / 输出 / 缓存（cacheRead + cacheWrite） */
  private tokenBreakdown(): string {
    if (this.appState.statsDays.length === 0 && this.appState.statsLoading) {
      return I18n.t('统计加载中…', 'Loading stats…')
    }
    if (this.appState.statsText.length > 0 && this.appState.statsDays.length === 0) {
      return this.appState.statsText
    }
    if (this.appState.totalTokens7d <= 0) {
      return I18n.t('近 7 日暂无用量', 'No usage in the last 7 days')
    }
    let input: number = 0
    let cache: number = 0
    let output: number = 0
    for (const d of this.appState.statsDays) {
      input += d.input
      cache += d.cacheRead + d.cacheWrite
      output += d.output
    }
    return I18n.t('输入 ', 'In ') + this.compact(input) +
      I18n.t(' · 输出 ', ' · Out ') + this.compact(output) +
      I18n.t(' · 缓存 ', ' · Cache ') + this.compact(cache)
  }

  private pendingTotal(): number {
    return this.appState.pendingApprovals.length + this.appState.pendingQuestions.length
  }

  @Builder
  pendingRow() {
    Row({ space: 8 }) {
      Circle({ width: 8, height: 8 }).fill(this.pendingTotal() > 0 ? Design.WARNING : Design.SUCCESS)
      Text(I18n.t('待处理事项', 'Pending items'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Design.TEXT_MAIN(this.uiDark))
      Blank()
      if (this.pendingTotal() > 0) {
        Text(I18n.t('审批 ', 'Approvals ') + this.appState.pendingApprovals.length.toString() +
          I18n.t(' · 提问 ', ' · Questions ') + this.appState.pendingQuestions.length.toString())
          .fontSize(12)
          .fontColor(Design.WARNING)
      } else {
        Text(I18n.t('无待处理', 'Nothing pending'))
          .fontSize(13)
          .fontColor(Design.TEXT_HINT(this.uiDark))
      }
    }
    .width('100%')
    .padding({ left: Design.PAD_CARD, right: Design.PAD_CARD, top: 14, bottom: 14 })
    .alignItems(VerticalAlign.Center)
  }

  // ------------------------------------------------------------------
  // 当前服务器
  // ------------------------------------------------------------------

  private serverTitle(): string {
    const s = this.appState.server
    if (s === null) {
      return I18n.t('未配置服务器', 'No server configured')
    }
    const note = s.note.trim()
    if (note.length > 0) {
      return note
    }
    if (s.host.length > 0) {
      return s.host
    }
    return I18n.t('当前服务器', 'Current server')
  }

  private serverUrl(): string {
    const s = this.appState.server
    return s !== null ? s.normalizedUrl() : I18n.t('扫码或手动添加地址与令牌', 'Scan or add a URL and token manually')
  }

  private platformLabel(p: string): string {
    if (p === 'darwin') {
      return 'macOS'
    }
    if (p === 'win32') {
      return 'Windows'
    }
    if (p === 'linux') {
      return 'Linux'
    }
    return p
  }

  private gatewayColor(): string {
    if (this.appState.server === null) {
      return Design.TEXT_HINT(this.uiDark)
    }
    const h = this.appState.health
    if (h === null) {
      return Design.DANGER
    }
    return h.ok ? Design.SUCCESS : Design.DANGER
  }

  /** 元信息一行：在线状态 · 网关版本 · 平台 · 服务器数量 */
  private serverMeta(): string {
    const s = this.appState.server
    if (s === null) {
      return I18n.t('点此打开服务器管理', 'Tap to open server management')
    }
    const parts: string[] = []
    const h = this.appState.health
    if (h !== null) {
      parts.push(h.ok ? I18n.t('网关在线', 'Gateway online') : I18n.t('网关异常', 'Gateway error'))
      if (h.version.length > 0) {
        parts.push('v' + h.version)
      }
      if (h.platform.length > 0) {
        parts.push(this.platformLabel(h.platform))
      }
    } else {
      parts.push(this.appState.mode === 'connecting'
        ? I18n.t('正在连接网关', 'Connecting to gateway')
        : I18n.t('网关不可达', 'Gateway unreachable'))
    }
    if (this.appState.servers.length > 1) {
      parts.push(this.appState.servers.length.toString() + I18n.t(' 台服务器', ' servers'))
    }
    // 标题用备注名时，把主机名补进元信息；标题已经是主机名则不重复
    if (s.host.length > 0 && s.note.trim().length > 0) {
      parts.unshift(s.host)
    }
    return parts.join(' · ')
  }

  @Builder
  serverSection() {
    Column() {
      // 名称 + 地址同一行：字号/颜色做层级，右侧只留一个 › 表示可点，
      // 不再写「管理」（文字动作在这条整宽行里显得突兀）。
      Row({ space: 8 }) {
        Text() {
          Span(this.serverTitle())
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(Design.TEXT_MAIN(this.uiDark))
          Span('   ')
            .fontSize(13)
          Span(this.serverUrl())
            .fontSize(13)
            .fontColor(Design.TEXT_SUB(this.uiDark))
        }
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text('›')
          .fontSize(20)
          .fontColor(Design.TEXT_HINT(this.uiDark))
      }
      .width('100%')
      .padding({ left: Design.PAD_CARD, right: Design.PAD_CARD, top: 14, bottom: 10 })
      .alignItems(VerticalAlign.Center)

      Row({ space: 6 }) {
        Circle({ width: 6, height: 6 }).fill(this.gatewayColor())
        Text(this.serverMeta())
          .fontSize(12)
          .fontColor(Design.TEXT_HINT(this.uiDark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: Design.PAD_CARD, right: Design.PAD_CARD, bottom: 14 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor(this.rowBg('server'))
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressRow('server')
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.releaseRow()
      }
    })
    .onClick(() => {
      this.releaseRow()
      // 服务器管理：手机 router / 平板 NavPathStack 由 AppNav 分发
      AppNav.push(AppNav.R_SERVERS)
    })
  }
}
