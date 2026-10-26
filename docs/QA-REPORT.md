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

---

# 1.1.0「大小联动」增量验收（2026-10-26 14:00–14:18）

> 本节是 1.0.0 交付之后的增量验收；上方 1.0.0 历史章节与证据原样保留、未被覆盖。验收对象为 13:55 冻结的 `build/桌宠合集.app` 与 `dist/PetHub-1.1.0.dmg`（sha256 `0a897f7c…`）。
> 仓库在验收前已建 git（`v1.0.0` tag + 未提交工作树），变更可用 `git diff v1.0.0 --stat` 复核（10 个文件，+192/−36）。

## A. 结论

**1.1.0 验收通过（PASS）**：大小联动（改一只四只同档）、统一大小、开关默认开与持久化、四只 size 偏好写入、关掉联动只改自己、诊断只读、无递归/重复写、`--self-test` 201 项、`--chain-test`、dump/preview、单实例、DMG、文档一致性全部实测通过，无阻塞缺陷。

| 项目 | 结果 |
| --- | --- |
| 大小联动（真实总菜单/桌宠菜单 action → 四只同档 + 四只偏好） | PASS |
| 关掉联动后各改各的（真实 hub 读回 `hub.linkSize=false`） | PASS |
| 「统一大小 → 小/中/大」真实 action 四只同档 + 写四只偏好 | PASS |
| 默认开（干净域无 `hub.linkSize` 时第一次 toggle 写 false）+ 持久化读写回 | PASS |
| 无递归/重复写（连续 30 次改大小不漂移、不卡死） | PASS |
| 诊断模式只读（size/iconSide/位置都不写） | PASS |
| `./build.sh` 最后一行 PASS / `--self-test` 201 项 | PASS（独立 /tmp 副本复跑；工作区产物直跑 201） |
| `--chain-test`（4 句、hop 0/1/2/3、root 全薄肌、无第五句、允许一次重试） | PASS（3/3 首跑即过） |
| `--dump-state` / `--preview`（四张 2x + 合影，version=1.1.0） | PASS |
| DMG（sha/verify/卷名/Info.plist 1.1.0/挂载自检 201/只读） | PASS |
| 文档（1.1.0、大小联动、hub.linkSize、201 项、重试说明） | PASS |

## B. 变更范围与静态审查

`git diff v1.0.0 --stat`：`AudioPetController.swift +22`、`PetHost.swift +8`、`PetHubApp.swift +121`、`JellyPetController.swift +17`、`main.swift` 版本号、`build.sh` 版本号、README/TECHNICAL/AGENTS/DESIGN。

- 协议：`PetHubContext` 新增 `linkSizeEnabled` / `petSizeTierChanged(_:tier:)`；`PetHost` 新增 `applySizeTier(_:)` / `sizeTier`（带默认实现），[Sources/Hub/PetHost.swift:21-23](../Sources/Hub/PetHost.swift)、[:54-56](../Sources/Hub/PetHost.swift)。
- 主控：[Sources/Hub/PetHubApp.swift:34](../Sources/Hub/PetHubApp.swift) `linkSizeEnabled = hubDefaults.object(forKey:"hub.linkSize") as? Bool ?? true`（默认开）；[:133-137](../Sources/Hub/PetHubApp.swift) `petSizeTierChanged` 只在 `linkSizeEnabled` 时对 `order` 里除自己外的三只 `applySizeTier`；[:233-236](../Sources/Hub/PetHubApp.swift) toggle 持久化；[:238-241](../Sources/Hub/PetHubApp.swift) `setAllSizeTiers` 对四只应用；[:197-211](../Sources/Hub/PetHubApp.swift) 总菜单接线（「大小联动（改一只，四只一起变）」+「统一大小 ▸ 小/中/大」+ `commonSizeTier` 勾选）。
- 语音桌宠：[AudioPetController.swift:572-607](../Sources/Audio/AudioPetController.swift) `setSize` 写自己 + `savePosition` + 回报 tier；`applySizeTier` 只应用不回调；`sizeTier` 按 `sizeChoices` 映射（190/260/340、130/180/240、190/260/340）。
- 果冻：[JellyPetController.swift:536-554](../Sources/Jelly/JellyPetController.swift) `changeSize` 写 `pet.jelly.iconSide` + 回报 tier；`applySizeTier` 只应用不回调；档位 104/128/160。
- 递归/循环审查：`applySizeTier` 的实现不再调用 `context`，主控回调只从用户菜单 action 进入一次，链路是「菜单 → setSize/changeSize → context.petSizeTierChanged → 其余三只 applySizeTier」单向，不存在回环；`guard linkSizeEnabled` 让关闭时只写自己。
- 持久化键：语音三只 `pet.<id>.size`（Double），果冻 `pet.jelly.iconSide`（Int，沿用 1.0.0 已文档化的键）；四只互不覆盖。
- 诊断只读：音频 `diagnostic = testing || previewing || dumping || chainTesting`（[AudioPetController.swift:64](../Sources/Audio/AudioPetController.swift)）；果冻同样四件套（[JellyPetController.swift:577-582](../Sources/Jelly/JellyPetController.swift)），`setSize`/`applySizeTier`/`persist`/`savePosition` 均有 `!diagnostic` 保护。
- chain-test 重试：[PetHubApp.swift:530-590](../Sources/Hub/PetHubApp.swift) 首次不足 4 句时（接话让位属设计内放弃）等 1s 重试一次，第二次仍失败才 FAIL；成功仍 `exit(0)`。产品路径（播放/联动）无改动。

## C. 自检 / 只读（工作区 1.1.0 构建）

```text
$ defaults delete local.pethub.app
$ build/桌宠合集.app/Contents/MacOS/PetHub --self-test
== 201 项检查 ==
PASS                      # exit 0，OK=201，FAIL=0
$ defaults read local.pethub.app
Domain local.pethub.app does not exist      ← 干净域跑完不写偏好
```

新增 5 项全 OK：`统一大小：四只一起到「大」`、`大小联动：改一只，其余三只跟着变`、`菜单「统一大小 → 大」四只一起变`、`真实菜单：改薄肌大小，其余三只跟着变`、`关掉大小联动后各改各的`；总菜单结构断言从 15 项涨到 17 项仍 OK。

## D. 真实主控 harness（PetHubApp 正常启动，非诊断）

