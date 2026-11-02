import { AppNav } from '../common/AppNav'
import { Theme, Design, sheetSpringBack } from '../models/Theme'

import { AppState } from '../services/AppState'
import { StorageService } from '../services/StorageService'
import { LiveViewService } from '../services/LiveViewService'
import { I18n } from '../common/I18n'
import { Constants } from '../common/Constants'
import { UiFeedback } from '../common/UiFeedback'

/**
 * 设置页：按功能分组的设置列表（鸿蒙设置风格）。
 *
 * 排版约定：


 * - 开关行（通知/后台轮询）与导航行（服务器管理等）行高一致，视觉密度统一
 * - 危险操作（重置本地数据）独立成组，红色标题
 */
@Component
export struct SettingsPage {
  @StorageLink('appState') appState: AppState = AppState.instance
  /** 深浅判定（AppState 写入）；变更驱动整页刷新 */
  @StorageLink('uiDark') uiDark: boolean = false
  /** 当前主题 id 原语（AppState 写入）；主题切换驱动整页刷新 */
  @StorageLink('uiTheme') uiTheme: string = 'deep-space'
  /** 后台轮询间隔原语（分钟，SettingsPage 写入）；副标题响应式刷新 */
  @StorageLink('bgInterval') bgInterval: number = Constants.DEFAULT_BG_INTERVAL_MIN
  /** 后台轮询间隔弹层 */
  @State showIntervalSheet: boolean = false
  @State intervalText: string = ''
  @State intervalNote: string = ''

