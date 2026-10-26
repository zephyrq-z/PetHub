# 桌宠合集 · 独立验收报告

- 验收方：qa-dev（独立验收，不参与实现）
- 验收对象：`/Users/zzq/Developer/tools-set/Pet`，版本 1.0.0
- 验收时间：2026-10-26 13:07–13:38（Asia/Shanghai）
- 环境：macOS 15.8（24H23）· arm64 · 主屏 visibleFrame `(65, 0, 1663, 1079)` @2x · 第二块屏在主机上方
- 构建源快照：2026-10-26 13:21 的 `build/桌宠合集.app` / `dist/PetHub-1.0.0.dmg`（sha256 `130b4c0c…`），之后构建/打包冻结；13:36 只更新了文档（TECHNICAL/AGENTS/DESIGN/licenses/README），未重新构建
- 说明：本报告只写验收证据与结论；未修改 `Sources/`、`Assets/`、`build.sh`、`install.sh`、`README` 等实现/交付文件（唯一写入本文件）。

## 0. 结论

**验收通过（PASS）**：单进程合集、四只桌宠规格、联动策略、果冻移植、构建/自检/四步链/预览/单实例/DMG/偏好边界全部实测通过。

| 项目 | 结果 |
| --- | --- |
| 单进程合集（不是四个 .app 套壳） | PASS |
| 规格一致性（素材/默认大小/动画/菜单/偏好键/联动） | PASS（仅文案级差异，见 §2.3） |
| 移植回归（对比 upstream 四个仓库） | PASS（果冻模型逐行一致；语音引擎仅做有意的归一化） |
| `./build.sh` 最后一行 `PASS` | PASS（196 项自检全 OK，18s） |
| `--self-test` | PASS（196 OK / 0 FAIL / exit 0） |
| `--chain-test` | PASS（4 句，hop 0/1/2/3，root 全薄肌，无第五句，19.3s） |
| `--dump-state` / `--preview` | PASS（四只状态齐全；四张 2x + 2880×1280 合影） |
| `--package` → dmg / 挂载自检 | PASS（UDZO、卷名「桌宠合集」、app+Applications 软链、`hdiutil verify` VALID、挂载后 196 项 PASS） |
| 单实例 / 显隐 / 布局 / 偏好隔离 | PASS |
| 文档与实现一致 | PASS（D1、D2 已由 Lead 修改，13:36 复核通过，见 §7） |

修复记录：验收过程中发现并已由 Lead 修复 1 个实现缺陷（F1：`--self-test` 会写果冻偏好）和 2 处文档不准确（D1 `--trace` 定位、D2 `SunPet-MIT.txt` 说明）；全部复验通过（§6.1、§7.2）。

## 1. 验收方法与证据来源

- 静态审查：`docs/DESIGN.md`、`AGENTS.md`、`README.md`、`TECHNICAL.md`、`NOTICE.md`、`docs/UPSTREAM.md`、`licenses/`；`Sources/` 全部 11 个文件；`upstream/` 四个仓库的对应实现；`build.sh`、`install.sh`、`Tools/make-icon.swift`。
- 独立编译检查：`swiftc -typecheck` 直接对 `Sources/**/*.swift` 通过（exit 0），不依赖 `build.sh`。
- 归一化 diff：把合并版类型名替换回上游名字后逐行对比（果冻模型/渲染/视图）。
- 动态实测：全部使用 13:21 冻结构建；诊断/自检采用干净偏好域（`defaults delete local.pethub.app`）；用 `CGWindowListCopyWindowInfo` 取窗口 bounds/layer（无屏幕录制权限也可靠），不用 `screencapture`。
- 独立构建/打包：把仓库 rsync 到 `/tmp/qa-pet-repo` 跑 `./build.sh --package`，不触碰交付目录 `build/`、`dist/`。
- 边界行为 harness：用项目自身 `Sources/` 编出一个独立测试 app（拷贝正式 app 资源到 `/tmp`，bundle id 改为 `local.pethub.qa-harness`），实测隐藏/联动开关/待播取消/默认位置/果冻预览/偏好前缀，不写真实偏好域。
- 不做的事：不安装 `/Applications`、不改实现文件、不在 Lead 构建期间并发跑真实实例。

