# 桌宠合集 · 技术文档

只想装上玩的话看 [README](README.md)。这一份写给要自己编译、改代码、加角色，或者被派来验证这个 App 的 agent。
素材权利在 [NOTICE.md](NOTICE.md)，上游来源在 [docs/UPSTREAM.md](docs/UPSTREAM.md)。

## 1. 这是什么架构

四个独立仓库（ShaolanPet / SunPet / FengGe-Desktop-Pet / JellyPet）合并成**一个进程**：

```
main.swift
  └─ NSApplication（accessory，无 Dock 图标）
       └─ PetHubApp（AppDelegate + PetHubContext + 所有 CLI 模式）
            ├─ PetRelay          进程内捧哏广播（替代原 Bridge.swift 的 DistributedNotificationCenter）
            ├─ PetLayout         首次启动 / 全部归位时的右下角站位
            ├─ PetSettings       每只桌宠一份偏好，键名自动加 pet.<id>. 前缀
            ├─ AudioPetController × 3（薄肌 / 太对了 / 峰哥）
            │    └─ AudioPetProfiles（三份 profile）、AudioPetViews、Motion（仅太对了）
            └─ JellyPetController × 1
                 └─ JellyModel（弹簧）、Jelly 视图/渲染
```

- 三只语音桌宠共用 `AudioPetController` 这一份引擎，差异全部收在 profile 里；果冻单独一套。
- 主控通过 `PetHost` 协议操作四只（`start` / `setVisible` / `makeMenu` / `moveToDefaultPosition` /
  `setRelayEnabled` / `handleRelay` / `selfTest` / `shutdown` / `previewImage` / `showStartupHint`，
  以及 `stateDescription` 诊断行），通过 `PetHubContext` 反向提供显隐、联动开关、退出。
- 没有第三方依赖，不联网；唯一的本机通信是「机身摇晃」辅助进程走的 127.0.0.1 回环 UDP。

要求：Apple Silicon（arm64）+ macOS 14+，`swiftc`（Xcode Command Line Tools 即可，不需要完整 Xcode）。
App 开 `LSUIElement`，不占 Dock，只有一个菜单栏状态项。

## 2. 模块表

| 路径 | 作用 |
| --- | --- |
| `Sources/main.swift` | 入口：`-h` 帮助、`--probe-sensor`、内部 `--motion-helper` 分流，然后交给 `PetHubApp` |
| `Sources/Hub/PetIdentity.swift` | `PetID` 四只的枚举（rawValue 同时是偏好前缀和素材目录名）、`PetSettings` |
| `Sources/Hub/PetHost.swift` | `PetHost` / `PetHubContext` 协议，主控与四只之间的唯一接口 |
| `Sources/Hub/PetRelay.swift` | `PetSpeech` 与 `PetRelay`：进程内广播、hop/root 字段、trace 输出 |
| `Sources/Hub/PetLayout.swift` | 右下角一排的槽位宽度、间距、每只的默认原点 |
| `Sources/Hub/PetHubApp.swift` | 主控：单实例、启动顺序、菜单栏、显隐、联动开关、CLI 模式、自检 |
| `Sources/Audio/AudioPetController.swift` | 三只语音桌宠的通用引擎：播放、轮播池、接话、菜单、状态、自检 |
| `Sources/Audio/AudioPetViews.swift` | `AudioPetPanel` / 头像视图 / 字幕，窗口尺寸与布局参数 |
| `Sources/Audio/AudioPetProfiles.swift` | 三份 profile、`Clip`、动画风格、捧哏池、reaction 策略 |
| `Sources/Audio/Motion.swift` | 太对了的 SPU 加速度计客户端、摇晃判定、`--motion-helper` 子进程实现 |
| `Sources/Jelly/JellyModel.swift` | 果冻的按压/拉动阻尼弹簧与软限位 |
| `Sources/Jelly/JellyPetController.swift` | 果冻窗口、点击区域、CIBumpDistortion 渲染、菜单、自检 |
| `Tools/make-icon.swift` | 四张脸拼 1024 圆角图标 → `build/AppIcon.iconset` → `Assets/AppIcon.icns` |
| `build.sh` | 环境检查、编译、资源、Info.plist、签名、自检、`--package` |
| `install.sh` | 装进 /Applications、去隔离标记、启动；`--uninstall` |

