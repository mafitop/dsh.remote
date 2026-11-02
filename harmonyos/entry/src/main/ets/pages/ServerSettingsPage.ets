import { AppNav } from '../common/AppNav'
import { Theme, Design } from '../models/Theme'
import { AppState } from '../services/AppState'
import { ServerInfo } from '../models/ServerInfo'
import { StorageService } from '../services/StorageService'
import { ScanService } from '../services/ScanService'
import { PairParser } from '../services/PairParser'
import { I18n } from '../common/I18n'
import { UiFeedback } from '../common/UiFeedback'

/**
 * 列表行（扁平化）：组头行 + 服务器行混排在一个 List 里。
 * key 里带上 host，host 一变就可能整组重排，key 唯一才不会出现「同一台出现两次 / 组头丢失」。
 */
class ListRow {
  key: string = ''
  header: boolean = false
  host: string = ''
  count: number = 0
  /** 组头行放占位对象（渲染时按 header 分支忽略），避免可空类型在闭包里收窄不了 */
  server: ServerInfo = new ServerInfo('', '', '', '', '')
  last: boolean = false

  static headerRow(host: string, count: number, placeholder: ServerInfo): ListRow {
    const r = new ListRow()
    r.key = 'h:' + host
    r.header = true
    r.host = host
    r.count = count
    r.server = placeholder
    return r
  }

  static serverRow(item: ServerInfo, last: boolean): ListRow {
    const r = new ListRow()
    r.key = 's:' + item.id + ':' + item.host
    r.server = item
    r.last = last
    return r
  }

  label(): string {
    return this.host.length > 0 ? this.host : I18n.t('未知主机', 'Unknown host')
  }
}

/**
 * 服务器管理页（列表态）。
 *
 * 布局取舍（按用户反馈重做）：
 * - 顶部右上角「+」→ 跳 ServerEditPage 手动录入；列表页不再内嵌输入框，一进来就是服务器列表。
 * - 右下角圆形 FAB（扫码图标）→ 扫码配对。
 * - 列表项完全不可点（避免误触）：所有变更都走左滑动作条——「设为当前 / 编辑 / 删除」，
 *   动作条与卡片同高、滑开时卡片右侧去圆角，拼成 iOS 邮件那样的一条。
 * - 右侧只显示「当前」状态标签，不做成可点控件。
 * - 「备注」「分组」都已移除：列表按网关返回的 hostname 自动分组（只读），行内留地址 + 令牌状态。
 */
@Component
export struct ServerSettingsPageView {
  @StorageLink('appState') appState: AppState = AppState.instance
  @StorageLink('uiDark') uiDark: boolean = false
  @StorageLink('uiTheme') uiTheme: string = 'deep-space'

  /** 列表项固定高度（滑动按钮与之等高，避免高度不一致露白） */
  private static readonly ROW_H: number = 76
  /** 滑动按钮宽度 */
  private static readonly ACT_W: number = 72

  /**
   * 列表滚动器：除了滚动，还用来在「设为当前」后收合滑动动作条。
   * 当前项的动作集比非当前项少一个「设为当前」（3 个 → 2 个），
   * 行还停在原来 3 个按钮的偏移上，右侧就会空出一大块。
   */
  private listScroller: ListScroller = new ListScroller()

  aboutToAppear(): void {
    // 补齐各服务器的 hostname，列表才能按「哪台机器」分组
    this.appState.probeServerHosts()
  }

  private pageBg(): string {
    return Theme.bgOf(Theme.get(this.uiTheme), this.uiDark)
  }

  private accent(): string {
    return Theme.accentOf(Theme.get(this.uiTheme), this.uiDark)
  }

  private surface(): string {
    return Design.SURFACE(this.uiDark)
  }

