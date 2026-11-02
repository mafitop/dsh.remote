/* 首次使用：插件抽屉和管理页共用。鸿蒙 App 通过 hdc/DevEco 安装，这里不提供离线安装包下载。 */
'use strict'
;(function () {
  const words = {
    zh: {
      title: '连接你的第一台手机', again: '连接手机', intro: '电脑保持 DSH 运行，按下面三步开始。已安装 App 可直接进行第 3 步。',
      app: '安装鸿蒙 App', appHint: '在电脑上用 DevEco Studio 或 hdc 把签名后的 HAP 装到手机（仓库脚本 scripts/install-hap.sh）。鸿蒙不支持从浏览器直接安装。',
      service: '准备电脑端', ready: '网关已运行。首次连接请让手机和电脑处于同一 Wi-Fi。', standalone: '网关当前未就绪，请检查主机上的网关进程。',
      down: '网关尚未就绪。插件已包含网关，可在此启动。', auth: '网关认证异常，请打开控制台查看诊断。', upstream: '网关已运行，但 DSH 暂不可达。请到控制台检查连接。',
      attention: '网关进程已运行，但尚未能读取管理状态。请到控制台检查。',
      start: '启动网关', console: '打开控制台', diagnose: '检查连接',
      connect: '在 App 中扫码连接', pair: '显示连接二维码', key: '添加设备并配对',
      pairHint: '在 App 的「设置 → 服务器」中扫码。连接码含访问凭据，请勿分享。',
      online: '已检测到手机在线，可以开始使用。', waiting: '等待手机连接。',
      noHost: '暂无手机可访问的地址。请先启动网关；若仍无地址，在控制台的「主机 IP 地址」中添加宿主地址。',
      localOnly: '网关仅监听本机，手机无法访问。请在主机配置可供局域网访问的监听地址，再重启网关。',
      host: '手机访问的电脑地址', network: '手机需能访问所选地址。扫码打不开时，检查同一 Wi-Fi、VPN 和电脑防火墙；可在控制台诊断。',
      pairCode: '连接二维码 · 用 DSH Remote 扫描', qrError: '二维码暂不可用，请使用下方地址或打开控制台。',
      unavailable: '状态暂不可用，请稍后重试或打开控制台。'
    },
    en: {
      title: 'Connect your first phone', again: 'Connect a phone', intro: 'Keep DSH running on your computer. Three steps; skip to step 3 if the app is installed.',
      app: 'Install the HarmonyOS app', appHint: 'Use DevEco Studio or hdc on the computer to install the signed HAP (repo script scripts/install-hap.sh). HarmonyOS cannot install directly from a browser.',
      service: 'Prepare your computer', ready: 'The gateway is running. For your first connection, use the same Wi-Fi on both devices.', standalone: 'The gateway is not ready. Check its process on the host.',
      down: 'The gateway is not ready. It is included with the plugin; start it here.', auth: 'Gateway authentication needs attention. Open the console for diagnostics.', upstream: 'The gateway is running, but DSH is unreachable. Check the connection in the console.',
      attention: 'The gateway process is running, but its management state is unavailable. Check the console.',
      start: 'Start gateway', console: 'Open console', diagnose: 'Check connection',
      connect: 'Scan in the app to connect', pair: 'Show connection QR', key: 'Add a device to pair', pairHint: 'Scan under Settings → Servers in the app. The connection code contains credentials; keep it private.',
      online: 'A phone is online. You are ready to use Remote.', waiting: 'Waiting for a phone.',
      noHost: 'No address accessible to your phone. Start the gateway, then add a host address under “Host IP addresses” in the console if needed.',
      localOnly: 'The gateway listens on loopback only. Configure a LAN listening address on the host and restart the gateway.',
      host: 'Computer address accessible to your phone', network: 'Your phone must reach this address. If scanning fails, check Wi-Fi, VPN and the computer firewall, or open console diagnostics.',
      pairCode: 'Connection QR · scan in DSH Remote', qrError: 'QR unavailable. Use the address below or open the console.',
      unavailable: 'Status unavailable. Retry later or open the console.'
    }
  }
  function mount(root, options) {
    if (!root) return { update() {} }
    const lang = () => window.I18N?.lang === 'en' ? 'en' : 'zh'
    const t = key => words[lang()][key]
    const labels = []
    const node = (tag, label, className) => {
      const el = document.createElement(tag)
      if (label) { el.textContent = t(label); labels.push([el, label]) }
      if (className) el.className = className
      return el
    }
    const details = node('details', '', 'remote-setup')
    const summary = node('summary', 'title')
    details.append(summary, node('p', 'intro'))
    const stepNav = node('div', '', 'setup-step-nav')
    stepNav.setAttribute('aria-label', lang() === 'zh' ? '连接步骤' : 'Connection steps')
    details.append(stepNav)
    const list = node('ol'); details.append(list); root.append(details)
    const steps = [], stepButtons = []
    let currentStep = 0, stepSelected = false
    function step(title) {
      const el = node('li'); el.append(node('h3', title)); list.append(el); steps.push(el); return el
    }
    function button(parent, label, action, primary = false) {
      const el = node('button', label, primary ? 'setup-primary' : '')
      el.type = 'button'; el.addEventListener('click', action); parent.append(el); return el
    }
    const first = step('service'), service = node('p')
    first.append(service)
    const serviceAction = button(first, 'console', () => {
      if (canStart()) options.start()
      else options.console()
    })
    const install = step('app'); install.append(node('p', 'appHint'))
    const second = step('connect'), connection = node('p', 'waiting'); connection.setAttribute('role', 'status'); second.append(connection)
    const pair = button(second, 'pair', () => {
      if (state?.deviceKeys?.enabled) options.deviceKey()
      else showCode('pair')
    }, true)
    const pairQr = node('div', '', 'setup-qr'); pairQr.hidden = true; second.append(pairQr, node('p', 'pairHint'))
    const network = node('p', 'network'); second.append(network)
    const addressLabel = node('label'), select = node('select')
    select.setAttribute('aria-label', t('host')); addressLabel.append(node('span', 'host'), select); second.insertBefore(addressLabel, pair)
    for (const [index,title] of ['service','app','connect'].entries()) {
      const control = button(stepNav,title,()=>chooseStep(index))
      stepButtons.push(control)
    }
    function chooseStep(index,manual=true) {
      currentStep = Math.max(0,Math.min(2,index))
      if (manual) stepSelected = true
      steps.forEach((el,i)=>{el.hidden=i!==currentStep})
      stepButtons.forEach((el,i)=>el.setAttribute('aria-current',i===currentStep?'step':'false'))
    }
    chooseStep(0,false)
    let state = null, initialized = false
    const shownCodes = new Set(), codeSignatures = new Map()
    const running = () => state?.mode === 'gateway' && !state.gatewayAuthError
    const canStart = () => state && !state.gatewayRunning && state.mode !== 'gateway' && !state.gatewayAuthError && state.gatewayInstalled !== false && options.canStart !== false
    function bases() {
      if (!running() || /^(127\.|localhost$|\[?::1\]?$)/i.test(state.host || '')) return []
      const hosts = options.hosts ? options.hosts(state) : state.lanIPs || []
      const port = Number(state.port)
      if (!Number.isInteger(port) || port < 1 || port > 65535) return []
      return [...new Set(hosts)].filter(host => typeof host === 'string' && /^[a-z0-9.-]+$/i.test(host)
        && !/^(127\.|0\.0\.0\.0$|localhost$)/i.test(host)).map(host => `http://${host}:${port}`)
    }
    function showCode() {
      shownCodes.add('pair')
      const box = pairQr
      const base = select.value
      if (!bases().includes(base) || !state?.token || state.deviceKeys?.enabled) { box.hidden = true; box.replaceChildren(); return }
      const url = 'dshremote://pair?' + new URLSearchParams({ token: state.token, server: base })
      const signature = lang() + '|' + url + '|' + !!state.deviceKeys?.enabled
      if (!box.hidden && codeSignatures.get('pair') === signature) return
      codeSignatures.set('pair', signature)
      box.replaceChildren()
      const caption = node('p'); caption.textContent = t('pairCode'); box.append(caption)
      try {
        const qr = window.qrcode(0, 'M'); qr.addData(url); qr.make()
        const image = node('div'); image.innerHTML = qr.createSvgTag({ cellSize: 4, margin: 2, scalable: true }); box.append(image)
      } catch { const error = node('p'); error.textContent = t('qrError'); box.append(error) }
      box.hidden = false
    }
    function update(next) {
      state = next
      for (const [el, key] of labels) el.textContent = t(key)
      stepButtons.forEach((el,i)=>{el.textContent=(i+1)+' '+t(['service','app','connect'][i])})
      select.setAttribute('aria-label', t('host'))
      const online = (state?.devices || []).some(d => d.online && (d.kind === 'app' || d.kind === 'web'))
      if (!initialized) { details.open = !online; initialized = !!state }
      if (state && !stepSelected) chooseStep(state.mode === 'gateway' ? 2 : 0,false)
      summary.textContent = t(online ? 'again' : 'title')
      service.textContent = t(!state ? 'unavailable' : state.gatewayAuthError ? 'auth' : !running() ? state.gatewayRunning ? 'attention' : options.canStart === false ? 'standalone' : 'down' : state.upstream?.reachable === false ? 'upstream' : 'ready')
      serviceAction.textContent = t(canStart() ? 'start' : options.inConsole ? 'diagnose' : 'console')
      connection.textContent = t(online ? 'online' : 'waiting')
      pair.textContent = t(state?.deviceKeys?.enabled ? 'key' : 'pair')
      const previous = select.value, urls = bases()
      if (Array.from(select.options).map(o => o.value).join('|') !== urls.join('|')) {
        select.replaceChildren(...urls.map(url => { const el = node('option'); el.value = url; el.textContent = url; return el }))
        if (urls.includes(previous)) select.value = previous
      }
      select.hidden = addressLabel.hidden = !urls.length
      pair.disabled = !urls.length || !running() || (!state?.deviceKeys?.enabled && !state?.token)
      network.textContent = t(urls.length ? 'network' : /^(127\.|localhost$|\[?::1\]?$)/i.test(state?.host || '') && running() ? 'localOnly' : 'noHost')
      for (const kind of shownCodes) showCode(kind)
    }
    select.addEventListener('change', () => { for (const kind of shownCodes) showCode(kind) })
    function conceal() {
      shownCodes.clear(); codeSignatures.clear()
      pairQr.hidden = true; pairQr.replaceChildren()
    }
    details.addEventListener('toggle',()=>{if(!details.open)conceal()})
    return { update, conceal, show(step=1) { chooseStep(typeof step === 'number' && step >= 2 ? 2 : 0); details.open = true; details.scrollIntoView?.({ behavior: 'smooth', block: 'start' }) } }
  }
  window.DshSetup = { mount }
})()