素材（运行时按目录名从 `Bundle.main.resourceURL` 读，不嵌进二进制）：

| 路径 | 内容 |
| --- | --- |
| `Assets/shaolan/` | `face.png`、`clips.json`、`Clips/*.wav`，37 句 |
| `Assets/sun/` | `face.png`、`clips.json`、`Clips/*.m4a`，28 句 |
| `Assets/fengge/` | `face.png`、`clips.json`、`Clips/*.wav`，11 句 |
| `Assets/jelly/` | `claude-mark.png`、`gpt-mark.png`、`gemini-mark.png` |
| `Assets/AppIcon.icns` | 合集图标，由 `Tools/make-icon.swift` 生成 |

## 3. 启动流程

`PetHubApp.applicationDidFinishLaunching`：

1. 非诊断模式下检查单实例：同 bundle id 已有别的进程就 `terminate`（正常启动只允许一份）。
2. 读偏好 `hub.relayEnabled`（默认 `true`），设置到 `PetRelay`。
3. 按 `PetLayout.order` 建四只 controller：有 profile 的是语音桌宠，否则是果冻。
4. 逐只 `start()`；素材缺失会抛错，主控弹窗后退出。
5. 给三只语音桌宠注册 relay handler（果冻不参与）。
6. 把联动开关同步给四只。
7. CLI 模式在此分流：`--preview` → `--self-test` → `--dump-state` → `--chain-test`，跑完 `exit`。
8. 正常启动：建菜单栏「桌宠」状态项，三只语音桌宠各显示 5 秒启动提示。

`applicationWillTerminate` 里逐只 `shutdown()`、注销 relay。

## 4. 进程内联动（hop / root）

### 4.1 数据结构

```swift
struct PetSpeech: Equatable {
    let from: PetID        // 谁开口
    let clipID: Int        // 播的是哪句
    let label: String      // 字幕文案
    let duration: TimeInterval
    let hop: Int           // 第几跳：用户点出来的算 0，接话的人 +1
    let root: PetID        // 这条链是谁起的头，一路原样传下去
}
```

`PetRelay.announce(_:)` 广播给所有已注册的桌宠，**发送者本人收不到自己的广播**；
`isEnabled == false` 时整条广播被丢掉。这和原来三份 `Bridge.swift` 的语义一致，
只是从 `DistributedNotificationCenter` 换成了进程内直接调用，跳数和 root 规则没改。

### 4.2 接话规则

- 用户点击（或摇机身）：`hop = 0`，`root = 自己`。
- 收到一句：`relayEnabled && 自己可见 && profile.reaction(speech) && hop < 3` 才考虑接。
- 决定了接之后由 `scheduleCompanion` 排一句捧哏：
  - 取消上一句还没开口的接话（`companionWork?.cancel()`），避免排队叠音；
  - 从捧哏池里随机拿一句（一轮内不重复）；
  - `overlap = hop == 1 ? 0.2 : 0.3` 秒（第二跳压紧 0.1 秒，四步连起来才不拖）；
  - `delay = max(0.02, speech.duration - overlap - leadingSilence)`，`leadingSilence` 是
    该句音频开头垫的静音（启动时逐句量出来），保证第一个字压在上一句尾音上；
  - 到时间时如果自己正在播（手点、摇机身），这一捧直接放弃，不叠两个声音；
  - 真正播放时广播 `hop + 1`、`root` 原样。
- 捧哏句启动时预解码成 `AVAudioPlayer`（`prepareToPlay`），接话不走读文件路径。
- `setRelayEnabled(false)` 会取消待播接话并更新状态文案；隐藏某只时 `stopPlayback()` + 取消接话。
- 所有诊断模式（`--self-test` / `--dump-state` / `--chain-test` / `--preview`）只读：
  不写偏好、不自动开启机身摇晃。自检还额外不广播、不接话，播放音量置 0。

