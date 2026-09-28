const { app, Tray, Menu, BrowserWindow, Notification, nativeImage, ipcMain, shell } = require('electron')
const { spawn } = require('child_process')
const path = require('path')
const fs = require('fs')

const W = 380, H = 576
const POLL_MS = 30_000, WARN = 20, CRIT = 10
const DEMO = process.argv.includes('--demo')

// 极简文件日志：data\qiubar.log，超 512KB 轮转为 .old（只保留两代，够用）
function log(msg) {
  try {
    const f = path.join(app.getPath('userData'), 'qiubar.log')
    if (!fs.existsSync(f)) fs.writeFileSync(f, '\uFEFF')   // BOM：记事本/PowerShell 正确识别 UTF-8
    try { if (fs.statSync(f).size > 512 * 1024) fs.renameSync(f, f + '.old') } catch { }
    fs.appendFileSync(f, `${new Date().toLocaleString('zh-CN', { hour12: false })}  ${msg}\n`)
  } catch { /* 日志失败不影响主流程 */ }
}

// 全局兜底：主进程任何裸抛异常都记入日志，避免弹"JavaScript error"崩溃框
process.on('uncaughtException', e => log(`主进程异常 ${(e && e.stack) || e}`))
process.on('unhandledRejection', e => log(`未处理的Promise拒绝 ${(e && e.stack) || e}`))

let tray = null, win = null, devices = [], alerts = {}, loaded = false, demoTick = 0, first = true

function createWindow() {
  win = new BrowserWindow({
    width: W, height: H, show: false, frame: false, transparent: true,
    resizable: false, skipTaskbar: true, alwaysOnTop: true,
    backgroundMaterial: 'acrylic',
    // 本地单文件 UI、无远程内容，nodeIntegration 换掉 preload 文件
    webPreferences: { nodeIntegration: true, contextIsolation: false, backgroundThrottling: false }
  })
  win.loadFile('index.html')
  win.webContents.on('did-finish-load', () => { loaded = true; push(); updateTray() })
  win.on('blur', () => win.hide())
  win.on('show', () => win.webContents.send('shown'))
}

function showPopup() {
  // ponytail: screen 必须调用时再取——模块顶层解构拿到的是 ready 前的空壳（Electron 44 实测方法未挂载）
  const { screen } = require('electron')
  const pt = screen.getCursorScreenPoint ? screen.getCursorScreenPoint() : { x: 0, y: 0 }
  const wa = (screen.getDisplayNearestToPoint ? screen.getDisplayNearestToPoint(pt) : screen.getPrimaryDisplay()).workArea
  win.setPosition(wa.x + wa.width - W - 8, wa.y + wa.height - H - 8)
  win.show(); win.focus()
  log('打开面板')
}

function createTray() {
  // ponytail: 先用现成的 icon.ico 兜底，托盘任何时刻都不会是空白；拿到真实电量后再换成数字图标
  const base = nativeImage.createFromPath(path.join(__dirname, 'icon.ico'))
  tray = new Tray(base.isEmpty() ? nativeImage.createEmpty() : base)
  tray.setToolTip('QiuBar · 蓝牙电量监控')
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: '打开面板', click: showPopup },
    { label: '立即刷新', click: refresh },
    { label: '打开日志', click: () => shell.openPath(path.join(app.getPath('userData'), 'qiubar.log')).catch(() => { }) },
    { type: 'separator' },
    { label: '退出', role: 'quit' }
  ]))
  tray.on('click', () => (win.isVisible() && win.isFocused()) ? win.hide() : showPopup())
}

function refresh(manual) {
  if (DEMO) { demoTick++; return onDevices(demoData()) }
  if (manual) log('手动刷新')
  const t0 = Date.now()
  const p = spawn('powershell.exe',
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(__dirname, 'battery.ps1')],
    { windowsHide: true })
  let out = '', err = ''
  const kill = setTimeout(() => p.kill(), 25_000)
  p.stdout.on('data', d => out += d)
  p.stderr.on('data', d => err += d)
  p.on('error', e => { clearTimeout(kill); log(`轮询失败 无法启动PowerShell: ${e.message}`); onDevices(devices, '无法启动 PowerShell') })
  p.on('close', () => {
    clearTimeout(kill)
    try {
      const arr = JSON.parse(out.trim())
      const list = Array.isArray(arr) ? arr : []
      log(`轮询成功 ${list.length} 台设备 · ${((Date.now() - t0) / 1000).toFixed(1)}s · ` +
        (list.map(d => `${d.name} ${d.battery >= 0 ? d.battery + '%' : '--'}`).join(' | ') || '无设备'))
      onDevices(list)
    } catch (e) {
      log(`轮询失败 ${((err || out) + '').trim().slice(0, 200) || e.message}`)
      onDevices(devices, err || '读取失败')
    }
  })
}