## 2. 规格一致性（DESIGN §3、§4、§5）

### 2.1 单进程合集（不是壳）

证据：

- [Sources/Hub/PetHubApp.swift:94-104](../Sources/Hub/PetHubApp.swift) 的 `buildPets()` 在同一个进程里直接 `new` 三个 `AudioPetController` + 一个 `JellyPetController`，全部挂到本进程的 `PetHubContext`；没有 `NSTask`/子 .app/`open` 启动四个旧 App。
- 唯一子进程是上游原设计的机身摇晃 helper（[Sources/Audio/Motion.swift:175-176](../Sources/Audio/Motion.swift) `--motion-helper`，127.0.0.1 回环 UDP），只在正常启动且传感器可用时拉起，与“四只桌宠同进程”不矛盾。
- 全仓库 `grep`：无 `NSTask`、无 `DistributedNotificationCenter` 使用；`Process(` 仅 Motion helper 一处；旧三份 `Bridge.swift` 没有被编进合集（`upstream/` 只读参考）。
- 运行时验证：正常启动后 `pgrep` 只有 `PetHub` + 可选 `PetHub --motion-helper` 两个进程；四只窗口同一 owner pid（`桌宠合集`），layer=3。

### 2.2 四只规格（与 DESIGN 表逐项核对）

| 项 | DESIGN | 实现/实测 | 结果 |
| --- | --- | --- | --- |
| 薄肌素材/句数 | 37 句 `.wav` | `Assets/shaolan`：37 句，`clips.json` 字段齐全，文件无缺失；`dump-state clips=37` | PASS |
| 太对了 | 28 句 `.m4a` | 28 句；`clips=28` | PASS |
| 峰哥 | 11 句 `.wav` | 11 句；`clips=11` | PASS |
| 默认大小 | 260 / 180 / 260 | 实测窗口 `260×296` / `180×228` / `260×291`；公式与 DESIGN §3.2、上游一致 | PASS |
| 果冻 | 窗口 560×560，图标 104/128/160 默认 128 | 窗口 560×560；默认 128；CGWindowList 图标中心 (1640,88) | PASS |
| 动画 | 竖压 12%/30fps；±0.055rad+上浮3px | [Sources/Audio/AudioPetViews.swift:115-145](../Sources/Audio/AudioPetViews.swift) 与 upstream 逐行一致（含 Reduce Motion） | PASS（静态+上游 diff） |
| 菜单 | 三只：挑一句/播放方式/轮播内容(真 NSButton)/音量 6 档/大小/停止/移回/隐藏；太对了另有捧哏开关+摇晃；峰哥/薄肌联动状态；果冻：回原位/大小/图标/隐藏 | 自检断言菜单结构与隐藏项全 OK；代码逐项核对见 [AudioPetController.swift:375-484](../Sources/Audio/AudioPetController.swift)、[JellyPetController.swift:480-518](../Sources/Jelly/JellyPetController.swift) | PASS |
| 偏好键 | `pet.<id>.` 前缀 | 干净域正常启动只出现 `pet.shaolan.excludedIDs`；harness 验证四前缀互不串 | PASS |
| 布局 | 右下角一行，槽位 260/180/260/128、间距 36、边距 24 | 实测窗口 768/1064/1280、果冻图标中心 1640,88 | PASS |

### 2.3 文案级差异（不影响功能，记录备查）

- 语音菜单“移回屏幕右下角” vs DESIGN §3.1 写作“移回默认位置”；行为是回到 `PetLayout` 槽位，不是简单靠右，建议 DESIGN 或菜单二选一统一。
- DESIGN §5 菜单标题写“桌宠合集 · 4 只”，实现是“桌宠合集 · 四只”。
- DESIGN §5 说 `--dump-state` “每只一行 `...` 加 `relay=on/off`”，实现只在首行给全局 `relay=on/off`，果冻行只有 `visible/size/pos`（TECHNICAL §7 已按实际写清楚）。
- 太对了普通点击的字幕时长：上游 SunPet 是 `duration+0.5`，合并版统一成 `duration+0.4`（捧哏句仍是 `+0.5`）。纯视觉停留 0.1s 差异，DESIGN §3.3 的“duration+0.4/0.5s”可涵盖，判定为可接受的归一化。
- 大小恢复的夹取范围：合并版按菜单档位夹取（190–340 / 130–240），上游夹取更宽（160–400 / 120–260）。只影响手工改过的偏好，UI 无法产生越界值，无用户可见影响。

