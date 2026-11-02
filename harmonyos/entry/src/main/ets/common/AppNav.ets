import { router } from '@kit.ArkUI'
import { Breakpoint } from './Breakpoint'

/** 路由参数（显式类满足 arkts-no-untyped-obj-literals） */
export class NavParams {
  /** 会话详情：目标会话 id */
  sessionId: string = ''
  /** 服务器管理：进入时自动打开扫码 */
  openScan: boolean = false
  /** 服务器编辑页：要编辑的服务器 id（空 = 新增） */
  serverId: string = ''
}

/** router.pushUrl 参数（显式类满足 arkts-no-untyped-obj-literals） */
class RouterTarget {
  url: string = ''
  params?: Object = undefined
}

/**
 * 模式感知导航 helper：页面统一经它跳转/返回，不再直接调用 router.*。
 *
 * - 手机（uiWide=false）：走系统 router（pages/* 注册页），行为与改造前完全一致。
 * - 平板（uiWide=true）：走 TabletIndex 挂载的 NavPathStack——
 *   侧栏主视图（主页/文件/插件/设置）用 replacePathByName 替换栈顶（栈内
 *   始终只有一个主视图），子页面（公告/服务器管理/反馈/ASR）用 pushPathByName
 *   叠加在当前视图之上，返回逐层 pop。
 *
 * NavPathStack API 出处：
 * developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-navigation
 * （pushPathByName10+ / replacePathByName11+ / pop10+ / size10+）
 */
export class AppNav {
  /** 平板导航栈；TabletIndex 挂载时注册（aboutToAppear），卸载即失效 */
  static tabletStack: NavPathStack | null = null

  /** 路由名常量：与 router 的 pages/<name> 名称复用，navDestination builder 同名映射 */
  static readonly R_CHAT: string = 'ChatPage'
  /**
   * 平板右栏会话路由名前缀：真实路由名 = 前缀 + sessionId。
   * 每个会话一个唯一名字，replace 时才会新建 NavDestination/ChatView 实例
   * （同名 replace 会复用实例，ChatView 的实时回调只在 aboutToDisappear 注销，
   * 复用会让新旧会话串流）。
   */
  static readonly CHAT_ROUTE_PREFIX: string = 'ChatPage#'
  static readonly R_SERVERS: string = 'ServerSettingsPage'
  static readonly R_SERVER_EDIT: string = 'ServerEditPage'
  static readonly R_HOME: string = 'tabletHome'
  static readonly R_SETTINGS: string = 'tabletSettings'

  /** 打开子页面：手机 router.pushUrl；平板栈上叠加 */
  static push(name: string, params?: NavParams): void {
    if (Breakpoint.isWide() && AppNav.tabletStack !== null) {
      AppNav.tabletStack.pushPathByName(name, params as Object ?? new NavParams())
    } else {
      const target = new RouterTarget()
      target.url = 'pages/' + name
      if (params !== undefined) {
        target.params = params as Object
      }
      router.pushUrl(target)
        .catch(() => {
        })
    }
  }

  /** 关闭当前页：手机 router.back；平板 pop 栈顶 */
  static back(): void {
    if (Breakpoint.isWide() && AppNav.tabletStack !== null) {
      AppNav.tabletStack.pop()
    } else {
      router.back()
    }
  }

  /**
   * 打开服务器编辑页（新增 / 编辑）。
   *
   * id 经 AppStorage('serverEditId') 传递而非栈 param：navDestination builder
   * 构建时机早于参数入栈索引，getParamByName 会查到空值（openChat 踩过同样的坑）。
   * 手机 router 与平板 NavPathStack 共用同一条路径，页面侧只读 AppStorage。
   */
  static openServerEditor(serverId: string): void {
    AppStorage.setOrCreate('serverEditId', serverId)
    const p = new NavParams()
    p.serverId = serverId
    AppNav.push(AppNav.R_SERVER_EDIT, p)
  }

  /** 平板侧栏主视图切换：空栈 push，非空栈 replacePathByName（替换栈顶） */
  static switchMain(name: string): void {
    const stack = AppNav.tabletStack
    if (stack === null) {
      return
    }
    if (stack.size() === 0) {
      stack.pushPathByName(name, new NavParams())
    } else {
      stack.replacePathByName(name, new NavParams())
    }
  }

  /**
   * 平板打开会话：按「主视图切换」处理（replace），路由名带 sessionId 后缀
   * 以强制新建 ChatView 实例（同名 replace 会复用实例 → 新旧会话串流）。
   *
   * sessionId 经 AppStorage('tabletChatSession') 传递而非栈 param 反查：
   * navDestination builder 执行早于 push 参数入栈索引，
   * getParamByName 在构建时刻查到空值，导致右栏 ChatView 拿到空
   * sessionId、不加载任何消息（点会话只显示空壳的 bug）。
   * AppStorage 先写后 push，builder 构建时必然读到正确值。
   */
  static openChat(sessionId: string): void {
    const stack = AppNav.tabletStack
    if (stack === null) {
      return
    }
    AppStorage.setOrCreate('tabletChatSession', sessionId)
    const p = new NavParams()
    p.sessionId = sessionId
    // 宽屏右栏是「主视图」不是子页：用 replace（系统交叉淡入、没有返回层级），
    // 不再 clear + push（那是抽屉式子页的语义，还自带返回按钮）。
    const route = AppNav.CHAT_ROUTE_PREFIX + sessionId
    if (stack.size() === 0) {
      stack.pushPathByName(route, p)
    } else {
      stack.replacePathByName(route, p)
    }
  }
}