用项目 `Sources/` 编出独立 app（bundle id `local.pethub.hub-harness`，资源拷贝自 1.1.0 build），真实跑 `PetHubApp` 正常启动，通过 `NSApp.sendAction` 走真实菜单 action，偏好落独立域（不碰真实 `local.pethub.app`）。

**Phase 1（干净域，17/17 PASS）**：
- 干净域无 `hub.linkSize`；第一次点「大小联动」写入 `false`（证明默认是开），再点写回 `true`；
- 联动开：点薄肌菜单「人物大小→大」→ 三只语音窗口 340/240/340，四只偏好 `pet.shaolan.size=340`、`pet.sunpet.size=240`、`pet.fengge.size=340`、`pet.jelly.iconSide=160`（没有误写果冻位置）；
- 关联动：薄肌菜单「小」→ 只有薄肌窗口 190、其余 240/340 不动，只有 `pet.shaolan.size` 变 190；
- 总菜单「统一大小→中」真实 action → 三只窗口 260/180/260、四只偏好 260/180/260/128。

**Phase 2（预置 `hub.linkSize=false` 后新进程启动，9/9 PASS）**：
- 启动读回 false；点薄肌菜单「大」→ 只有薄肌 340/偏好 340，另外三只不动；
- 打开联动写回 true；再由太对了菜单「小」发起 → 四只 190/130/190/104，四只偏好同步写入。

日志：`/tmp/qa4-hub-phase1.log`、`/tmp/qa4-hub-phase2b.log`。

## E. 控制器层 harness（23/23 + 5/5 PASS）

同一套 Sources 编出的第二个 harness（独立 suite），覆盖真实菜单 action + 偏好 + 窗口宽度：联动开改一只 → 340/240/340/160 且四只偏好写入；连续 30 次小/中/大循环不递归/不漂移；统一大小写四只；关联动只改自己；果冻发起联动也带动三只；全部 shutdown 后重建四只 → 尺寸从偏好恢复到最后档位（340/240/340/160）。
诊断模式（`--self-test` 参数）下同样是真实菜单 action，内存尺寸变化但 suite 里**没有** size/iconSide/位置键（只留下 harness 自己为静音写的 volume，不是应用写的）。

日志：`/tmp/qa4-harness-normal.log`、`/tmp/qa4-harness-diag.log`。

## F. chain-test

3 次连续实测均 PASS，首跑即 4 句、无第五句、未触发重试：

```text
$ build/桌宠合集.app/Contents/MacOS/PetHub --chain-test
[chain] 第 1 次：3 秒后模拟点一下薄肌，等四步链跑完
[chain]   0: 薄肌 句=31 hop=0 root=薄肌 ...
[chain]   1: 太对了 句=11 hop=1 root=薄肌 ...
[chain]   2: 峰哥 句=9 hop=2 root=薄肌 ...
[chain]   3: 太对了 句=13 hop=3 root=薄肌 ...
PASS 四步捧哏链：…；real 0m19.240s；跑完偏好域不存在
```

`--chain-test` 的重试分支未强制触发（正常 3/3 通过），已代码审查 + 文档核对：只重试一次、第二次仍失败才 FAIL、成功退出码 0；重试仅影响测试，不改产品行为。日志：`/tmp/qa4-chain-{1,2,3}.log`。

## G. dump-state / preview / 单实例 / 窗口

- `--dump-state` 首行 `version=1.1.0 relay=on pets=4`，四只齐全；默认尺寸 260x296 / 180x228 / 260x291，果冻 560 pos=1640,88；写 `pet.*.size`/`pet.jelly.iconSide` 后恢复为 340x376 / 240x288 / 340x369，且 dump-state 前后偏好逐字节不变（只读）。
- `--preview` 四张 2x（520×592 / 360×456 / 520×582 / 1120×1120）+ 合影 2880×1280，与 1.0.0 一致；跑完不写偏好。
- 单实例回归：第一个正常实例在跑时第二个 0.14s 退出、窗口数不变；CGWindowList 见 4 只 layer=3 窗口（默认尺寸 768/1064/1280,24，果冻 560 透明窗口 1360,−192，图标中心 1640,88）+ 菜单栏状态项窗口。

## H. DMG 与独立构建

交付 dmg：

```text
sha256  0a897f7c26783a7c1c8bea37b74b11e3ca6e0bb754020644dfa46e60c7bd3fcc  PetHub-1.1.0.dmg（与 Lead 提供值一致，shasum -c OK）
hdiutil verify → checksum is VALID；UDZO；卷名「桌宠合集」
内容：桌宠合集.app + Applications -> /Applications
Info.plist：local.pethub.app / 桌宠合集 / CFBundleShortVersionString=1.1.0 / CFBundleVersion=1 / LSUIElement=true / CFBundleIconFile=AppIcon
Resources：四只素材 + AppIcon.icns + LICENSE + NOTICE.md + licenses/
挂载后直接 --self-test：201 OK / 0 FAIL / PASS / exit 0，跑完 local.pethub.app 域不存在
dist/ 只有 PetHub-1.1.0.{dmg,zip,sha256} 一套；1.0.0 在 /tmp/PetHub-1.0.0-archive
```

独立复跑（`/tmp/qa4-pet-repo`，rsync 交付源 + 排除 build/dist/.git/upstream，不碰交付目录）：`./build.sh --package` → 201 OK、末行 PASS、31.3s；dist 只出 1.1.0 一套，sha256 -c OK；该 dmg 挂载后 `--self-test` 201 PASS、Info.plist 1.1.0、不写偏好。

## I. 文档一致性

- README：安装/构建命令改 1.1.0；玩法表新增「大小联动 / 统一大小」行；`docs/preview-all.png` 链接存在（2880×1280）。
- TECHNICAL：新增大小联动段、`hub.linkSize` 偏好行、`--self-test 目前 201 项`、`--chain-test` 重试说明、dump 首行 1.1.0、构建版本 1.1.0。
- AGENTS：版本 1.1.0、`dist/PetHub-1.1.0.*`、大小联动边界（`PetHost.applySizeTier/sizeTier`）、`hub.linkSize`、chain-test 重试说明。
- docs/DESIGN：协议新增 `applySizeTier/sizeTier`、菜单结构加「大小联动/统一大小」、自检增加真实菜单 action、chain-test 18s+重试、ShortVersion/dmg 名 1.1.0、验收清单加大小联动。
- NOTICE/UPSTREAM/licences 与 1.1.0 无关且未被改坏（仍与 1.0.0 验收一致）；文档里无残留 `1.0.0`/`196` 引用；README/TECHNICAL 相对链接全部存在。

