import { AppNav, NavParams } from '../common/AppNav'
import { Theme, Design, sheetSpringBack } from '../models/Theme'
import { AppState } from '../services/AppState'
import { SessionView } from '../models/SessionView'
import { WorkspaceInfo } from '../models/WorkspaceInfo'
import { WorkspaceGroup } from '../models/WorkspaceGroup'
import { SessionListLogic } from '../common/SessionListLogic'
import { SessionActions } from '../common/SessionActions'
import { sessionMenu, SessionMenuParams } from '../components/SessionContextMenu'
import { handoffCard, HandoffCardParams } from '../components/HandoffCard'
import { SkeletonList } from '../components/SkeletonList'
import { I18n } from '../common/I18n'
import { NewSessionDialog } from '../components/NewSessionDialog'
import { NewWorkspaceDialog } from '../components/NewWorkspaceDialog'

/**
 * 会话列表：session.list、下拉刷新、新建会话（可选工作区）。
 *
 * 会话按工作区（cwd）分组折叠展示：分组头显示工作区名与会话数，
 * 点击展开/收起组内会话；有运行中会话的组默认展开。
 *
 * 鸿蒙化要点：大圆角卡片 + 轻投影、按压缩放反馈、胶囊状态标签、
 * 新建按钮胶囊形、列表弹性边缘（Spring）。
 */
@Component
export struct SessionsPage {
  @StorageLink('appState') appState: AppState = AppState.instance
  /** 深浅判定（AppState 写入）；变更驱动整页刷新 */
  @StorageLink('uiDark') uiDark: boolean = false
  /** 当前主题 id 原语（AppState 写入）；主题切换驱动整页刷新 */
  @StorageLink('uiTheme') uiTheme: string = 'deep-space'
  @State refreshing: boolean = false
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

