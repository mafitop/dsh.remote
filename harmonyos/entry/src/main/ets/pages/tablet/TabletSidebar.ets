import { Theme, Design } from '../../models/Theme'
import { AppNav } from '../../common/AppNav'
import { AppState } from '../../services/AppState'
import { SessionView } from '../../models/SessionView'
import { WorkspaceGroup } from '../../models/WorkspaceGroup'
import { SessionListLogic } from '../../common/SessionListLogic'
import { SessionActions } from '../../common/SessionActions'
import { sessionMenu, SessionMenuParams } from '../../components/SessionContextMenu'
import { handoffCard, HandoffCardParams } from '../../components/HandoffCard'
import { I18n } from '../../common/I18n'
import { NewSessionDialog } from '../../components/NewSessionDialog'
import { NewWorkspaceDialog } from '../../components/NewWorkspaceDialog'

/**
 * 平板侧栏（Navigation 的 navBar 区域），会话列表对齐手机端
 * SessionsPage 的工作区分组折叠：按 cwd 分组、组头可展开/收起
 * （有运行中会话的组强制展开）、默认隐藏已归档会话。组头为轻量
 * 行形态（侧栏窄，不用手机端的大卡片投影），组内会话行跟随桌面端
 * 单行样式，点击会话即替换右栏内容。
 */
@Component
export struct TabletSidebar {
  @StorageLink('appState') appState: AppState = AppState.instance
  @StorageLink('uiDark') uiDark: boolean = false
  @StorageLink('uiTheme') uiTheme: string = 'deep-space'
  /** 当前选中的 nav 项（'' = 未选中，例如右栏是会话详情） */
  @StorageLink('tabletNav') tabletNav: string = ''
  /** 当前打开的会话（AppNav.openChat 写入），用于侧栏高亮 */
  @StorageLink('tabletChatSession') activeSessionId: string = ''
  /** 按压中的会话卡片 */
  @State pressedId: string = ''