## J. 非阻塞观察（本轮新增）

- O4：默认尺寸下四只可见区域仍不重叠（自检断言 + CGWindowList 复核）；但「大」档时窗口会互相压住（薄肌 340 与太对了 240 窗口重叠 34pt，峰哥 340 与果冻 160 图标重叠 20pt），这是 DESIGN §5「改大小后允许溢出槽位、不挤压邻居」的预期结果，自检只断言默认布局，不算 1.1.0 缺陷。
- O5：`sizeTier` 在尺寸不等于任何菜单档位时回退为 1（中）；只有手工改偏好会产生这种值（UI 只能选三档），此时「统一大小」的勾选状态可能与实际像素不符，无正常路径影响。
- O6：打开联动不会立刻把四只已不同的大小拉齐，下一次改大小才同步（需求描述是“改一只四只一起变”，与 README/TECHNICAL 一致）。
- O7：TECHNICAL 写重试后“最长约 42 秒”，按 3+18+1+3+18 实际最坏约 43 秒（“约”可接受，未改文档）。
- 盲区：本会话无辅助功能/屏幕录制权限，真实鼠标点菜单/肉眼动画未自动化；本轮用“真实 PetHubApp + `NSApp.sendAction` 走真实菜单 action”替代点击路径，窗口尺寸从 `NSWindow.frame`/CGWindowList 读取；chain-test 重试分支未强制触发。

## K. task-4 清单覆盖

| # | 要求 | 结果 |
| --- | --- | --- |
| 1 | build.sh PASS / self-test 201 / 干净偏好不写 | PASS（工作区 201 + 独立 /tmp 构建 201，两处都 Domain does not exist） |
| 2 | 静态审查联动（递归/关闭各改各的/档位/持久化/默认开/GUI 接线） | PASS（§B；真实 action 已动态复核） |
| 3 | 动态联动与偏好（开/关/统一/持久化） | PASS（§D、§E） |
| 4 | chain-test / dump-state / preview | PASS（§F、§G；chain 3/3 首跑过） |
| 5 | DMG（sha/verify/卷名/1.1.0/挂载自检/只读/dist 唯一） | PASS（§H） |
| 6 | 文档一致性 | PASS（§I） |
| 7 | 报告追加 + complete task-4 | 本节即追加内容 |

**1.1.0 增量验收结论：PASS。无阻塞缺陷；交付物可发布。**

---

# 1.2.0「滑块大小 + 紧凑排列」增量验收（2026-10-26 15:04–15:32）

> 本节是 1.1.0 交付之后的增量验收；上方 1.0.0 / 1.1.0 历史章节原样保留、未覆盖。验收对象为 15:02 冻结的 `build/桌宠合集.app` 与 `dist/PetHub-1.2.0.dmg`（sha256 `ceee953b…`，验收期间 Sources/build/dist 未再变动）。
> 变更可用 `git diff v1.1.0 --stat` 复核（10 个文件 +192/−36 量级，新增未跟踪文件 `Sources/Hub/SizeSliderView.swift`）。

## A. 结论

**1.2.0 验收通过（PASS）**：大小滑块的菜单内 NSSlider 接线、50%–180% 范围与夹取、总菜单滑块永远四只一起、单只滑块受「大小联动」控制、四只偏好写入、紧凑排列（约 6pt/16pt、底边对齐、屏内不重叠、100%/180% 两档）、compact 后持久化与重启恢复、全部归位回标准布局、`--self-test` 204 项只读、`--chain-test`、dump/preview、DMG 与独立构建、文档一致性全部通过。无阻塞缺陷。

| 项目 | 结果 |
| --- | --- |
| SizeSliderView（NSMenuItem.view + 连续 NSSlider + target/action） | PASS（真实 target-action 派发 + applyForTesting） |
| 50%–180% 范围、四只按各自默认比例映射、两端夹取 | PASS |
| 总菜单滑块 160% → 四只一起变 | PASS（自检真实 hub slider） |
| 单只滑块（联动开/关）、写四只偏好、无递归 | PASS（真实 PetHubApp harness） |
| 紧凑排列 100% / 180%：底边 16、间距约 6、贴右 16、屏内、不重叠 | PASS |
| compact 持久化 + 重启恢复；全部归位回标准槽位 | PASS |
| `--self-test` 204 项 / 干净偏好不写 | PASS |
| `--chain-test`（4 句、hop 0/1/2/3、root 全薄肌、无第五句） | PASS（3/3） |
| `--dump-state`（version=1.2.0）/ `--preview` | PASS |
| DMG（sha/verify/卷名/Info.plist 1.2.0/挂载自检 204/只读） | PASS |
| 文档（1.2.0、滑块 50%–180%、紧凑排列、204、旧字样清除） | PASS（D3/D4 已修并复核） |

## B. 变更范围与静态审查