  /** 新建会话弹窗（与折叠屏侧栏共用） */
  private newSessionDialog: CustomDialogController = new CustomDialogController({
    builder: NewSessionDialog({
      appState: AppState.instance,
      onCreated: (sessionId: string) => {
        const p = new NavParams()
        p.sessionId = sessionId
        AppNav.push(AppNav.R_CHAT, p)
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    // 组件自己画卡片（宽 380 + 圆角 20）；不开 customStyle 时系统会再套一层
    // 自己的对话框卡片，两层叠在一起就是那圈「重影」
    customStyle: true
  })
  /** 按压中的会话卡片 */
  @State pressedId: string = ''
  /** 收起的分组 key 集合（@State 持有驱动重渲染；规则见 SessionListLogic 纯函数） */
  @State collapsedKeys: string[] = []
  /** 分组/过滤纯逻辑（与平板侧栏共享，见 SessionListLogic） */
  private listLogic: SessionListLogic = new SessionListLogic()
  /** 列表视图：false 全部会话（隐藏已归档）/ true 已归档 */
  @State archivedView: boolean = false

  aboutToAppear(): void {
    this.appState.refreshSessions()
    this.appState.refreshWorkspaces()
    this.appState.refreshHandoff()
  }

  private refreshList(): void {
    this.refreshing = true
    this.appState.refreshSessions().then(() => {
      this.appState.refreshWorkspaces().then(() => {
        this.appState.refreshHandoff().then(() => {
          this.refreshing = false
        })
      })
    })
  }

  /** 接续卡片命中会话：指针指向的会话仍在列表里时带出状态（运行中绿点） */
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

  /** 点击接续卡片：跳入指针指向的会话并清掉本地展示（指针留给其他设备） */
  private openHandoff(): void {
    const h = this.appState.handoff
    if (!h) {
      return
    }
    const p = new NavParams()
    p.sessionId = h.sessionId
    this.appState.handoff = null
    AppNav.push(AppNav.R_CHAT, p)
  }

  /** 忽略接续卡片：清网关指针（不再提示） */
  private dismissHandoff(): void {
    this.appState.handoff = null
    this.appState.clearHandoff()
  }

  /** 接续卡片参数（动态值经闭包求值：@Builder 按值传参不建立渲染依赖） */
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

  private openNewSheet(): void {
    // 每次打开都刷新工作区列表，保证新绑定的工作区可见
    this.appState.refreshWorkspaces()
    this.newSessionDialog.open()
  }

  /** 分组数据：按视图过滤（默认视图隐藏已归档；归档视图只显示已归档） */
  private groups(): WorkspaceGroup[] {
    return this.listLogic.groups(this.appState.sessions, this.appState.archivedSessionIds, this.archivedView)
  }

  /** 归档会话：确认后 workspace.archiveSession（与 Web 端 sc-archive-btn 一致） */
  private confirmArchive(item: SessionView): void {
    SessionActions.confirmArchive(item, () => {
      this.appState.archiveSession(item.sessionId)
    })
  }

  /** 分组是否收起；有运行中会话的组始终视为展开 */
  private isCollapsed(g: WorkspaceGroup): boolean {
    return SessionListLogic.isCollapsedIn(this.collapsedKeys, g, g.sessions)
  }

  private toggleGroup(g: WorkspaceGroup): void {
    // animateTo 包裹状态变更：本次变化涉及的插入/删除走 transition 动画
    // （springMotion 物理曲线下 duration 不生效，时长由弹簧参数决定）
    this.getUIContext().animateTo({
      curve: Design.motionCurve
    }, () => {
      this.collapsedKeys = SessionListLogic.toggleInto(this.collapsedKeys, g, g.sessions)
    })
  }

  private pageBg(): string {
    return Theme.bgOf(Theme.get(this.uiTheme), this.uiDark)
  }

  private cardBg(): string {
    return Design.SURFACE(this.uiDark)
  }

  private accent(): string {
    return Theme.accentOf(Theme.get(this.uiTheme), this.uiDark)
  }

  /** 状态标签颜色：运行中 / 空白 / 空闲（共享规则，见 SessionListLogic） */
  private statusColor(item: SessionView): string {
    return SessionListLogic.statusColor(item, this.uiDark)
  }

  build() {
    Column() {
      Row() {
        Text(I18n.t('会话', 'Sessions'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Design.TEXT_MAIN(this.uiDark))
        Blank()
        // 新建工作区 / 新建会话：统一成右上角两个图标按钮（文件夹＝工作区，气泡＝会话）
        Row({ space: 8 }) {
          this.iconButton($r('app.media.ic_folder'), false, I18n.t('新建工作区', 'New workspace'), () => {
            this.newWorkspaceDialog.open()
          })
          this.iconButton($r('app.media.ic_message_filled'), true, I18n.t('新建会话', 'New session'), () => {
            this.openNewSheet()
          })
        }
      }
      .width('100%')
      .padding({ left: Design.PAD_PAGE, right: Design.PAD_PAGE, top: 16 + Design.safeTop(), bottom: 10 })

      // 视图切换：全部 / 已归档（归档计数 > 0 时显示）
      if (this.appState.archivedSessionIds.length > 0) {
        Row({ space: 8 }) {
          this.viewChip(I18n.t('全部', 'All'), (): boolean => !this.archivedView, (): boolean => false)
          this.viewChip(I18n.t('已归档 ', 'Archived ') + this.appState.archivedSessionIds.length.toString(),
            (): boolean => this.archivedView, (): boolean => true)
        }
        .width('100%')
        .padding({ left: Design.PAD_PAGE, right: Design.PAD_PAGE, bottom: 8 })
      }

      Stack() {
        Refresh({ refreshing: $$this.refreshing }) {
          List({ space: 10 }) {
            // 跨端接续卡片：另一设备最近打开的会话（appState.handoff 非空时置顶）
            if (this.appState.handoff !== null) {
              ListItem() {
                handoffCard(this.handoffParams())
              }
            }
            ForEach(this.groups(), (g: WorkspaceGroup) => {
              ListItem() {
                this.groupSection(g)
              }
            }, (g: WorkspaceGroup) => g.key + '#' + g.sessions.length.toString())
          }
          .width('100%')
          .height('100%')
          .padding({ top: 2 })
          // 列表满屏：内容可以一直滚到屏幕底边（胶囊浮在上面，不占列表高度）。
          // 只给滚动末端留出胶囊那一段（Design.contentBottomInset → navReserve），
          // 滚到底时最后一行停在胶囊上方；用 `contentEndOffset` 而不是 `padding`，
          // 因为 padding 只改 List 自身尺寸，不是「滚动内容末端的留白」。
          .contentEndOffset(Design.contentBottomInset())
        }
        .onRefreshing(() => {
          this.refreshList()
        })
        .width('100%')
        .height('100%')

        if (this.appState.sessions.length === 0) {
          if (this.appState.sessionsLoading) {
            // 首拉骨架屏：灰色块还原条目布局 + 透明度闪烁（官方 skeletondiagram 案例）
            Column() {
              SkeletonList({ rows: 6 })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            // 自绘空态，替代原 IBestEmpty
            Column({ space: 8 }) {
              Text(this.emptyText())
                .fontSize(14)
                .fontColor(Design.TEXT_SUB(this.uiDark))
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          }
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBg())
}

  /** 工作区分组：分组头 + （展开时）组内会话卡片；收放带展开/收起动画 */
  @Builder
  groupSection(g: WorkspaceGroup) {
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
        Text(g.sessions.length.toString() + I18n.t(' 个会话', ' sessions'))
          .fontSize(12)
          .fontColor(Design.TEXT_HINT(this.uiDark))
        // 折叠箭头：18px，字符框收到 16 居中——右侧的避让由行 padding 负责，
        // 这里不再留多余空白，箭头就贴着「xx 个会话」
        Text(this.isCollapsed(g) ? '▸' : '▾')
          .fontSize(18)
          .fontColor(Design.TEXT_SUB(this.uiDark))
          .width(16)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      // 右侧留 24：箭头不贴边，避开列表滚动条
      .padding({ left: 16, right: 24, top: 12, bottom: 6 })
      .onClick(() => {
        this.toggleGroup(g)
      })

      if (!this.isCollapsed(g)) {
        Column() {
          ForEach(g.sessions, (item: SessionView, index: number) => {
            this.sessionCard(item, index === g.sessions.length - 1)
          }, (item: SessionView) => item.sessionId)
        }
        .width('100%')
        .backgroundColor(Design.SURFACE(this.uiDark))
      }
    }
    .width('100%')
  }

  private emptyText(): string {
    const srv = this.appState.server
    if (!srv) {
      return I18n.t('请先在设置中配置服务器', 'Configure a server in Settings first')
    }
    const err = this.appState.lastError
    const url = srv.normalizedUrl()
    if (err.length > 0) {
      return err + '\n' + url + '\n' + I18n.t('下拉重试', 'Pull down to retry')
    }
    return I18n.t('下拉刷新或新建会话', 'Pull to refresh or create a session') + '\n' + url
  }

  /** 顶部图标按钮：主色实心（主操作）或浅底（次操作），与平板侧栏同款 */
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

  /**
   * 视图切换胶囊。高亮通过 getActive 闭包读取（@Builder 按值传参不建立
   * 渲染依赖，直接传值会导致切换后高亮不动）；点击显式设置目标视图
   * （onTargetView 返回该胶囊代表的视图状态，避免 toggle 语义让"全部"变空操作）。
   */
  @Builder
  viewChip(label: string, getActive: () => boolean, onTargetView: () => boolean) {
    Text(label)
      .fontSize(13)
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .fontColor(getActive() ? Color.White : Design.TEXT_SUB(this.uiDark))
      .backgroundColor(getActive() ? this.accent() : Design.SURFACE_SUB(this.uiDark))
      .borderRadius(Design.RADIUS_PILL)
      .animation({ curve: Design.pressCurve })
      .onClick(() => {
        this.archivedView = onTargetView()
      })
  }

  @Builder
  sessionCard(item: SessionView, last: boolean) {
    Row({ space: 12 }) {
      Text(item.displayLabel())
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Design.TEXT_MAIN(this.uiDark))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      // 右侧信息列：上面运行状态、下面时间，两端对齐 → 各占一半高度
      Column() {
        Row({ space: 4 }) {
          if (item.running) {
            Circle({ width: 6, height: 6 }).fill(Design.SUCCESS)
          }
          Text(item.statusLabel())
            .fontSize(11)
            .fontColor(this.statusColor(item))
        }
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .borderRadius(Design.RADIUS_PILL)
        .backgroundColor(item.running ? Design.successBg() : Design.FILL_LIGHT(this.uiDark))

        Text(item.updatedLabel())
          .fontSize(12)
          .fontColor(Design.TEXT_HINT(this.uiDark))
      }
      .height(52)
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .height(76)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: last ? 0 : 0.5 }, color: Design.borderHair(this.uiDark) })
    // 收放动画：展开时淡入并自上方 14vp 滑入，收起时淡出
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -14 })))
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
    // 长按弹出会话操作菜单（归档/取消归档）；对齐平板侧栏同款
    // outlineWidth(0)：去掉系统背板默认描边（真机黑框）
    .bindContextMenu(sessionMenu(this.menuParams(item)), ResponseType.LongPress, {
      outlineWidth: 0,
      borderRadius: Design.RADIUS_CONTROL,
      backgroundColor: Design.SURFACE(this.uiDark),
      backgroundBlurStyle: BlurStyle.NONE
    })
    .onClick(() => {
      const p = new NavParams()
      p.sessionId = item.sessionId
      AppNav.push(AppNav.R_CHAT, p)
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

  /** 长按菜单已抽为共享 Builder sessionMenu（components/），两端共用 */

  /** 删除会话：二次确认（不可恢复，网关侧是移入回收站）；共享弹窗见 SessionActions */
  private confirmDelete(item: SessionView): void {
    SessionActions.confirmDelete(item, () => {
      this.appState.deleteSession(item.sessionId)
    })
  }
}
