# 桌宠合集 · 合并设计说明（给一起干活的 agent）

目标：把四个独立仓库（ShaolanPet / SunPet / FengGe-Desktop-Pet / JellyPet）
合成**一个项目、一个 App、一个 DMG**，四只桌宠同时住在同一个进程里。

2.0 起在此基础上把代码拆成 **PetKit 可复用内核 + PetHub 成品 App**，并支持用户用
PetPack 内容包把薄肌换成自己的角色（例如「我的老师」），其余三只和四步捧哏链不变。

- 产品名：**桌宠合集**（英文 PetHub），bundle id `local.pethub.app`，版本 2.0.0
- 要求：Apple Silicon + macOS 14+，`swiftc` 直接编，无第三方依赖，不联网
- 唯一交付物：`dist/PetHub-2.0.0.dmg`（卷名「桌宠合集」），里面一个 `桌宠合集.app` + `Applications` 软链
- 验收命令：`./build.sh` 最后一行 `PASS`；`./build.sh --package` 出单个 dmg；
  `PetHub --chain-test` 打印完整四步链并 `PASS`；`--self-test`（默认内置四只时 222 项）`PASS`

## 1. 目录与文件归属

```
Sources/PetKit/PetHost.swift              PetHost / PetHubContext 协议、PetError、PetSizing
Sources/PetKit/PetIdentity.swift          PetID、PetSettings
Sources/PetKit/PetRelay.swift             PetSpeech、PetRelay（进程内联动）
Sources/PetKit/PetPack.swift              PetPack 内容包模型/校验/安装（PetPackStore）
Sources/PetKit/SizeSliderView.swift       菜单里的 50%–180% 大小滑块
Sources/PetKit/Audio/AudioPetController.swift  三只语音桌宠的通用引擎（薄肌/太对了/峰哥）
Sources/PetKit/Audio/AudioPetViews.swift       AudioPetPanel / 头像视图 / 字幕
Sources/PetKit/Audio/AudioPetProfiles.swift    三份 profile + Clip
Sources/PetKit/Audio/Motion.swift              太对了的机身摇晃（从 SunPet 原样搬）
Sources/PetKit/Jelly/JellyModel.swift          果冻弹簧模型（从 JellyPet/Jelly.swift 移植）
Sources/PetKit/Jelly/JellyPetController.swift  果冻控制器 + 视图 + 渲染
Sources/PetKit/README.md                       内核分层与复用边界
Sources/PetHub/main.swift                      入口：--motion-helper / --probe-sensor / NSApp.run
Sources/PetHub/PetHubApp.swift                 主控：AppDelegate + 菜单栏 + 排列 + CLI + 自检
Sources/PetHub/PetLayout.swift                 四只桌宠首次启动的站位
Sources/PetHub/CustomHeadImporter.swift        「自定义桌宠」编辑窗口（头像/语音/中文）
Assets/shaolan/{face.png,clips.json,Clips/*.wav}
Assets/sun/{face.png,clips.json,Clips/*.m4a}
Assets/fengge/{face.png,clips.json,Clips/*.wav}
Assets/jelly/{claude-mark.png,gpt-mark.png,gemini-mark.png}
Assets/AppIcon.icns                    合集图标（Tools/make-icon.swift 生成）
Tools/make-icon.swift                  四张脸拼成 1024 圆角图标 → icns
build.sh / install.sh                  构建、安装、打包
README.md TECHNICAL.md AGENTS.md NOTICE.md CONTRIBUTING.md LICENSE licenses/
docs/ARCHITECTURE.md docs/PETPACK.md docs/MAKE_YOUR_OWN_PET.md docs/UPSTREAM.md
Examples/MyTeacher/                    内容包模板（不含二进制素材）
upstream/                              四个原始仓库的只读副本（.gitignore 掉，不进交付仓库）
```

改名已经做完：原 `Jelly` 结构体在合并版里叫 `JellyModel`，其余果冻类型统一加 `Jelly` 前缀，
避免和语音桌宠的 `PetPanel` / `PetView` 重名。语音桌宠侧的类型统一用 `Audio` 前缀或
放在对应文件里，只有一份实现。

## 2. 核心接口（已落盘，不要改签名）

