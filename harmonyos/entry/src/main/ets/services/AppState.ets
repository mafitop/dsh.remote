import { common } from '@kit.AbilityKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { ServerInfo } from '../models/ServerInfo'
import { HealthInfo } from '../models/HealthInfo'
import { SessionView } from '../models/SessionView'
import { StatsDay } from '../models/StatsDay'
import { PendingApproval, PendingQuestion } from '../models/PendingItem'
import { ApproveValue, AnswerItem, AnswerBody, AnswerValue } from '../models/RpcPayloads'
import { SessionCreatePayload, SessionRenamePayload } from '../models/RpcPayloads'
import { WorkspaceInfo } from '../models/WorkspaceInfo'
import { Theme } from '../models/Theme'
import { Constants } from '../common/Constants'
import { Logger } from '../common/Logger'
import { I18n } from '../common/I18n'
import { StorageService } from './StorageService'
import { GatewayApi } from './GatewayApi'
import { RealtimeService } from './RealtimeService'
import { NotificationService } from './NotificationService'
import { PairParser } from './PairParser'
import { HandoffState } from '../models/HandoffState'

/**
 * 会话事件回调（ChatPage 注册；payload 中的 event 对象）。
 */
export type ChatEventSink = (ev: Record<string, Object>) => void

/** 会话投影回调（ChatPage 注册；该会话 projection 合并后的 values 快照） */
export type ProjectionSink = (values: Record<string, Object>) => void

/**
 * 全局可观察状态：当前服务器、健康、会话、连接模式。
 * 组件通过 @StorageLink('appState') 绑定（EntryAbility 中已 setOrCreate）。
 */
@Observed
export class AppState {
  static readonly instance: AppState = new AppState()

  server: ServerInfo | null = null
  /** 每次选择/重新配对递增；即使 A→B→A 也不能复用旧确认与回执。 */
  connectionGeneration: number = 0

  /** 仅作内存内身份比较，包含令牌；不得记录到日志或持久化。 */
  connectionContext(): string {
    const s = this.server
    return JSON.stringify([this.connectionGeneration, s ? s.id : '',
      s ? s.normalizedUrl() : '', s ? s.token : ''])
  }
  servers: ServerInfo[] = []
  health: HealthInfo | null = null
  /** idle | connecting | ws | poll | error */
  mode: string = 'idle'
  statusText: string = I18n.t('未连接', 'Not connected')
  /** 顶层会话（按 updatedAt 倒序） */
  sessions: SessionView[] = []
  /** 会话列表首次加载中（骨架屏判定：仅首拉显示，刷新/失败回落空态或数据） */
  sessionsLoading: boolean = false
  /** 统计首次加载中（统计页骨架屏判定） */
  statsLoading: boolean = false
  /** 网关返回的会话总数（含子代理），用于诊断展示 */
  totalSessionCount: number = 0
  totalTokens7d: number = 0
  statsText: string = ''
  statsDays: StatsDay[] = []
  lastError: string = ''
  initialized: boolean = false
  /** 当前打开的会话 id（ChatPage 设置） */
  activeSessionId: string = ''
  /** ChatPage 注册的会话事件回调 */
  chatSink: ChatEventSink | null = null
  /** ChatPage 注册的会话投影回调（goal/todo/统计卡片） */
  projectionSink: ProjectionSink | null = null
  /** 每会话 projection 序号（去旧保新，对齐 Web 端 asOfSeq 语义） */
  private projectionSeq: Map<string, number> = new Map()
  /** 每会话 projection 合并值（sessionId → values；goal/todos/sessionStats/...） */
  private projectionValues: Map<string, Record<string, Object>> = new Map()
  /** 待处理的工具审批 */
  pendingApprovals: PendingApproval[] = []
  /** 待处理的用户提问 */
  pendingQuestions: PendingQuestion[] = []
  /** 通知开关 */
  notifyEnabled: boolean = false
  /** 当前主题 id */
  /** 固定深空主题 */
  themeId: string = Constants.DEFAULT_THEME
  /** 深色模式：system 跟随系统 / light 常浅 / dark 常深 */
  /** 固定浅色模式 */
  darkMode: string = Constants.DARK_LIGHT
  /** 后台轮询开关 */
  backgroundPoll: boolean = false
  /** 工作区列表（workspace.list，建会话时选择用） */
  workspaces: WorkspaceInfo[] = []
  /** 新建会话选中的工作区（持久化，手机与折叠屏侧栏共用） */
  selectedWorkspaceId: string = ''
  /** 已归档会话 id（workspace.list.archivedSessionIds，与 Web 端 wbArchived 一致） */
  archivedSessionIds: string[] = []
  /** 跨端接续指针（网关 /handoff；已排除本设备写入的记录） */
  handoff: HandoffState | null = null