  aboutToAppear(): void {
    // 首次进页把已存的间隔值播种进 AppStorage（@StorageLink 初值只是兜底默认）
    const raw = Number(StorageService.getString(Constants.KEY_BG_INTERVAL_MIN,
      Constants.DEFAULT_BG_INTERVAL_MIN.toString()))
    this.bgInterval = Number.isNaN(raw) || raw <= 0 ? Constants.DEFAULT_BG_INTERVAL_MIN : raw
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

  /**
   * 后台轮询状态描述。
   * 长时任务（continuous task）是否获批只能在退后台时得知，
   * 因此由 BackgroundService 把结果落盘，这里读上次结果。
   */
  private bgPollDesc(): string {
    if (this.loginExpired()) {
      return I18n.t('令牌已失效，后台轮询已停止（请重新扫码配对）', 'Token expired; background polling stopped (re-pair required)')
    }
    const state = StorageService.getString(Constants.KEY_CONTINUOUS_STATE, '')
    if (state === '1') {
      return I18n.t('退到后台后继续轮询审批 / 提问（长时任务已获批）', 'Keep polling approvals/questions in background (long task granted)')
    }
    if (state === '0') {
      return I18n.t('退到后台后尽力轮询；长时任务未获批，可能被系统挂起', 'Best-effort polling in background; long task not granted, may be suspended')
    }
    return I18n.t('退到后台后继续轮询审批 / 提问（受系统后台限制）', 'Keep polling approvals/questions in background (subject to system limits)')
  }

  private bgPollColor(): string {
    if (this.loginExpired()) {
      return Design.DANGER
    }
    return StorageService.getString(Constants.KEY_CONTINUOUS_STATE, '') === '1' ? Design.SUCCESS : Design.TEXT_SUB(this.uiDark)
  }

  /** 后台轮询间隔文案（分钟，可配；读 bgInterval 原语，保存后即时刷新） */
  private bgIntervalDesc(): string {
    const v = this.bgInterval > 0 ? this.bgInterval : Constants.DEFAULT_BG_INTERVAL_MIN
    return I18n.t('后台拉取最小间隔：', 'Background min interval: ') + (Math.round(v * 10) / 10).toString() + I18n.t(' 分钟', ' min')
  }

  private bgIntervalValue(): string {
    return (Math.round(this.bgInterval * 10) / 10).toString()
  }

  private applyBgInterval(value: string): void {
    const n = Number(value)
    if (Number.isNaN(n) || n < 0.2 || n > 60) {
      this.intervalNote = I18n.t('请输入 0.2 ~ 60 之间的分钟数', 'Enter minutes between 0.2 and 60')
      return
    }
    const v = Math.round(n * 10) / 10
    StorageService.putString(Constants.KEY_BG_INTERVAL_MIN, v.toString())
    // 间隔落 AppStorage 原语：BackgroundService 仍读存储键，副标题读原语即时刷新
    this.bgInterval = v
    this.intervalNote = ''
    this.showIntervalSheet = false
  }

  private loginExpired(): boolean {
    return StorageService.getString(Constants.KEY_LOGIN_EXPIRED, '') === '1'
  }

  build() {
    Column() {
      Row() {
        Row() {
          Text(I18n.t('设置', 'Settings'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Design.TEXT_MAIN(this.uiDark))
        Blank()
        Text(Constants.APP_VERSION)
          .fontSize(12)
          .fontColor(Design.TEXT_HINT(this.uiDark))
      }
        .width('100%')
        .constraintSize({ maxWidth: 720 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ left: Design.PAD_PAGE, right: Design.PAD_PAGE, top: 16 + Design.safeTop(), bottom: 12 })

      Scroll() {
        Row() {
          Column({ space: 8 }) {
          // ---- 通用：通知 / 后台轮询 ----
          this.groupLabel(I18n.t('通用', 'General'))
          this.generalGroup()

          // ---- 连接：服务器管理 ----
          this.groupLabel(I18n.t('连接', 'Connection'))
          this.connectionGroup()

          // ---- 危险区：重置本地数据 ----
          this.groupLabel(I18n.t('数据', 'Data'))
          this.dataGroup()
        }
          .width('100%')
          // 列表通栏：左右不留边距（行内自带 16 的文字缩进）；
          // 底部呼吸：手机形态的胶囊已由 Index 的 Tabs padding 让开，
          // 这里只要一点收尾空间（宽屏时会额外让开系统手势条）
          .padding({ bottom: Design.contentBottomInset() })
          .constraintSize({ maxWidth: 720 })
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
    .backgroundColor(this.pageBg())
    .bindSheet($$this.showIntervalSheet, this.intervalSheet(), {
      height: 240,
      showClose: true,
      title: { title: I18n.t('后台轮询间隔', 'Polling interval') },
      backgroundColor: this.cardBg(),
      // 下滑关闭带弹性回弹（未注册时官方无回弹行为）
      onWillSpringBackWhenDismiss: sheetSpringBack
    })
  }

  /** 后台轮询间隔输入弹层 */
  @Builder
  intervalSheet() {
    Column({ space: 12 }) {
      Text(I18n.t('每轮后台拉取的最小间隔（分钟）。到达事件时仍会立即返回，不受间隔影响。', 'Minimum interval (minutes) between background fetch rounds. Arriving events still return immediately; this only applies when idle.'))
        .fontSize(12)
        .fontColor(Design.TEXT_HINT(this.uiDark))
        .width('100%')
      TextInput({ text: $$this.intervalText, placeholder: I18n.t('0.2 ~ 60（分钟）', '0.2 – 60 (minutes)') })
        .height(42)
        .fontSize(14)
      if (this.intervalNote.length > 0) {
        Text(this.intervalNote)
          .fontSize(12)
          .fontColor(Design.DANGER)
          .width('100%')
      }
      Button(I18n.t('保存', 'Save'))
        .fontSize(15)
        .height(44)
        .width('100%')
        .backgroundColor(this.accent())
        .onClick(() => {
          this.applyBgInterval(this.intervalText)
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
  }

  /** 组标签：小号次级文字，与后卡片左缘对齐 */
  @Builder
  groupLabel(text: string) {
    Text(text)
      .fontSize(13)
      .fontColor(Design.TEXT_SUB(this.uiDark))
      .padding({ left: 16, right: 16 })
      .margin({ top: 12, bottom: 4 })
      .width('100%')
  }

  /** 通用组：通知 / 后台轮询开关行（整组一张卡片） */
  @Builder
  generalGroup() {
    Column() {
      this.switchRow(I18n.t('通知', 'Notifications'), I18n.t('审批 / 提问到达时本地提醒', 'Local alerts when approvals / questions arrive'), (): boolean => this.appState.notifyEnabled,
        (v: boolean) => {
          this.toggleNotify(v)
        })
      this.rowDivider()
      this.switchRow(I18n.t('后台轮询', 'Background polling'), I18n.t('退到后台后继续轮询审批 / 提问', 'Keep polling after backgrounding'),
        (): boolean => this.appState.backgroundPoll,
        (v: boolean) => {
          this.appState.setBackgroundPoll(v)
        }, (): string => this.bgPollDesc(), (): string => this.bgPollColor())
      this.rowDivider()
      this.switchRow(I18n.t('实况窗', 'Live View'), I18n.t('任务运行时在锁屏 / 状态栏展示进度胶囊', 'Show progress capsule on lock screen / status bar while a task runs'),
        (): boolean => LiveViewService.isEnabled(),
        (v: boolean) => {
          LiveViewService.setEnabled(v)
        })
      this.rowDivider()
      this.navRow((): string => this.bgIntervalDesc(), I18n.t('打开输入弹层修改', 'Tap to edit'), () => {
        this.intervalText = this.bgIntervalValue()
        this.intervalNote = ''
        this.showIntervalSheet = true
      })
    }
    .width('100%')
    .backgroundColor(this.cardBg())
  }

  /**
   * 通知开关：乐观更新（开关立即翻转），权限申请失败自动回退并提示。
   */
  private async toggleNotify(enabled: boolean): Promise<void> {
    const prev = this.appState.notifyEnabled
    this.appState.notifyEnabled = enabled
    const ok = await this.appState.setNotifyEnabled(enabled)
    if (!ok) {
      this.appState.notifyEnabled = prev
      this.toast(I18n.t('未获得通知权限，开关已还原；请在系统设置中允许本应用发送通知', 'Notification permission denied; toggle reverted. Allow notifications in system settings'))
    }
  }

  /**
   * 后台轮询开关：乐观更新；开启需要通知权限（提醒依赖通知），失败自动回退并提示。
   */
  private async toggleBgPoll(enabled: boolean): Promise<void> {
    const prev = this.appState.backgroundPoll
    this.appState.backgroundPoll = enabled
    const ok = await this.appState.setBackgroundPoll(enabled)
    if (!ok) {
      this.appState.backgroundPoll = prev
      this.toast(I18n.t('未获得通知权限，后台轮询已还原；审批 / 提问提醒依赖通知', 'Notification permission denied; polling reverted. Approvals / questions depend on notifications'))
    }
  }

  /** 轻提示（自动消失，不打断操作）；统一走 UiFeedback */
  private toast(msg: string): void {
    UiFeedback.toast(this.getUIContext(), msg, 3500)
  }

  /** 连接组：服务器管理 / 扫码配对导航行 */
  @Builder
  connectionGroup() {
    Column() {
      this.navRow(I18n.t('服务器与配对', 'Servers & pairing'), (): string => this.serverSubtitle(), () => {
        AppNav.push(AppNav.R_SERVERS)
      })
    }
    .width('100%')
    .backgroundColor(this.cardBg())
  }

  /** 数据组：重置本地数据（危险操作） */
  @Builder
  dataGroup() {
    Column() {
      this.navRow(I18n.t('重置本地数据', 'Reset local data'), I18n.t('清除已保存的服务器与令牌，不可恢复', 'Erase saved servers and tokens; irreversible'), () => {
        this.confirmReset()
      }, Design.DANGER)
    }
    .width('100%')
    .backgroundColor(this.cardBg())
  }

  /** 行间分割线：左侧缩进与标题文字对齐（鸿蒙列表惯例） */
  @Builder
  rowDivider() {
    Divider()
      .color(Design.FILL_LIGHT(this.uiDark))
      .strokeWidth(0.5)
      .margin({ left: 16 })
  }

  /**
   * 开关行：主标题 + 可选多行说明，右侧开关。
   * value 通过 getValue 闭包读取（@Builder 按值传参不建立依赖，
   * 且 appState 实例属性变更不推送 UI——闭包保证每次渲染取最新值）。
   * 副标题/颜色同样用闭包：按值传 string 在重渲染时不更新（viewChip 同坑）。
   */
  @Builder
  switchRow(title: string, desc: string, getValue: () => boolean, onChange: (v: boolean) => void,
    getSubDesc?: () => string, getSubColor?: () => string) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Design.TEXT_MAIN(this.uiDark))
        Text(getSubDesc !== undefined && getSubDesc().length > 0 ? getSubDesc() : desc)
          .fontSize(13)
          .lineHeight(19)
          .fontColor(getSubColor !== undefined && getSubColor().length > 0 ? getSubColor() : Design.TEXT_SUB(this.uiDark))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 系统 Toggle：selectedColor 用主题强调色（官方 ts-basic-components-toggle 文档）
      Toggle({ type: ToggleType.Switch, isOn: getValue() })
        .selectedColor(this.accent())
        .onChange((v: boolean) => {
          onChange(v)
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
  }

  /**
   * 胶囊选择行：标题 + 说明 + 胶囊选项组（单选）。
   * options 形如 [[value, label], ...]。
   * current 通过 getCurrent 闭包读取（@Builder 按值传参不建立依赖，
   * 直接传值会导致选中态在状态变化后不刷新）。
   */
  @Builder
  pillRow(title: string, options: string[][], getCurrent: () => string, onPick: (v: string) => void,
    note: string) {
    Column({ space: 10 }) {
      if (title.length > 0) {
        Text(title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Design.TEXT_MAIN(this.uiDark))
          .width('100%')
      }
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(options, (opt: string[]) => {
          Text(opt[1])
            .fontSize(14)
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .backgroundColor(getCurrent() === opt[0] ? this.accent() : Design.FILL_LIGHT(this.uiDark))
            .fontColor(getCurrent() === opt[0] ? Color.White : Design.TEXT_MAIN(this.uiDark))
            .borderRadius(Design.RADIUS_PILL)
            .margin({ right: 8, bottom: 4 })
            .animation({ curve: Design.pressCurve })
            .onClick(() => {
              onPick(opt[0])
            })
        }, (opt: string[]) => opt[0] + opt[1])
      }
      .width('100%')
      if (note.length > 0) {
        Text(note)
          .fontSize(12)
          .fontColor(Design.TEXT_HINT(this.uiDark))
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
  }

  /**
   * 导航行：标题 + 说明，右侧箭头（用字符，避免新增图标资源）。
   * title/desc 支持传闭包（动态副标题随状态即时刷新；静态字符串调用点不受影响）。
   */
  @Builder
  navRow(title: string | (() => string), desc: string | (() => string), action: () => void, titleColor?: string) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(typeof title === 'function' ? title() : title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(titleColor !== undefined && titleColor.length > 0 ? titleColor : Design.TEXT_MAIN(this.uiDark))
        Text(typeof desc === 'function' ? desc() : desc)
          .fontSize(13)
          .lineHeight(19)
          .fontColor(Design.TEXT_SUB(this.uiDark))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('›')
        .fontSize(20)
        .fontColor(Design.TEXT_HINT(this.uiDark))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .onClick(() => {
      action()
    })
  }

  /** 当前服务器摘要（连接组副标题） */
  private serverSubtitle(): string {
    const s = this.appState.server
    if (!s) {
      return I18n.t('未配置服务器', 'No server configured')
    }
    const count = this.appState.servers.length
    const hostPart = s.host.length > 0 ? s.host + ' · ' : ''
    return (count > 1 ? count.toString() + I18n.t(' 个服务器 · ', ' servers · ') : '') +
      hostPart + s.normalizedUrl()
  }

  private confirmReset(): void {
    AlertDialog.show({
      title: I18n.t('确认重置', 'Confirm reset'),
      message: I18n.t('将清除本地全部服务器配置与令牌，不可恢复。', 'This erases all saved server configs and tokens on this device. Irreversible.'),
      primaryButton: {
        value: I18n.t('取消', 'Cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: I18n.t('重置', 'Reset'),
        action: () => {
          this.appState.stopRealtime()
          StorageService.deleteKey('servers_v2')
          this.appState.servers = []
          this.appState.server = null
          this.appState.health = null
          this.appState.sessions = []
          this.appState.mode = 'idle'
          this.appState.statusText = I18n.t('未连接', 'Not connected')
        }
      }
    })
  }

}