## 3. 代码审查：对比 upstream 的移植回归

### 3.1 果冻（JellyPet）

- `JellyModel.swift` 与 `upstream/JellyPet/Sources/Jelly.swift`：把 `JellySpring/JellyModel` 换回 `Spring/Jelly` 后 diff **仅文件末尾换行差异**；弹簧参数（bulge 340/8.5、pullX/Y 420/28、popLevel 160/22）、软限位 `maxPullRatio 1.1`、tanh 软化、欠阻尼判据全部原样。
- `JellyPetController.swift` 的窗口/视图/渲染部分与 `main.swift` 归一化 diff：除类型名、`previewScale`/`SettingsKey`/`JellyPetError`/`JellyAssets` 等合集适配外，`hitTest` 半径 `iconSide*0.47`、`clampToIcon`、`CIBumpDistortion`（radius 0.35、strength 上限 ±0.35）、按压整体放大、朝光标单侧拉伸、`applyCenter()` 只在启动/回原位/唤醒时设窗口原点——**拖动/按压过程中没有任何 `setFrameOrigin`**；“窗口不动”成立。
- 静止停表：`tick()` 在 `model.isSettled` 时 `stopTicker()`，与上游一致；窗口显隐、`shutdown` 也停表。
- 自检保留上游全部断言（冲过头、过冲小凹坑、≥3 次过零、软限位、阻尼、局部放大中心/别处不动、真实素材离屏渲染三张图），并写入 `NSTemporaryDirectory()/jelly-pet-selftest/`；`--self-test` 输出包含这些项。

### 3.2 语音三只（Shaolan/Sun/FengGe）

逐项与 `upstream/FengGe-Desktop-Pet`、`SunPet`、`ShaolanPet` 对照：

- hop/root：用户点击 hop0/root 自己；接话播放广播 hop+1、root 原样；`PetRelay.announce` 不发给发送者、总开关关闭直接丢弃（[PetRelay.swift:43-52](../Sources/Hub/PetRelay.swift)）。
- reaction：薄肌恒 false；太对了 `(from == .shaolan || from == .fengge) && hop < 3`；峰哥 `from == .sunpet && root == .shaolan && hop < 3`（[AudioPetProfiles.swift:142-167](../Sources/Audio/AudioPetProfiles.swift)）——与上游三份 Bridge 的条件一致。
- `scheduleCompanion`：再 `guard hop < 3`；取消上次待播；`overlap = hop == 1 ? max(0.05, 0.3-0.1) : 0.3`；`delay = max(0.02, duration - overlap - lead)`；到点自己正在播就放弃——与 SunPet 原实现逐行对齐。
- 捧哏预解码：启动时 `AVAudioPlayer(contentsOf:).prepareToPlay()` 存入 `companionPlayers`；接话直接复用，不走读文件路径。
- 开头静音补偿：`leadingSilence` 读前 0.6s、阈值 `max(0.004, peak*0.06)`、逐样本找第一声——与上游算法一致；自检断言 `0 ≤ lead ≤ duration*0.6` 且全部捧哏句都量到。
- 捧哏池：太对了 `{1,2,4,11,13,14}` 且排除勾掉句；峰哥全部 11 句（上游就是 `companionPool = clips`）——与 DESIGN 一致。
- 轮播/固定模式/勾选排除：`ShuffleBag` 按 clip.id 存池（避免下标错位），100 轮不重复、首尾不重复；固定模式每次播钉住句；勾掉句不参与随机且太对了捧哏池同步排除——自检全 OK。
- 隐藏：`setVisible(false)` 停播、取消字幕与待播接话；`handleRelay` 首行 `guard isVisible, relayEnabled, bridgeEnabled, !testing`——隐藏后不接话（harness 实测）。
- 单实例与诊断：正常启动才做单实例检查；`--self-test/--chain-test/--dump-state/--preview` 豁免且只读（见 §6.1）。
- Motion：`Sources/Audio/Motion.swift` 与 upstream 仅差文件末尾新增的 `sensorAvailable()` 便利函数（[Motion.swift:194-201](../Sources/Audio/Motion.swift)），摇晃判定 `ShakeDetector` 原样。