- 新文件 `Sources/Hub/SizeSliderView.swift`（58 行）：`NSMenuItem.view` 里放 48pt 高的自定义视图（NSSlider 252×20 + 说明文字），`NSSlider(value:minValue:0.5,maxValue:1.8)`、`isContinuous = true`、`target = self`、`action = #selector(sliderChanged)`；`sliderChanged()` 更新百分比文字并回调 `onChange(slider.doubleValue)`；`applyForTesting` 设值后直接走同一个 `sliderChanged`。范围常量与 `PetSizing.minScale/maxScale`（[PetHost.swift:37-40](../Sources/Hub/PetHost.swift)）一致。
- 菜单接线：主控 [PetHubApp.swift:168-211](../Sources/Hub/PetHubApp.swift) 与语音/果冻菜单都设 `autoenablesItems = false`（避免自定义视图被自动启用逻辑禁用）；总菜单顺序实际为「捧哏联动 → 大小联动 → 大小滑块 → 全部显示/隐藏/归位/紧凑排列」，与 15:27 版 README/DESIGN 一致（本轮已按实现修正文档顺序）。
- 主控联动：`linkSizeEnabled` 读 `hub.linkSize` 默认 true；`petSizeScaleChanged` 在联动开时对另外三只 `applySizeScale(scale)`；总菜单滑块走 `applyGlobalSizeScale` 直接四只一起（不受开关影响）；`toggleSizeLink` 持久化；`compactArrange` 见 §D。
- 控制器：[AudioPetController.swift:578-607](../Sources/Audio/AudioPetController.swift) `applySizeScale` 先夹取 `PetSizing.minScale...maxScale`，`size = defaultSize × scale`，更新窗口尺寸，`!diagnostic` 时写 `pet.<id>.size` 并 `savePosition`；`sizeScale = size/defaultSize`；`changeSizeScale` 应用后回报主控（`applySizeScale` 本身不回调，故无递归）。果冻 [JellyPetController.swift:532-554](../Sources/Jelly/JellyPetController.swift) 同理，写 `pet.jelly.iconSide`（Int）。
- 新协议边界：`PetHost.sizeScale/applySizeScale/visualWidth/moveToRow`；`PetHubContext.linkSizeEnabled/petSizeScaleChanged`。音频 `visualWidth = 窗口宽`，果冻 `visualWidth = iconSide`；`moveToRow` 音频直接设窗口原点，果冻把 `left/bottom` 换算成图标中心 `(left+side/2, bottom+side/2)` 再 `applyCenter()`，并在非诊断时 `persist()`。
- 旧接口清除：`Sources/` 里已无 `applySizeTier` / `sizeTier` / `sizeChoices` / `sizeLabel`（`grep` 仅 SizeSliderView 注释里提到历史「三档」，属说明性文字）；`AudioPetProfiles` 的 min/max 改为默认大小 × 0.5/1.8。
- 诊断只读：音频/果冻的 `diagnostic` 仍覆盖 `--self-test/--preview/--dump-state/--chain-test`；滑块回调里的 `settings.set` 与 `savePosition/persist` 都有 `!diagnostic` 保护。
- 紧凑排列（[PetHubApp.swift:246-262](../Sources/Hub/PetHubApp.swift)）：`gap=6`、`margin=16`、宽度取 `visualWidth`、`x = max(visible.minX+16, visible.maxX-16-total)`、`bottom = visible.minY+16`、按顺序 `moveToRow`。默认布局仍由 `PetLayout`（槽位/36/24）负责，「全部归位」不变。

## C. 自检 / dump / 偏好夹取（工作区 1.2.0 构建）

```text
$ defaults delete local.pethub.app
$ build/桌宠合集.app/Contents/MacOS/PetHub --self-test
== 204 项检查 ==
PASS                      # exit 0，OK=204，FAIL=0
$ defaults read local.pethub.app
Domain local.pethub.app does not exist      ← 干净域跑完不写偏好
```

新增/替换断言全 OK：总菜单滑块 160% → 四只 160%、薄肌菜单滑块 70% → 四只 70%、关掉联动只改自己、紧凑排列底边对齐/屏内/不重叠/语音间距 6pt/峰哥-果冻间距 6pt；菜单结构断言为 18 项。`--self-test` 只读（含滑块与 compact 动作）已由上面 Domain does not exist 证明。

`--dump-state`：

```text
version=1.2.0 relay=on pets=4
shaolan ... size=260x296 pos=768,24 ...
sunpet  ... size=180x228 pos=1064,24 ...
fengge  ... size=260x291 pos=1280,24 ...
jelly visible=true size=560x560 pos=1640,88
```

偏好夹取/恢复（写入 `size=10 / 999`、`iconSide=1000` 后 `--dump-state`）：薄肌 130x166、太对了 324x372（10→50%、999→180%），`--dump-state` 前后偏好文件逐字节不变（只读）；`--preview` 四张 2x（520×592/360×456/520×582/1120×1120）+ 合影 2880×1280，不写偏好。

单实例回归：第二个正常启动 0.13s 退出、第一个存活；CGWindowList 见 4 只 layer=3 窗口（默认 768/1064/1280,24，果冻 560 透明窗口）+ 状态项。

## D. 真实主控 harness（PetHubApp 正常启动，独立偏好域）

用项目 `Sources/` 编出独立 app（bundle id `local.pethub.hub-harness12`，资源拷贝自 1.2.0 build），真实跑 `PetHubApp`，用 Mirror 取内部 `pets` 后直接操作真实 `SizeSliderView`/菜单 action（不碰真实 `local.pethub.app`）。

**Phase 1（干净域，34/34 PASS）关键项**：
- 六项接线检查：默认宽度 260/180/260/128；桌宠菜单 `autoenablesItems=false`；滑块 min/max=0.5/1.8；`isContinuous + target/action` 非空；果冻菜单同样有滑块。
- 真实 NSSlider target-action 派发（`slider.doubleValue=0.9` + `NSApp.sendAction(action,to:target,from:slider)`）→ 四只都 90%；`applyForTesting(0.7)`（走同一 `sliderChanged`）→ 四只 70%，窗口 182/126/182，偏好 `pet.shaolan.size=182 / pet.sunpet.size=126 / pet.fengge.size=182 / pet.jelly.iconSide=89`，未误写果冻位置。
- 干净域无 `hub.linkSize`，第一次 toggle 写 false（默认开），再开写 true；关联动时太对了滑块 50% → 只有太对了 0.5，其余保持 0.7。
- 夹取：`applySizeScale(2.5)→1.8`、`applySizeScale(0.1)→0.5`、滑块拖到 1%→0.5、拖到 500%→1.8。
- 紧凑排列 100%：四只底边 16、全在 visibleFrame、互不重叠、间距 6.0/6.0/6.0、宽度 260/180/260/128、最右=1712（visible.maxX−16）。
- 紧凑排列 180%：先滑块到 180%（四只 1.8/1.8/1.8/1.8），四只底边 16、屏内、不重叠、间距 6.0/6.0/6.6、宽度 468/324/468/230、最右=1712；薄肌 origin 203.6、太对了 677.6、峰哥 1007.6、果冻图标中心 1596.8（phase1 实测 203,16 / 677,16 / 1007,16 / 1481,15 取整打印）。

