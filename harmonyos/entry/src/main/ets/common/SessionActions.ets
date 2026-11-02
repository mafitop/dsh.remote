import { SessionView } from '../models/SessionView'
import { Design } from '../models/Theme'
import { I18n } from './I18n'

/**
 * 会话操作确认弹窗：手机端 SessionsPage 与平板端 TabletSidebar 共用
 * （此前归档/删除确认在两端各写一份 AlertDialog，文案与按钮语义必须
 * 严格一致，抽到一处防止漂移）。
 *
 * 删除：DSH 上游没有 session.delete，改由 gateway.js 直接按存储布局删除
 * （移入 ~/.dsh-remote/trash，可从回收站恢复），长按菜单已接回该入口。
 */
export class SessionActions {
  /** 归档确认：归档后从列表移除（手机端可在「已归档」视图查看） */
  static confirmArchive(item: SessionView, onOk: () => void): void {
    AlertDialog.show({
      title: I18n.t('归档会话', 'Archive session'),
      message: I18n.t('归档「' + item.displayLabel() + '」？归档后从会话列表移除，可在"已归档"视图查看。', 'Archive ' + item.displayLabel() + '? It will leave the list; view it under Archived.'),
      primaryButton: { value: I18n.t('取消', 'Cancel'), action: () => { } },
      secondaryButton: {
        value: I18n.t('归档', 'Archive'),
        action: () => {
          onOk()
        }
      }
    })
  }

  /** 删除确认（不可恢复） */
  static confirmDelete(item: SessionView, onOk: () => void): void {
    AlertDialog.show({
      title: I18n.t('删除会话', 'Delete session'),
      message: I18n.t('删除「' + item.displayLabel() + '」？会从会话列表移除；数据由网关移入回收站（~/.dsh-remote/trash）。',
        'Delete ' + item.displayLabel() + '? It leaves the list; the gateway moves its data to a trash folder.'),
      primaryButton: { value: I18n.t('取消', 'Cancel'), action: () => { } },
      secondaryButton: {
        value: I18n.t('删除', 'Delete'),
        fontColor: Design.DANGER,
        action: () => {
          onOk()
        }
      }
    })
  }
}