  private refreshTimer: number = -1
  private lastHealthAt: number = 0
  /** host 探测每启动一次即可（失败的记录留给下次启动再试） */
  private hostProbeDone: boolean = false

  init(context: common.UIAbilityContext): void {
    if (this.initialized) {
      return
    }
    StorageService.init(context)
    // 系统语言判定（无应用内切换，跟随系统；变更下次启动生效）
    I18n.init()
    this.servers = StorageService.getServers()
    this.notifyEnabled = StorageService.getString(Constants.KEY_NOTIFY, '') === '1'
    this.backgroundPoll = StorageService.getString(Constants.KEY_BG_POLL, '') === '1'
    this.selectedWorkspaceId = StorageService.getString(Constants.KEY_SELECTED_WORKSPACE, '')
    const activeId = StorageService.getActiveServerId()
    this.applyActiveServer(activeId, true)
    // 深浅判定落 AppStorage：必须在首帧前完成，否则 Design.isDark() 读不到值
    AppStorage.setOrCreate('systemDark', false)
    this.syncThemeStorage()
    this.initialized = true
  }

  /** 手动切换当前服务器并持久化 */
  setCurrentServer(id: string): boolean {
    for (const s of this.servers) {
      if (s.id === id) {
        StorageService.setActiveServerId(id)
        this.applyActiveServer(id, true)
        return true
      }
    }
    return false
  }

  private applyActiveServer(id: string, startRealtime: boolean): void {
    let found: ServerInfo | null = null
    for (const s of this.servers) {
      if (s.id === id) {
        found = s
        break
      }
    }
    this.server = found
    this.connectionGeneration++
    AppStorage.setOrCreate('connectionGeneration', this.connectionGeneration)
    if (!found) {
      this.mode = 'idle'
      this.statusText = I18n.t('未连接', 'Not connected')
      this.health = null
      this.sessions = []
      return
    }
    this.mode = 'connecting'
    this.statusText = I18n.t('连接 ', 'Connecting ') + found.normalizedUrl()
    this.lastError = ''
    this.refreshHealth()
    this.refreshSessions()
    if (startRealtime) {
      this.startRealtime()
    }
  }

  private startRealtime(): void {
    const s = this.server
    if (!s) {
      return
    }
    const clientId = StorageService.getOrCreateClientId()
    RealtimeService.getInstance().start(s.normalizedUrl(), s.token, clientId,
      (kind: string, frame: string) => {
        AppState.instance.handleFrame(kind, frame)
      },
      (m: string) => {
        AppState.instance.onModeChanged(m)
      })
  }

  private onModeChanged(m: string): void {
    this.mode = m
    // 供 ChatView 之类的页面观察「断线→重连」跳变，做历史对账
    AppStorage.setOrCreate('connMode', m)
    if (m === 'ws') {
      this.statusText = I18n.t('实时已连接', 'Realtime connected')
    } else if (m === 'poll') {
      this.statusText = I18n.t('轮询模式', 'Polling mode')
    } else if (m === 'connecting') {
      this.statusText = this.server ? I18n.t('连接 ', 'Connecting ') + this.server.normalizedUrl() : I18n.t('连接中', 'Connecting')
    } else if (m === 'error') {
      this.statusText = I18n.t('连接失败', 'Connection failed')
    } else {
      this.statusText = I18n.t('未连接', 'Not connected')
    }
    this.refreshHealth()
  }

  stopRealtime(): void {
    RealtimeService.getInstance().stop()
    this.mode = 'idle'
    this.statusText = I18n.t('未连接', 'Not connected')
  }