**Phase 2（重启，9/9 PASS，同一偏好域）**：
- 重启恢复：大小 `[1.8, 1.8, 1.8, 1.796875]`（果冻 `iconSide` 存 Int 230，见 O9），compact 位置恢复（薄肌 203.6,16；果冻中心 x 1596.8）。
- 「全部归位」真实 action：薄肌/太对了/峰哥 回标准槽位 664/992/1176,24（`PetLayout.origin` 按各自 180% 面板宽算），果冻回默认中心 1640,88；大小保持 180% 不变。
- 终止后偏好落盘：`pet.*.panelX/Y` 分别为 664/992/1176,24，`pet.jelly.centerX/Y=1640,88`，尺寸 468/324/468/230。

日志：`/tmp/qa5-hub-phase1.log`、`/tmp/qa5-hub-phase2.log`。

> 说明：总菜单滑块 160% 的真实 hub 路径由 `--self-test` 直接取 `makeHubMenu()` 里的 `SizeSliderView` 走 `applyForTesting(1.6)` 覆盖（输出行 `OK 总菜单大小滑块：四只一起到 160%`）；harness 额外覆盖了单只滑块的真实 NSSlider target-action 与联动/持久化。**没有辅助功能权限，未做真实鼠标在菜单里按住拖动**（见 §H 盲区）。

## E. chain-test

3 次连续实测均 PASS、首跑即 4 句、无第五句、未触发重试：

```text
$ build/桌宠合集.app/Contents/MacOS/PetHub --chain-test
[chain] 第 1 次：3 秒后模拟点一下薄肌，等四步链跑完
[chain]   0..3: 薄肌 hop0 → 太对了 hop1 → 峰哥 hop2 → 太对了 hop3，root 全薄肌
PASS 四步捧哏链：…；real 0m19.231s；跑完偏好域不存在
```

`--chain-test` 重试实现未改（同 1.1.0），重试分支未强制触发；日志 `/tmp/qa5-chain-{1,2,3}.log`。

## F. DMG 与独立构建

```text
sha256  ceee953bcfbeeee9aae51b7569fcc2ec541e2654c97cb28b326856d4bfe7dcde  PetHub-1.2.0.dmg（与 Lead 提供值一致，shasum -c OK）
hdiutil verify → checksum is VALID；UDZO；卷名「桌宠合集」；app + Applications -> /Applications
Info.plist：local.pethub.app / 桌宠合集 / CFBundleShortVersionString=1.2.0 / CFBundleVersion=1 / LSUIElement=true / CFBundleIconFile=AppIcon
挂载后直接 --self-test：204 OK / 0 FAIL / PASS / exit 0，跑完 local.pethub.app 域不存在；codesign verify OK
dist/ 只有 PetHub-1.2.0.{dmg,zip,sha256}；1.1.0 在 /tmp/PetHub-1.1.0-archive
```

独立复跑（`/tmp/qa5-pet-repo`，rsync 源 + 排除 build/dist/.git/upstream）：`./build.sh --package` → 204 OK、末行 PASS、27.2s；dist 只出 1.2.0 一套，sha256 -c OK；该 dmg 挂载后自检 204 PASS、Info.plist 1.2.0、不写偏好。

## G. 文档一致性

- 1.2.0 版本号：README 安装/构建、TECHNICAL dump/构建/ShortVersion、AGENTS、DESIGN §6/§8、`main.swift`/PetHubApp 关于与 dump、`build.sh` 全部一致。
- 滑块：README/TECHNICAL/AGENTS/DESIGN 均写 50%–180%、默认 100%、总菜单永远四只一起、单只受 `hub.linkSize` 控制；`hub.linkSize` 偏好行保留。
- 紧凑排列：统一为「约 6pt 间距 + 16pt 边距」并说明像素对齐可能差零点几（15:27 版）。
- 旧字样：文档中无残留 `1.1.0` / `201` / `统一大小` / `applySizeTier` / `sizeTier` / `sizeChoices` / 「小/中/大」三档（`grep` 无命中；源码仅 SizeSliderView 注释提到历史三档）。
- 本轮发现并已由 Lead 修复的文档遗漏（15:27 版复核）：
  - **D3**：`docs/DESIGN.md` 的 `PetHubContext` 缺 `linkSizeEnabled` / `petSizeScaleChanged`，已补（现 :83-84）。
  - **D4**：`TECHNICAL.md` §2 模块表缺 `Sources/Hub/SizeSliderView.swift`，已补（现 :41）。
  - 菜单条目顺序改为「大小联动 → 大小滑块」，与 `makeHubMenu` 一致；6pt 统一为「约 6pt」。
- README/TECHNICAL 相对链接全部存在；`docs/preview-all.png` 链接有效（2880×1280）。
- NOTICE/UPSTREAM/licenses 未被本轮改动，内容仍与 1.0.0/1.1.0 验收一致。

## H. 非阻塞观察与盲区

- O8：180% 下「全部归位」按标准槽位（默认大小算）会溢出/互相压住：果冻图标中心仍是 1640、边 230 → 右缘 1755 > visibleFrame.maxX 1728，即贴出屏幕约 27pt；三只语音窗口也会互相压。这是 DESIGN §5 明确的「改大小后允许溢出槽位」，标准布局不是大尺寸的收拢方案；大尺寸应使用「紧凑排列」（180% 已验五段全在屏内、贴 16pt）。实现无 bug，建议文档/README 可补一句用法提示（本轮未改）。
- O9：果冻 `iconSide` 偏好仍存 Int，180% = 128×1.8 = 230.4 落盘为 230，重启后 `sizeScale = 230/128 = 1.796875`（180% 差 0.3%，肉眼无感）；`commonScale` 的 0.01 容差可正确识别为一致。
- O10：四只比例不一致时总菜单滑块回 100%（`commonScale()==nil`），拖一下即四只统一；行为合理，文档未专门描述。
- O11：`moveToRow`/`savePosition` 在 `isVisible=false` 时不落盘（`savePosition` 原有守卫）；隐藏状态执行紧凑排列，其新位置不会持久化，重新显示后位置可能回旧值。属边缘操作组合，未发现正常路径影响。
- 盲区：无辅助功能/屏幕录制权限，**未做真实鼠标在打开菜单里按住 NSSlider 连续拖动**；用真实 NSSlider target-action 派发 + `applyForTesting`（同一个 `sliderChanged`）+ 自检里的真实 hub 菜单滑块覆盖。`--chain-test` 重试分支未强制触发。真实鼠标点击/肉眼动画建议交付后人工补 1 分钟。
- 清理：测试期间弹出的 `/Volumes/桌宠合集` 是遗留的 **1.1.0** 挂载（plist 已确认），已 `hdiutil detach`；当前无 PetHub 进程、无挂载、偏好域已清空，`build/`、`dist/` 未被改动。

