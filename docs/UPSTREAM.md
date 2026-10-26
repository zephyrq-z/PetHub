# 上游来源

桌宠合集由四个独立仓库在 **2026-10-26** 合并而成。`upstream/` 下是四个仓库的只读副本
（已 `.gitignore`，不进交付仓库）；这里记录合并时对应的 commit，方便对照原始实现和追溯许可。

| 上游仓库 | 合并时 commit | commit 日期 | 许可 |
| --- | --- | --- | --- |
| [Ganzhe2028/ShaolanPet](https://github.com/Ganzhe2028/ShaolanPet) | `7ce7e2b1ed49c4da66d19d5aac419794af0d32db`（7ce7e2b） | 2026-10-25 | MIT |
| [Ganzhe2028/SunPet](https://github.com/Ganzhe2028/SunPet) | `9b68d0911552d8c880a46ca72980d3f9af9743ee`（9b68d09） | 2026-10-25 | MIT |
| [Ganzhe2028/FengGe-Desktop-Pet](https://github.com/Ganzhe2028/FengGe-Desktop-Pet) | `d3336debfafc37963ec5612cb27793e250228b9b`（d3336de） | 2026-10-25 | MIT |
| [aurelius358/JellyPet](https://github.com/aurelius358/JellyPet) | `7306d4ea722e092e26973c4a80a3561c4b17ba7a`（7306d4e） | 2026-10-25 | 无 LICENSE 文件（见下） |

## ShaolanPet（薄肌）

**贡献**：最早的一版语音桌宠引擎——透明悬浮窗、字幕、随机轮播（一轮不重复）、
「挑一句」、音量 / 大小、拖动位置、右键菜单、自检；薄肌的 37 句 `.wav` 音频、
`clips.json`（带 `source` / `defaultOff` / `answer` 字段）、`face.png`；
`build.sh` / `install.sh` 的中文风格和自检 PASS 约定。

**合并进**：`Sources/Audio/AudioPetController.swift`、`AudioPetViews.swift`、
`AudioPetProfiles.swift` 的 `shaolan` profile（竖向压扁动画、默认只开 8 句、链头不接话）；
素材放到 `Assets/shaolan/`。

**许可**：MIT，Copyright (c) 2026 Ganzhe2028，全文见 `licenses/LICENSE-ShaolanPet.txt`。

## SunPet（太对了）

**贡献**：`Motion.swift` 的 SPU 加速度计读取、`--motion-helper` 子进程和摇晃事件；
捧哏机制的关键细节——预解码捧哏句、逐句测开头静音 `leadingSilence`、按 hop 调整接话重叠；
太对了的 28 句 `.m4a` 音频和 `face.png`。

**合并进**：`Sources/Audio/Motion.swift`（去掉文件底部的入口，交给 `main.swift`）、
`AudioPetController` 的接话调度 / 预解码 / 静音补偿、`sunpet` profile
（左右摇晃 ±0.055 rad、6 句短捧哏池、`reaction` 接薄肌和峰哥、保留自己的「捧哏联动」开关）；
素材放到 `Assets/sun/`。

**许可**：MIT，Copyright (c) 2026 Ganzhe2028，全文见 `licenses/LICENSE-SunPet.txt`
和 `licenses/SunPet-MIT.txt`。

## FengGe-Desktop-Pet（峰哥 / 好事）

**贡献**：三份 `Bridge.swift` 里联动最全的一份——`PetRole` / peers、hop 封顶、`root` 条件；
完整的语音引擎实现，包括菜单结构、「轮播内容」真 `NSButton` 复选框、固定模式；
峰哥的 11 句 `.wav`、`clips.json`、`face.png`。

**合并进**：`PetRelay` 的协议语义（`PetSpeech` 的 `hop` / `root` 规则直接沿用）、
`AudioPetController` 的菜单与轮播内容、`fengge` profile
（只接太对了、且 `root == .shaolan` 才接，接完断链）；素材放到 `Assets/fengge/`。

**许可**：MIT，Copyright (c) 2026 好事桌宠 contributors，全文见
`licenses/LICENSE-FengGe-Desktop-Pet.txt`。

## JellyPet（果冻）

**贡献**：`Jelly.swift` 的按压 / 拉动欠阻尼弹簧模型与软限位；`main.swift` 的
560×560 透明窗口、只让图标附近接收点击、CIBumpDistortion 局部肿起、朝光标单侧拉伸、
Q 弹归位、图标切换、大小 / 位置记忆和那套弹簧自检；三个 Claude / GPT / Gemini 标志 PNG。

**合并进**：`Sources/Jelly/JellyModel.swift`、`Sources/Jelly/JellyPetController.swift`；
类型统一加 `Jelly` 前缀避免和语音桌宠重名（`Jelly`→`JellyModel`、`Spring`→`JellySpring`、
`PetView`→`JellyView`、`PetPanel`→`JellyPanel`、`PetStyle`→`JellyStyle`、
`PetGeometry`→`JellyGeometry`、`PetRenderer`→`JellyRenderer`、`PetAssets`→`JellyAssets`、
`PetController`→`JellyPetController`）；素材放到 `Assets/jelly/`。
果冻没有语音，不参与 `PetRelay`。

**许可**：**该仓库没有 LICENSE 文件**，不能标成 MIT。合集只按它 README 里
「代码可自由修改」的声明合并了代码并保留出处；公开再分发（尤其商业用途）前应先联系原作者
取得明确许可。详见 [NOTICE.md](../NOTICE.md)。

## 合并时做的结构性替换

| 原实现 | 合集里的实现 |
| --- | --- |
| 三个 App 各一份 `Bridge.swift`，靠 `DistributedNotificationCenter` 跨进程通知、用 bundle id 查存活 | 单进程内 `PetRelay` 注册表直接分发；`PetSpeech` / `hop` / `root` 字段和策略原样保留 |
| 三个 App 各自一个 bundle id 和偏好域 | 一个 `local.pethub.app`，偏好键加 `pet.<id>.` 前缀 |
| 三个几乎相同的 `main.swift` 语音引擎 | 一份 `AudioPetController` + 三份 `AudioPetProfiles` |
| 四只各自占屏幕右下角 | `PetLayout` 把它们排成右下角一行（槽位宽 260/180/260/128，间距 36） |
| 四个菜单栏状态项 | 一个「桌宠」状态项，四只的菜单作为子菜单 |
| 果冻的 `Pet*` 类型和语音桌宠同名 | 果冻侧统一加 `Jelly` 前缀 |

## 怎么核对

```bash
# 四个上游副本的 commit（upstream/ 已在 .gitignore 里，不随仓库分发）
git -C upstream/ShaolanPet log -1 --format='%H %ad'
git -C upstream/SunPet log -1 --format='%H %ad'
git -C upstream/FengGe-Desktop-Pet log -1 --format='%H %ad'
git -C upstream/JellyPet log -1 --format='%H %ad'

# 许可全文
ls licenses/
```

素材权利、商标和 JellyPet 的例外说明见 [NOTICE.md](../NOTICE.md)；
合并后的代码许可见根目录 [LICENSE](../LICENSE)。