  /** 实时帧入口：会话事件转发给 ChatPage，审批/提问进入待处理列表 */
  handleFrame(kind: string, frame: string): void {
    if (frame.length === 0) {
      return
    }
    let full: Record<string, Object> | null = null
    try {
      full = JSON.parse(frame) as Record<string, Object>
    } catch (e) {
      return
    }
    const payload = full['payload'] as Record<string, Object>
    if (!payload) {
      return
    }
    const type = String(payload['type'] ?? '')

    if (kind === 'mux' && type === 'session/event') {
      const sid = String(payload['sessionId'] ?? '')
      const ev = payload['event'] as Record<string, Object>
      if (sid.length > 0 && sid === this.activeSessionId && ev && this.chatSink) {
        this.chatSink(ev)
      }
      return
    }
    // 网关把 DSH 0.1.5 assistant-stream 折叠成 session/reasoning 基线广播
    // （payload 携带 partialReasoning: 流式思考块数组，见 gateway.js modernReasoningValue）。
    // 交给当前会话的 chatSink；ChatPage 用它恢复「思考中」气泡（切后台/晚加入场景）。
    if (kind === 'mux' && type === 'session/reasoning') {
      const sid = String(payload['sessionId'] ?? '')
      if (sid.length > 0 && sid === this.activeSessionId && this.chatSink) {
        this.chatSink(payload)
      }
      return
    }
    if (kind === 'mux' && type === 'approval/requested') {
      const rpcId = String(full['rpcId'] ?? '')
      const approvalId = String(payload['approvalId'] ?? '')
      const sessionId = String(payload['sessionId'] ?? '')
      const toolName = String(payload['toolName'] ?? '工具')
      const summary = String(payload['summary'] ?? '')
      let exists = false
      for (const a of this.pendingApprovals) {
        if (a.approvalId === approvalId && a.rpcId === rpcId) {
          exists = true
          break
        }
      }
      if (!exists) {
        this.pendingApprovals = [...this.pendingApprovals,
          new PendingApproval(rpcId, sessionId, approvalId, toolName, summary)]
        if (this.notifyEnabled) {
          NotificationService.notifyApproval(toolName)
        }
      }
      return
    }
    if (kind === 'mux' && type === 'approval/resolved') {
      const approvalId = String(payload['approvalId'] ?? '')
      this.pendingApprovals = this.pendingApprovals.filter((a) => a.approvalId !== approvalId)
      return
    }
    if (kind === 'mux' && type === 'question/requested') {
      const rpcId = String(full['rpcId'] ?? '')
      const sessionId = String(payload['sessionId'] ?? '')
      const questions = payload['questions'] as Array<Record<string, Object>> ?? []
      const title = questions.length > 0 ?
        String(questions[0]['question'] ?? '') : I18n.t('待回答', 'Pending answer')
      let exists = false
      for (const q of this.pendingQuestions) {
        if (q.rpcId === rpcId) {
          exists = true
          break
        }
      }
      if (!exists) {
        this.pendingQuestions = [...this.pendingQuestions,
          new PendingQuestion(rpcId, sessionId, questions, title)]
        if (this.notifyEnabled) {
          NotificationService.notifyQuestion(title)
        }
      }
      return
    }
    if (kind === 'mux' && type === 'question/resolved') {
      const rpcId = String(payload['questionRpcId'] ?? '')
      this.pendingQuestions = this.pendingQuestions.filter((q) => q.rpcId !== rpcId)
      return
    }
    if (kind === 'mux' && type === 'session/projection') {
      // 投影增量（goal/todos/sessionStats/...）：合并进快照并通知当前会话页
      this.applyProjection(
        String(payload['sessionId'] ?? ''),
        String(payload['key'] ?? ''),
        payload['value'] as Object,
        Number(payload['seq'] ?? 0))
      return
    }
    // host 通道会话状态变化 → 刷新列表
    this.scheduleRefresh()
  }

  /** 投影合并：seq 回退丢弃；当前会话变化时通知 ChatPage 重渲染卡片 */
  private applyProjection(sessionId: string, key: string, value: Object, seq: number): void {
    if (sessionId.length === 0 || key.length === 0) {
      return
    }
    const current = this.projectionSeq.get(sessionId) ?? 0
    if (seq > 0 && seq < current) {
      return
    }
    this.projectionSeq.set(sessionId, Math.max(seq, current))
    let values = this.projectionValues.get(sessionId)
    if (!values) {
      values = {}
    }
    const next: Record<string, Object> = {}
    for (const k of Object.keys(values)) {
      next[k] = values[k]
    }
    next[key] = value
    this.projectionValues.set(sessionId, next)
    if (sessionId === this.activeSessionId && this.projectionSink) {
      this.projectionSink(next)
    }
  }

  /** 会话 projection 合并快照（无数据返回空对象，不共享内部引用） */
  projectionOf(sessionId: string): Record<string, Object> {
    const values = this.projectionValues.get(sessionId)
    if (!values) {
      return {}
    }
    const out: Record<string, Object> = {}
    for (const k of Object.keys(values)) {
      out[k] = values[k]
    }
    return out
  }

  /** 会话 projection 序列号比较（ChatPage 合并 session.list 初值用） */
  projectionSeqOf(sessionId: string): number {
    return this.projectionSeq.get(sessionId) ?? 0
  }

