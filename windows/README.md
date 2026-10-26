# 桌宠合集 PetHub · Windows 版（Electron）

macOS 原生版（Swift/AppKit，v2.0.0）已经完成；这个目录是给 Windows 用户准备的**跨平台重写版**：

- 同一批素材（`../Assets/`：薄肌 37 句、太对了 28 句、峰哥 11 句、果冻三个标志）；
- 同一套内容包格式（[docs/PETPACK.md](../docs/PETPACK.md)）；
- 同样的 `hop` / `root` 四步捧哏链和接话策略；
- 最终产物是单文件 `PetHub-2.0.0-Windows-x64.exe`，放在仓库根 `dist/windows/`。

技术栈刻意压到最小：**Electron + 原生 HTML/CSS/JS**，没有 React/Vue，npm 依赖只有
`electron` / `electron-builder` 两个（devDependencies），不联网、不申请额外权限。

- 给最终用户看的安装/使用说明：[docs/WINDOWS.md](../docs/WINDOWS.md)
- 三平台（macOS / Windows / 源码）对照：[docs/PLATFORMS.md](../docs/PLATFORMS.md)
- 仓库根 README 的 Windows 安装段由 Lead 统一维护（本目录不直接改根 README）。

> **⚠️ 整合项目，不是原创角色项目。**
> 薄肌 / 太对了 / 峰哥 / 果冻的角色、原声、头像和原始玩法来自
> [ShaolanPet](https://github.com/Ganzhe2028/ShaolanPet)、[SunPet](https://github.com/Ganzhe2028/SunPet)、
> [FengGe-Desktop-Pet](https://github.com/Ganzhe2028/FengGe-Desktop-Pet)、
> [JellyPet](https://github.com/aurelius358/JellyPet)，版权归原作者。
> **JellyPet 仓库没有 LICENSE**，本项目只按它 README 的「代码可自由修改」合并，公开再分发（尤其商用）
> 前应先联系原作者。完整声明见仓库根 [CREDITS.md](../CREDITS.md) 与 [NOTICE.md](../NOTICE.md)。

## 目录结构

```
windows/
├── package.json              # 依赖只有 electron / electron-builder；electron-builder 配置在 build 字段
├── main.js                   # 主进程：窗口、联动、菜单、托盘、设置、PetPack、smoke
├── preload.js                # contextBridge，只暴露必要 IPC
├── lib/
│   ├── pets.js               # 四只的 profile（大小/音量/动画/接话条件/捧哏池）
│   ├── layout.js             # 默认 / 紧凑 / 合影站位、窗口尺寸
│   ├── settings.js           # settings.json 读写与范围收紧
│   ├── petpack.js            # PetPack v1 校验 + 原子安装
│   └── probe.js              # 隐藏窗口里解码头像/音频，量时长
├── renderer/
│   ├── pet.html / pet.css / pet.js        # 三只语音桌宠 + 果冻共用的透明窗口
│   ├── settings.html/.css/.js             # 设置窗口
│   └── probe.html                         # 解码探测页
├── scripts/
│   ├── copy-assets.js        # ../Assets → windows/assets（+ icns→png 图标）
│   ├── launch.js             # 清掉 ELECTRON_RUN_AS_NODE 再启动 electron
│   └── make-sfx-exe.sh       # portable 失败时的 7z SFX 兜底
├── build-win.sh              # 一键构建 Windows 产物
├── build/icon.png            # electron-builder 用图标（由 copy-assets.js 生成）
├── assets/                   # 生成目录，gitignore；build/start 时从 ../Assets 复制
└── README.md                 # 本文件
```

## 开发

需要 Node.js ≥ 20（本机验证用 Node 22 / Electron 38.8.6）。

```bash
cd windows
npm install                 # 下载 electron 与 electron-builder
npm start                   # 正常启动（macOS 上也能跑，用于开发验证）
npm start -- --settings     # 启动后直接打开设置窗口
npm run smoke               # 自动验收，最后一行 PASS 后退出
```

本机网络需要代理时：

```bash
export HTTPS_PROXY=http://127.0.0.1:7897 HTTP_PROXY=http://127.0.0.1:7897 ALL_PROXY=socks5://127.0.0.1:7897
```

`npm start` 之后：四只出现在屏幕右下角，托盘多一个「桌宠合集」图标。macOS 上开发时会保留 Dock 图标
（Windows 版 `skipTaskbar`，正常只有托盘）。开发模式的设置写在 `~/Library/Application Support/PetHub-Windows-Dev/`，
不会污染 macOS 原生版的 `~/Library/Application Support/PetHub/`；打包后的 Windows 版写在
`%APPDATA%\PetHub\`。

### 诊断 / QA 命令

这些是 Windows 版额外提供的入口（macOS 原生版的 CLI 不受影响）：

| 命令 | 作用 |
| --- | --- |
| `npm run smoke` | 起四只窗口 → 校验素材（37/28/11 句全部可解码、头像、三个标志）→ 模拟点薄肌跑四步链 → 检查托盘/四只右键菜单能构建 → 隐藏的设置窗口里真点「大小联动」、拖全局滑块、校验版权声明 → 最后一行 `PASS`，9~10 秒后退出。使用临时 userData，不碰真实设置。 |
| `node scripts/launch.js --chain-test` | 用**当前** userData 实测四步链（装了自定义内容包也可以跑），输出 `PASS 四步捧哏链`。 |
| `node scripts/launch.js --dump-state` | 打印四只的状态（窗口位置/大小/句数/标题/内容版权来源）后退出。 |
| `node scripts/launch.js --install-pack <目录>` | 不弹窗，直接校验并安装一个 PetPack；失败打印 `FAIL <原因>` 且退出码 1。 |
| `node scripts/launch.js --restore-builtin` | 删除已安装内容包，恢复原版薄肌。 |
| `node scripts/launch.js --screenshot <目录>` | 把四只窗口 + 设置窗口各截一张 png（`capturePage`）后退出，便于肉眼检查。 |
| `node scripts/launch.js --trace` | 正常启动 + 把每一跳 `[relay]` / `[trace]` 打到 stdout。 |

`npm run smoke` 的通过标准（脚本会自己断言，不满足就 `FAIL` 并退出码 1）：

1. 4 个窗口全部创建，尺寸与布局计算一致；
2. 薄肌 37 / 太对了 28 / 峰哥 11 条音频全部可解码且时长 > 0.1s，三张头像和三个果冻标志可解码；
3. 模拟点薄肌后，联动记录恰好是：
   `shaolan hop0 root=shaolan → sunpet hop1 → fengge hop2 → sunpet hop3`，root 全程 `shaolan`，
   1.5 秒内没有第五句；
4. 大小/显隐/联动开关的 IPC 生效，`settings.json` 能写回并读回；
5. 托盘菜单包含显示/隐藏、自定义桌宠、捧哏联动、设置、关于、退出；四只右键菜单能构建；
6. 设置窗口（隐藏）里点「大小联动」、拖全局滑块 150% 再回 100%，四只比例真的跟着变，
   并且页面上有「整合自 … / JellyPet 无 LICENSE」版权声明。

## 构建 Windows 产物

```bash
cd windows
./build-win.sh
```

脚本按顺序做：

1. 检查 node / npm / `../Assets`，没有代理环境变量时用本机默认 `127.0.0.1:7897`；
2. `npm install`（缺依赖时）、`node scripts/copy-assets.js`（复制素材 + 生成 `build/icon.png`）；
3. 清空并重建 `../dist/windows/`（**不会**碰 macOS 的 `dist/PetHub-2.0.0.dmg`）；
4. `electron-builder --win portable --x64` → `PetHub-2.0.0-Windows-x64.exe`；
5. `electron-builder --win zip --x64` → `PetHub-2.0.0-Windows-x64.zip`；
6. 若 portable 失败：`scripts/make-sfx-exe.sh` 用 7zS.sfx 把 zip 包成单文件 exe（7-Zip 官方
   9.20 Extra 里的模块，构建时下载，不进仓库）；连 SFX 模块也拿不到就保留 zip 并打印明确 WARN；
7. 生成 `PetHub-2.0.0-Windows-x64.sha256`，打印路径 / 大小 / sha256。

本机（macOS 24.6 / arm64 / electron-builder 26.18.0）实测 **portable 可直接构建成功，不需要 Wine**；
electron-builder 自己会下载 `nsis-3.0.4.1`、`nsis-resources-3.4.1`、Windows 版 Electron 和图标工具。
如果目标机器网络不通，先确认代理，或预先把 electron-builder 的 cache 准备好再跑。

产物：

```
dist/windows/
├── PetHub-2.0.0-Windows-x64.exe     # portable 单文件（双击直接跑，不安装）
├── PetHub-2.0.0-Windows-x64.zip     # 免安装兜底（解压后双击 PetHub.exe）
└── PetHub-2.0.0-Windows-x64.sha256
```

`win-unpacked/`、`.icon-ico/`、`builder-debug.yml` 是 electron-builder 的中间产物，脚本跑完会
自动删掉，所以交付目录里只剩上面三个文件。想在 Windows 上跑打包版的 smoke，可以（PowerShell）：

```
.\PetHub.exe --smoke > smoke.log 2>&1
Get-Content smoke.log
```

截图诊断同理：`.\PetHub.exe --screenshot C:\temp\pethub-shots`。

### 图标

`Assets/AppIcon.icns` 用 `sips -s format png` 转成 1024×1024 PNG，写进 `build/icon.png` 和
`assets/AppIcon.png`（托盘用，运行时会缩到 16/18px）。electron-builder 把 PNG 转成 Windows 用的 ico。

## 和 macOS 原生版的映射

| macOS（Swift） | Windows（本目录） |
| --- | --- |
| `Sources/PetKit/PetIdentity.swift` 的 `PetID` | `lib/pets.js` 的 `PET_PROFILES` / `ASSETS_FOLDER` |
| `AudioPetProfiles.swift` 的 `defaultSize` / `volume` / `animation` / `reaction` / 捧哏池 | `lib/pets.js` 的 `PET_PROFILES`（数值、条件逐条照抄） |
| `PetRelay.swift` 的 `PetSpeech` / `announce` | `main.js` 的 `announce()` / `scheduleCompanion()` / `playSpeech()` |
| `PetHubApp` 的菜单栏 | 托盘菜单 + 设置窗口（`main.js` 的 `buildTrayMenu` / `renderer/settings.html`） |
| `PetLayout.swift` | `lib/layout.js`（默认 260/180/260/128、gap 36、margin 24；紧凑 6/16；合影 1.2/1.4/1.2/0.65） |
| `PetPack.swift` | `lib/petpack.js`（format=1、1–200 条、安全相对路径、中文非空、头像/音频解码、>0.1s、临时目录+原子替换） |
| `AudioPetViews.swift` 的字幕 / 动画 | `renderer/pet.html` + `pet.css`（压扁 / 摇摆 / 字幕两行） |
| `JellyModel` / `JellyPetController`（CoreImage） | `renderer/pet.js` 的按压放大 + 拖动拉长 + 回弹 + 标志切换（简化版，不追求像素级复刻） |
| `UserDefaults`（`pet.<id>.*` / `hub.*`） | `settings.json`（结构见 `lib/settings.js`） |

### 联动语义（和 macOS 完全一致，不要改）

| 桌宠 | 接谁 | 条件 | 捧哏池 |
| --- | --- | --- | --- |
| 薄肌 shaolan | 从不接 | `reaction` 恒 false | 无 |
| 太对了 sunpet | 薄肌、峰哥 | `(from == shaolan \|\| from == fengge) && hop < 3` | id ∈ {1,2,4,11,13,14}，且排除「轮播内容」勾掉的句子 |
| 峰哥 fengge | 太对了 | `from == sunpet && root == shaolan && hop < 3` | 全部 11 句 |

- 用户点击：`hop = 0`、`root = 自己`；接话者播放时广播 `hop + 1`、`root` 原样；
- 收到 hop 1 的话时接话压紧到 `0.2s`，其余 `0.3s`；到点时自己正在播就放弃这一捧，不叠音；
- 第 4 跳（hop 3）再广播时，太对了和峰哥都因为 `hop < 3` 不再接，链收住，没有第五句；
- 自定义 PetPack 只改薄肌的素材来源，`PetID` 和 `root` 仍是 `shaolan`，显示名只走 `displayTitle`。

### 与 macOS 版的行为差异（有意为之）

- **没有菜单栏状态项**：Windows 用托盘图标 + 设置窗口（`npm start -- --settings`）。
- **没有机身摇晃**：SPU 加速度计是 macOS 私有接口，Windows 版不做。
- **果冻是简化形变**：按压放大、拖动拉长、松手回弹、图标切换，没有 CoreImage 的 CIBumpDistortion。
- **没有「自定义角色编辑器」**：macOS 版可以现场填名字/选头像/加语音；Windows 版只做
  「导入现成 PetPack + 恢复原版」，符合任务范围。
- **托盘/右键菜单的「轮播内容」勾选**：Windows 原生菜单点一次就关，勾多句要重开两三次；
  连续调节大小请用设置窗口里的滑块。
- **接话时机没有量 `leadingSilence`**：macOS 会逐句量开头静音并补偿；Windows 版用
  `duration - overlap` 近似，连续两句的重叠会比 macOS 略紧一点点（策略、hop、root 都不变）。
- **偏好文件位置不同**：Windows 是 `%APPDATA%\PetHub\settings.json`，和 macOS 的
  `local.pethub.app` UserDefaults 不互通（迁移不在本版范围）。

## 已知限制

- **Windows 实机未测**：所有验证都在 macOS 上完成（`npm start`、`npm run smoke`、`--chain-test`、
  `--screenshot`、electron-builder 交叉打包）。透明窗口、置顶层级、DPI 缩放、托盘菜单在真实
  Windows 10/11 上仍需跑一遍验收。
- **透明窗口点击区域**：语音桌宠是整窗可点（窗口基本被头像填满）；果冻窗口比图标大一圈，
  用 `setIgnoreMouseEvents(true, {forward:true})` + renderer 命中检测让图标以外点击穿透桌面。
  Windows 上 `forward` 的行为需要实机确认；如果失效，果冻图标外的透明区域会挡住桌面点击。
- **必须用 `scripts/launch.js` 启动**：某些环境自带 `ELECTRON_RUN_AS_NODE=1`，直接 `electron .`
  会变成纯 Node 不开窗口；`npm start` / `npm run smoke` 已经包裹好了。
- **exe 未签名**：Windows SmartScreen 会提示「未知发布者」，选「更多信息 → 仍要运行」。
- **单文件 exe 每次启动会解压**：portable target 是 NSIS 自解压，第一次/每次启动会解到临时目录，
  比安装版慢一两秒；要更快就用 zip 解压后的免安装版。
- **不联网 / 不自动更新**：没有 auto-update、没有崩溃上报。

## 验证记录（本机 macOS，2026-10-26）

```
$ npm run smoke
[smoke] PetHub 2.0.0 · electron 38.8.6 · node 22.22.0
[smoke] windows=4 shaolan=260x296@768,797 sunpet=180x228@1064,865 fengge=260x290@1280,803 jelly=224x224@1528,917
[smoke] validate shaolan clips=37/37 avatar=820x820 ok
[smoke] validate sunpet clips=28/28 avatar=1254x1254 ok
[smoke] validate fengge clips=11/11 avatar=1269x1239 ok
[smoke] validate jelly marks=3/3 ok
[smoke] step 1/4 from=shaolan hop=0 root=shaolan clip=32 “中国人必须得吃饭”
[smoke] step 2/4 from=sunpet hop=1 root=shaolan clip=11 “这这太对了”
[smoke] step 3/4 from=fengge hop=2 root=shaolan clip=11 “人有欲望是好事”
[smoke] step 4/4 from=sunpet hop=3 root=shaolan clip=04 “你说的太对了”
[smoke] 第 4 步之后 1.5s 内没有第五句
[smoke] settings/scale/visibility/relay IPC ok; settings.json 持久化 ok
[smoke] tray menu ok（19 项，四只右键菜单可构建）
[smoke] settings window ok（大小联动 / 全局滑块 / 版权声明 / 四只缩放）
PASS windows=4 clips=37/28/11 chain=shaolan>sunpet>fengge>sunpet root=shaolan elapsed=9.0s
```

本次最终构建的完整 smoke 输出留在 `windows/smoke-pass.log`（证据文件，可删）；
构建日志在 `windows/build/build-win-final.log`（build/ 目录 gitignore）。

自定义 PetPack（`我的老师`，3 句）导入后：

```
$ node scripts/launch.js --install-pack /tmp/pethub-test-pack
PASS petpack installed name=我的老师 author=QA clips=3 avatar=820x820 dir=.../HeadPet
$ node scripts/launch.js --dump-state
shaolan ... clips=3 ... title=我的老师 content=custom
$ node scripts/launch.js --chain-test
[chain] 1/4 from=shaolan hop=0 root=shaolan clip=01 “同学们好”
...
PASS 四步捧哏链：shaolan > sunpet > fengge > sunpet，root 全 shaolan（content=custom:我的老师）
$ node scripts/launch.js --restore-builtin
PASS restore-builtin removed=true
```

坏包会被拒绝（format 不是 1 / 路径含 `..` / 音频解不出来，分别打印对应 FAIL）。

打包后的 app（`app.isPackaged = true`，素材/文档从 `resources/` 读）也用同一份 smoke 验证过：
在 macOS 上先 `electron-builder --mac dir` 出一个 PetHub.app，再
`PetHub.app/Contents/MacOS/PetHub --smoke`，同样 `PASS`（8.9s），确认 dev 和打包两种路径都对。
另外确认了：
- zip 解压后根目录就是 `PetHub.exe` + `resources/`（内含 `assets/`、`docs/WINDOWS.md`、`CREDITS.md`、`NOTICE.md`）；
- `resources/app.asar` 里的 `main.js` / `renderer/settings.js` 是修复后的最终版；
- 成功装一个包后再导入坏包会 `FAIL`，但 `--dump-state` 仍显示 `content=custom`（旧内容没被破坏），
  `--restore-builtin` 能回到内置 37 句。

**最终产物**（`./build-win.sh` 生成）：

| 文件 | 大小 | sha256 |
| --- | --- | --- |
| `PetHub-2.0.0-Windows-x64.exe` | 102,250,257 B（约 97.5 MiB） | `41f3bf53d8c76ae1d7034ca6905dea96af1db96b696209b2451ff3b339cb48b0` |
| `PetHub-2.0.0-Windows-x64.zip` | 141,254,674 B（约 134.7 MiB） | `8e0ad59c8d734ca6349a2b80a59d57890338db1e3cdc5d66cfc74ec5c977f197` |

每次构建的准确值以同目录 `PetHub-2.0.0-Windows-x64.sha256` 为准（上面的数字是 2026-10-26 的最终构建）。

## 版权

- 整合部分代码 MIT，见仓库根 [LICENSE](../LICENSE)；
- 音频、头像、Claude/GPT/Gemini 标志版权归原权利人，**不在 MIT 范围内**，不商用；
- JellyPet 无 LICENSE，果冻相关实现只按上游 README 的「代码可自由修改」合并，公开再分发前联系原作者；
- 完整署名：[CREDITS.md](../CREDITS.md)；素材边界：[NOTICE.md](../NOTICE.md)。