```swift
enum PetID: String, CaseIterable, Codable { case shaolan, sunpet, fengge, jelly
    var title: String        // 薄肌 / 太对了 / 峰哥 / 果冻
    var fullName: String     // 薄肌桌宠 / 太对了桌宠 / 好事桌宠 / 果冻桌宠
    var assetsFolder: String // shaolan / sun / fengge / jelly
    var isAudio: Bool        // 果冻为 false
}

final class PetSettings { init(_ pet: PetID); bool/int/double/float/string/intSet/set/setIntSet/... }
// 键名自动加 "pet.<id>." 前缀

protocol PetHost: AnyObject {
    var id: PetID { get }
    var isVisible: Bool { get }
    var panelSize: NSSize { get }
    weak var context: PetHubContext? { get set }
    func start() throws
    func setVisible(_ visible: Bool)
    func makeMenu() -> NSMenu
    func moveToDefaultPosition()
    func setRelayEnabled(_ enabled: Bool)
    func handleRelay(_ speech: PetSpeech)
    func selfTest(_ report: (Bool, String) -> Void)
    func shutdown()
    func previewImage() -> NSImage?
    func showStartupHint()
    var stateDescription: String { get }
    var displayTitle: String { get }      // 菜单/关于面板的显示名；自定义薄肌时是用户起的名字
    var sizeScale: Double { get }        // 相对默认大小，1.0 = 默认；滑块 0.5–1.8
    func applySizeScale(_ scale: Double)
    var visualWidth: CGFloat { get }      // 紧凑排列算间距用
    func moveToRow(left: CGFloat, bottom: CGFloat)
    func bringToFront()
    var windowFrame: NSRect { get }
    func moveBy(dx: CGFloat, dy: CGFloat)  // 被拖的那只自己按增量平移
    func beginGroupDrag()                 // 其余三只记下基准位置
    func setGroupDragOffset(dx: CGFloat, dy: CGFloat)  // 基准 + 累计偏移，避免量化漂移
    func endGroupDrag()
    func persistPosition()
}

protocol PetHubContext: AnyObject {
    var relayEnabled: Bool { get }
    func isPetVisible(_ id: PetID) -> Bool
    func hidePet(_ id: PetID); func showPet(_ id: PetID); func togglePet(_ id: PetID)
    func forwardSpeech(_ speech: PetSpeech)
    func quitApp()
    var linkSizeEnabled: Bool { get }
    func petSizeScaleChanged(_ id: PetID, scale: Double)
    var groupDragEnabled: Bool { get }
    func petDragBegan(_ id: PetID)
    func petDragged(_ id: PetID, dx: CGFloat, dy: CGFloat)
    func petDragEnded(_ id: PetID)
}

struct PetSpeech: Equatable { let from: PetID; let clipID: Int; let label: String
                              let duration: TimeInterval; let hop: Int; let root: PetID }
final class PetRelay { var isEnabled: Bool; var traceEnabled: Bool
    func register(_ id: PetID, _ handler: @escaping (PetSpeech) -> Void)
    func announce(_ speech: PetSpeech)   // 发送者本人收不到
}

enum PetLayout { // 薄肌→太对了→峰哥→果冻，屏幕右下角一行
    static func origin(for id: PetID, panelSize: NSSize) -> NSPoint // 语音桌宠用
    static func slotCenterX(_ id: PetID, on screen: NSScreen) -> CGFloat // 果冻用
    static func bottom(on screen: NSScreen) -> CGFloat
}
```

`PetHost.start()` 里的窗口位置：有保存的位置就恢复，没有就调 `moveToDefaultPosition()`。
`moveToDefaultPosition()` 用 `PetLayout.origin(for:panelSize:)`；果冻用
`slotCenterX + bottom + 64` 作为图标中心（图标边长 128）。

**内容包不在协议里**：`PetPack` / `PetPackClip` / `PetPackStore`（`Sources/PetKit/PetPack.swift`）
只影响薄肌引擎读取素材的来源，不改变 `PetHost` / `PetHubContext` 的签名。流程是：

1. 菜单「自定义桌宠」→「换成我的角色…」编辑头像/语音/中文，或「导入 petpack.json 文件夹…」；
2. `PetPackStore.install` 写到临时目录、完整校验后原子替换
   `~/Library/Application Support/PetHub/HeadPet/`；