  /** 会话离开时清掉内存快照（历史数据以服务器为准） */
  clearProjection(sessionId: string): void {
    this.projectionSeq.delete(sessionId)
    this.projectionValues.delete(sessionId)
  }

  /** 归档会话（workspace.archiveSession，与 Web 端 sc-archive-btn 一致） */
  async archiveSession(sessionId: string): Promise<boolean> {
    const s = this.server
    if (!s) {
      return false
    }
    try {
      const payload: Record<string, Object> = { 'sessionId': sessionId }
      await GatewayApi.rpc(s.normalizedUrl(), s.token, 'workspace.archiveSession', payload)
      if (this.archivedSessionIds.indexOf(sessionId) < 0) {
        this.archivedSessionIds = [...this.archivedSessionIds, sessionId]
      }
      await this.refreshSessions()
      await this.refreshWorkspaces()
      return true
    } catch (e) {
      this.lastError = I18n.t('归档失败：', 'Archive failed: ') + (e as Error).message
      return false
    }
  }

  /** 取消归档（workspace.archiveSession 反向语义由 DSH 侧处理；失败静默提示） */
  async unarchiveSession(sessionId: string): Promise<boolean> {
    const s = this.server
    if (!s) {
      return false
    }
    try {
      const payload: Record<string, Object> = { 'sessionId': sessionId, 'archived': false }
      await GatewayApi.rpc(s.normalizedUrl(), s.token, 'workspace.archiveSession', payload)
      this.archivedSessionIds = this.archivedSessionIds.filter((id: string) => id !== sessionId)
      await this.refreshSessions()
      await this.refreshWorkspaces()
      return true
    } catch (e) {
      this.lastError = I18n.t('取消归档失败：', 'Unarchive failed: ') + (e as Error).message
      return false
    }
  }

  /**
   * 删除会话（session.delete）。网关 ADAPTIVE_RPC_METHODS 当前未收录该方法，
   * 调用会返回 legacy fallback 错误——UI 层据此提示「暂不支持」，待网关/DSH
   * 暴露删除能力后本方法无需改动即可生效。
   */
  async deleteSession(sessionId: string): Promise<boolean> {
    const s = this.server
    if (!s) {
      return false
    }
    try {
      const payload: Record<string, Object> = { 'sessionId': sessionId }
      await GatewayApi.rpc(s.normalizedUrl(), s.token, 'session.delete', payload)
      await this.refreshSessions()
      await this.refreshWorkspaces()
      return true
    } catch (e) {
      this.lastError = I18n.t('删除失败：', 'Delete failed: ') + (e as Error).message
      return false
    }
  }

  /**
   * 设置本地通知开关并持久化。
   * 乐观更新：调用方先翻开关；开启时若通知权限申请失败则回退并返回 false。
   */
  async setNotifyEnabled(enabled: boolean): Promise<boolean> {
    this.notifyEnabled = enabled
    if (enabled) {
      const granted = await NotificationService.requestPermission()
      if (!granted) {
        this.notifyEnabled = false
        StorageService.putString(Constants.KEY_NOTIFY, '0')
        return false
      }
    }
    StorageService.putString(Constants.KEY_NOTIFY, enabled ? '1' : '0')
    return true
  }

  /** 设置通知开关（不回退版本，权限申请失败时保持开启但通知不可用） */
  async setNotifyEnabledUnchecked(enabled: boolean): Promise<void> {
    this.notifyEnabled = enabled
    StorageService.putString(Constants.KEY_NOTIFY, enabled ? '1' : '0')
    if (enabled) {
      await NotificationService.requestPermission()
    }
  }

  /** 系统色模式变化时回调（EntryAbility.onConfigurationUpdate） */
  onSystemDarkChange(systemDark: boolean): void {
    if (this.darkMode === Constants.DARK_SYSTEM) {
      this.syncThemeStorage()
    }
  }

  /** 当前主题下应使用的深浅判定，写入 AppStorage 供 Design 与页面读取 */
  private syncThemeStorage(): void {
    const dark = this.darkMode === Constants.DARK_DARK ||
      (this.darkMode === Constants.DARK_SYSTEM && AppStorage.get<boolean>('systemDark') === true)
    AppStorage.setOrCreate('uiDark', dark)
    AppStorage.setOrCreate('uiTheme', this.themeId)
  }