function onDevices(list, err) {
  devices = list
  for (const d of devices) {
    const key = d.address || d.name
    const b = d.battery < 0 ? 0 : d.battery <= CRIT ? 2 : d.battery <= WARN ? 1 : 0   // 电量未知(-1)不提醒
    if (b === 0) { delete alerts[key]; continue }
    if ((alerts[key] || 0) < b) {          // 仅跨过阈值时提醒一次，回升后自动复位
      alerts[key] = b
      log(`低电量提醒 ${d.name} ${d.battery}%（${b === 2 ? '严重不足' : '偏低'}）`)
      new Notification({
        title: `${d.name} · 电量 ${d.battery}%`,
        body: b === 2 ? '电量严重不足，请立即充电' : '电量偏低，建议尽快充电'
      }).show()
    }
  }
  push(list.length ? null : (err || ''))
  updateTray()
  if (first && list.length) { first = false; setTimeout(showPopup, 100) }   // 首次拿到数据自动亮一次面板（延迟一拍，避开 ready 早期 screen API 未挂载）
}

function push(err) { if (loaded) win.webContents.send('devices', { devices, err: err || '', ts: Date.now() }) }

async function updateTray() {
  if (!loaded || !tray) return
  const live = devices.filter(d => d.battery >= 0)
  const level = live.length ? Math.min(...live.map(d => d.battery)) : -1
  const st = level < 0 ? 'none' : level <= CRIT ? 'crit' : level <= WARN ? 'warn' : 'ok'
  try {
    const url = await win.webContents.executeJavaScript(`window.trayIcon(${level}, ${JSON.stringify(st)})`)
    if (url) {
      tray.setImage(nativeImage.createFromDataURL(url))
      tray.setToolTip(devices.length
        ? devices.map(d => `${d.battery >= 0 ? d.battery + '%' : '--'}  ${d.name}`).join('\n')
        : 'QiuBar · 未发现蓝牙设备')
    }
  } catch (e) { log(`托盘图标更新失败 ${e.message}`) }   // 渲染层未就绪时跳过，下次轮询再试
}

function demoData() {
  const t = demoTick
  return [
    { name: 'AirPods Pro 2', address: 'demo-1', battery: Math.max(0, 86 - (t % 60)), connected: true },
    { name: 'MX Master 3S', address: 'demo-2', battery: Math.max(0, 22 - Math.floor(t / 2) % 22), connected: true },
    { name: 'Keychron K3 Pro', address: 'demo-3', battery: 60 + Math.round(Math.sin(t / 5) * 15), connected: true }
  ]
}

ipcMain.on('refresh', () => refresh(true))
ipcMain.on('hide', () => win.hide())
app.on('before-quit', () => log('退出'))

// userData 必须在 app ready 之前重定向（GPU 缓存路径在启动早期锁定），同时实现绿色便携
// ponytail: app.isPackaged 在 npx electron 下曾误判为 true，改用 __dirname 判定（dev=项目根，打包=resources\app）
const BASE = __dirname.includes(`${path.sep}resources${path.sep}app`) ? path.dirname(process.execPath) : __dirname
try { app.setPath('userData', path.join(BASE, 'data')) } catch { /* 已锁定则忽略 */ }

if (!app.requestSingleInstanceLock()) app.quit()
else app.whenReady().then(() => {
  app.setAppUserModelId('QiuBar')
  log(`启动 QiuBar v${app.getVersion()}${DEMO ? '（演示模式）' : ''}`)
  createWindow()
  createTray()
  refresh()
  setInterval(refresh, POLL_MS)
})