## I. task-5 清单覆盖

| # | 要求 | 结果 |
| --- | --- | --- |
| 1 | 静态审查滑块/autoenablesItems/范围/映射/无递归/总菜单 vs 单只/compact 坐标 | PASS（§B） |
| 2 | build.sh PASS / self-test 204 / 不写偏好 / dump 1.2.0 / chain PASS | PASS（§C、§E；独立构建亦 204） |
| 3 | harness：总菜单 160%、单只 70%、关联动、偏好、重启、50%/180% 夹取 | PASS（§D；总菜单真实路径由自检覆盖） |
| 4 | 紧凑排列 100%/180%、底边/间距/屏内/不重叠/持久化/全部归位 | PASS（§D） |
| 5 | DMG sha/verify/卷名/1.2.0/挂载自检 204/只读/dist 唯一 | PASS（§F） |
| 6 | 文档（1.2.0/滑块/紧凑排列/hub.linkSize/204/旧字样） | PASS（§G；D3/D4 已修） |
| 7 | 报告追加 + complete task-5 | 本节即追加内容 |

**1.2.0 增量验收结论：PASS。无阻塞缺陷；交付物可发布。**

---

# 1.3.0「捧哏排列（合影）+ 绑定相对位置」增量验收（2026-10-26 17:00–19:17）

> 本节是 1.2.0 之后的增量验收；上方 1.0.0/1.1.0/1.2.0 历史章节原样保留。最终验证对象为 **17:30 冻结的干净构建**：`build/桌宠合集.app`（604272 字节）与 `dist/PetHub-1.3.0.dmg`（sha256 `8a9d627a…`）。
> 期间发生一次环境冲突：另一个会话在 17:13 往 `Sources/Hub/PetHubApp.swift` 注入 `[zdebug]` 并重建 build/，Lead 清理后 17:30 重新出干净构建；本报告以 17:30 构建为准，17:02/17:16 的旧结果只作为过程证据。

## A. 结论

**1.3.0 验收通过（PASS）**：捧哏排列（比例/坐标/抬高/左右/果冻右肩后/z 序/自动绑定/屏幕跟随）、绑定相对位置（真实 view 拖动、四只同增量、果冻跟随但不发起、开关持久化、重启恢复、落盘、亚点步长不漂移）、预览三图、DMG、文档全部通过。验收中发现 2 个实现缺陷（F2 排列屏幕选择、F3 绑定拖动亚点漂移）均已由 Lead 修复并在最终构建复验；2 处文档遗漏已修。无遗留阻塞项。

| 项目 | 结果 |
| --- | --- |
| 捧哏排列（1.2/1.4/1.2/0.65、抬高 62pt、左右、果冻右肩后、屏内） | PASS |
| z 序（前→后）薄肌 / 峰哥 / 太对了 / 果冻 | PASS（CGWindowList，runloop 提交后查） |
| 排列后自动绑定 + 持久化 `hub.groupDrag` | PASS |
| 绑定拖动：真实 AudioPetView 多步拖动四只同增量 + 果冻跟随 + 松手落盘 | PASS |
| 关掉绑定只动被拖的那只；重启恢复 groupDrag/位置 | PASS |
| F3：4 步 ×2.5 → 其余三只 +10,+10（0.2pt 内）；整数步长对照 | PASS（修复后） |
| 排列/紧凑排列跟随薄肌所在屏幕（双屏场景） | PASS |
| `--self-test` 213 项 / 干净偏好不写 | PASS |
| `--chain-test`（3 次，1 次自动重试后 PASS、4 句、无第五句） | PASS |
| `--preview` 四单图 + preview-all + preview-stage（6 张） | PASS |
| DMG（sha/verify/卷名/1.3.0/挂载自检 213/只读/唯一） | PASS |
| 文档（1.3.0、213、hub.groupDrag、preview-stage、D5/D6） | PASS |

## B. 变更范围与静态审查

`git diff v1.2.0 --stat`：`AudioPetController/AudioPetViews/PetHost/PetHubApp/JellyPetController/main.swift/build.sh` + README/TECHNICAL/AGENTS/DESIGN + `docs/preview-all.png` 重新生成；新增 `docs/preview-stage.png`（未跟踪交付图）。

- **捧哏排列**（[PetHubApp.swift:303-340](../Sources/Hub/PetHubApp.swift)）：先 `applySizeScale` 1.2/1.4/1.2/0.65；`arrangementScreen()` 用薄肌窗口中心的屏幕（[PetHubApp.swift:276-284](../Sources/Hub/PetHubApp.swift)）作为基准；`base=visible.minY+36`、行内间距 6；薄肌/太对了/峰哥 按宽度从左到右，太对了 `raise = max(56, 薄肌高×0.18)`（实测 62pt）；果冻中心 `x=峰哥右边−0.55×图标边长`、`y=base+峰哥高×0.68`；随后按 `[果冻, 太对了, 峰哥, 薄肌]` 依次 `bringToFront()`（后→前，薄肌最前）；最后 `groupDragEnabled=true` 并在非诊断模式写 `hub.groupDrag=true`。
- **绑定相对位置 / F3 修复**：`AudioPetView.mouseDragged` 首次越过 4pt 阈值时 `groupDragBegan()`，之后每步把增量回调 `groupDragMoved`，`mouseUp` 先 `savePosition()` 再 `groupDragEnded()`（[AudioPetViews.swift](../Sources/Audio/AudioPetViews.swift)）。主控 `petDragBegan` 记录其余三只基准并清零 `groupDragTotal`；`petDragged` 累加**总偏移**后用 `setGroupDragOffset(dx: total, dy: total)` 让其余三只相对基准绝对定位；`petDragEnded` 统一 `endGroupDrag()` 落盘（[PetHubApp.swift:146-170](../Sources/Hub/PetHubApp.swift)）。被拖的那只仍走原来的 `initialWindow+delta` 绝对路径；果冻 `beginGroupDrag` 记图标中心、`setGroupDragOffset` 用 `center=基准+偏移`（[JellyPetController.swift:575-590](../Sources/Jelly/JellyPetController.swift)），果冻自己的 `JellyView` 拖动仍只做原地 Q 弹、不调用 group drag。这样避免逐步读回 window server 量化后的 frame origin 造成累积丢点（F3 根因）。
- 协议：`PetHost` 新增 `bringToFront/windowFrame/moveBy/persistPosition`（排列/拖动/合成用），F3 又加 `beginGroupDrag/setGroupDragOffset/endGroupDrag`；`PetHubContext` 新增 `groupDragEnabled/petDragged/petDragEnded`，F3 加 `petDragBegan`。DESIGN §2 已同步（D6）。
- 预览：`--preview` 先写四张单图 + `preview-all.png`，再写 `makeStageComposite()`：`stageArrange()` 后按 `[果冻,太对了,峰哥,薄肌]` 取 `previewImage()` 与 `windowFrame` 在 1440×720 画布（2x 输出 2880×1440）上按 z 序合成；果冻的 `windowFrame` 已实现（560×560 透明窗口），修复了此前合成缺果冻的问题。
- 自检：204 → **213**（新增捧哏排列 8 项 + 绑定拖动小数步长 1 项）；`--self-test/--preview/--dump-state/--chain-test` 仍只读（`PetHubApp.diagnostic` + 各处 `!diagnostic` 保护）。
- 诊断只读复核：干净域下 `--self-test`、`--preview` 均不产生 `local.pethub.app` 域（含 stage 排列/自动绑定路径）。

