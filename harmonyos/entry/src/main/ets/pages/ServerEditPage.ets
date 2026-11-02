import { AppNav } from '../common/AppNav'
import { Theme, Design } from '../models/Theme'
import { AppState } from '../services/AppState'
import { ServerInfo } from '../models/ServerInfo'
import { GatewayApi } from '../services/GatewayApi'
import { Constants } from '../common/Constants'
import { I18n } from '../common/I18n'
import { UiFeedback } from '../common/UiFeedback'

/**
 * 服务器手动录入页（新增 / 编辑）。
 *
 * 设计取舍：
 * - 服务器管理页只负责「列表 + 切换 + 左滑编辑/删除 + 扫码」，手工输入全部搬到本页，
 *   避免列表页一进来就是一堆输入框（用户反馈「太乱」）。
 * - 字段只有两个：网关地址、访问令牌。「备注」和「分组」都删了——
 *   分组改为由网关 /health 返回的 hostname 自动归并（只读，用户不可编辑）。
 * - 入口统一走 AppNav.openServerEditor(id)：id 经 AppStorage('serverEditId') 传递，
 *   手机 router 与平板 NavPathStack 共用（栈 param 在 builder 构建时机读不到，
 *   ChatView 踩过同样的坑）。
 */
@Component
export struct ServerEditPageView {
  @StorageLink('appState') appState: AppState = AppState.instance
  /** 要编辑的服务器 id；空串 = 新增（AppNav.openServerEditor 在跳转前写入） */
  @StorageLink('serverEditId') @Watch('onTargetChange') editId: string = ''
  @StorageLink('uiDark') uiDark: boolean = false
  @StorageLink('uiTheme') uiTheme: string = 'deep-space'

  @State url: string = ''
  @State token: string = ''
  /** 测试/保存结果文案（空串不显示） */
  @State feedback: string = ''
  @State feedbackOk: boolean = false
  @State testing: boolean = false

  aboutToAppear(): void {
    this.load()
  }

  private onTargetChange(): void {
    this.load()
  }

  private isEditing(): boolean {
    return this.editId.length > 0
  }

  private accent(): string {
    return Theme.accentOf(Theme.get(this.uiTheme), this.uiDark)
  }

  private surface(): string {
    return Design.SURFACE(this.uiDark)
  }

  private load(): void {
    this.feedback = ''
    this.feedbackOk = false
    if (!this.isEditing()) {
      this.url = ''
      this.token = ''
      return
    }
    for (const s of this.appState.servers) {
      if (s.id === this.editId) {
        this.url = s.url
        this.token = s.token
        return
      }
    }
  }