3. `AudioPetController.reloadContent()` 重新读内容、换头像/句数/名字，内容指纹变化时重置轮播勾选和固定句；
4. `PetID` 仍是 `.shaolan`，`root` 仍是 `.shaolan`，太对了/峰哥的 reaction 不改；
5. 「恢复原版薄肌」删除内容包并再走一次 `reloadContent()`。

格式和校验规则见 `docs/PETPACK.md`。

## 3. 三只语音桌宠（Shaolan / Sun / FengGe 是同一份代码的三个变体）

参考实现：`upstream/FengGe-Desktop-Pet/Sources/main.swift`（联动最全）、
`upstream/SunPet/Sources/main.swift`（Motion、捧哏预解码）、`upstream/ShaolanPet/Sources/main.swift`（轮播/默认关闭的 ē）。

### 3.1 三份 profile

| | 薄肌 shaolan | 太对了 sunpet | 峰哥 fengge |
|---|---|---|---|
| 素材 | 37 句 .wav | 28 句 .m4a | 11 句 .wav |
| 默认大小 | 260（滑块 50%–180%） | 180（滑块 50%–180%） | 260（滑块 50%–180%） |
| 动画 | 竖向压扁 12%，30fps | 摇晃：绕中心 ±0.055rad + 上浮 3px | 同薄肌 |
| 接话策略 reaction | 从不接 | `(from == .shaolan || from == .fengge) && hop < 3` | `from == .sunpet && root == .shaolan && hop < 3` |
| 捧哏池 | 无 | id ∈ {1,2,4,11,13,14}，且排除 excludedIDs | 全部 11 句 |
| 接话重叠 | — | hop==1 时 0.2s，其余 0.3s | 0.2s |
| 菜单额外项 | 联动状态 | 「捧哏联动」开关 + 机身摇晃开关/状态 | 联动状态 |
| 初次运行 | `defaultOff == true` 的句子默认排除轮播 | — | — |

三只都：默认音量 0.65；窗口 `borderless + nonactivatingPanel`、clear、floating、
`canJoinAllSpaces/fullScreenAuxiliary/stationary/ignoresCycle`；点击随机播一句（一轮不重复）、
拖动换位置、右键设置；固定模式；「挑一句」；「轮播内容」用真 NSButton 复选框；
音量 0/25/50/65/80/100；停止播放；移回默认位置；隐藏这只。

### 3.2 布局参数（AudioFaceLayout）

```
panelWidth  = size
panelHeight = (size - 2*insetX) * faceRatio + insetY + captionBand
face.frame  = (insetX, insetY, width - 2*insetX, height - insetY - captionBand)
caption     = (3, height - captionBand + 4, width - 6, 34)
薄肌/峰哥: insetX=8,  insetY=8,  captionBand=44
太对了:    insetX=12, insetY=12, captionBand=60
```
字幕样式：白字 13pt medium（太对了 12pt），黑底 0.76 alpha（太对了 0.72），圆角 9（10），最多两行。

### 3.3 播放与接话（照抄原逻辑）

- `play(clip, hop:root:)`：读文件 → `AVAudioPlayer` → 播 → 字幕 `duration+0.4/0.5s` →
  `context.forwardSpeech(PetSpeech(from: id, clipID:, label:, duration:, hop:, root:))`
- 用户点击：hop=0，root=自己
- `handleRelay(speech)`：`relayEnabled && visible && reaction(speech) && hop < 3` →
  `scheduleCompanion(after: speech.duration, hop: speech.hop, root: speech.root)`
- `scheduleCompanion`：取消上一次排的接话；选一句捧哏；`overlap` 按 hop 取；
  `delay = max(0.02, duration - overlap - lead)`；自己正在播就放弃这一捧；
  播放时广播 hop+1、root 原样
- 捧哏句启动预解码 + 量每句开头静音（`leadingSilence`）
- `setRelayEnabled(false)` 取消待播接话；状态栏文案同步
- 自检时不得写偏好、不得启动 motion helper；播音量设 0

### 3.4 机身摇晃（太对了）