### 3.3 有意差异（合理）

- 三份 `Bridge.swift` + `DistributedNotificationCenter` → `PetRelay` 进程内注册表（DESIGN 明确要求）；`PetRole`→`PetID`。
- 三只重复的 `AppDelegate` 引擎合并为一份 `AudioPetController`，差异收进 profile；三个独立 status item 收成一个合集菜单。
- 旧 App 偏好不迁移（bundle id 改变，README/TECHNICAL/NOTICE 已说明）。

## 4. 构建验收（独立复跑）

### 4.1 工作区构建（13:13 快照；最终代码的独立复跑见 §4.2）

```text
$ ./build.sh    # 观察时序为 13:13，代码与最终 13:21 构建仅差 Jelly 只读修复
...
== 196 项检查 ==
完成：build/桌宠合集.app
安装：./install.sh（或把 app 拖进「应用程序」）
PASS
real 0m18.127s
```

- 最后一行 `PASS`；`OK` 196 行、`FAIL` 0 行；含新增 6 项布局断言：
  `四只默认布局都能算出来`、四只各自 `默认位置完整落在屏幕可见区`、`四只默认可见区域互不重叠`。
- 编译：`swiftc -O -target arm64-apple-macosx14.0` + 5 个 framework；`file` 产物为 arm64 Mach-O；ad-hoc 签名 `codesign --verify` 通过。
- 环境检查（Darwin/arm64/macOS14+/swiftc）、`bash -n build.sh install.sh` 均通过。
- `--help` 退出 0；未知参数退出 2；`--no-self-test` 正常退出 0 且最后一行不是 `PASS`（与脚本注释一致）。

### 4.2 最终构建的独立 `--package`（/tmp 副本）

```text
$ cd /tmp/qa-pet-repo && ./build.sh --package
...
  -rw-r--r--  1 zzq  staff    10M Oct 26 13:25 PetHub-1.0.0.zip
完成：build/桌宠合集.app
安装：./install.sh（或把 app 拖进「应用程序」）
PASS
real 0m27.772s
$ (cd dist && shasum -a 256 -c PetHub-1.0.0.sha256)
PetHub-1.0.0.zip: OK
PetHub-1.0.0.dmg: OK
```

- 产物只有 `dist/PetHub-1.0.0.{dmg,zip,sha256}`；dmg 10 MB；挂载后 `桌宠合集.app` 的 `--self-test` 196 项 PASS、干净偏好不落盘；卷名「桌宠合集」。
- `Tools/make-icon.swift` 在 /tmp 副本独立运行：1.8s 生成 1024×1024 `Assets/AppIcon.icns`（1166257 字节）与 10 档 iconset，且 icns md5 与仓库内 `Assets/AppIcon.icns` 完全一致（`416d3ff8d9fe…`），可重复。

## 5. 打包验收（交付 dmg）

工作区 `dist/PetHub-1.0.0.dmg`（冻结版本）：

```text
sha256  130b4c0cd0787c5c9384710a3055d4d4d5dede69bcd6257b70b374398146e06d  PetHub-1.0.0.dmg
        （与 Lead 提供值一致；shasum -c OK）
hdiutil verify → "checksum of dist/PetHub-1.0.0.dmg is VALID"
格式 UDZO；卷名「桌宠合集」；只读挂载
内容：桌宠合集.app + Applications -> /Applications
Info.plist：CFBundleIdentifier=local.pethub.app、CFBundleName/DisplayName=桌宠合集、
            1.0.0 / 1、LSMinimumSystemVersion=14.0、LSUIElement=true、
            NSHighResolutionCapable=true、CFBundleIconFile=AppIcon、CFBundleExecutable=PetHub
Resources：shaolan/ sun/ fengge/ jelly/ + AppIcon.icns + LICENSE + NOTICE.md + licenses/(含 README.md)
签名：adhoc，codesign --verify --deep --strict OK；dmg 内可执行文件与 build/ 内 sha256 相同
挂载后直接跑 app --self-test：196 OK / 0 FAIL / PASS / exit 0；跑完 local.pethub.app 域仍不存在
```