  /** 新建工作区弹窗（与新建会话分离） */
  private newWorkspaceDialog: CustomDialogController = new CustomDialogController({
    builder: NewWorkspaceDialog({
      appState: AppState.instance,
      onCreated: (workspaceId: string) => {
        this.appState.refreshSessions()
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    // 组件自己画卡片（宽 380 + 圆角 20）；不开 customStyle 时系统会再套一层
    // 自己的对话框卡片，两层叠在一起就是那圈「重影」
    customStyle: true
  })

  /** 新建会话弹窗：与手机会话页共用，工作区选择持久化 */
  private newSessionDialog: CustomDialogController = new CustomDialogController({
    builder: NewSessionDialog({
      appState: AppState.instance,
      onCreated: (sessionId: string) => {
        this.tabletNav = ''
        AppNav.openChat(sessionId)
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    // 组件自己画卡片（宽 380 + 圆角 20）；不开 customStyle 时系统会再套一层
    // 自己的对话框卡片，两层叠在一起就是那圈「重影」
    customStyle: true
  })
  /** 收起的分组 key 集合（@State 持有驱动重渲染；规则见 SessionListLogic 纯函数） */
  @State collapsedKeys: string[] = []
  /** 分组/过滤纯逻辑（与手机端 SessionsPage 共享，见 SessionListLogic） */
  private listLogic: SessionListLogic = new SessionListLogic()

  aboutToAppear(): void {
    this.appState.refreshSessions()
    this.appState.refreshHandoff()
  }

  /** 接续卡片命中会话（对齐手机端 SessionsPage.handoffSession） */
  private handoffSession(): SessionView | null {
    const h = this.appState.handoff
    if (!h) {
      return null
    }
    for (const s of this.appState.sessions) {
      if (s.sessionId === h.sessionId) {
        return s
      }
    }
    return null
  }

  /** 点击接续卡片：右栏打开该会话并清掉本地展示 */
  private openHandoff(): void {
    const h = this.appState.handoff
    if (!h) {
      return
    }
    this.appState.handoff = null
    this.tabletNav = ''
    AppNav.openChat(h.sessionId)
  }

  /** 忽略接续卡片：清网关指针（不再提示） */
  private dismissHandoff(): void {
    this.appState.handoff = null
    this.appState.clearHandoff()
  }

  /** 接续卡片参数（动态值经闭包求值） */
  private handoffParams(): HandoffCardParams {
    const p = new HandoffCardParams()
    p.handoff = this.appState.handoff
    p.session = this.handoffSession()
    p.getDark = (): boolean => this.uiDark
    p.getAccent = (): string => this.accent()
    p.onOpen = (): void => {
      this.openHandoff()
    }
    p.onDismiss = (): void => {
      this.dismissHandoff()
    }
    return p
  }

  private pageBg(): string {
    return Theme.bgOf(Theme.get(this.uiTheme), this.uiDark)
  }

  private accent(): string {
    return Theme.accentOf(Theme.get(this.uiTheme), this.uiDark)
  }

  /** 分组数据：默认视图隐藏已归档会话（与手机端 groups() 同源） */
  private groups(): WorkspaceGroup[] {
    return this.listLogic.groups(this.appState.sessions, this.appState.archivedSessionIds, false)
  }

  /** 分组是否收起；有运行中会话的组始终视为展开 */
  private isCollapsed(g: WorkspaceGroup): boolean {
    return SessionListLogic.isCollapsedIn(this.collapsedKeys, g, g.sessions)
  }

  private toggleGroup(g: WorkspaceGroup): void {
    this.getUIContext().animateTo({
      curve: Design.motionCurve
    }, () => {
      this.collapsedKeys = SessionListLogic.toggleInto(this.collapsedKeys, g, g.sessions)
    })
  }

  /** 状态点颜色：运行中绿 / 空白警示 / 空闲灰（共享规则） */
  private statusColor(item: SessionView): string {
    return SessionListLogic.statusColor(item, this.uiDark)
  }

  /** 侧栏会话行：标题独占左侧；右侧「状态 / 时间」上下各占一半 */
  @Builder
  sessionRow(item: SessionView, last: boolean) {
    Row({ space: 10 }) {
      Text(item.displayLabel())
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Design.TEXT_MAIN(this.uiDark))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      Column() {
        Row({ space: 4 }) {
          if (item.running) {
            Circle({ width: 6, height: 6 }).fill(Design.SUCCESS)
          }
          Text(item.statusLabel())
            .fontSize(11)
            .fontColor(this.statusColor(item))
        }
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(Design.RADIUS_PILL)
        .backgroundColor(item.running ? Design.successBg() : Design.FILL_LIGHT(this.uiDark))

        Text(item.updatedLabel())
          .fontSize(12)
          .fontColor(Design.TEXT_HINT(this.uiDark))
          .maxLines(1)
      }
      .height(44)
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(this.tabletNav === '' && this.activeSessionId === item.sessionId
      ? Design.chipBg(this.accent()) : Color.Transparent)
    .border({ width: { bottom: last ? 0 : 0.5 }, color: Design.borderHair(this.uiDark) })
    .scale({
      x: this.pressedId === item.sessionId ? Design.PRESS_SCALE : 1,
      y: this.pressedId === item.sessionId ? Design.PRESS_SCALE : 1
    })
    .animation({ curve: Design.pressCurve })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedId = item.sessionId
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedId = ''
      }
    })
    .onClick(() => {
      this.tabletNav = ''
      AppNav.openChat(item.sessionId)
    })
    // 长按弹出会话操作菜单（归档/取消归档）——共享 Builder，与手机端同款
    // outlineWidth(0)：系统默认给菜单背板加一圈描边（真机上呈黑色外框），
    // 显式置 0 去掉；圆角/背板色/投影由菜单自绘内容承担。
    .bindContextMenu(sessionMenu(this.menuParams(item)), ResponseType.LongPress, {
      outlineWidth: 0,
      borderRadius: Design.RADIUS_CONTROL,
      backgroundColor: Design.SURFACE(this.uiDark),
      backgroundBlurStyle: BlurStyle.NONE
    })
  }

  /** 长按菜单参数（共享 Builder sessionMenu 消费；见 components/SessionContextMenu） */
  private menuParams(item: SessionView): SessionMenuParams {
    const p = new SessionMenuParams()
    p.item = item
    p.dark = this.uiDark
    p.archived = this.appState.archivedSessionIds.indexOf(item.sessionId) >= 0
    p.onArchive = (): void => {
      this.confirmArchive(item)
    }
    p.onUnarchive = (): void => {
      this.appState.unarchiveSession(item.sessionId)
    }
    p.onDelete = (): void => {
      this.confirmDelete(item)
    }
    return p
  }

  /** 删除会话：二次确认（不可恢复，网关侧是移入回收站）；共享弹窗见 SessionActions */
  private confirmDelete(item: SessionView): void {
    SessionActions.confirmDelete(item, () => {
      this.appState.deleteSession(item.sessionId)
    })
  }

  /** 归档会话：确认后走 AppState（与手机端同一确认弹窗语义） */
  private confirmArchive(item: SessionView): void {
    SessionActions.confirmArchive(item, () => {
      this.appState.archiveSession(item.sessionId)
    })
  }

  /** 顶部图标按钮：主色实心（主操作）或浅底（次操作），与手机会话页同款 */
  @Builder
  iconButton(icon: Resource, primary: boolean, label: string, action: () => void) {
    Row() {
      Image(icon)
        .width(19)
        .height(19)
        .fillColor(primary ? Color.White : this.accent())
    }
    .width(36)
    .height(36)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(primary ? this.accent() : Design.FILL_LIGHT(this.uiDark))
    .borderRadius(Design.RADIUS_PILL)
    .accessibilityText(label)
    .onClick(() => {
      action()
    })
  }

  build() {
    Column() {
      // 品牌行（对齐桌面端 ds-brand）
      Row({ space: 8 }) {
        // 左上角：设置（原菱形 ◆ 的位置）；品牌文字「Remote」仍回主页
        Row() {
          Image($r('app.media.ic_settings'))
            .width(20)
            .height(20)
            .fillColor(this.tabletNav === AppNav.R_SETTINGS ? this.accent() : Design.TEXT_MAIN(this.uiDark))
        }
        .width(30)
        .height(30)
        .justifyContent(FlexAlign.Center)
        .accessibilityText(I18n.t('设置', 'Settings'))
        .onClick(() => {
          this.tabletNav = AppNav.R_SETTINGS
          AppNav.switchMain(AppNav.R_SETTINGS)
        })
        Text('Remote')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.tabletNav === AppNav.R_HOME ? this.accent() : Design.TEXT_MAIN(this.uiDark))
          .layoutWeight(1)
          .accessibilityText(I18n.t('主页', 'Home'))
          .onClick(() => {
            this.tabletNav = AppNav.R_HOME
            AppNav.switchMain(AppNav.R_HOME)
          })
        // 与手机会话页一致：右上角两个图标按钮（文件夹＝工作区，气泡＝会话）
        this.iconButton($r('app.media.ic_folder'), false, I18n.t('新建工作区', 'New workspace'), () => {
          this.appState.refreshWorkspaces()
          this.newWorkspaceDialog.open()
        })
        this.iconButton($r('app.media.ic_message_filled'), true, I18n.t('新建会话', 'New session'), () => {
          this.appState.refreshWorkspaces()
          this.newSessionDialog.open()
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: Design.safeTop() + 14, bottom: 8 })

      Row({ space: 4 }) {
        Text(I18n.t('会话', 'Sessions'))
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Design.TEXT_HINT(this.uiDark))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .padding({ left: 12, right: 8, top: 4, bottom: 4 })

      // 会话列表：工作区分组折叠（对齐手机端 SessionsPage）。
      // 每个工作区一个浅色背板块（SURFACE_SUB + 细边框），与页面底色分层，
      // 一眼区分「工作区容器」和其内的会话行。
      List({ space: 8 }) {
        // 跨端接续卡片：另一设备最近打开的会话（与手机端同款）
        if (this.appState.handoff !== null) {
          ListItem() {
            handoffCard(this.handoffParams())
          }
        }
        ForEach(this.groups(), (g: WorkspaceGroup) => {
          ListItem() {
            Column() {
              // 分组头：轻量标签行（工作区名 + 运行点 + 会话数 + 折叠箭头）
              Row({ space: 4 }) {
                Text(g.name)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Design.TEXT_SUB(this.uiDark))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                if (g.sessions.some((s: SessionView) => s.running)) {
                  Circle({ width: 6, height: 6 }).fill(Design.SUCCESS)
                }
                // 与手机会话页一致：带「个会话」后缀，不再只显示一个数字
                Text(g.sessions.length.toString() + I18n.t(' 个会话', ' sessions'))
                  .fontSize(12)
                  .fontColor(Design.TEXT_HINT(this.uiDark))
                // 折叠箭头 18px、字符框 16 居中，紧贴会话数（右侧避让靠行 padding）
                Text(this.isCollapsed(g) ? '▸' : '▾')
                  .fontSize(18)
                  .fontColor(Design.TEXT_SUB(this.uiDark))
                  .width(16)
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
              .padding({ left: 8, right: 18, top: 10, bottom: 6 })
              .onClick(() => {
                this.toggleGroup(g)
              })

              if (!this.isCollapsed(g)) {
                Column() {
                  ForEach(g.sessions, (item: SessionView, index: number) => {
                    this.sessionRow(item, index === g.sessions.length - 1)
                  }, (item: SessionView) => item.sessionId + '#' + item.updatedAt.toString())
                }
                .width('100%')
                .backgroundColor(Design.SURFACE(this.uiDark))
              }
            }
            .width('100%')
            .padding({ top: 2, bottom: 10 })
          }
        }, (g: WorkspaceGroup) => g.key + '#' + g.sessions.length.toString())
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)

    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBg())
  }
}