`upstream/SunPet/Sources/Motion.swift` 原样搬到 `Sources/PetKit/Audio/Motion.swift`，
删掉文件底部的 `--motion-helper` / `--probe-sensor` / NSApp 入口（已在 main.swift）。
启动时自动尝试开启（原行为）；菜单里可开关；`motion.onEvent`：`ready` 状态、
`shake` 时没在播就 `playNext()`、`error:` 停掉并显示。退出时 `motion.stop()`。

## 4. 果冻（JellyPet）移植

来源 `upstream/JellyPet/Sources/{main.swift,Jelly.swift}`。必须保持：
- 窗口 560×560，只有图标附近（半径 `iconSide * 0.47`）接收点击，其余透明区让给桌面
- 按压以按压点为圆心整体放大、CIBumpDistortion 局部肿起、拖动朝光标侧拉伸、松手 Q 弹
- 窗口坐标全程不动；静止时计时器停掉
- 图标 Claude/GPT/Gemini 三选一；大小用滑块 50%–180%（默认 128）；位置/大小/图标记住
- 菜单：回到原位、大小、图标、隐藏果冻
- 自检：原 `runSelfTest()` 的弹簧/软限位/渲染断言全部保留，改用 `report` 回调；
  检查图仍写到 `NSTemporaryDirectory()/jelly-pet-selftest/`

合并版调整：
- 类型改名：`Jelly`→`JellyModel`，`Spring`→`JellySpring`，`PetView`→`JellyView`，
  `PetPanel`→`JellyPanel`，`PetStyle`→`JellyStyle`，`PetGeometry`→`JellyGeometry`，
  `PetRenderer`→`JellyRenderer`，`PetAssets`→`JellyAssets`，`PetController`→`JellyPetController`，
  `Const`/`DefaultsKey` 留在文件内 private 即可
- 素材从 `Bundle.main.resourceURL/jelly/claude-mark.png` 等读
- 偏好改用 `PetSettings(.jelly)`，键：`centerX` `centerY` `iconSide` `style`
- 实现 `PetHost`：`start()`（建窗口显示）、`setVisible`（orderOut / orderFront）、
  `makeMenu`、`moveToDefaultPosition`、`shutdown`、`previewImage`（panel.contentView 离屏渲染）、
  `selfTest(report)`；`setRelayEnabled` / `handleRelay` 空实现
- 删掉 AppDelegate、`--self-test` 顶层入口、`quit()`（退出由合集菜单负责）
- 菜单里「隐藏果冻」调 `context?.hidePet(.jelly)`

## 5. 主控（PetHubApp）

- 单实例：`NSRunningApplication.runningApplications(withBundleIdentifier:)` 除自己外有就退出
  （自检/诊断模式除外）
- 启动顺序：建 relay（`isEnabled` 读 `hub.relayEnabled`，默认 true）→ 建四只 controller
  → `start()` → 注册 relay handler → 建菜单栏
- 薄肌启动时优先读 `~/Library/Application Support/PetHub/HeadPet/` 的自定义内容包；
  没有内容包时用内置 37 句；有包但读失败会抛错、弹窗并退出（删掉 `HeadPet/` 可恢复）
- relay handler：`pets[id]?.handleRelay(speech)`；桌宠 `forwardSpeech` → `relay.announce`
- 菜单栏一个状态项，标题「桌宠」，菜单（每次打开重建）：
  ```
  桌宠合集 · 4 只（disabled 标题）
  显示/隐藏 ▸ 薄肌[✓] 太对了[✓] 峰哥[✓] 果冻[✓]（名字用 displayTitle）
  ───
  薄肌 ▸ / 太对了 ▸ / 峰哥 ▸ / 果冻 ▸   （各自完整菜单）
  ───
  自定义桌宠 ▸ 当前：原版薄肌 / 当前：<名字>（替换薄肌）
              换成我的角色…（替换薄肌）
              导入 petpack.json 文件夹…
              打开内容包文件夹
              恢复原版薄肌（有自定义内容时才出现）
  ───
  捧哏联动[✓]（全局开关，持久化到 hub.relayEnabled）
  大小联动[✓]（默认开，持久化到 hub.linkSize；每只菜单的滑块是否同步四只）
  大小滑块（50%–180%，总菜单永远四只一起）
  全部显示 / 全部隐藏 / 全部归位 / 紧凑排列（约 6pt 间距、16pt 边距）
  捧哏排列（合影）：薄肌左 / 太对了抬高 / 峰哥右 / 果冻右肩后，自动绑定相对位置
  绑定相对位置[✓]（持久化 hub.groupDrag；拖一只语音桌宠四只一起平移）
  ───
  关于桌宠合集 / 退出桌宠合集
  ```