## 6. 边界与行为实测

### 6.1 诊断/自检只读（F1 修复复验）

- F1（曾 FAIL，已修）：`--self-test` 的布局断言调用 `jelly.moveToDefaultPosition()`，而果冻 `persist()` 当时无条件写 `pet.jelly.centerX/centerY`。复现：干净域跑 `--self-test` 后出现这两个键。Lead 给 `JellyPetController` 加 `diagnostic` 后复验：
  ```text
  $ defaults delete local.pethub.app; build/桌宠合集.app/Contents/MacOS/PetHub --self-test
  == 196 项检查 == / PASS / exit 0
  $ defaults read local.pethub.app
  Domain local.pethub.app does not exist      ← 不再写
  ```
- 同样复验 `--dump-state`、`--preview`、`--chain-test`：跑完偏好域均不存在。
- `--self-test`、`--dump-state` 在已有正常实例运行时可直接执行（不触发单实例拦截），执行后原实例窗口数不变、偏好不变。

### 6.2 单实例

```text
第一个正常实例：pid 66698 存活，窗口 6 个（4 只 + 2 个菜单栏镜像窗口）
第二个正常启动：exit 0，耗时 0.13s，第一个仍存活，窗口数不变，偏好不变
```

`--trace` 实测会被单实例检测拦下（0.14s 退出）——它属于正常启动，不是只读诊断（见 D1）。

### 6.3 窗口/布局（CGWindowList，layer=3）

| 桌宠 | 窗口 bounds（左下原点） | 大小 | 说明 |
| --- | --- | --- | --- |
| 薄肌 | (768, 24) | 260×296 | 在 visibleFrame 内 |
| 太对了 | (1064, 24) | 180×228 | 在 visibleFrame 内 |
| 峰哥 | (1280, 24) | 260×291 | 在 visibleFrame 内 |
| 果冻 | 窗口 (1360, −192) | 560×560 | 透明窗口允许出屏；可见图标中心 (1640,88)，即 1576..1704 × 24..152，在屏内 |

- 三只语音窗口两两不重叠；果冻**可见图标**与三只语音窗口不重叠（与峰哥窗口物理重叠 180pt 是 560 透明窗口导致，上游手感，见 §8 口径）。
- 菜单栏：只创建一个 `NSStatusItem`（launch 后 CGWindowList 见 layer=25 的状态项窗口；两块屏的菜单栏各镜像一个，属 macOS 正常行为，不是四个入口）。
- `--dump-state` 首行 `version=1.0.0 relay=on pets=4`，四只齐全；数值与窗口实测一致。

### 6.4 显隐 / 联动开关 / 待播取消（harness，21/21 PASS）

```text
OK 链路共 4 句（shaolan hop0, sunpet hop1, fengge hop2, sunpet hop3）
OK 四步链 hop/root 全对
OK 第四跳后没有第五句
OK 隐藏的桌宠不接话（实际 ["shaolan"]）
OK 隐藏状态点击自己不出声
OK 联动关闭后不广播（实际 ["shaolan"]）
OK setRelayEnabled(false) 取消待播接话（实际 ["shaolan"]）
OK 三只默认位置 = PetLayout（768,24 / 1064,24 / 1280,24）
OK 果冻图标中心 = 槽位中心/bottom+64（1640,88）
OK 果冻窗口 560×560 / 显隐 / 预览 560pt·1120px
OK 四只偏好键前缀分开 / 各前缀取值互不串
== 21 项，FAIL 0 项 ==
```

说明：harness 用项目 `Sources/` 编译、跑在 `/tmp` 拷贝的 app 资源上、独立偏好 suite，不写用户域；“隐藏”通过 controller API 驱动（与菜单 action 最终调用同一方法）。