  /** 按 host 归并后摊平成「组头 + 行」（保持 servers 里的原始顺序） */
  private listRows(): ListRow[] {
    const hosts: string[] = []
    const buckets: Map<string, ServerInfo[]> = new Map()
    for (const s of this.appState.servers) {
      let bucket = buckets.get(s.host)
      if (bucket === undefined) {
        bucket = []
        buckets.set(s.host, bucket)
        hosts.push(s.host)
      }
      bucket.push(s)
    }
    const rows: ListRow[] = []
    for (const h of hosts) {
      const bucket = buckets.get(h)
      if (bucket === undefined || bucket.length === 0) {
        continue
      }
      rows.push(ListRow.headerRow(h, bucket.length, bucket[0]))
      for (let i = 0; i < bucket.length; i++) {
        rows.push(ListRow.serverRow(bucket[i], i === bucket.length - 1))
      }
    }
    return rows
  }

  private isActive(item: ServerInfo): boolean {
    const cur = this.appState.server
    return cur !== null && cur.id === item.id
  }

  private toast(msg: string): void {
    UiFeedback.toast(this.getUIContext(), msg, 2200)
  }

  build() {
    Column() {
      this.header()
      Stack({ alignContent: Alignment.BottomEnd }) {
        if (this.appState.servers.length === 0) {
          this.emptyState()
        } else {
          this.serverList()
        }
        this.scanFab()
      }
      .width('100%')
      .layoutWeight(1)
      .alignContent(Alignment.BottomEnd)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBg())
  }

