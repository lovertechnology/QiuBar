# QiuBar

> 常驻系统托盘的蓝牙设备电量监控小工具 —— 耳机、鼠标、键盘的电量，一眼看到。

QiuBar 通过 Windows 原生的蓝牙 GATT 接口直接读取设备电量，托盘图标实时显示当前所有已连接设备中的**最低电量**，电量偏低时弹系统通知提醒。

![platform](https://img.shields.io/badge/platform-Windows%2010%2B-3DFFA2)
![electron](https://img.shields.io/badge/Electron-44-93A8B0)
![license](https://img.shields.io/badge/license-MIT-FFC53D)

## 特性

- **托盘常驻**：图标直接把最低电量画成数字，按电量变色（薄荷绿 / 琥珀 / 红）
- **设备轮播**：面板里滚轮即可在已连接设备之间切换，弧形表盘 + 电池格条；顺序固定（已连接优先、按名称排序），刷新不会跳页
- **接入即刷**：常驻监听进程（WMI 事件驱动，空闲零 CPU）发现蓝牙设备接入后自动刷新，无需等下一轮轮询
- **刷新频率可调**：面板右上角齿轮进入设置，10 秒 ~ 5 分钟六档可选，改动即时生效并持久化
- **低电量提醒**：≤20% 提醒一次，≤10% 判定为严重不足；电量回升后自动复位，同一档位不会反复打扰
- **悬停即看**：托盘悬停提示里列出每台设备的电量
- **开机即用**：首次拿到数据自动亮一次面板；重复启动程序会唤起已有实例的面板
- **演示模式**：没有蓝牙设备也能看效果（`npm run demo`）
- **绿色便携**：数据写在程序目录旁的 `data/`，不碰 `AppData`
- **可访问性**：跟随系统 `prefers-reduced-motion` 设置

## 工作原理

```
main.js (Electron 主进程)
   │  spawn powershell.exe -File battery.ps1            按设定间隔轮询（默认 30s）
   │  spawn powershell.exe -File battery.ps1 -Watch     常驻监听蓝牙设备接入（WMI 事件）
   ▼
battery.ps1 (PowerShell 5.1 + WinRT)
   │  BluetoothLEDevice.FromBluetoothAddressAsync()
   │  → GetGattServicesForUuidAsync(0x180F  Battery Service)
   │  → GetCharacteristicsForUuidAsync(0x2A19  Battery Level)
   ▼
JSON 输出 → main.js（排序收口：已连接优先、按名称） → ipc → index.html (面板) / Tray (托盘图标) / Notification
```

- **电量来源**：标准 BLE **GATT Battery Service**（`0x180F`）下的 **Battery Level** 特征（`0x2A19`），这是耳机、键鼠等外设通用的标准做法。
- **托盘图标**：主进程通过 `win.webContents.executeJavaScript()` 调用渲染层的 `window.trayIcon(level, state)`，由 canvas 画好后回传 data URL，再 `tray.setImage()`。这样图标和面板共用同一套配色与字体。
- **PowerShell 为什么要这么写**：PS 5.1 对 `IAsyncOperation<T>` 的投影依赖返回类型是否已加载，`Where-Object` 在 WinRT 上也不可用，因此脚本里用反射拿 `AsTask`，并用 `DataReader.FromBuffer` 的反射调用来绕过绑定器。细节见 `battery.ps1` 里的注释。

## 目录结构

```
QiuBar/
├── main.js                 主进程：托盘、窗口、轮询、接入监听、设置持久化、低电量通知、日志
├── index.html              全部 UI（单文件）：表盘、轮播、设置页、GSAP 动效、托盘图标绘制
├── battery.ps1             PowerShell + WinRT 读取 BLE 电量；-Watch 模式监听设备接入
├── make-icon.ps1           生成 icon.ico（多尺寸 PNG-in-ICO）
├── icon.ico                应用图标 / 托盘图标兜底
├── cross-tmp-pack.cmd      打包脚本（同盘暂存 + npmmirror 镜像）
├── package.json
├── .npmrc                  npmmirror 源（国内安装用）
├── data/                   运行时数据，qiubar.log 在此（已 gitignore）
└── dist/                   打包产物（已 gitignore）
```

## 快速开始

**环境要求**

- Windows 10 1809 及以上（需要 `Windows.Devices.Bluetooth` WinRT API）
- Node.js 18+
- PowerShell 5.1（系统自带）

```bash
git clone https://github.com/lovertechnology/QiuBar.git
cd QiuBar
npm install

npm start        # 正常运行
npm run demo     # 演示模式：伪造 3 台设备，方便看 UI 和动效
npm run pack     # 打包成 dist/QiuBar-win32-x64/QiuBar.exe（约 326 MB）
```

## 使用说明

**托盘**

| 操作 | 效果 |
| --- | --- |
| 左键单击 | 打开 / 隐藏面板 |
| 右键 | 菜单：打开面板、立即刷新、打开日志、退出 |
| 悬停 | 显示每台设备的电量 |

**面板**

| 操作 | 效果 |
| --- | --- |
| 滚轮 | 在设备之间轮播 |
| `Esc` | 隐藏面板（设置页里是返回） |
| 右上角齿轮 | 设置页：刷新频率六档（10s / 15s / 30s / 1m / 2m / 5m），即时生效并持久化到 `data/settings.json` |
| 右上角刷新按钮 | 立即重新扫描 |
| 点击面板外（失焦） | 自动隐藏 |

## 日志

所有操作都会记到 `data/qiubar.log`（UTF-8 带 BOM，记事本能直接打开），超过 512 KB 自动轮转为 `.old`：

```
2026/9/29 00:05:30  启动 QiuBar v0.1.0（演示模式）
2026/9/29 00:05:30  打开面板
2026/9/29 00:05:32  轮询成功 2 台设备 · 3.4s · RAPOO Keyboard 96% | RAPOO Mouse 85%
```

日志位置随运行方式而变：开发时在项目根的 `data/`，打包后在 `QiuBar.exe` 同级的 `data/`。

## 已知限制

- **只认标准 GATT 电池服务**。部分 2.4G 私有协议键鼠、老式设备不提供 `0x180F`，会显示 `--` 而不是假装有电。
- **每次轮询要起一个 PowerShell 进程**，单次通常 2–5 秒；轮询间隔 30 秒，不会一直占着 CPU。
- **仅 Windows**。
- 托盘图标显示的是所有设备里的**最低**电量，具体哪台请看悬停提示或面板。

## 打包踩坑记录

这几条都是实际踩出来的，改打包脚本前请先读：

1. **必须 `--no-asar`**。外部 `powershell.exe` 读不到 asar 包里的 `battery.ps1`。
2. **不要给 `--out` 目录写 `--ignore=^/dist`**。`cmd` 会把 `^` 当转义符吃掉，参数变成**无锚点**的正则 `/dist`，于是 `node_modules/gsap/dist/` 被一并删除 —— 结果是 `gsap.min.js` 404、内联脚本报错中断、托盘图标空白，而且没有任何报错提示。`electron-packager` 本身就会忽略 `--out` 目录，不需要手动排除。
3. **`TMP`/`TEMP` 必须指向与项目同盘的目录**（脚本里用 `..\qiubar-packtmp`，且在项目树外更稳），否则跨卷 `rename` 会 `EPERM`。
4. **`app.setPath('userData', ...)` 必须在 `app` ready 之前调用**，否则 GPU 缓存仍会写到 `AppData` 并在受限环境下崩溃。
5. **`.ps1` 必须存成 UTF-8 带 BOM**。PS 5.1 对无 BOM 文件按系统 ANSI（中文系统是 GBK）解码，注释里的中文多字节序列会吞掉后面的换行符，把两行代码拼成一行，报出位置完全对不上的括号错误。仓库里 `.gitattributes` 已锁定，重存文件时别去掉 BOM。
6. 打包产物约 326 MB，是 Electron 运行时本身的体积，不是代码。

## License

MIT