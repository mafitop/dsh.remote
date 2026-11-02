import { AppState } from '../services/AppState'
import { WorkspaceInfo } from '../models/WorkspaceInfo'
import { Theme, Design } from '../models/Theme'
import { I18n } from '../common/I18n'

/**
 * 新建会话弹窗（手机会话页与折叠屏侧栏共用）。
 *
 * 关键修复：
 * - 侧栏的「新会话」原先直接 createSession('')，完全忽略工作区；现在两端都走本弹窗
 * - 工作区选择持久化到 preferences，下次打开默认选中上次的工作区
 * - 支持直接新建工作区（DSH workspace.create 只接受目录路径）
 */
@CustomDialog
export struct NewSessionDialog {
  controller?: CustomDialogController
  appState: AppState = AppState.instance
  onCreated: (sessionId: string) => void = (sessionId: string) => {
    // 调用方负责跳转；默认无操作
  }
  @StorageLink('uiDark') uiDark: boolean = false
  @State selected: string = ''
  @State creating: boolean = false
  @State note: string = ''
  /** 本地工作区副本：异步刷新后靠它驱动重渲染 */
  @State workspaces: WorkspaceInfo[] = []
  private listScroller: Scroller = new Scroller()

  private accent(): string {
    return Theme.accentOf(Theme.get(this.appState.themeId), this.uiDark)
  }

  aboutToAppear(): void {
    this.selected = this.appState.selectedWorkspaceId
    this.workspaces = this.appState.workspaces
    this.reloadWorkspaces()
  }

  private async reloadWorkspaces(): Promise<void> {
    await this.appState.refreshWorkspaces()
    this.workspaces = this.appState.workspaces
    this.scrollToSelected()
  }

  /** 打开时把上次选中的工作区滚到可见位置 */
  private scrollToSelected(): void {
    if (this.selected.length === 0) {
      return
    }
    const index = this.workspaces.findIndex((w: WorkspaceInfo) => w.workspaceId === this.selected)
    if (index >= 0) {
      try {
        this.listScroller.scrollToIndex(index)
      } catch (e) {
        // 列表尚未布局完成时忽略
      }
    }
  }

  private pick(workspaceId: string): void {
    this.selected = this.selected === workspaceId ? '' : workspaceId
    this.appState.setSelectedWorkspace(this.selected)
  }

  private createSession(): void {
    if (this.creating) {
      return
    }
    this.creating = true
    this.note = ''
    this.appState.createSession(this.selected).then((sessionId: string) => {
      this.creating = false
      if (sessionId.length === 0) {
        this.note = this.appState.lastError.length > 0
          ? this.appState.lastError : I18n.t('创建会话失败', 'Create session failed')
        return
      }
      this.controller?.close()
      this.onCreated(sessionId)
    })
  }

  build() {
    Column({ space: 12 }) {
      Text(I18n.t('新建会话', 'New session'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Design.TEXT_MAIN(this.uiDark))
        .width('100%')

      Text(I18n.t('工作区', 'Workspace'))
        .fontSize(12)
        .fontColor(Design.TEXT_SUB(this.uiDark))
        .width('100%')

      if (this.workspaces.length === 0) {
        Text(I18n.t('未获取到工作区列表，将按默认方式创建', 'No workspace list; creating with defaults'))
          .fontSize(12)
          .fontColor(Design.TEXT_HINT(this.uiDark))
          .width('100%')
      } else {
        List({ space: 6, scroller: this.listScroller }) {
          ForEach(this.workspaces, (w: WorkspaceInfo) => {
            ListItem() {
              Row({ space: 10 }) {
                Column()
                  .width(16)
                  .height(16)
                  .borderRadius(Design.RADIUS_PILL)
                  .borderWidth(this.selected === w.workspaceId ? 5 : 1)
                  .borderColor(this.selected === w.workspaceId
                    ? this.accent() : Design.TEXT_HINT(this.uiDark))
                  .animation({ curve: Design.pressCurve })
                Column({ space: 2 }) {
                  Text(w.displayName())
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Design.TEXT_MAIN(this.uiDark))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (w.path.length > 0 && w.path !== w.displayName()) {
                    Text(w.path)
                      .fontSize(11)
                      .fontColor(Design.TEXT_HINT(this.uiDark))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .padding(10)
              .borderRadius(Design.RADIUS_CONTROL)
              .backgroundColor(this.selected === w.workspaceId
                ? Design.selectedBg(this.accent()) : Design.FILL_LIGHT(this.uiDark))
              .onClick(() => {
                this.pick(w.workspaceId)
              })
            }
          }, (w: WorkspaceInfo) => w.workspaceId)
        }
        .width('100%')
        .height(220)
        .edgeEffect(EdgeEffect.Spring)
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
        Button(this.creating ? I18n.t('创建中…', 'Creating…') : I18n.t('创建会话', 'Create session'))
          .layoutWeight(1)
          .height(42)
          .fontSize(15)
          .backgroundColor(this.accent())
          .fontColor(Color.White)
          .enabled(!this.creating)
          .onClick(() => {
            this.createSession()
          })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width(380)
    .padding(20)
    .backgroundColor(Design.SURFACE(this.uiDark))
    .borderRadius(20)
    .shadow(Design.cardShadow(this.uiDark))
  }
}
