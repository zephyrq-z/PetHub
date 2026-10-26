# 桌宠合集 · 架构说明（v2.0.0）

这份文档写给三种人：

- 想给桌宠加一个**内置角色**、改联动策略的开发者；
- 想把 **PetKit 内核** 复用到自己 macOS App 里的人；
- 想搞清楚「自定义桌宠」为什么换了头像和声音、四步捧哏链还照旧的人。

只想装来玩：[README](../README.md)。成品 App 的实现细节：[TECHNICAL](../TECHNICAL.md)。
内容包格式：[PETPACK](PETPACK.md)。普通用户换角色：[MAKE_YOUR_OWN_PET](MAKE_YOUR_OWN_PET.md)。

## 1. 为什么要分层

1.x 把所有代码放在同一层：主控、四只桌宠、素材读取、菜单、构建脚本互相知道对方。
2.0 把**能复用的内核**和**这一个 App 的装配**拆开：

```
Sources/PetKit/   通用内核：协议、联动通道、偏好、语音引擎、果冻引擎、内容包、大小滑块
Sources/PetHub/   成品 App：入口、主控、菜单栏、布局、自定义桌宠编辑器
Assets/           内置四只的素材（不打进二进制，运行时从 App Resources 读）
```

四只内置桌宠 = PetKit 的引擎 + PetHub 的装配 + `Assets/` 里的素材。
自定义角色 = 用户内容包替换掉薄肌引擎的素材来源，**不新增代码**。

目前**还不是 Swift Package**：`build.sh` 把 `Sources/**/*.swift` 一起交给 `swiftc` 编成一个
可执行文件 `PetHub`。PetKit 是「源码级内核」，不是独立的 `.framework`。

## 2. 目录树

```
Sources/
├── PetKit/                       可复用内核
│   ├── README.md                 这一层的说明
│   ├── PetHost.swift             PetHost / PetHubContext 协议、PetError、PetSizing、默认实现
│   ├── PetIdentity.swift         PetID（四只）、PetSettings（偏好键前缀）
│   ├── PetRelay.swift            PetSpeech、PetRelay（进程内 hop/root 广播）
│   ├── PetPack.swift             内容包模型、校验、安装/导入/删除
│   ├── SizeSliderView.swift      菜单里的 50%–180% 大小滑块
│   ├── Audio/
│   │   ├── AudioPetController.swift   语音桌宠通用引擎
│   │   ├── AudioPetViews.swift        AudioPetPanel / 头像 / 字幕
│   │   ├── AudioPetProfiles.swift     三份 profile（薄肌/太对了/峰哥）+ Clip
│   │   └── Motion.swift               太对了的 SPU 加速度计 + 摇晃 helper
│   └── Jelly/
│       ├── JellyModel.swift           果冻弹簧与软限位
│       └── JellyPetController.swift   果冻窗口、点击区域、渲染、菜单、自检
└── PetHub/                       成品 App
    ├── main.swift                 入口：-h / --motion-helper / --probe-sensor / NSApp.run
    ├── PetHubApp.swift            主控、菜单栏、CLI、自检、排列、自定义内容包接线
    ├── PetLayout.swift            四只桌宠的默认站位（槽位、间距、边距）
    └── CustomHeadImporter.swift   「自定义桌宠」编辑窗口（头像/语音/中文）
```

## 3. 依赖方向

**PetHub → PetKit**，反过来不行。`Sources/PetKit` 里不应该 import 或直接调用 `PetHubApp`、
`CustomHeadImporter` 这些成品 App 的类型。

但要诚实说明三处现有耦合（写进 [Sources/PetKit/README.md](../Sources/PetKit/README.md)）：

1. **`PetLayout`**：`AudioPetController.moveToDefaultPosition()` 和 `JellyPetController` 的默认中心
   都调用 `PetLayout`（定义在 `Sources/PetHub/PetLayout.swift`）。把 PetKit 单独拿走时，
   要么自己提供同样签名的布局函数，要么先把 `PetLayout` 移进 PetKit。