### 6.5 偏好、恢复与越界回退

- 写入 `pet.shaolan.size=190`、`pet.sunpet.size=240`、`pet.fengge.size=340`、`pet.shaolan.panelX/Y=200,200`、`pet.jelly.iconSide=160`、`pet.jelly.centerX/Y=500,200`、`hub.relayEnabled=false` 后 `--dump-state`：
  ```text
  version=1.0.0 relay=off pets=4
  shaolan ... size=190x226 pos=200,200 ... relay=off
  sunpet  ... size=240x288 pos=1034,24 ... relay=off
  fengge  ... size=340x369 pos=1240,24 ... relay=off
  jelly visible=true size=560x560 pos=500,200
  ```
  尺寸/位置/图标中心/全局开关全部生效；`--dump-state` 前后偏好文件逐字节不变（只读）。
- 越界回退：`panelX/Y = ±30000` / `centerX/Y = 30000` → 三只回默认槽位、果冻回 (1640,88)。
- 前缀隔离：四只键分别落到 `pet.shaolan.* / pet.sunpet.* / pet.fengge.* / pet.jelly.*`，互不覆盖（同时见 harness S8）。
- 默认大小下四只可见区域互不重叠（§6.3 + 自检断言）；把峰哥调到最大 340 时窗口会越出槽位、与果冻**窗口**有 4pt 重叠（与果冻可见图标仍不重叠），属于 DESIGN 允许的“改大后溢出一点”。

### 6.6 Preview

- 四张单图 + 合影，尺寸严格 2x：`preview-shaolan.png 520×592`、`preview-sunpet.png 360×456`、`preview-fengge.png 520×582`、`preview-jelly.png 1120×1120`、`preview-all.png 2880×1280`。
- 肉眼确认：薄肌/太对了/峰哥头像正确、透明背景、无字幕残留；果冻是居中的 Claude 标志（透明 560 窗口）。`docs/preview-all.png` 同为 2880×1280。

## 7. 文档/许可审查

### 7.1 已核对一致

- `README.md`：四只介绍句数（37/28/11）、默认 8 句轮播、玩法表（本次已按修复后的版本核对：拖动只限三只语音、果冻单独一行、右键菜单拆成语音三只/果冻）、安装三步、与四个独立 App 的关系、构建命令、版权声明、成品图 `docs/preview-all.png`；引用的 `Assets/*`、TECHNICAL.md、docs/UPSTREAM.md、NOTICE.md、LICENSE 全部存在（含 13:22 版新增的 `docs/preview-all.png`，文件存在且 2880×1280）。实测功能与之相符（“不联网”指不联外网，唯一通信是机身摇晃 helper 的 127.0.0.1 回环，TECHNICAL §1/§10 已写明）。
- `TECHNICAL.md`：架构图、模块表、启动流程、hop/root、reaction 表、四步链、布局参数、偏好键、CLI、构建打包、上游映射、已知限制与实现一致；§4.5 的“约 21 秒”实测 19.3s，量级正确。
- `AGENTS.md`：构建必须 PASS、hop/root 不可改、素材不进 MIT、JellyPet 无 LICENSE、arm64+macOS14、不联网、协议签名、单进程等约束与实现相符。
- `NOTICE.md`：音频/头像版权与非商用、三仓库 MIT、JellyPet 无 LICENSE 的例外、设计致谢；逐条与上游 NOTICE/README 对照（薄肌 BV 号/source 字段、太对了时间码、峰哥 `Work/audio-cut-notes.md`、Simple Icons/Wikimedia 标志来源）均能对上。
- `docs/UPSTREAM.md`：四个 URL、完整 commit 与短 hash、日期均与 `upstream/*/.git` 实测一致（`7ce7e2b…`/`9b68d09…`/`d3336de…`/`7306d4e…`，2026-10-25）；贡献/替换表与代码一致。
- `licenses/`：`LICENSE-ShaolanPet.txt`、`LICENSE-SunPet.txt`、`LICENSE-FengGe-Desktop-Pet.txt` 与上游 `LICENSE` 逐字节一致（md5 相同）；`SunPet-MIT.txt` 与上游 Shaolan/FengGe 仓库里的同名文件逐字节一致；JellyPet 确实没有 LICENSE 文件（已核对仓库根目录）。
- 构建会把 `LICENSE`、`NOTICE.md`、`licenses/`（含 README）一起拷进 app 的 `Contents/Resources/`，dmg 内已确认。