### 4.3 三只的 reaction 与捧哏池

| 桌宠 | 接谁的话 | 条件 | 捧哏池 |
| --- | --- | --- | --- |
| 薄肌 shaolan | 从不接 | `reaction` 恒 `false` | 无 |
| 太对了 sunpet | 薄肌、峰哥 | `(from == .shaolan \|\| from == .fengge) && hop < 3` | id ∈ {1,2,4,11,13,14}，且排除被「轮播内容」勾掉的句子 |
| 峰哥 fengge | 太对了 | `from == .sunpet && root == .shaolan && hop < 3` | 全部 11 句 |

薄肌和峰哥之间没有直接通道，太对了接完峰哥链自然断掉，不会无限接。
防环靠的是数据本身（`hop` 封顶 + `reaction` 里的 `root` 条件），不是靠「记得别接」。

### 4.4 四步链

点薄肌起头：

| 序 | 谁开口 | hop | root |
| --- | --- | --- | --- |
| 1 | 薄肌 | 0 | 薄肌 |
| 2 | 太对了 | 1 | 薄肌 |
| 3 | 峰哥 | 2 | 薄肌 |
| 4 | 太对了 | 3 | 薄肌 |

第四跳再广播时：薄肌从不接；峰哥要求 `hop < 3`；太对了要求 `hop < 3`。链在这里收住。

另外两种起头：点峰哥 → 太对了接一句（hop 1，root 峰哥），峰哥因为 `root != .shaolan` 不再接，共 2 句；
点太对了 → 薄肌从不接、峰哥要求 `root == .shaolan`，共 1 句。

### 4.5 怎么验联动

- `--self-test` 里有拓扑断言：用每只自己的 `reaction` 拼一遍四步链（`wouldAccept`），
  检查谁接谁、第四跳收住；但这只是策略断言，不是真的播放。
- `--chain-test` 才是实测：打开 trace、三只静音、3 秒后模拟点一下薄肌，再等 18 秒收结果，
  校验口头记录恰好是「薄肌 hop0 → 太对了 hop1 → 峰哥 hop2 → 太对了 hop3，root 全薄肌」。
  全程约 21 秒，成功最后一行 `PASS ...`，失败 `FAIL 四步链不对…` 并退出码 1。

## 5. 布局、窗口与动画

- `PetLayout.order = [.shaolan, .sunpet, .fengge, .jelly]`，从屏幕右下角开始排一行；
  槽位宽 260 / 180 / 260 / 128，间距 36，屏幕边距 24。改大小或拖动后允许溢出槽位，不挤压邻居。
- 语音桌宠窗口 `origin = 槽位中心 - panelWidth/2`，底边对齐 `visibleFrame.minY + 24`。
- 果冻的窗口本身是 560×560 全透明，只有图标附近（半径 `iconSide * 0.47`）接收点击，其余点击穿透给桌面；
  首次图标中心 = 果冻槽位中心，纵向 `bottom + 64`（图标默认边长 128）。
- 三只语音桌宠：`borderless + nonactivatingPanel`、透明、floating、跟随所有桌面空间 / 全屏、不参与
  Cmd-Tab。台下布局参数（`AudioFaceLayout`）：薄肌 / 峰哥 inset 8、字幕带 44，头像区按原图比例；
  太对了 inset 12、字幕带 60。字幕白字 13pt（太对了 12pt）、黑底 0.76（0.72）、圆角 9（10），最多两行。
- 动画：薄肌 / 峰哥竖直压扁 12%、30fps；太对了绕中心 ±0.055 rad 摇晃 + 上浮 3px；
  系统开启「减少动态效果」时不动。果冻全部是弹簧状态（按压 / 局肿 / 拉动 / 回弹），窗口坐标不动。