  /**
   * 设置后台轮询开关并持久化。
   * 轮询本身是本地定时器必然可用，但审批/提问提醒依赖通知权限——
   * 开启时若通知未授权则回退开关并返回 false，由调用方提示。
   */
  async setBackgroundPoll(enabled: boolean): Promise<boolean> {
    if (enabled) {
      const granted = await NotificationService.requestPermission()
      if (!granted) {
        return false
      }
    }
    this.backgroundPoll = enabled
    StorageService.putString(Constants.KEY_BG_POLL, enabled ? '1' : '0')
    return true
  }

  /** 工具审批：允许 / 拒绝 */
  async approveApproval(approvalId: string, allow: boolean): Promise<boolean> {
    const s = this.server
    if (!s) {
      return false
    }
    let target: PendingApproval | null = null
    for (const a of this.pendingApprovals) {
      if (a.approvalId === approvalId) {
        target = a
        break
      }
    }
    if (!target) {
      return false
    }
    try {
      const value: ApproveValue = {
        sessionId: target.sessionId,
        approvalId: target.approvalId,
        outcome: allow ? 'allowed-once' : 'rejected'
      }
      const ok = await GatewayApi.respond(s.normalizedUrl(), s.token, target.rpcId, value)
      this.pendingApprovals = this.pendingApprovals.filter((a) => a.approvalId !== approvalId)
      return ok
    } catch (e) {
      Logger.warn('approve failed: ' + (e as Error).message)
      return false
    }
  }

  /** 用户提问：提交回答（answers: [{id, selected[], custom?}]） */
  async answerQuestion(rpcId: string, answers: Array<AnswerItem>): Promise<boolean> {
    const s = this.server
    if (!s) {
      return false
    }
    let target: PendingQuestion | null = null
    for (const q of this.pendingQuestions) {
      if (q.rpcId === rpcId) {
        target = q
        break
      }
    }
    if (!target) {
      return false
    }
    try {
      const body: AnswerBody = { answers: answers }
      const value: AnswerValue = { sessionId: target.sessionId, answer: body }
      const ok = await GatewayApi.respond(s.normalizedUrl(), s.token, target.rpcId, value)
      this.pendingQuestions = this.pendingQuestions.filter((q) => q.rpcId !== rpcId)
      return ok
    } catch (e) {
      Logger.warn('answer failed: ' + (e as Error).message)
      return false
    }
  }

  private scheduleRefresh(): void {
    if (this.refreshTimer >= 0) {
      clearTimeout(this.refreshTimer)
    }
    this.refreshTimer = setTimeout(() => {
      this.refreshTimer = -1
      this.refreshSessions()
    }, 600)
  }

  async refreshHealth(): Promise<void> {
    const s = this.server
    if (!s) {
      return
    }
    const now = Date.now()
    if (now - this.lastHealthAt < 3000) {
      return
    }
    this.lastHealthAt = now
    try {
      const h = await GatewayApi.getHealth(s.normalizedUrl())
      this.health = h
      if (h.host.length > 0 && h.host !== s.host) {
        // 顺手记下「这个 IP 是哪台机器」：只更新当前服务器这一条，变化时才持久化
        const list: ServerInfo[] = []
        for (const item of this.servers) {
          list.push(item.id === s.id
            ? new ServerInfo(item.id, item.url, item.note, item.group, item.token, h.host)
            : item)
        }
        this.servers = list
        StorageService.saveServers(list)
        // this.server 是同一份数据的另一个引用，换了对象要跟着换，否则当前服务器卡片读不到 host
        const cur = this.server
        if (cur !== null) {
          for (const item of list) {
            if (item.id === cur.id) {
              this.server = item
              break
            }
          }
        }
      }
      if (this.mode === 'connecting' || this.mode === 'idle') {
        this.mode = 'connecting'
      }
    } catch (e) {
      this.health = null
      this.lastError = I18n.t('网关不可达：', 'Gateway unreachable: ') + s.normalizedUrl()
      Logger.warn(this.lastError)
    }
  }