2. **内容包默认目录**：`PetPack.defaultStoreURL` 写死
   `~/Library/Application Support/PetHub/HeadPet`。嵌进别的 App 时用
   `PetPackStore(baseURL:)` 注入自己的目录。
3. **素材目录约定**：引擎按 `Bundle.main.resourceURL/<PetID.assetsFolder>` 读素材，
   果冻固定读 `Bundle.main.resourceURL/jelly/`。嵌入时资源要按同名目录放进主 bundle。

## 4. 内核里有什么

| 文件 | 作用 | 依赖 |
| --- | --- | --- |
| `PetKit/PetHost.swift` | `PetHost`（主控操作一只桌宠）、`PetHubContext`（桌宠回调主控）、`PetError`、`PetSizing`、协议默认实现 | AppKit、Foundation |
| `PetKit/PetIdentity.swift` | `PetID`（四只的身份、素材目录、是否语音）、`PetSettings`（`pet.<id>.` 前缀偏好） | AppKit、Foundation |
| `PetKit/PetRelay.swift` | `PetSpeech`、`PetRelay`：进程内广播，发送者不收到自己的话 | Foundation |
| `PetKit/PetPack.swift` | `PetPackManifest`、`PetPackClip`、`PetPack`、`PetPackStore`：内容包读取、校验、原子安装 | AppKit、AVFoundation |
| `PetKit/SizeSliderView.swift` | 塞进 `NSMenuItem.view` 的连续滑块，范围 50%–180% | AppKit |
| `PetKit/Audio/AudioPetController.swift` | 语音桌宠引擎：播放、轮播池、接话、菜单、状态、自检；自定义内容包优先读 | AppKit、AVFoundation、IOKit |
| `PetKit/Audio/AudioPetViews.swift` | 透明悬浮窗、头像、字幕的布局与动画 | AppKit |
| `PetKit/Audio/AudioPetProfiles.swift` | 三只语音桌宠的差异：默认大小/音量、动画、捧哏池、reaction、菜单文案 | AppKit |
| `PetKit/Audio/Motion.swift` | SPU 加速度计、摇晃判定、`--motion-helper` 子进程（回环 UDP） | IOKit、Network |
| `PetKit/Jelly/JellyModel.swift` | 果冻按压/拉动弹簧、软限位 | CoreGraphics |
| `PetKit/Jelly/JellyPetController.swift` | 果冻窗口、点击穿透、CIBumpDistortion 渲染、菜单、自检 | AppKit、CoreImage |

PetKit **不负责**：`NSApplication` 生命周期、菜单栏状态项、单实例、CLI 参数、`--preview`/自检的
总调度、默认排列（`PetLayout`）、构建与打包。这些都在 PetHub 层。

## 5. 扩展点

### 5.1 `PetHost` / `PetHubContext`

这是主控和桌宠之间唯一的边界。加一种全新形态的桌宠（不是语音、也不是果冻）时实现 `PetHost` 即可。

| 能力组 | 方法 / 属性 | 说明 |
| --- | --- | --- |
| 身份与生命周期 | `id`、`isVisible`、`panelSize`、`context`、`start()`、`shutdown()` | `start()` 负责建窗口并显示，素材错误抛 `PetError` |
| 显隐与菜单 | `setVisible(_:)`、`makeMenu()`、`displayTitle`、`showStartupHint()` | 菜单由每只自己拼，主控只做子菜单 |
| 联动 | `setRelayEnabled(_:)`、`handleRelay(_:)` | 不接话的桌宠留空实现 |
| 布局与大小 | `moveToDefaultPosition()`、`moveToRow(left:bottom:)`、`sizeScale`、`applySizeScale(_:)`、`visualWidth`、`bringToFront()`、`windowFrame` | 默认实现已经给出，语音/果冻各自覆盖 |
| 拖动 | `moveBy(dx:dy:)`、`beginGroupDrag()`、`setGroupDragOffset(dx:dy:)`、`endGroupDrag()`、`persistPosition()` | 「绑定相对位置」用 |
| 诊断 | `selfTest(_:)`、`previewImage()`、`stateDescription` | 自检、`--preview`、`--dump-state` |