## C. 基线（17:30 最终构建）

```text
$ defaults delete local.pethub.app
$ build/桌宠合集.app/Contents/MacOS/PetHub --self-test
== 213 项检查 ==
PASS                     # exit 0，OK=213，FAIL=0
$ defaults read local.pethub.app
Domain local.pethub.app does not exist

$ ... --dump-state
version=1.3.0 relay=on pets=4
shaolan size=260x296 pos=768,24 / sunpet 180x228 pos=1064,24 / fengge 260x291 pos=1280,24 / jelly 560 pos=1640,88

$ ... --help → 桌宠合集 PetHub 1.3.0
```

`--chain-test` 在最终构建连跑 3 次均 PASS（第 2 次首轮按设计放弃一捧，日志出现“重试一次”，第 2 次 4 句、hop 0/1/2/3、root 全薄肌、无第五句；其余两次首轮即过）。`--preview /tmp/qa6c-preview` 出 6 个文件：四张单图 2x（520×592 / 360×456 / 520×582 / 1120×1120）+ `preview-all.png` 2880×1280 + `preview-stage.png` 2880×1440，跑完偏好域不存在。单实例：第二个正常启动 0.14s 退出、第一个存活。

## D. 捧哏排列：视觉与坐标

`docs/preview-stage.png`（最终构建生成，2880×1440）用 read_image 复核：薄肌在左、太对了居中且明显抬高、峰哥在右、果冻（Claude 标记）缩在峰哥右肩后且可见（未被完全遮死），四只按后→前叠放，背景透明区干净。`docs/preview-all.png` 一排名与 1.2.0 一致。

真实 PetHubApp harness（独立域）点击真实 `stageArrange` 后的窗口坐标（主屏 visibleFrame `(70,0,1658,1079)`）：

```text
[stage] shaolan 455.0,36.0  312.0x348.0
[stage] sunpet  773.0,98.0  252.0x300.0   （抬高 62pt）
[stage] fengge 1031.0,36.0  312.0x342.0
[stage] jelly  1255.6,227.0  83.2x83.2    （峰哥右肩后，中心 1297.2,268.6）
```

比例 1.2/1.4/1.2/0.65、四只都在屏内、果冻与峰哥可见区重叠（叠放）、自动 `hub.groupDrag=true`、尺寸偏好 312/252/312/83、四只位置均已落盘。z 序用 CGWindowList（**runloop 提交后**查询）：前→后 = 薄肌 / 峰哥 / 太对了 / 果冻，与 `bringToFront` 顺序一致。

## E. 绑定相对位置与重启（真实 AudioPetView 事件 + 真实主控）

- **真实 view 拖动**（合成 mouseDown/mouseDragged×4/mouseUp，窗口随步移动）：绑定开时拖薄肌 Δ(40,−20) → shaolan/sunpet/fengge/jelly 全部 +40,−20，果冻图标中心同样 +40,−20，松手后其余三只位置落盘。
- **关掉绑定**：真实 toggle 写 `hub.groupDrag=false`；再拖薄肌 24pt → 只有薄肌动，其余三只不动；重新开启写回 true。
- **重启（Phase2，18/18 PASS）**：恢复比例 `[1.2,1.4,1.2,0.6484375]`、`hub.groupDrag=true`；实际 frame 与落盘坐标一致（shaolan 455,36 / sunpet 773,98 / fengge 1031,36 / jelly 中心 1255.74,227.06），相对关系（抬高/左右/果冻右肩后/屏内）保持；重启后真实拖动太对了 Δ(−20,+8) → 四只同增量（整数步长）。
- **回归**：compact 后底边=minY+16、间距约 6（6.0/6.0/6.8，亚点取整）、最右贴 16、屏内不重叠；全部归位回标准槽位（742/1028/1254,24，果冻 1640,88）；大小滑块 1.0 四只联动仍正常。

**F3 修复复验（Phase4）**：

```text
[drift-frac-fixed] shaolan=0.00,0.00 / sunpet=10.00,10.00 / fengge=10.00,10.00 / jelly=10.00,10.00
OK F3 修复：4 步 ×2.5 其余三只整体 +10,+10（0.2pt 容差）
OK 整数步长对照 5×2 = +10,+10 仍正确
```

修复前同用例日志在 `/tmp/qa6b-hub-phase4.log`：audio 两只 8pt、果冻 10pt（差 2pt）；修复后一致。

## F. 本轮缺陷与修复