  build() {
    Column() {
      this.header()

      Scroll() {
        Row() {
          Column() {
            this.formCard()
          }
          .width('100%')
          // 表单通栏：左右、顶部都不留边距，表单块与页头直接相接
          .padding({ bottom: 40 })
          .constraintSize({ maxWidth: 640 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Top)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    // 整页一片底色：页头 + 表单连成一张纸，不在中间出现灰色断层
    .backgroundColor(this.surface())
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

      Text(this.isEditing() ? I18n.t('编辑服务器', 'Edit server') : I18n.t('新增服务器', 'Add server'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Design.TEXT_MAIN(this.uiDark))
        .margin({ left: 6 })
      Blank()
    }
    .width('100%')
    .padding({ left: 12, right: Design.PAD_PAGE, top: 10 + Design.safeTop(), bottom: 10 })
    .backgroundColor(this.surface())
  }

  @Builder
  fieldLabel(text: string) {
    Text(text)
      .fontSize(12)
      .fontColor(Design.TEXT_SUB(this.uiDark))
      .width('100%')
  }

  @Builder
  fieldHint(text: string) {
    Text(text)
      .fontSize(11)
      .fontColor(Design.TEXT_HINT(this.uiDark))
      .width('100%')
      .margin({ top: 2 })
  }

  @Builder
  formCard() {
    Column({ space: 16 }) {
      Column({ space: 6 }) {
        this.fieldLabel(I18n.t('网关地址', 'Gateway address'))
        TextInput({ text: $$this.url, placeholder: '192.168.1.10:8787' })
          .height(46)
          .fontSize(15)
          .padding({ left: 12, right: 12 })
          .type(InputType.URL)
          .fontColor(Design.TEXT_MAIN(this.uiDark))
          .placeholderColor(Design.TEXT_HINT(this.uiDark))
          .backgroundColor(Design.FILL_LIGHT(this.uiDark))
          .borderRadius(Design.RADIUS_CONTROL)
        this.fieldHint(I18n.t('可省略 http://，默认按 http 连接', 'http:// may be omitted; http is used by default'))
      }.alignItems(HorizontalAlign.Start).width('100%')

      Column({ space: 6 }) {
        this.fieldLabel(I18n.t('访问令牌', 'Access token'))
        TextInput({ text: $$this.token, placeholder: I18n.t('Bearer token', 'Bearer token') })
          .height(46)
          .fontSize(15)
          .padding({ left: 12, right: 12 })
          .type(InputType.Password)
          .fontColor(Design.TEXT_MAIN(this.uiDark))
          .placeholderColor(Design.TEXT_HINT(this.uiDark))
          .backgroundColor(Design.FILL_LIGHT(this.uiDark))
          .borderRadius(Design.RADIUS_CONTROL)
      }.alignItems(HorizontalAlign.Start).width('100%')

      Row({ space: 10 }) {
        Button(this.testing ? I18n.t('测试中…', 'Testing…') : I18n.t('测试连接', 'Test'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .height(46)
          .layoutWeight(1)
          .enabled(!this.testing)
          .backgroundColor(Design.withAlpha(this.accent(), '1F'))
          .fontColor(this.accent())
          .borderRadius(Design.RADIUS_CONTROL)
          .onClick(() => {
            this.testConnection()
          })
        Button(I18n.t('保存', 'Save'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .height(46)
          .layoutWeight(1)
          .backgroundColor(this.accent())
          .fontColor(Color.White)
          .borderRadius(Design.RADIUS_CONTROL)
          .onClick(() => {
            this.save()
          })
      }.width('100%')

      if (this.feedback.length > 0) {
        Text(this.feedback)
          .fontSize(12)
          .fontColor(this.feedbackOk ? Design.SUCCESS : Design.DANGER)
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor(this.surface())
    .alignItems(HorizontalAlign.Start)
  }

  /** 补协议 + 去空白；空串表示非法 */
  private normalizedUrl(): string {
    let url = this.url.trim()
    if (url.length === 0) {
      return ''
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://' + url
    }
    return url
  }

  private async testConnection(): Promise<void> {
    const url = this.normalizedUrl()
    if (url.length === 0) {
      this.feedback = I18n.t('请先输入网关地址', 'Enter the gateway address first')
      this.feedbackOk = false
      return
    }
    this.testing = true
    this.feedback = I18n.t('正在测试…', 'Testing…')
    this.feedbackOk = false
    const token = this.token.trim()
    const start = Date.now()
    try {
      const h = await GatewayApi.getHealth(url, 8000)
      const ms = Date.now() - start
      const upstream = h.upstreamOk ? I18n.t('上游正常', 'Upstream OK') : I18n.t('上游降级', 'Upstream degraded')
      // /health 免鉴权：没有令牌就不能声称「配置正确」
      if (token.length === 0) {
        this.feedback = I18n.t('网关可达（', 'Gateway reachable (') + ms.toString() + I18n.t('ms），但未填令牌，无法校验鉴权',
          'ms) but no token, cannot verify auth')
        this.feedbackOk = false
      } else {
        try {
          await GatewayApi.diagnosticsOk(url, token, 8000)
          this.feedback = I18n.t('连接成功（', 'Connected (') + ms.toString() + I18n.t('ms），版本 ', 'ms), version ') +
            h.version + (h.host.length > 0 ? I18n.t('，主机 ', ', host ') + h.host : '') +
            I18n.t('，', ', ') + upstream + I18n.t('，令牌有效', ', token valid')
          this.feedbackOk = true
        } catch (e) {
          const msg = (e as Error).message
          this.feedback = msg === 'AUTH'
            ? I18n.t('网关可达（', 'Gateway reachable (') + ms.toString() + I18n.t('ms），但令牌无效（401）', 'ms), token rejected (401)')
            : I18n.t('网关可达（', 'Gateway reachable (') + ms.toString() + I18n.t('ms），鉴权检查失败：', 'ms), auth check failed: ') + msg
          this.feedbackOk = false
        }
      }
    } catch (e) {
      this.feedback = I18n.t('连接失败：', 'Connection failed: ') + (e as Error).message
      this.feedbackOk = false
    }
    this.testing = false
  }

  private save(): void {
    const url = this.normalizedUrl()
    if (url.length === 0) {
      this.feedback = I18n.t('请先输入网关地址', 'Enter the gateway address first')
      this.feedbackOk = false
      return
    }
    const token = this.token.trim()
    const id: string = this.isEditing() ? this.editId : 's-' + Date.now().toString(36)

    const list: ServerInfo[] = []
    let replaced = false
    for (const s of this.appState.servers) {
      if (s.id === id) {
        list.push(new ServerInfo(id, url, s.note, s.group, token, s.host))
        replaced = true
      } else {
        list.push(s)
      }
    }
    if (!replaced) {
      list.push(new ServerInfo(id, url, '', Constants.DEFAULT_GROUP, token))
    }

    // 新增即设为当前；编辑保持原来的当前服务器不变（除非本来就没得选）
    const current = this.appState.server
    let activeId = this.isEditing() && current !== null ? current.id : id
    let exists = false
    for (const s of list) {
      if (s.id === activeId) {
        exists = true
        break
      }
    }
    if (!exists) {
      activeId = list.length > 0 ? list[0].id : ''
    }

    this.appState.saveServers(list, activeId)
    const ctx = this.getUIContext()
    UiFeedback.toast(ctx, this.isEditing() ? I18n.t('已保存', 'Saved') : I18n.t('已添加并设为当前', 'Added and set active'), 2000)
    AppNav.back()
  }
}

/**
 * @Entry 路由页壳（手机端 router 入口）。
 * 目标 id 由 AppNav.openServerEditor 写入 AppStorage('serverEditId')，
 * 手机与平板（TabletIndex 直接内嵌本 View）行为一致。
 */
@Entry
@Component
struct ServerEditPage {
  build() {
    Column() {
      ServerEditPageView()
    }
    .width('100%')
    .height('100%')
  }

  /** 与服务器管理页一致的抽屉式转场 */
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