`PetHubContext` 是反向接口：显隐、联动开关、`forwardSpeech`、退出、大小联动、拖动同步。
`PetHost` 有一份默认实现扩展，简单角色只需要实现 `start`/`setVisible`/`makeMenu` 等核心方法。

### 5.2 `AudioPetProfile`

三只语音桌宠是同一个引擎的三个变体，差异全在 `AudioPetProfiles.swift`：

```swift
struct AudioPetProfile {
    let id: PetID
    let menuHeader: String
    let defaultSize: CGFloat
    let defaultVolume: Float
    let animation: AudioPetAnimation                   // .squash / .tilt
    let layout: AudioFaceLayout                        // 头像/字幕留白
    let hint: String
    let accessibilityLabel: String
    let companion: CompanionSelection                  // .none / .all / .ids(...)
    let companionRespectsExclusions: Bool
    let initialDefaultOffExclusions: Bool
    let reaction: (PetSpeech) -> Bool
    let idleRelayStatus: String
    let showsRelayToggle: Bool                         // 只有太对了有
    let hasMotion: Bool                                // 只有太对了有
}
```

`defaultSize` 只是初始大小；实际大小统一走 `PetHost.sizeScale` / `applySizeScale(_:)`，
范围是默认大小的 **50%–180%**（`PetSizing` / `SizeSliderView`），不再是「小/中/大」三档。

`reaction` 决定「听到谁的话才接」，`companion` 决定「拿哪些句子去接」，两者都遵守 `hop`/`root`。

### 5.3 `PetPack`（用户内容包）

`PetPack` 在 PetKit 里，但它**不是** `PetHost` 协议的一部分：它只改薄肌引擎的内容来源。
内置角色不需要内容包；用户自定义角色不需要改代码。格式见 [PETPACK](PETPACK.md)。

### 5.4 `PetLayout`（产品级站位）

`PetLayout.order`、`slotWidth`、`gap`、`margin` 是产品决定：四只按
薄肌 → 太对了 → 峰哥 → 果冻在右下角排一行。加内置角色要动它；用户内容包只替换薄肌，不动布局。

## 6. 进程内联动（hop / root）

```swift
struct PetSpeech: Equatable {
    let from: PetID        // 谁开口
    let clipID: Int
    let label: String
    let duration: TimeInterval
    let hop: Int           // 用户点出来的是 0，接话者 +1
    let root: PetID        // 链头，原样往下传
}

final class PetRelay {
    var isEnabled: Bool
    var traceEnabled: Bool
    func register(_ id: PetID, _ handler: @escaping (PetSpeech) -> Void)
    func announce(_ speech: PetSpeech)   // 发送者本人收不到
}
```

规则：

- 用户点击（或摇机身）：`hop = 0`，`root = 自己`；
- 收到一句：`relayEnabled && 可见 && reaction(speech) && hop < 3` 才考虑接；
- 接话者安排一句捧哏，播放时广播 `hop + 1`、`root` 原样；
- 薄肌从不接；太对了接薄肌/峰哥；峰哥只在 `root == .shaolan` 时接太对了；
- 第四跳后再广播，峰哥和太对了都因为 `hop < 3` 不接，链收住。

四步链（点薄肌起头）：

| 序 | 谁开口 | hop | root |
| --- | --- | --- | --- |
| 1 | 薄肌 | 0 | 薄肌 `.shaolan` |
| 2 | 太对了 | 1 | 薄肌 |
| 3 | 峰哥 | 2 | 薄肌 |
| 4 | 太对了 | 3 | 薄肌 |

**自定义薄肌为什么不用改联动**：`PetSpeech.from` / `root` 存的是 `PetID`，不是显示名字。
用户把薄肌换成「我的老师」之后，这只桌宠的 `PetID` 仍然是 `.shaolan`，所以：

- `root` 仍然是 `.shaolan`；
- 太对了的 `(from == .shaolan || from == .fengge) && hop < 3` 不用改；
- 峰哥的 `from == .sunpet && root == .shaolan && hop < 3` 不用改；
- `displayTitle` 只影响菜单、关于面板、提示字幕这些**显示**，不影响协议字段。