- 位置、大小、音量、轮播勾选等都会持久化（见下表），启动时恢复；恢复点不在任何屏幕内时退回默认站位。
- 自检里有默认布局断言：三只语音窗口 + 果冻的 128×128 可见图标互不重叠，且都完整落在屏幕可见区内。
  果冻的 560×560 透明窗口允许伸出屏幕（点击区域只按中间的图标算），这是上游原有的手感，不算布局错误。

## 6. 偏好键

偏好域：`local.pethub.app`（`UserDefaults.standard`，随 bundle id）。
`PetSettings(id)` 自动加前缀 `pet.<PetID.rawValue>.`，四只互不覆盖。

三只语音桌宠（`shaolan` / `sunpet` / `fengge`）：

| 键（去掉前缀） | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `volume` | Float | 0.65 | 0 / 0.25 / 0.5 / 0.65 / 0.8 / 1，菜单里 6 档 |
| `size` | Double | 260 / 180 / 260 | 人物（头像）边长，菜单三档 |
| `randomMode` | Bool | true | 随机一句 / 固定模式 |
| `pinnedID` | Int | 无 | 固定模式选中的句子 id；键不存在＝未固定 |
| `excludedIDs` | [Int] | 薄肌首次按素材 `defaultOff`；其余空 | 「轮播内容」里勾掉的句子 |
| `panelX` / `panelY` | Double | 无 → `PetLayout` | 窗口原点 |
| `reactionEnabled` | Bool | true | 仅太对了：自己的「捧哏联动」开关 |

果冻（前缀 `pet.jelly.`）：

| 键 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `centerX` / `centerY` | Double | 果冻默认槽位 | 图标中心（屏幕坐标） |
| `iconSide` | Int | 128 | 104 / 128 / 160 |
| `style` | Int | 0 | `JellyStyle`：0=Claude，1=GPT，2=Gemini |

主控：

| 键 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `hub.relayEnabled` | Bool | true | 全局「捧哏联动」开关 |

旧的四只独立 App 的偏好不会自动迁过来：bundle id 不同（例如 `local.shaolan.desktop-pet`），
合集按自己的默认布局重新摆。自检模式只读不写。

## 7. CLI 诊断

`--self-test` / `--chain-test` / `--dump-state` / `--preview` 是**只读诊断**：不做单实例拦截，
可以在已有实例运行时跑，跑完自己 `exit`，不写偏好、不自动开机身摇晃。
`--trace` **不是**只读诊断——它只是正常启动多打开一份 trace 输出，仍受单实例限制，
也会正常写偏好、按正常启动开机身摇晃。`-h` / `--probe-sensor` 是纯命令行入口，不起 UI。

| 命令 | 作用 | 输出 / 退出码 |
| --- | --- | --- |
| `-h` / `--help` | 打印用法 | 退出码 0 |
| `--self-test` | 四只 controller 自检 + 主控断言（relay、三只 reaction、菜单、显隐、默认布局、诊断字段），目前 196 项 | 每项 `OK` / `FAIL`，最后一行 `PASS` 或 `FAIL: [...]`；失败退出码 1 |
| `--chain-test` | 模拟点薄肌，实测四步捧哏链 | trace + `[chain]` 记录，成功 `PASS 四步捧哏链：…`，失败 `FAIL`；约 21 秒 |
| `--dump-state` | 打印当前状态后退出 | 首行 `version=1.0.0 relay=on pets=4`，随后每只一行，见下 |
| `--preview <目录>` | 四只各离屏渲染一张 `preview-<id>.png`（2x），再拼一张 `preview-all.png` | 打印写出的路径；目录不存在会自动建 |
| `--trace` | **正常启动**，额外把联动和桌宠的每一跳打到 stdout（受单实例限制、会写偏好） | `[relay] <时间戳> …`、`[trace] <时间戳> pet=<id> …` |
| `--probe-sensor` | 检查这台 Mac 有没有可用的 SPU 运动传感器 | `sensor available; open result=…; uid=…` 或 `sensor unavailable` |

上述 `--self-test` / `--chain-test` / `--dump-state` / `--preview` 都**只读**：不写偏好、
不自动开启机身摇晃，也不做单实例拦截，可以在已有实例运行时执行；`--trace` 见上，按正常启动算。