  /**
   * 补齐各服务器的 host（列表按主机分组用）。
   * host 来自 /health（免鉴权）：并发探测、只探还没有 host 的记录、每次启动最多跑一轮，
   * 单台失败就跳过（下次启动再试），避免每次打开列表都等一堆超时。
   */
  async probeServerHosts(): Promise<void> {
    if (this.hostProbeDone) {
      return
    }
    this.hostProbeDone = true
    const pending: ServerInfo[] = []
    for (const s of this.servers) {
      if (s.host.length === 0) {
        pending.push(s)
      }
    }
    if (pending.length === 0) {
      return
    }
    const found: Map<string, string> = new Map()
    await Promise.all(pending.map(async (s: ServerInfo) => {
      try {
        const h = await GatewayApi.getHealth(s.normalizedUrl(), 4000)
        if (h.host.length > 0) {
          found.set(s.id, h.host)
        }
      } catch (e) {
        // 单台不可达/旧版本：跳过（手机没连 tailnet 时 100.x 就会留空，属预期）
      }
    }))
    if (found.size === 0) {
      return
    }
    const list: ServerInfo[] = []
    for (const item of this.servers) {
      const host = found.get(item.id)
      list.push(host === undefined
        ? item
        : new ServerInfo(item.id, item.url, item.note, item.group, item.token, host))
    }
    this.servers = list
    StorageService.saveServers(list)
    const cur = this.server
    if (cur !== null) {
      for (const item of list) {
        if (item.id === cur.id && item.host !== cur.host) {
          this.server = item
          break
        }
      }
    }
  }

  async refreshSessions(): Promise<void> {
    const s = this.server
    if (!s || s.token.length === 0) {
      return
    }
    const firstLoad = this.sessions.length === 0 && !this.sessionsLoading
    if (firstLoad) {
      this.sessionsLoading = true
    }
    try {
      const empty: Record<string, Object> = {}
      const value = await GatewayApi.rpc(s.normalizedUrl(), s.token, 'session.list', empty)
      // session.list 项内的 projections 是初始快照（对齐 Web 端 hydrateSessionProjections）
      SessionView.hydrateProjections(value,
        (sessionId: string, seq: number, values: Record<string, Object>) => {
          const current = this.projectionSeq.get(sessionId) ?? 0
          if (seq >= current) {
            this.projectionSeq.set(sessionId, seq)
            this.projectionValues.set(sessionId, values)
            if (sessionId === this.activeSessionId && this.projectionSink) {
              this.projectionSink(this.projectionOf(sessionId))
            }
          }
        })
      // 只展示顶层会话（过滤子代理），按最近活动倒序
      const all = SessionView.fromRpcValue(value)
      const top: SessionView[] = []
      for (const item of all) {
        if (item.isTopLevel() && item.sessionId.length > 0) {
          top.push(item)
        }
      }
      top.sort((a: SessionView, b: SessionView) => b.updatedAt - a.updatedAt)
      this.sessions = top
      this.totalSessionCount = all.length
      this.lastError = ''
      this.sessionsLoading = false
    } catch (e) {
      const msg = (e as Error).message
      if (msg === 'AUTH') {
        this.lastError = I18n.t('令牌无效，请在设置中重新配置', 'Token invalid; re-pair in Settings')
      } else {
        this.lastError = I18n.t('会话加载失败：', 'Session load failed: ') + msg
      }
      Logger.warn(this.lastError + ' ' + msg)
      this.sessionsLoading = false
    }
  }

  /**
   * 拉取跨端接续指针（会话列表页进入时调用）。
   * 本设备自己写的记录不展示（clientId 比对）；失败静默保持上次值。
   */
  async refreshHandoff(): Promise<void> {
    const s = this.server
    if (!s || s.token.length === 0) {
      return
    }
    try {
      const h = await GatewayApi.handoffGet(s.normalizedUrl(), s.token)
      const mine = StorageService.getOrCreateClientId()
      this.handoff = h && h.clientId !== mine ? h : null
    } catch (e) {
      // 接续是增强能力：拉不到就当作没有，不打扰会话列表
      Logger.warn('handoff fetch failed: ' + (e as Error).message)
    }
  }

  /**
   * 写入接续指针（离开会话时调用，fire-and-forget）。
   * 设备名取 deviceInfo.marketName（如 "HUAWEI Mate 60 Pro"），
   * 供对端展示"在 xx 上打开过"。空会话（新建没发一句话）不上传，
   * 与 discardEmptySession 的清理语义一致，避免对端接续到死指针。
   */
  putHandoff(sessionId: string, title: string): void {
    const s = this.server
    if (!s || s.token.length === 0 || sessionId.length === 0) {
      return
    }
    for (const item of this.sessions) {
      if (item.sessionId === sessionId && item.blank && !item.running) {
        return
      }
    }
    const state = new HandoffState()
    state.sessionId = sessionId
    state.title = title
    state.clientId = StorageService.getOrCreateClientId()
    try {
      state.device = deviceInfo.marketName
    } catch (e) {
      state.device = ''
    }
    GatewayApi.handoffPut(s.normalizedUrl(), s.token, state).catch((e: Error) => {
      Logger.warn('handoff put failed: ' + e.message)
    })
  }

