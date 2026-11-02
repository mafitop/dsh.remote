import { AppState } from '../services/AppState'
import { Theme, Design } from '../models/Theme'
import { I18n } from '../common/I18n'
import { GatewayApi } from '../services/GatewayApi'
import { DirListing, FsEntry, parentPathOf, lastSegmentOf } from '../models/FsEntry'

/**
 * 新建工作区弹窗（与「新建会话」分离）。
 *
 * DSH 的 workspace.create 只接受一个**已存在**的目录路径。手机上让人手打
 * `/Users/you/WorkSpace/xxx` 不合理，所以这里直接浏览「网关所在电脑」的目录：
 * 走 GET /fs/list（网关只暴露 FS_ROOTS 之下），进入目录后点「在此新建」即可。
 * 兜底保留「手动输入」，个别被隐藏/无权限的目录仍可手填。
 */
@CustomDialog
export struct NewWorkspaceDialog {
  controller?: CustomDialogController
  appState: AppState = AppState.instance
  onCreated: (workspaceId: string) => void = (workspaceId: string) => {
    // 调用方按需处理；默认无操作
  }
  @StorageLink('uiDark') uiDark: boolean = false
  @State creating: boolean = false
  @State note: string = ''

  /** 当前浏览目录（服务端返回的绝对路径） */
  @State curPath: string = ''
  /** 当前目录下的全部子目录（含隐藏项，渲染时按开关过滤） */
  @State allDirs: FsEntry[] = []
  /** 是否显示以 . 开头的目录（默认不显示，home 下几十个隐藏目录太吵） */
  @State showHidden: boolean = false
  /** 可浏览的根目录 */
  @State roots: string[] = []
  @State loading: boolean = false
  @State loadError: string = ''
  /** 手动输入模式（兜底） */
  @State manual: boolean = false
  @State manualPath: string = ''

  aboutToAppear(): void {
    // 弹窗组件会被 CustomDialogController 复用：每次打开都重置交互状态，
    // 否则上次的「显示隐藏项 / 手动输入 / 错误提示」会带进下一次
    this.showHidden = false
    this.manual = false
    this.manualPath = ''
    this.note = ''
    this.curPath = ''
    this.allDirs = []
    this.roots = []
    this.loadError = ''
    this.load('')
  }

  private accent(): string {
    return Theme.accentOf(Theme.get(this.appState.themeId), this.uiDark)
  }

  /** 读取主机目录；path 为空表示服务端默认根 */
  private async load(path: string): Promise<void> {
    const s = this.appState.server
    if (!s) {
      this.loadError = I18n.t('未配置服务器', 'No server configured')
      return
    }
    this.loading = true
    this.loadError = ''
    try {
      const v = await GatewayApi.fsList(s.normalizedUrl(), s.token, path)
      const listing: DirListing = DirListing.fromRecord(v)
      this.curPath = listing.path
      this.roots = listing.roots
      this.allDirs = listing.dirs()
    } catch (e) {
      const msg = (e as Error).message
      // 网关只开放 FS_ROOTS 之下的目录；退到根外时会拿到 403，给个人话提示
      this.loadError = msg.indexOf('403') >= 0
        ? I18n.t('该目录不在可浏览范围（网关只开放共享根目录）',
          'Directory is outside the shared roots the gateway exposes')
        : I18n.t('读取目录失败：', 'Listing failed: ') + msg
    } finally {
      this.loading = false
    }
  }

  /** 只在「上一级仍在可浏览根之内」时允许返回：退到根外面网关会返回 403 */
  private canGoUp(): boolean {
    const up = parentPathOf(this.curPath)
    if (up.length === 0 || this.curPath === '/') {
      return false
    }
    return this.withinRoots(up)
  }

  /** path 是否落在可浏览根之内（含根本身） */
  private withinRoots(path: string): boolean {
    for (const r of this.roots) {
      const root = r.endsWith('/') ? r.slice(0, -1) : r
      if (path === root || path.startsWith(root + '/')) {
        return true
      }
    }
    return false
  }