### 7.2 文档缺陷（D1、D2 已修复并复核）

**D1｜`--trace` 曾被写成“只读诊断”（已修复）**

问题：实测 `--trace` 是正常启动——写偏好（干净域跑 3 秒即出现 `pet.shaolan.excludedIDs`）、自动拉起 `--motion-helper`、在已有实例运行时被单实例检测拦下（0.14s 退出）。但 13:18 版文档把 `--trace` 归入“诊断模式”，并声称诊断模式免单实例拦截且只读（TECHNICAL.md:199-200/212、AGENTS.md:14/60、docs/DESIGN.md:209-210）。

修复复核（13:36 版）：

- [TECHNICAL.md §7](../TECHNICAL.md) 开头明确：「`--self-test` / `--chain-test` / `--dump-state` / `--preview` 是只读诊断……`--trace` **不是**只读诊断——它只是正常启动多打开一份 trace 输出，仍受单实例限制，也会正常写偏好、按正常启动开机身摇晃」；表格 `--trace` 行标注“**正常启动**”；段末再次区分；`--self-test` 项数也更新为“目前 196 项”。
- [AGENTS.md:14-15](../AGENTS.md) 诊断入口列表已移除 `--trace`，单独加一句“`--trace` 是**正常启动**加日志：受单实例限制、会写偏好、会按正常启动开机身摇晃，别当只读诊断用”；文末规则改为“自检/诊断模式（四件套）不做单实例拦截；正常启动（含 `--trace`）只允许一个实例”。
- [docs/DESIGN.md §5](DESIGN.md) `--trace` 标注“**正常启动**……受单实例限制、会写偏好”；同时 chain-test 的等待时间改为“等 18 秒（全程约 21 秒）”，与实现（18s 定时 + 3s 起播）一致。
- 复核结论：文档描述与我实测的进程行为完全一致。

**D2｜`licenses/README.md` 对 `SunPet-MIT.txt` 的描述不准确（已修复）**

问题：原写“与 `LICENSE-SunPet.txt` 内容相同”，实际 `SunPet-MIT.txt` 末尾多一段 “This license covers the source code only… audio clips… avatar image…” 素材例外（该文件与上游 Shaolan/FengGe 的 `licenses/SunPet-MIT.txt` 逐字节相同）。

修复复核（13:36 版）：[licenses/README.md:10](../licenses/README.md) 已改为“与 `LICENSE-SunPet.txt` 基本相同，但保留上游原文件末尾的「素材例外」段（源代码 MIT、音频/头像不在此许可内）；FengGe 和 Shaolan 的 NOTICE 原本链接的就是这个名字，保留以兼容上游链接”——与文件和 NOTICE 的措辞一致。

## 8. 验收口径说明（果冻 560 窗口 vs 可见图标）

按 Lead 裁决与本报告采用的口径：**布局验收看“可见区域”**——三只语音桌宠的窗口 + 果冻 128×128 的可见图标，必须互不重叠且完整落在 `NSScreen.visibleFrame` 内；果冻 560×560 的全透明窗口允许伸出屏幕、允许与峰哥窗口在物理 bounds 上重叠（这是 JellyPet 上游手感：窗口不动、只在图标附近 `hitTest`，其余透明区点击穿透）。DESIGN §8 已同步这个口径，自检断言也按此实现（6 项）。

## 9. 测试盲区（无屏幕录制/辅助功能权限）