`--dump-state` 的语音桌宠行（示例，数值随实际状态变）：

```text
shaolan visible=true window=on size=260x296 pos=1780,24 clips=37 pool=8 mode=random pinned=nil volume=0.65 relay=on
```

果冻那行只有 `visible / size / pos`（窗口固定 560×560，`pos` 是图标中心，不是窗口原点）：
`jelly visible=true size=560x560 pos=…`。

常用的两条：

```bash
./build/桌宠合集.app/Contents/MacOS/PetHub --self-test
./build/桌宠合集.app/Contents/MacOS/PetHub --preview /tmp/pethub-preview
```

## 8. 构建与打包

`build.sh` 依次做：

1. 检查 Darwin、arm64、macOS 14+、`swiftc`。
2. `find Sources -name '*.swift' | sort` 收集全部源文件（含 `Sources/main.swift`），
   `swiftc -O -target arm64-apple-macosx14.0 -framework AppKit -framework AVFoundation
   -framework CoreImage -framework IOKit -framework Network …` 输出到
   `build/桌宠合集.app/Contents/MacOS/PetHub`。
3. 建 `Contents/{MacOS,Resources}`；拷 `Assets/{shaolan,sun,fengge,jelly}` 四个目录、
   `Assets/AppIcon.icns`、`LICENSE`、`NOTICE.md`、`licenses/` 到 Resources。
4. 写 `Contents/Info.plist`：`CFBundleExecutable=PetHub`、`CFBundleIdentifier=local.pethub.app`、
   `CFBundleName/DisplayName=桌宠合集`、`CFBundleShortVersionString=1.0.0`、`CFBundleVersion=1`、
   `LSMinimumSystemVersion=14.0`、`LSUIElement=true`、`NSHighResolutionCapable=true`、
   `CFBundleIconFile=AppIcon`。
5. `xattr -cr` → `codesign --force --sign -` → `codesign --verify`。
6. 跑 `--self-test`，最后一行必须是 `PASS`；脚本自己的最后一行也输出 `PASS`（`--no-self-test` 例外）。
7. `--package`：`ditto` 出 zip；`mktemp -d` 里放 app + `/Applications` 软链，`hdiutil create
   -volname 桌宠合集 -format UDZO` 出 dmg，`hdiutil verify` 通过后 `shasum -a 256` 写校验文件。

```bash
./build.sh                 # 编译 + 自检 → build/桌宠合集.app，最后一行 PASS
./build.sh --package       # 另出 dist/PetHub-1.0.0.zip / .dmg / .sha256（卷名「桌宠合集」）
./build.sh --no-self-test  # 无图形会话时跳过自检（发布前别用）
```

环境变量 `PET_VERSION`（默认 1.0.0）、`PET_BUILD`（默认 1）。dmg 里是
「桌宠合集.app」+「Applications」软链，拖进去就是安装。

图标改动后重新生成：

```bash
swift Tools/make-icon.swift   # build/AppIcon.iconset + Assets/AppIcon.icns + /tmp/pethub-icon-preview.png
```

`install.sh`：默认从 `build/` 装（没有就编译）；`--build` 强制重编；`--from 路径.app` 装现成的包；
`--uninstall` 退出并删掉 `/Applications/桌宠合集.app`（偏好设置保留，不碰四个独立 App）。

## 9. 上游映射