  /** 实际展示的子目录（过滤隐藏项） */
  private visibleDirs(): FsEntry[] {
    if (this.showHidden) {
      return this.allDirs
    }
    const list: FsEntry[] = []
    for (const e of this.allDirs) {
      if (!e.name.startsWith('.')) {
        list.push(e)
      }
    }
    return list
  }

  private async create(): Promise<void> {
    if (this.creating) {
      return
    }
    const target = this.manual ? this.manualPath.trim() : this.curPath
    if (target.length === 0) {
      this.note = I18n.t('请先选择一个目录', 'Pick a directory first')
      return
    }
    this.creating = true
    this.note = ''
    const id = await this.appState.addWorkspace(target)
    this.creating = false
    if (id.length === 0) {
      this.note = this.appState.lastError.length > 0
        ? this.appState.lastError : I18n.t('新建工作区失败', 'Create workspace failed')
      return
    }
    // 新建后默认作为下次新建会话的工作区
    this.appState.setSelectedWorkspace(id)
    this.controller?.close()
    this.onCreated(id)
  }

  build() {
    Column({ space: 10 }) {
      // 标题 + 右上角三个控件（返回 / 根目录 / 显示隐藏项）
      Row({ space: 6 }) {
        Text(I18n.t('新建工作区', 'New workspace'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Design.TEXT_MAIN(this.uiDark))
          .layoutWeight(1)
        if (!this.manual) {
          if (this.canGoUp()) {
            this.backButton()
          }
          ForEach(this.roots, (r: string) => {
            this.rootChip(r)
          }, (r: string) => r)
          this.hiddenToggle()
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.manual
        ? I18n.t('手动填写主机上已存在的目录路径', 'Enter an existing directory on the host')
        : I18n.t('选择网关所在电脑上的目录，进入后点「在此新建」',
          'Pick a directory on the host running the gateway, then tap Create here'))
        .fontSize(12)
        .fontColor(Design.TEXT_SUB(this.uiDark))
        .width('100%')

      if (this.manual) {
        this.manualBox()
      } else {
        this.browser()
      }

      if (this.note.length > 0) {
        Text(this.note)
          .fontSize(12)
          .fontColor(Design.DANGER)
          .width('100%')
      }

      Row({ space: 10 }) {
        Button(I18n.t('取消', 'Cancel'))
          .layoutWeight(1)
          .height(42)
          .fontSize(15)
          .backgroundColor(Design.FILL_LIGHT(this.uiDark))
          .fontColor(Design.TEXT_MAIN(this.uiDark))
          .onClick(() => {
            this.controller?.close()
          })
        Button(this.creating
          ? I18n.t('创建中…', 'Creating…')
          : (this.manual ? I18n.t('新建', 'Create') : I18n.t('在此新建', 'Create here')))
          .layoutWeight(1)
          .height(42)
          .fontSize(15)
          .backgroundColor(this.accent())
          .fontColor(Color.White)
          .enabled(!this.creating)
          .onClick(() => {
            this.create()
          })
      }
      .width('100%')
      .margin({ top: 2 })
    }
    .width(380)
    .padding(20)
    .backgroundColor(Design.SURFACE(this.uiDark))
    .borderRadius(20)
    .shadow(Design.cardShadow(this.uiDark))
  }

  @Builder
  manualBox() {
    Column({ space: 8 }) {
      TextInput({ text: $$this.manualPath, placeholder: '/Users/you/WorkSpace/project' })
        .height(40)
        .fontSize(14)
        .width('100%')
      Text(I18n.t('返回浏览目录', 'Browse instead'))
        .fontSize(12)
        .fontColor(this.accent())
        .onClick(() => {
          this.manual = false
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  browser() {
    Column({ space: 8 }) {
      // 当前目录 + 手动输入兜底入口
      Row({ space: 8 }) {
        Text(this.curPath.length > 0 ? this.curPath : I18n.t('加载中…', 'Loading…'))
          .fontSize(12)
          .fontColor(Design.TEXT_HINT(this.uiDark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(I18n.t('手动输入', 'Type path'))
          .fontSize(12)
          .fontColor(this.accent())
          .onClick(() => {
            this.manual = true
            this.manualPath = this.curPath
          })
      }
      .width('100%')

      // 子目录列表
      if (this.loadError.length > 0) {
        Text(this.loadError)
          .fontSize(12)
          .fontColor(Design.DANGER)
          .width('100%')
          .padding({ top: 8, bottom: 8 })
      } else if (this.visibleDirs().length === 0) {
        Text(this.loading
          ? I18n.t('读取中…', 'Loading…')
          : I18n.t('该目录没有子目录，可直接「在此新建」', 'No subdirectories; you can create here'))
          .fontSize(12)
          .fontColor(Design.TEXT_HINT(this.uiDark))
          .width('100%')
          .padding({ top: 8, bottom: 8 })
      } else {
        List({ space: 4 }) {
          ForEach(this.visibleDirs(), (e: FsEntry) => {
            ListItem() {
              Row({ space: 10 }) {
                Image($r('app.media.ic_folder'))
                  .width(18)
                  .height(18)
                  .fillColor(this.accent())
                Text(e.name)
                  .fontSize(14)
                  .fontColor(Design.TEXT_MAIN(this.uiDark))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 10, right: 10, top: 9, bottom: 9 })
              .borderRadius(Design.RADIUS_CONTROL)
              .backgroundColor(Design.FILL_LIGHT(this.uiDark))
              .onClick(() => {
                this.load(e.path)
              })
            }
          }, (e: FsEntry) => e.path)
        }
        .width('100%')
        .height(200)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 返回上一级：用返回箭头图标，比「↑ 上级」文字胶囊更省空间、更直观 */
  @Builder
  backButton() {
    Row() {
      Image($r('app.media.ic_back'))
        .width(16)
        .height(16)
        .fillColor(Design.TEXT_MAIN(this.uiDark))
    }
    .width(30)
    .height(30)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Design.FILL_LIGHT(this.uiDark))
    .borderRadius(Design.RADIUS_PILL)
    .accessibilityText(I18n.t('返回上一级目录', 'Go to parent directory'))
    .onClick(() => {
      const up = parentPathOf(this.curPath)
      if (up.length > 0) {
        this.load(up)
      }
    })
  }

  /** 根目录胶囊（右上角）：点了回到该根 */
  @Builder
  rootChip(target: string) {
    Text(lastSegmentOf(target).length > 0 ? lastSegmentOf(target) : target)
      .fontSize(12)
      .fontColor(Design.TEXT_MAIN(this.uiDark))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: 96 })
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(Design.FILL_LIGHT(this.uiDark))
      .borderRadius(Design.RADIUS_PILL)
      .onClick(() => {
        this.load(target)
      })
  }

  /** 显示/隐藏以 . 开头的目录（右上角图标开关） */
  @Builder
  hiddenToggle() {
    Row() {
      Image(this.showHidden ? $r('app.media.ic_visible') : $r('app.media.ic_invisible'))
        .width(16)
        .height(16)
        .fillColor(Design.TEXT_MAIN(this.uiDark))
    }
    .width(30)
    .height(30)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.showHidden ? Design.withAlpha(this.accent(), '1F') : Design.FILL_LIGHT(this.uiDark))
    .borderRadius(Design.RADIUS_PILL)
    .accessibilityText(this.showHidden
      ? I18n.t('隐藏以 . 开头的目录', 'Hide dotfolders')
      : I18n.t('显示以 . 开头的目录', 'Show dotfolders'))
    .onClick(() => {
      this.showHidden = !this.showHidden
    })
  }
}