- 未做真实鼠标路径：菜单栏下拉、右键菜单点选“隐藏/全部归位/关于”、点击透明区验证穿透、实际听声音。原因是本会话没有辅助功能/屏幕录制权限，`osascript` UI 脚本会卡在 TCC 授权。
- `install.sh --build/--from`（会写 `/Applications`）按 Lead 要求未实跑；`--help`/未知参数/`--uninstall`（未安装时 no-op）已实测，`bash -n` 通过。
- 替代证据：菜单结构由 `--self-test` 断言（含隐藏项、15 项总菜单）；菜单 action 最终调用的 controller 方法由 harness 实测；动画/弹簧由果冻自检与上游归一化 diff 证明；窗口存在/bounds/layer 由 CGWindowList 证明。
- 建议交付后人工补一次 5 分钟点击核对（装 dmg → 点四只/右键/隐藏/全部归位/关于），本报告不把该盲区算作实现缺陷。

## 10. 附：关键复现命令

```bash
# 自检（干净偏好，最后一行 PASS，且不写偏好）
defaults delete local.pethub.app 2>/dev/null
build/桌宠合集.app/Contents/MacOS/PetHub --self-test
defaults read local.pethub.app           # 期望：Domain does not exist

# 四步链（约 20s）
build/桌宠合集.app/Contents/MacOS/PetHub --chain-test

# 状态 / 预览
build/桌宠合集.app/Contents/MacOS/PetHub --dump-state
build/桌宠合集.app/Contents/MacOS/PetHub --preview /tmp/pethub-preview
sips -g pixelWidth -g pixelHeight /tmp/pethub-preview/*.png

# 单实例：先起第一个，再起第二个（应 <2s 退出）
build/桌宠合集.app/Contents/MacOS/PetHub & sleep 3
time build/桌宠合集.app/Contents/MacOS/PetHub   # 期望 0.x 秒退出

# dmg
hdiutil verify dist/PetHub-1.0.0.dmg
hdiutil attach -nobrowse -readonly -mountpoint /tmp/mnt dist/PetHub-1.0.0.dmg
/tmp/mnt/桌宠合集.app/Contents/MacOS/PetHub --self-test
plutil -p /tmp/mnt/桌宠合集.app/Contents/Info.plist
hdiutil detach /tmp/mnt

# 窗口 bounds/layer（无需屏幕录制权限）
# CGWindowListCopyWindowInfo(.optionOnScreenOnly) 过滤 owner pid，读 kCGWindowBounds/kCGWindowLayer

# 独立构建/打包（不碰交付 build/dist）
rsync -a --exclude build --exclude dist --exclude upstream ./ /tmp/qa-pet-repo/
cd /tmp/qa-pet-repo && ./build.sh --package && (cd dist && shasum -a 256 -c PetHub-1.0.0.sha256)
```

## 11. 缺陷清单汇总

| 编号 | 类型 | 严重度 | 状态 | 说明 |
| --- | --- | --- | --- | --- |
| F1 | 实现：`--self-test` 写果冻偏好 | 中（违反只读约定） | **已修复并复验** | `JellyPetController.moveToDefaultPosition→persist()` 未受 diagnostic 保护；修复后干净域自检不落盘 |
| D1 | 文档：`--trace` 曾被写成只读/免单实例诊断 | 低（准确性） | **已修复并复核（13:36）** | TECHNICAL §7、AGENTS、DESIGN §5 已按实测改写；与新文档逐条核对一致 |
| D2 | 文档：`SunPet-MIT.txt` 描述“内容相同” | 低（准确性） | **已修复并复核（13:36）** | licenses/README.md 已改为“基本相同，但保留上游原文件末尾素材例外段” |
| O1 | 文案：菜单“移回屏幕右下角” vs DESIGN“移回默认位置” | 极低 | 备查 | 行为正确（回 `PetLayout` 槽位） |
| O2 | 文案：菜单标题“四只” vs DESIGN“4 只”；dump-state 果冻行无 relay | 极低 | 备查 | TECHNICAL 已按实际文档化 |
| O3 | 移植归一化：太对了普通点击字幕 +0.4（上游 +0.5）；大小夹取范围按菜单档位 | 极低 | 备查 | 无用户可见功能影响 |

**最终结论：实现、构建、自检、四步链、打包、DMG、单实例、布局、显隐/联动边界、文档/许可一致性全部通过。F1（实现）与 D1/D2（文档）均已修复并复核，无遗留阻塞项。验收结论：PASS。**