- **F2（实现，排列屏幕选择）**：原 `stageArrange/compactArrange` 用 `PetLayout.screen()`（`NSScreen.main`），App 不活跃时 main 可能指向副屏，排列可能跑到与四只当前所在不同的屏幕。Lead 新增 `arrangementScreen()`：优先薄肌窗口中心所在屏幕，找不到才回退。最终构建双屏复验（Phase3 8/8）：把薄肌移到左侧副屏后，捧哏排列与紧凑排列都落在副屏，未跑回移动前的屏幕，且底边/贴边都按副屏 visibleFrame 计算。
- **F3（实现，绑定拖动亚点漂移）**：见 §B/E；按“基准 + 累计偏移”绝对定位修复，复验 4×2.5 = +10,+10；`--self-test` 新增该项，计数 213。
- **D5（文档）**：`--preview` 现在 6 张（四单图+all+stage），TECHNICAL/DESIGN/AGENTS 已改；已复核。
- **D6（文档）**：DESIGN §2 补 `PetHubContext.petDragBegan` 与 `PetHost.beginGroupDrag/setGroupDragOffset/endGroupDrag`；AGENTS 拖动段改成“petDragBegan 建基准 → petDragged 累计偏移 → setGroupDragOffset 绝对定位”；已复核。
- 过程环境冲突：17:13 另一会话向 `Sources/Hub/PetHubApp.swift` 注入 `[zdebug]` 并重建 build/（非本次验收操作）；Lead 清理并 17:30 重新冻结。最终验收只用 17:30 干净构建；污染构建（587488 字节）未作为交付物。

## G. DMG 与独立构建

```text
sha256  8a9d627abcc9bdcf28809e908f2cdcbd04ad1c279aa8b67135eefc7932701bc8  PetHub-1.3.0.dmg（与 Lead 提供值一致；shasum -c OK）
hdiutil verify → checksum is VALID；UDZO；卷名「桌宠合集」；app + Applications -> /Applications
Info.plist：local.pethub.app / 桌宠合集 / CFBundleShortVersionString=1.3.0 / CFBundleVersion=1 / LSUIElement=true / CFBundleIconFile=AppIcon
挂载后直接 --self-test：213 OK / 0 FAIL / PASS / exit 0；跑完 local.pethub.app 域不存在；codesign verify OK
dist/ 只有 PetHub-1.3.0.{dmg,zip,sha256}；1.2.0 在 /tmp/PetHub-1.2.0-archive
```

独立复跑（`/tmp/qa6c-pet-repo`，rsync 源 + 排除 build/dist/.git/upstream）：`./build.sh --package` → 213 OK、末行 PASS、24.9s；dist 只出 1.3.0；sha256 -c OK；该 dmg 挂载后自检 213 PASS、不写偏好。

## H. 文档一致性

- README：安装 `PetHub-1.3.0.dmg`、玩法表加「捧哏排列」「绑定相对位置」、**两张**预览图 `docs/preview-all.png` / `docs/preview-stage.png` 链接均有效。
- TECHNICAL：§5 增加合影比例/抬高/果冻右肩后/后前层次、排列跟随薄肌屏幕、绝对定位防亚点漂移、`hub.groupDrag` 偏好行、`--self-test 213 项`、dump 首行 1.3.0、构建版本 1.3.0、`--preview` 六张。
- AGENTS：版本 1.3.0、排列/拖动的 `petDragBegan`→`petDragged`→`setGroupDragOffset` 链路、`hub.groupDrag`、六张预览图。
- docs/DESIGN：PetHost/PetHubContext 新成员、菜单新增两项、自检描述加捧哏排列/绑定相对位置、ShortVersion/dmg 名 1.3.0、验收清单加排列与绑定。
- 旧字样：文档无 `1.2.0` / `204` / `212` 残留；`--preview` 已统一“6 张”；README/TECHNICAL 相对链接无坏链。

## I. 非阻塞观察与盲区

- z 序断言已从 `--self-test` 移除（Lead 说明：同一 runloop 立刻查 CGWindowList 时 window server 未提交，时序不稳）；本轮 z 序由 harness 在 runloop 提交后用 CGWindowList 验证，结果正确。`bringToFront` 仍是 `orderFrontRegardless`（无后加的 order(.above)）。
- 果冻尺寸偏好 `iconSide` 仍存 Int：0.65×128=83.2 落盘 83，重启 `sizeScale=0.6484375`（差 0.15%，自检/harness 容差内）。
- 默认布局/「全部归位」仍走 `PetLayout.screen()`（`NSScreen.main`）；App 不活跃时可能把初始一排放到副屏（本轮曾在副屏看到 dump 928,1141）。本次只修了排列/紧凑排列的屏幕跟随（F2 范围），默认布局未改；真实 GUI 启动通常 main=主屏，故记观察不阻塞。
- 阶段合成图底部是窗口底边（人物素材本身在窗口内截断），不是裁切错误；果冻在峰哥右肩后可见约右侧一块，符合“别被完全遮死”。
- 盲区：无辅助功能/屏幕录制权限，未做真实鼠标拖菜单滑块/真实鼠标拖桌宠；用真实 AudioPetView 事件、真实 NSSlider target-action、真实 PetHubApp action 与 CGWindowList/NSWindow.frame 替代。chain-test 重试分支在最终构建第 2 次真实触发并恢复 PASS。
- 环境：本轮验收前有遗留 `/Applications/桌宠合集.app` 运行实例与 `/Volumes/桌宠合集`（1.2.0）挂载，已按 Lead 要求停止进程/卸载；最终无 PetHub 进程、无挂载、偏好域已清；`/Applications` 里 Lead 安装的 1.3.0 未删除、未安装新副本。

## J. task-6 清单覆盖

| # | 要求 | 结果 |
| --- | --- | --- |
| 1 | 静态审查排列/拖动链路（比例坐标、z 序、增量持久化、果冻不发起、递归、诊断只读） | PASS（§B；F3 修复后绝对定位） |
| 2 | build.sh PASS / self-test 213 只读 / dump 1.3.0 / chain 3 次 / preview 六张 stage 图 | PASS（§C、§D） |
| 3 | 真实 harness：排列 action、真实拖动、groupDrag 开关/落盘/重启、样式回归 | PASS（§D、§E；Phase1/2/3/4） |
| 4 | DMG sha/verify/卷名/1.3.0/挂载自检 213/只读/dist 唯一 | PASS（§G） |
| 5 | 文档（1.3.0/213/hub.groupDrag/preview-stage/旧字样） | PASS（§H；D5/D6 已修） |
| 6 | 报告追加 + complete task-6 | 本节即追加内容 |

**1.3.0 增量验收结论：PASS。F2/F3 已修复并复验，D5/D6 已修，无遗留阻塞项；交付物 `dist/PetHub-1.3.0.dmg`（sha256 `8a9d627a…`）可发布。**