  @Builder
  header() {
    Row() {
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor(Design.TEXT_MAIN(this.uiDark))
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .margin({ left: -8 })
      .borderRadius(Design.RADIUS_PILL)
      .onClick(() => {
        AppNav.back()
      })

      Text(I18n.t('服务器管理', 'Servers'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Design.TEXT_MAIN(this.uiDark))
        .margin({ left: 6 })
      Blank()

      // 右上角「+」：新页面手动录入
      Row() {
        Image($r('app.media.ic_add'))
          .width(20)
          .height(20)
          .fillColor(Design.TEXT_MAIN(this.uiDark))
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(Design.FILL_LIGHT(this.uiDark))
      .borderRadius(Design.RADIUS_PILL)
      .onClick(() => {
        AppNav.openServerEditor('')
      })
    }
    .width('100%')
    .padding({ left: 12, right: Design.PAD_PAGE, top: 10 + Design.safeTop(), bottom: 10 })
    .backgroundColor(this.surface())
  }

  @Builder
  serverList() {
    Column() {
      Row() {
        Text(I18n.t('左滑：设为当前 / 编辑 / 删除', 'Swipe left: set active / edit / delete'))
          .fontSize(12)
          .fontColor(Design.TEXT_HINT(this.uiDark))
        Blank()
        Text(this.appState.servers.length.toString())
          .fontSize(12)
          .fontColor(Design.TEXT_HINT(this.uiDark))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      List({ space: 0, scroller: this.listScroller }) {
        ForEach(this.listRows(), (row: ListRow) => {
          ListItem() {
            if (row.header) {
              // 组头＝主机名（只读，来自网关 /health；还没连过的显示「未知主机」）
              this.hostHeader(row)
            } else {
              this.serverRow(row.server, row.last)
            }
          }
          .swipeAction({
            end: this.rowActions(row),
            edgeEffect: SwipeEdgeEffect.Spring
          })
          .transition(TransitionEffect.OPACITY)
        }, (row: ListRow) => row.key)
      }
      .width('100%')
      .layoutWeight(1)
      // 通栏列表：左右不留边距，行与行之间用发丝线分隔（与「会话」列表一致）。
      // 不留底部留白：扫码 FAB 只占右下角一小块，列表可以一直铺到屏幕底边，
      // 白底保证内容少时下方也是白的一整片。
      .backgroundColor(this.surface())
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .layoutWeight(1)
  }

  /** 主机分组头：主机名 + 该主机下的服务器数量（只读信息，不可编辑） */
  @Builder
  hostHeader(g: ListRow) {
    Row({ space: 6 }) {
      Text(g.label())
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(g.host.length > 0 ? this.accent() : Design.TEXT_HINT(this.uiDark))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(g.count.toString())
        .fontSize(11)
        .fontColor(Design.TEXT_HINT(this.uiDark))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 6 })
  }

  @Builder
  serverRow(item: ServerInfo, last: boolean) {
    Row({ space: 12 }) {
      // 左半区：点开编辑页（非破坏性，不会误切当前服务器）
      Column({ space: 6 }) {
        Text(item.normalizedUrl())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Design.TEXT_MAIN(this.uiDark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row({ space: 8 }) {
          Row({ space: 4 }) {
            Circle()
              .width(6)
              .height(6)
              .fill(item.token.length > 0 ? Design.SUCCESS : Design.TEXT_HINT(this.uiDark))
            Text(item.token.length > 0 ? I18n.t('令牌已配置', 'Token set') : I18n.t('无令牌', 'No token'))
              .fontSize(11)
              .fontColor(Design.TEXT_HINT(this.uiDark))
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 右侧只表示状态（不是控件）：切换当前服务器统一走左滑动作，避免误触
      if (this.isActive(item)) {
        Text(I18n.t('当前', 'Active'))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.accent())
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(Design.withAlpha(this.accent(), '1F'))
          .borderRadius(Design.RADIUS_PILL)
          .margin({ right: 10 })
      }
    }
    .width('100%')
    .height(ServerSettingsPageView.ROW_H)
    .padding({ left: 16, right: 4 })
    .backgroundColor(this.surface())
    // 通栏行：不设圆角；行间用发丝线（最后一行不画）
    .border({ width: { bottom: last ? 0 : 0.5 }, color: Design.borderHair(this.uiDark) })
  }

  /** 单个滑动动作：不设圆角，靠外层 Row 裁出「一条」的观感（iOS 邮件那种） */
  @Builder
  swipeAction(label: string, bg: string, action: () => void) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .maxLines(1)
    }
    .width(ServerSettingsPageView.ACT_W)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(bg)
    .onClick(action)
  }

  @Builder
  rowActions(row: ListRow) {
    Row() {
      // 组头行不提供动作（空 Row），服务器行才有
      if (!row.header) {
        if (!this.isActive(row.server)) {
          this.swipeAction(I18n.t('设为当前', 'Set active'), this.accent(), () => {
            this.activate(row.server)
          })
        }
        this.swipeAction(I18n.t('编辑', 'Edit'), Design.swipeNeutral(this.uiDark), () => {
          AppNav.openServerEditor(row.server.id)
        })
        this.swipeAction(I18n.t('删除', 'Delete'), Design.DANGER, () => {
          this.confirmDelete(row.server)
        })
      }
    }
    .height(ServerSettingsPageView.ROW_H)
    .clip(true)
  }

  @Builder
  emptyState() {
    Column({ space: 10 }) {
      Stack() {
        Circle().width(64).height(64).fill(Design.FILL_LIGHT(this.uiDark))
        Image($r('app.media.ic_scan'))
          .width(26)
          .height(26)
          .fillColor(Design.TEXT_HINT(this.uiDark))
      }
      .width(64)
      .height(64)

      Text(I18n.t('还没有配置服务器', 'No servers yet'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Design.TEXT_MAIN(this.uiDark))
      Text(I18n.t('右上角「+」手动填写地址，或用右下角扫码配对', 'Tap + to enter an address, or scan a pairing QR with the button below'))
        .fontSize(12)
        .fontColor(Design.TEXT_HINT(this.uiDark))
        .textAlign(TextAlign.Center)
        .width('80%')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /** 右下角圆形扫码按钮 */
  @Builder
  scanFab() {
    Button({ type: ButtonType.Circle }) {
      Image($r('app.media.ic_scan'))
        .width(24)
        .height(24)
        .fillColor(Color.White)
    }
    .width(56)
    .height(56)
    .backgroundColor(this.accent())
    .shadow({
      radius: 18,
      color: Design.shadowColor(this.uiDark),
      offsetX: 0,
      offsetY: 6
    })
    .margin({ right: Design.PAD_PAGE + 4, bottom: Design.PAD_PAGE + Design.safeBottom() + 12 })
    .onClick(() => {
      this.scanPair()
    })
  }

  private activate(item: ServerInfo): void {
    if (this.isActive(item)) {
      return
    }
    const ok = this.appState.setCurrentServer(item.id)
    if (ok) {
      // 这一行的「设为当前」消失后动作条会变窄，行内容仍停在旧偏移上，
      // 右侧会露出空白：切换成功后先把滑动动作收起来。
      this.listScroller.closeAllSwipeActions()
    }
    this.toast(ok
      ? I18n.t('已切换当前服务器：', 'Active server: ') + item.normalizedUrl()
      : I18n.t('切换失败', 'Switch failed'))
  }

  /** 扫码配对：解析 dshremote://pair 并导入服务器 */
  private async scanPair(): Promise<void> {
    const ctx = StorageService.getContext()
    if (!ctx) {
      this.toast(I18n.t('无法获取应用上下文', 'App context unavailable'))
      return
    }
    const raw = await ScanService.scanText(ctx)
    if (raw.length === 0) {
      return
    }
    const payload = PairParser.parsePairUrl(raw)
    if (!payload) {
      this.toast(I18n.t('不是有效的 Remote 配对二维码', 'Not a valid Remote pairing QR code'))
      return
    }
    const ok = this.appState.addServersFromPair(payload.token, payload.servers)
    this.toast(ok
      ? I18n.t('配对成功：已导入 ', 'Paired: imported ') + payload.servers.length.toString() + I18n.t(' 个地址', ' addresses')
      : I18n.t('配对失败：二维码内容不完整', 'Pairing failed: incomplete QR content'))
  }

  private confirmDelete(item: ServerInfo): void {
    AlertDialog.show({
      title: I18n.t('删除服务器', 'Delete server'),
      message: I18n.t('确定删除 ', 'Delete ') + item.normalizedUrl() + I18n.t(' 吗？', '?'),
      primaryButton: {
        value: I18n.t('取消', 'Cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: I18n.t('删除', 'Delete'),
        action: () => {
          this.deleteServer(item)
        }
      }
    })
  }

  private deleteServer(item: ServerInfo): void {
    const list: ServerInfo[] = []
    for (const s of this.appState.servers) {
      if (s.id !== item.id) {
        list.push(s)
      }
    }
    // 删掉的正好是当前服务器时，顺延到列表里的下一台（没有就置空）
    const cur = this.appState.server
    let activeId: string = cur !== null ? cur.id : ''
    if (cur === null || cur.id === item.id) {
      activeId = list.length > 0 ? list[0].id : ''
    }
    this.appState.saveServers(list, activeId)
    this.toast(I18n.t('已删除 ', 'Deleted ') + item.normalizedUrl())
  }
}

/**
 * @Entry 路由页壳（手机端 router 入口）：直接转发到可内嵌的 ServerSettingsPageView。
 * 平板分栏由 TabletIndex 的 navDestination builder 直接挂 ServerSettingsPageView。
 */
@Entry
@Component
struct ServerSettingsPage {
  build() {
    Column() {
      ServerSettingsPageView()
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 抽屉式转场：子页自右滑入、底层左移；返回反向。
   * PageTransitionEnter/Exit 只能直写在 pageTransition() 内（ArkUI 语法限制），
   * 参数统一取 Design 抽屉令牌。
   */
  pageTransition(): void {
    PageTransitionEnter({ type: RouteType.Push, duration: Design.DRAWER_DURATION, curve: Design.DRAWER_CURVE })
      .slide(SlideEffect.Right)
    PageTransitionExit({ type: RouteType.Push, duration: Design.DRAWER_DURATION, curve: Design.DRAWER_CURVE })
      .slide(SlideEffect.Left)
    PageTransitionEnter({ type: RouteType.Pop, duration: Design.DRAWER_DURATION, curve: Design.DRAWER_CURVE })
      .slide(SlideEffect.Left)
    PageTransitionExit({ type: RouteType.Pop, duration: Design.DRAWER_DURATION, curve: Design.DRAWER_CURVE })
      .slide(SlideEffect.Right)
  }
}