- 显隐：`setVisible(false)` 要停播、取消接话；隐藏的桌宠不再接话
- 关于面板：版本、四只句数、上游仓库链接、素材版权声明
- CLI（`applicationDidFinishLaunching` 里分流，跑完 `exit`）：
  - `--self-test`：四只 controller 的 `selfTest` + 主控断言（relay 机制、三只 reaction 策略、
    菜单结构、大小滑块（总菜单/单只真实 action 路径）、大小联动、紧凑排列、捧哏排列、
    绑定相对位置（拖一只四只平移）、显隐、默认布局：三只语音窗口 + 果冻可见图标
    互不重叠且完整落在屏幕可见区；自定义内容包安装/读取/替换/导入/编辑器/恢复），
    最后一行 `PASS`，失败 `FAIL: [...]`，退出码 1
    （默认内置四只时 222 项；装了自定义内容包后，逐句音频检查的数量会随语音条数变化）
  - `--chain-test`：打开 trace、静音、模拟点薄肌，等 18 秒（全程约 21 秒；偶发丢句自动重试一次），校验口头记录是
    `[shaolan hop0 root shaolan, sunpet hop1, fengge hop2, sunpet hop3]` 且没有第五句 → `PASS`
  - `--dump-state`：每只一行 `id visible=... size=... pos=...`，加 `relay=on/off`
  （`--diagnostic` 类模式只读：不写偏好、不自动开机身摇晃）
  - `--preview <dir>`：四只各写 `preview-<id>.png`（2x），再写 `preview-all.png`（一排）和
    `preview-stage.png`（捧哏排列合影），共 6 张，退出
  - `--trace`：**正常启动**，额外把 relay 和桌宠 trace 打到 stdout（格式 `[relay] <时间戳> ...`、
    `[trace] ...`）；受单实例限制、会写偏好
- `--self-test` / `--chain-test` / `--dump-state` / `--preview` 不做单实例拦截；正常启动（含 `--trace`）做

## 6. 构建与打包

`build.sh`：
1. 检查 Darwin / arm64 / macOS 14+ / swiftc
2. `swiftc -O -target arm64-apple-macosx14.0 -framework AppKit -framework AVFoundation
   -framework CoreImage -framework IOKit -framework Network`，源文件 = `Sources/**/*.swift`
   （`Sources/PetHub/main.swift` 须在列表里；swiftc 对多文件顺序不敏感）
3. 建 `build/桌宠合集.app/Contents/{MacOS,Resources}`，可执行文件 `PetHub`
4. 拷贝 `Assets/shaolan|sun|fengge|jelly` → `Contents/Resources/<同名>`，
   `Assets/AppIcon.icns` → Resources，`LICENSE`+`licenses/` → Resources
5. Info.plist：CFBundleExecutable=PetHub、CFBundleIdentifier=local.pethub.app、
   CFBundleName/DisplayName=桌宠合集、ShortVersion=2.0.0、Version=1、LSMinimumSystemVersion=14.0、
   LSUIElement=true、NSHighResolutionCapable=true、CFBundleIconFile=AppIcon
6. `xattr -cr`，`codesign --force --sign -`
7. 跑 `--self-test`，最后一行必须是 PASS（`--no-self-test` 可跳过）
8. `--package`：`ditto` 出 zip；stage 目录放 app + `Applications` 软链；
   `hdiutil create -volname 桌宠合集 -srcfolder stage -format UDZO dist/PetHub-2.0.0.dmg`；
   `shasum -a 256` 写 `PetHub-2.0.0.sha256`

`install.sh`：`--build` 编译并装进 /Applications、启动；`--uninstall` 退出并删除；默认从 `build/` 装。

`Tools/make-icon.swift`：用 AppKit 把四张脸（薄肌/太对了/峰哥 的 face.png + 果冻的
claude-mark.png）排成 2×2，画进 1024×1024 圆角底板（浅色渐变/白底都行），
生成 iconset 后 `iconutil -c icns` 输出 `Assets/AppIcon.icns`。
可直接 `swift Tools/make-icon.swift` 运行。图标要能一眼看出是四只合集。