  /** 清除接续指针（用户在卡片上点"不再提示"；顺带清本地引用） */
  async clearHandoff(): Promise<void> {
    this.handoff = null
    const s = this.server
    if (!s || s.token.length === 0) {
      return
    }
    try {
      await GatewayApi.handoffDelete(s.normalizedUrl(), s.token)
    } catch (e) {
      Logger.warn('handoff clear failed: ' + (e as Error).message)
    }
  }

  async refreshStats(): Promise<void> {
    const s = this.server
    if (!s || s.token.length === 0) {
      return
    }
    const firstLoad = this.statsDays.length === 0 && !this.statsLoading
    if (firstLoad) {
      this.statsLoading = true
    }
    try {
      const data = await GatewayApi.statsSummary(s.normalizedUrl(), s.token, Constants.STATS_DAYS)
      const rawDays = data['days'] as Array<Record<string, Object>> ?? []
      this.statsDays = StatsDay.fromArray(rawDays)
      let total: number = 0
      for (const d of this.statsDays) {
        total += d.tokens()
      }
      this.totalTokens7d = total
      // 卡片标题已经写了「近 7 日 Token 用量」，这里再放一句「近 7 日 Token 总量」就是重复，
      // 正常状态留空（只有不可用/加载失败时才用 statsText 兜底说明）
      this.statsText = ''
      this.statsLoading = false
    } catch (e) {
      this.totalTokens7d = 0
      this.statsDays = []
      this.statsText = I18n.t('统计暂不可用', 'Stats unavailable')
      this.statsLoading = false
    }
  }

  /**
   * 处理 dshremote://pair?token=..&server=.. 深链（扫码之外的配对入口）。
   * 返回是否成功导入。供 EntryAbility 的 onCreate/onNewWant 调用。
   */
  applyPairUri(uri: string): boolean {
    if (uri.length === 0) {
      return false
    }
    const payload = PairParser.parsePairUrl(uri)
    if (!payload) {
      return false
    }
    // 深链任何应用都能触发: 已配置服务器时不静默导入/切换，只接受与现有配置
    // 完全一致的重复配对; 首次配对(尚无服务器)仍然放行。
    if (this.servers.length > 0) {
      const unchanged = this.servers.some((s: ServerInfo) =>
        s.token === payload.token && payload.servers.some((addr: string) => s.normalizedUrl() === addr.replace(/\/+$/, '')))
      if (!unchanged) {
        Logger.warn('pair deep link ignored: server already configured')
        return false
      }
    }
    const ok = this.addServersFromPair(payload.token, payload.servers)
    Logger.info('pair deep link imported=' + (ok ? '1' : '0'))
    return ok
  }

  /** 新建会话（可指定工作区）；成功返回新 sessionId */
  async createSession(workspaceId: string): Promise<string> {
    const s = this.server
    if (!s || s.token.length === 0) {
      this.lastError = I18n.t('未连接服务器', 'Server not connected')
      return ''
    }
    try {
      const payload: SessionCreatePayload = workspaceId.length > 0 ? { workspaceId: workspaceId } : {}
      const v = await GatewayApi.rpc(s.normalizedUrl(), s.token, 'session.create', payload)
      await this.refreshSessions()
      const rec = v as Record<string, Object>
      return String(rec?.['sessionId'] ?? '')
    } catch (e) {
      this.lastError = I18n.t('创建会话失败：', 'Create session failed: ') + (e as Error).message
      Logger.warn(this.lastError)
      return ''
    }
  }

  /** 重命名会话（session.rename）；成功后刷新列表 */
  async renameSession(sessionId: string, title: string): Promise<boolean> {
    const s = this.server
    if (!s || s.token.length === 0 || sessionId.length === 0) {
      return false
    }
    const trimmed = title.trim()
    if (trimmed.length === 0) {
      return false
    }
    try {
      const payload: SessionRenamePayload = { sessionId: sessionId, title: trimmed }
      await GatewayApi.rpc(s.normalizedUrl(), s.token, 'session.rename', payload)
      await this.refreshSessions()
      return true
    } catch (e) {
      Logger.warn('rename failed: ' + (e as Error).message)
      return false
    }
  }

  /** 记住新建会话使用的工作区 */
  setSelectedWorkspace(workspaceId: string): void {
    this.selectedWorkspaceId = workspaceId
    StorageService.putString(Constants.KEY_SELECTED_WORKSPACE, workspaceId)
  }