点自定义角色起头的链：自定义角色 hop0 root `.shaolan` → 太对了 hop1 → 峰哥 hop2 → 太对了 hop3 → 停。

## 7. 自定义内容替换薄肌的完整流程

涉及文件：`Sources/PetHub/CustomHeadImporter.swift`、`Sources/PetHub/PetHubApp.swift`、
`Sources/PetKit/PetPack.swift`、`Sources/PetKit/Audio/AudioPetController.swift`。

1. **菜单**：主控菜单「自定义桌宠」→「换成我的角色…（替换薄肌）」打开编辑器。
2. **编辑器**：用户填名字、选头像、添加多条语音、逐条填中文；点「保存并应用」调
   `PetPackStore.install(name:avatarURL:clips:)`。
3. **安装**：写入 `HeadPet.tmp-<UUID>`，完整校验（头像可解码、每条音频可解码且时长 > 0.1 s、
   中文非空、1–200 条），通过后才替换 `~/Library/Application Support/PetHub/HeadPet/`，
   旧目录作备份、失败回滚。坏包不会把正在用的桌宠弄没。
4. **热切换**：`AudioPetController.reloadContent()`：
   - `loadContent()` 对 `.shaolan` 优先读 `petPackStore.current()`，否则回退内置素材；
   - 替换头像、`clips`、`customName`、内容指纹 `contentSignature`，重算窗口高度；
   - `loadPreferences()` 发现内容指纹变了 → 清空旧的 `excludedIDs` / `pinnedID`（句 id 对不上），
     音量/大小/位置保留；
   - 重新预解码捧哏句、更新 tooltip，字幕提示「已换成 我的老师」。
5. **联动不变**：relay 注册、`PetID`、`root` 全都没动，见上一节。
6. **恢复原版**：菜单「自定义桌宠」→「恢复原版薄肌」删除内容包并再次 `reloadContent()`，
   回到内置 37 句。

失败行为：导入/保存时校验失败会弹窗且保留旧内容；如果用户手工把已安装的 `HeadPet/` 改坏，
下次启动 `start()` 抛错，App 弹窗后退出——删掉该目录即可恢复。

自检里的 `selfTestPetPack` 用临时目录和独立的 `UserDefaults` suite 跑「安装 → 读取 → 替换 →
编辑器 → 导入 → 删除」，不碰用户真实的 `HeadPet/`。

## 8. 加一个内置角色

以「加第五只语音桌宠」为例：

1. `Sources/PetKit/PetIdentity.swift`：`PetID` 加 case，补 `title` / `fullName` / `assetsFolder` / `isAudio`。
2. `Sources/PetKit/Audio/AudioPetProfiles.swift`：加一份 `AudioPetProfile`，并在
   `profile(for:)` 里返回它；决定 `reaction`、捧哏池、动画、默认大小。
3. `Sources/PetHub/PetLayout.swift`：`order` 里排位置、`slotWidth` 给槽位宽度；否则默认站位会落到行外。
4. `Assets/<assetsFolder>/`：放 `face.png`、`clips.json`、`Clips/*`。
5. `build.sh`：素材目录和 `cp -R Assets/...` 的列表是写死的四只，新角色要一起加进去。
6. `Tools/make-icon.swift`：2×2 图标布局要改成 5 张脸的排布，重生成 `Assets/AppIcon.icns`。
7. 自检会自动覆盖菜单、显隐、默认布局；新的 reaction 如果改变四步链，同步改
   `PetHubApp` 的 `--chain-test` 期望序列和 [TECHNICAL](../TECHNICAL.md) 第 4 节。
8. 如果素材来自第三方，按 [NOTICE](../NOTICE.md) 的边界处理；新增许可放 `licenses/`。
9. 更轻量的做法：**不加内置角色**，把角色做成 PetPack 发给用户，让用户替换薄肌。

## 9. 把 PetKit 嵌进别的 macOS App

PetKit 提供的是「桌宠引擎 + 协议 + 联动 + 内容包」，不提供 App 壳。最小接线步骤：