## 7. 文档要求

- `README.md`：中文、给人看。开头一句话（四只桌宠一个 App 一个 dmg）、四只一句话介绍、
  安装三步、功能（点/拖/右键/菜单栏/联动/自定义角色）、与四个独立 App 的关系、素材版权声明、构建链接
- `TECHNICAL.md`：架构（PetKit/PetHub 分层）、进程内联动协议（hop/root 四步链）、模块表、偏好键、
  自定义内容包/热切换、CLI 诊断、构建打包、上游映射、已知限制（单 App 后不再与独立 App 跨进程联动）
- `docs/ARCHITECTURE.md`：分层、扩展点、加内置角色、把 PetKit 嵌进别的 App
- `docs/PETPACK.md`：内容包格式、校验、安装/导入、限制、开发者最小示例
- `docs/MAKE_YOUR_OWN_PET.md`：普通用户换角色步骤（我的老师例子）、恢复、文件位置、FAQ
- `CONTRIBUTING.md`：构建/测试、加角色流程、代码风格、素材边界、PR 检查清单
- `Sources/PetKit/README.md`：内核这一层是什么、文件、已知耦合、嵌入注意
- `Examples/MyTeacher/`：内容包模板（`petpack.json` + 说明，不放二进制素材）
- `AGENTS.md`：构建必须 PASS；不改 hop/root 语义；素材不进 MIT；只支持 arm64/macOS14；
  自定义内容不改协议、安装必须原子
- `NOTICE.md`：音频/头像版权归原权利人、非商用；三仓库 MIT；JellyPet 未附 LICENSE，
  仅按 README「代码可自由修改」合并，分发前需联系原作者；第三方设计致谢；用户导入内容归用户
- `LICENSE`：标准 MIT（合并版代码）；`licenses/` 保留上游四份许可文件
- `docs/UPSTREAM.md`：四个仓库 URL + 合并时的 commit（见下）+ 各自贡献
  - ShaolanPet 7ce7e2b、SunPet 9b68d09、FengGe-Desktop-Pet d3336de、JellyPet 7306d4e

## 8. 验收清单

- [ ] `./build.sh` 编译零 error，自检 PASS（默认内置四只时 222 项，含自定义内容包）
- [ ] `PetHub --chain-test` PASS（四步链，hop 0/1/2/3，root 全 shaolan，无第五句）
- [ ] `PetHub --preview /tmp/pethub-preview` 出 6 张（4 张单图 + `preview-all.png` + `preview-stage.png`），肉眼确认形象和站位正确
- [ ] 真机启动：四只同时在屏幕右下角一排；三只语音窗口 + 果冻的可见图标互不重叠
      （果冻 560×560 透明窗口允许伸出屏幕，判的是图标 128×128 的可见区域）；菜单栏只有一个「桌宠」
- [ ] 点每只都能出声/形变；右键菜单完整；隐藏/显示/全部归位可用
- [ ] 大小滑块：50%–180% 无级变化；总菜单拖一次四只一起变；每只菜单滑块受「大小联动」控制
- [ ] 紧凑排列：一键约 6pt 间距、16pt 边距贴右下角，四只不重叠且在屏内
- [ ] 捧哏排列：按合影站位摆好（太对了抬高、左中右顺序、果冻右肩后、前后层次），自动绑定
- [ ] 绑定相对位置：拖任意语音桌宠四只保持队形平移；关掉后只动被拖的那只
- [ ] 自定义桌宠：换成「我的老师」（名字/头像/多语音/中文）后立即热切换、标题与菜单显示新名字；
      点它起头仍是四步捧哏、root 全薄肌；「恢复原版薄肌」回到 37 句
- [ ] 内容包导入：合法的 `petpack.json` 文件夹能装；坏包（超 200 条、缺文件、中文空、格式错）
      被拒绝且不破坏当前内容；应用重启后自定义内容仍在
- [ ] `hdiutil verify dist/*.dmg` 通过；挂载后 `桌宠合集.app` 能启动并自检
- [ ] README/TECHNICAL/ARCHITECTURE/PETPACK/NOTICE 与实现一致，无夸大