  /** 新建工作区（workspace.create，只需目录路径）；返回新工作区 id，失败返回 '' */
  async addWorkspace(path: string): Promise<string> {
    const s = this.server
    if (!s || s.token.length === 0 || path.trim().length === 0) {
      return ''
    }
    try {
      const payload: Record<string, Object> = { 'path': path.trim() }
      const v = await GatewayApi.rpc(s.normalizedUrl(), s.token, 'workspace.create', payload)
      await this.refreshWorkspaces()
      const rec = v as Record<string, Object>
      const workspace = rec['workspace'] as Record<string, Object> ?? {}
      return String(workspace['workspaceId'] ?? '')
    } catch (e) {
      this.lastError = I18n.t('新建工作区失败：', 'Create workspace failed: ') + (e as Error).message
      Logger.warn(this.lastError)
      return ''
    }
  }

  /** 拉取工作区列表（workspace.list），供新建会话选择 */
  async refreshWorkspaces(): Promise<void> {
    const s = this.server
    if (!s || s.token.length === 0) {
      this.workspaces = []
      return
    }
    try {
      const empty: Record<string, Object> = {}
      const v = await GatewayApi.rpc(s.normalizedUrl(), s.token, 'workspace.list', empty)
      this.workspaces = WorkspaceInfo.fromRpcValue(v)
      // archivedSessionIds 与 Web 端 wbArchived 同源：workspace.list 顶层字段
      this.archivedSessionIds = []
      const rawArchived = (v as Record<string, Object>)['archivedSessionIds'] as Array<Object> ?? []
      for (const a of rawArchived) {
        const id = String(a ?? '')
        if (id.length > 0) {
          this.archivedSessionIds.push(id)
        }
      }
    } catch (e) {
      // 旧版网关/DSH 无该 RPC 时静默降级为不选工作区
      this.workspaces = []
      Logger.warn('workspace.list failed: ' + (e as Error).message)
    }
  }

  /**
   * 空会话本地清理（离开会话页时调用，与 WebUI shouldDiscardEmptySession 对齐）：
   * 无任何消息且无待处理事项时，从本地列表移除该会话。
   * DSH 侧不删数据，刷新后仍会出现，但该会话已被 DSH 标记为 blank，显示为「新会话」。
   */
  discardEmptySession(sessionId: string): void {
    if (sessionId.length === 0) {
      return
    }
    for (const p of this.pendingApprovals) {
      if (p.sessionId === sessionId) {
        return
      }
    }
    for (const q of this.pendingQuestions) {
      if (q.sessionId === sessionId) {
        return
      }
    }
    let target: SessionView | null = null
    for (const s of this.sessions) {
      if (s.sessionId === sessionId) {
        target = s
        break
      }
    }
    if (!target) {
      return
    }
    // 有消息（非 blank）的会话不清理；running 状态的会话不清理
    if (target.running || !target.blank) {
      return
    }
    this.sessions = this.sessions.filter((s: SessionView) => s.sessionId !== sessionId)
  }

  /** 保存服务器列表（设置页调用）并刷新当前连接 */
  saveServers(list: ServerInfo[], activeId: string): void {
    this.servers = list
    StorageService.saveServers(list)
    StorageService.setActiveServerId(activeId)
    // 重新配置服务器（含扫码/深链配对）即视为重新登录，清掉后台轮询的令牌失效标记
    StorageService.putString(Constants.KEY_LOGIN_EXPIRED, '0')
    this.applyActiveServer(activeId, true)
  }

  /** 扫码配对导入：token 绑定全部地址（同 url+token 去重），第一个地址设为当前 */
  addServersFromPair(token: string, servers: string[]): boolean {
    if (token.length === 0 || servers.length === 0) {
      return false
    }
    const list: ServerInfo[] = []
    for (const s of this.servers) {
      list.push(new ServerInfo(s.id, s.url, s.note, s.group, s.token, s.host))
    }
    let firstId: string = ''
    for (const addr of servers) {
      const url = addr.replace(/\/+$/, '')
      let exists = false
      for (const s of list) {
        if (s.normalizedUrl() === url && s.token === token) {
          exists = true
          if (firstId.length === 0) {
            firstId = s.id
          }
          break
        }
      }
      if (!exists) {
        const id = 's-' + Date.now().toString(36) + '-' + list.length.toString()
        list.push(new ServerInfo(id, url, '', Constants.DEFAULT_GROUP, token))
        if (firstId.length === 0) {
          firstId = id
        }
      }
    }
    if (firstId.length === 0) {
      return false
    }
    this.saveServers(list, firstId)
    return true
  }
}