1. **拿代码**：复制 `Sources/PetKit/` 到你的工程。仓库目前没有 `Package.swift`；
   想用 SwiftPM 得自己补一个本地 package（并把 AppKit/AVFoundation/CoreImage/IOKit/Network
   和资源拷贝配好）。
2. **补依赖**：`PetLayout` 目前不在 PetKit 里（见第 3 节）。要么把自己的布局函数放进同一 target，
   要么先把 `PetLayout.swift` 移进 PetKit，再让你的工程提供屏幕/槽位参数。
3. **资源**：把内置素材按 `Resources/<assetsFolder>/...` 拷进主 bundle；果冻固定读
   `Resources/jelly/`。素材目录名由 `PetID.assetsFolder` 决定。
4. **实现主控**：做一个 `PetHubContext`（显隐、`forwardSpeech`、退出、大小联动、拖动同步），
   然后建 controller、注册 relay：

```swift
final class MyHost: NSObject, PetHubContext {
    let relay = PetRelay()
    var relayEnabled = true
    var linkSizeEnabled = false
    var groupDragEnabled = false
    var pets: [PetID: PetHost] = [:]

    func forwardSpeech(_ speech: PetSpeech) { relay.announce(speech) }
    func quitApp() { NSApp.terminate(nil) }
    // 其余 isPetVisible / hidePet / showPet / togglePet /
    // petSizeScaleChanged / petDragBegan / petDragged / petDragEnded 按协议补齐
}

let host = MyHost()
for id in [PetID.shaolan, .sunpet, .fengge] {
    guard let profile = AudioPetProfiles.profile(for: id) else { continue }
    let pet = AudioPetController(profile: profile, settings: PetSettings(id))
    pet.context = host
    try pet.start()
    host.pets[id] = pet
    host.relay.register(id) { [weak host] speech in
        host?.pets[id]?.handleRelay(speech)
    }
}
```

5. **菜单**：直接复用 `makeMenu()`（里面已经接了大小滑块和联动开关），或者只拿
   `SizeSliderView` 做自己的 UI。
6. **内容包**：如果也要「换角色」，用 `PetPackStore(baseURL:)` 指向你自己 App 的
   Application Support 目录，不要用默认的 PetHub 路径。
7. **诊断**：`selfTest` / `previewImage` / `stateDescription` 都可以接进你自己的自检和日志。

成品 App 的完整装配可以直接读 `Sources/PetHub/PetHubApp.swift`（约 1000 行，含菜单栏、CLI、
排列、自检和自定义内容包接线）。

## 10. 构建与资源

- `./build.sh` 把 `Sources/**/*.swift`（含 `Sources/PetHub/main.swift`）编成
  `build/桌宠合集.app/Contents/MacOS/PetHub`，target `arm64-apple-macosx14.0`。
- `Assets/{shaolan,sun,fengge,jelly}`、`AppIcon.icns`、`LICENSE`、`NOTICE.md`、`licenses/`
  拷进 `Contents/Resources/`；素材不嵌进二进制。
- 无第三方依赖、不联网。唯一本机通信是摇晃 helper 的 `127.0.0.1` 回环 UDP。
- 构建/测试/发布流程见 [CONTRIBUTING](../CONTRIBUTING.md)。

## 11. 文档索引

| 文档 | 读者 |
| --- | --- |
| [README](../README.md) | 普通用户：装、玩、换角色 |
| [MAKE_YOUR_OWN_PET](MAKE_YOUR_OWN_PET.md) | 普通用户：把自己的头像和语音做成桌宠 |
| [PETPACK](PETPACK.md) | 想手写/分发内容包的人 |
| [TECHNICAL](../TECHNICAL.md) | 改成品 App 的开发者 |
| [CONTRIBUTING](../CONTRIBUTING.md) | 提 PR 的人 |
| [AGENTS](../AGENTS.md) | 在本仓库干活的 AI |
| [NOTICE](../NOTICE.md) | 素材版权与许可边界 |
| [UPSTREAM](UPSTREAM.md) | 四个上游仓库的来源 |