| 上游（合并时 commit） | 合并进 | 保留的行为 | 许可 |
| --- | --- | --- | --- |
| [ShaolanPet](https://github.com/Ganzhe2028/ShaolanPet) `7ce7e2b` | Audio 引擎基础、37 句素材、图标素材 | 竖向压扁动画、8 句默认轮播、大小 / 音量 / 挑一句、字幕布局 | MIT |
| [SunPet](https://github.com/Ganzhe2028/SunPet) `9b68d09` | `Motion.swift`、捧哏预解码 / 静音测量、摇晃动画与捧哏池 | 机身摇晃、`leadingSilence` 补偿、hop==1 压紧 0.1 秒、6 句短捧哏 | MIT |
| [FengGe-Desktop-Pet](https://github.com/Ganzhe2028/FengGe-Desktop-Pet) `d3336de` | 联动最全的语音引擎实现、11 句素材 | hop/root 防环、root 条件、全部 11 句捧哏池、build.sh 风格 | MIT |
| [JellyPet](https://github.com/aurelius358/JellyPet) `7306d4e` | `Jelly/JellyModel.swift`、`JellyPetController.swift`、三个标志 | 按压 / 肿起 / 拉动 / Q 弹、560 窗口、点击穿透、自检断言 | 无 LICENSE；按 README「代码可自由修改」合并，见 NOTICE |

合并时做的改名与替换：

- `Bridge.swift` 的三份副本 → `Sources/Hub/PetRelay.swift`；`DistributedNotificationCenter`
  + bundle id 存活检测 → 进程内注册表，`PetSpeech` / `hop` / `root` 字段不变。
- 果冻的类型统一加 `Jelly` 前缀避免重名：`Jelly`→`JellyModel`、`Spring`→`JellySpring`、
  `PetView`→`JellyView`、`PetPanel`→`JellyPanel`、`PetRenderer`→`JellyRenderer` 等。
- 三只语音桌宠的差异收进 `AudioPetProfiles`，引擎只有一份；动画、字幕、菜单在 `AudioPetViews` / controller。
- 偏好键从各自的旧 domain 改成 `local.pethub.app` 下的 `pet.<id>.*`；`bridgeEnabled` 改为
  `pet.sunpet.reactionEnabled`，`petX/petY` 改为 `panelX/panelY`。

上游每个仓库的贡献、URL 和 commit 详见 [docs/UPSTREAM.md](docs/UPSTREAM.md)。

## 10. 已知限制

- **只支持 Apple Silicon + macOS 14+**。`build.sh` 把 target 写死成 `arm64-apple-macosx14.0`；
  Intel Mac 需要自己改 target 并验证，不是官方支持路径。
- **ad-hoc 本地签名，没有 Apple 公证**。第一次打开要右键 → 打开，或去「隐私与安全性」里放行。
- **不再和四个独立 App 跨进程联动**。合集内部四只走进程内广播；如果你同时开着原来的独立 App，
  它们仍按旧的本机通知互相接话，但**不会**和合集里的桌宠接话，两套还可能叠在屏幕上。
- **不继承旧 App 的偏好**。bundle id 变了，位置、音量、大小按合集的默认值来。
- **机身摇晃依赖未公开的 SPU 传感器接口**。部分机型 / 系统版本读不到，会显示原因并自动关掉该功能，
  不影响其他三只；读取跑在独立子进程，只走 127.0.0.1，不联网。
- **果冻没有语音**，不参与捧哏链；它只有形变和图标切换。
- **正常启动只允许一个实例**；自检 / 诊断 / 预览模式例外。
- 音频、头像、Claude/GPT/Gemini 标志**不在 MIT 许可里**，不商用；公开再分发前先看 NOTICE.md。

## 11. 加第五只 / 改联动的检查清单

1. `PetID` 加 case；`title` / `fullName` / `assetsFolder` 补齐（`assetsFolder` 是 `Assets/` 下的目录名）。
2. `PetLayout` 加槽位宽度、排进 `order`；否则启动位置会落在行外。
3. 新角色如果是语音桌宠：在 `AudioPetProfiles` 加 profile（默认大小、动画、捧哏池、reaction），
   素材目录放 `Assets/<新目录>/`（`face.png`、`clips.json`、`Clips/`）。
4. 改 `reaction` / `hop` 上限 / `root` 条件时，同步改 `--chain-test` 的期望序列和本文档第 4 节；
   这三处不一致会被验收抓到。
5. 图标：把新脸加进 `Tools/make-icon.swift`，2×2 布局要改成 5 格或换排布；跑一遍生成 icns。
6. `./build.sh` 必须最后一行 `PASS`，`--self-test` 与 `--chain-test` 都要过，再 `--package`。