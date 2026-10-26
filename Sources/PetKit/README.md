# PetKit · 可复用内核

这一层是「桌宠 App 的发动机」：协议、进程内联动、偏好、语音桌宠引擎、果冻引擎、内容包、大小滑块。
它**不包含**桌面宠合集的 App 壳（菜单栏、单实例、CLI、默认排列、自定义编辑器）——那些在
[`Sources/PetHub/`](../PetHub/)。

完整分层说明、扩展点、嵌入示例见 [`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md)。

> 目前不是 Swift Package：`build.sh` 把 `Sources/**/*.swift` 一起编成一个 `PetHub` 可执行文件。
> 想把 PetKit 用到别的工程，直接拷这个目录（或自己补 `Package.swift`）。

## 文件

| 文件 | 内容 | 依赖 |
| --- | --- | --- |
| `PetHost.swift` | `PetHost` / `PetHubContext` 协议、`PetError`、`PetSizing`、`PetHost` 默认实现 | AppKit、Foundation |
| `PetIdentity.swift` | `PetID`（四只内置角色）、`PetSettings`（`pet.<id>.` 前缀偏好） | AppKit、Foundation |
| `PetRelay.swift` | `PetSpeech`、`PetRelay`：进程内 hop/root 广播 | Foundation |
| `PetPack.swift` | `PetPackManifest` / `PetPackClip` / `PetPack` / `PetPackStore`：内容包读取、校验、原子安装 | AppKit、AVFoundation |
| `SizeSliderView.swift` | 菜单里的 50%–180% 大小滑块（`NSMenuItem.view`） | AppKit |
| `Audio/AudioPetController.swift` | 语音桌宠引擎：播放、轮播、接话、菜单、状态、自检 | AppKit、AVFoundation、IOKit |
| `Audio/AudioPetViews.swift` | `AudioPetPanel` / 头像 / 字幕布局与动画 | AppKit |
| `Audio/AudioPetProfiles.swift` | `AudioPetProfile`、`Clip`、三份内置 profile、reaction/捧哏池 | AppKit |
| `Audio/Motion.swift` | SPU 加速度计客户端、摇晃判定、`--motion-helper` 子进程 | IOKit、Network |
| `Jelly/JellyModel.swift` | 果冻按压/拉动弹簧、软限位 | CoreGraphics |
| `Jelly/JellyPetController.swift` | 果冻窗口、点击区域、CIBumpDistortion、菜单、自检 | AppKit、CoreImage |

## 边界

依赖方向只能是 **PetHub → PetKit**。不要在 PetKit 里 import 或引用 `PetHubApp`、
`CustomHeadImporter` 等产品类型。

当前 PetKit 还有三处产品耦合，取用前必须知道：

1. **`PetLayout` 不在 PetKit 里。** `AudioPetController.moveToDefaultPosition()` 和
   `JellyPetController` 的默认中心调用 `PetLayout.origin/slotCenterX/bottom`
   （定义在 `Sources/PetHub/PetLayout.swift`）。单独拿走 PetKit 时，要自己提供这些函数，
   或先把 `PetLayout` 移进来。
2. **内容包默认目录写死 PetHub。** `PetPack.defaultStoreURL` 是
   `~/Library/Application Support/PetHub/HeadPet`；别的 App 用 `PetPackStore(baseURL:)` 注入自己的路径。
3. **素材按 bundle 目录名读。** 语音引擎读 `Bundle.main.resourceURL/<PetID.assetsFolder>/`，
   果冻读 `Bundle.main.resourceURL/jelly/`；嵌入时资源要按同名目录放进主 bundle。

`PetID` 目前是桌宠合集四个内置角色的枚举（`shaolan` / `sunpet` / `fengge` / `jelly`），
同时被当作素材目录名和偏好前缀。它不是参数化设计；复用到别的 App 时要么扩展它，
要么替换成你自己的身份类型并同步修改引擎对 `id.assetsFolder` / `PetSettings` 的使用。

## 什么该放这一层

适合：

- 与具体产品无关的桌宠能力：播放、字幕、弹簧、联动、内容包格式、大小滑块；
- 可以被另一个 App 直接复用的协议和默认实现；
- 新增引擎/新角色类型时，对主控只暴露 `PetHost` 的方法。

不适合：

- `NSApplicationDelegate`、菜单栏状态项、单实例、CLI 参数解析；
- 桌宠合集的具体默认排列、产品菜单文案、关于面板；
- 构建脚本、打包、图标生成；
- 依赖 `UserDefaults` 具体域名的逻辑（`PetSettings` 跟随 `UserDefaults.standard`，由宿主决定）。

## 加新东西时

- 新形态的桌宠：实现 `PetHost`，在主控 `buildPets()` 里按条件创建。
- 新语音角色：只加 `AudioPetProfile` 与素材，不改引擎；参见
  [`docs/ARCHITECTURE.md` 第 8 节](../../docs/ARCHITECTURE.md#8-加一个内置角色)。
- 新内容包字段：`PetPackManifest` 加可选字段，保持 `format: 1` 的旧包可读；
  不兼容改动升 `format`，同步 [`docs/PETPACK.md`](../../docs/PETPACK.md) 和自检。
- 不要为了某个产品需求往协议里塞方法；先想清楚是不是所有宿主都需要它。

## 测试与许可

没有独立的测试 target：`PetHub --self-test` 会覆盖这一层的播放、菜单、弹簧、布局、
内容包安装/导入等断言，`--chain-test` 覆盖联动实测。命令见
[`CONTRIBUTING.md`](../../CONTRIBUTING.md)。

代码 MIT（根目录 [LICENSE](../../LICENSE)）；内置素材不在 MIT 范围内，见
[NOTICE.md](../../NOTICE.md)。本目录不含任何音频、头像或图片。