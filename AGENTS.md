# AGENTS.md

给在这个仓库里干活的 AI。人看的在 [README.md](README.md)，技术细节在 [TECHNICAL.md](TECHNICAL.md)，
素材权利在 [NOTICE.md](NOTICE.md)，上游来源在 [docs/UPSTREAM.md](docs/UPSTREAM.md)。

这个仓库是「桌宠合集」：薄肌、太对了、峰哥、果冻四只桌宠，住在**一个 App、一个进程**里。

## 构建与验证

- `./build.sh` 编译并跑 `--self-test`，**最后一行必须是 `PASS`**。没 PASS 就是没改完。
- `./build.sh --package` 产出 `dist/PetHub-1.1.0.{zip,dmg,sha256}`；dmg 卷名「桌宠合集」，里面是 app + `/Applications` 软链。
- `./install.sh --build` 装进 /Applications 并启动；`./install.sh --uninstall` 卸载（偏好保留）。
- 只支持 Apple Silicon + macOS 14，`build.sh` 里写死 `arm64-apple-macosx14.0`，不要为 Intel 改。
- 诊断入口：`--self-test`、`--chain-test`、`--dump-state`、`--preview <目录>`、`--probe-sensor`、`-h`。
  `--trace` 是**正常启动**加日志：受单实例限制、会写偏好、会按正常启动开机身摇晃，别当只读诊断用。
- 改完联动一定要跑 `--chain-test`（约 21 秒；偶发丢句会自动重试一次）：自检只断言 reaction 策略，不真的放四步链。
- 画面改动用 `--preview /tmp/pethub-preview` 出四张单图和一张合影，肉眼确认后再算完成。
- 改图标：`swift Tools/make-icon.swift`，它会重生成 `Assets/AppIcon.icns` 和 `/tmp/pethub-icon-preview.png`。

## 不能破的约束

- **`hop` / `root` 语义不可改**：用户点击是 hop 0，接话者 hop+1，`root` 一路原样传；
  点薄肌必须得到「薄肌 hop0 → 太对了 hop1 → 峰哥 hop2 → 太对了 hop3」，root 全是薄肌，**没有第五句**。
  改 `reaction` 表、hop 上限或 root 条件时，`--chain-test` 的期望序列和 TECHNICAL.md 第 4 节必须一起改。
- **素材不进 MIT**：音频、头像、Claude/GPT/Gemini 标志的版权归原权利人，不商用。
  `LICENSE` 只放标准 MIT 全文，素材权利写 `NOTICE.md`；往 LICENSE 末尾追加例外会让 GitHub 判成 `NOASSERTION`。
  `licenses/` 只放上游许可全文，别往里塞代码或素材。
- **JellyPet 没有 LICENSE**：果冻代码只按原作者 README「代码可自由修改」合并。要公开再分发（尤其商用）前，
  先联系原作者取得明确许可，别把它描述成 MIT。
- **只支持 arm64 + macOS 14**。不要加兼容 Intel 的条件分支或依赖；不要引入 Homebrew / npm / pip 依赖。
- **不联网、不申请额外权限**。唯一的本机通信是机身摇晃 helper 的 127.0.0.1 回环 UDP；
  不碰麦克风、摄像头、辅助功能、屏幕录制。不要为了「让它能用」改系统安全设置。
- **`PetHost` / `PetHubContext` 协议签名**是四只和主控的边界，改之前先确认四只都跟得上。
- **一个进程、一个菜单栏入口、一个 App**：别再拆成多个 App，也不要在正常启动时放开单实例限制。
- **素材目录名和偏好前缀**：`PetID.rawValue` / `assetsFolder` 同时用作 `Assets/` 目录名和 `pet.<id>.` 前缀，
  改名会丢用户设置、读不到素材。

## 文档同步

- README 是给普通人看的落地页，只放：四只一句话、装三步、玩法、和独立 App 的关系、版权、构建入口。
  技术长文一律进 TECHNICAL.md。
- 行为、偏好键、CLI、构建产物有变化时，TECHNICAL.md 必须跟着改；不要写没实现的命令或功能。
- 换素材、加角色、改许可边界时，NOTICE.md 和 docs/UPSTREAM.md 要同步；素材版权说明不能删。
- 图标改了，README 里的四张脸和图标说明检查一遍。

## 发布

- 二进制不进仓库，安装包放 Releases / 交付目录。
- 分发包命名固定：`PetHub-<版本>.zip`、`PetHub-<版本>.dmg`、`PetHub-<版本>.sha256`；
  dmg 卷名「桌宠合集」；zip 用 `ditto`（中文文件名只有它能保证 Finder 双击正确解压）。
- 发布前至少跑一遍：`./build.sh --package` + `hdiutil verify dist/PetHub-1.1.0.dmg`。

## 这个仓库

- app：`桌宠合集.app`，可执行文件 `PetHub`，bundle id `local.pethub.app`，版本 1.1.0
- 四只顺序（也是右下角一排和菜单里的顺序）：薄肌 `shaolan` → 太对了 `sunpet` → 峰哥 `fengge` → 果冻 `jelly`
- 联动：三只语音桌宠进程内广播（`PetRelay`）；果冻只形变、不接话
- 大小联动：菜单栏「大小联动」默认开（`hub.linkSize`），改任意一只按各自小/中/大档位同步四只；
  `PetHost.applySizeTier` / `sizeTier` 是这个功能的边界，改档位时四只的 `sizeChoices` 要一起维护
- 偏好域：`local.pethub.app`；四只前缀 `pet.shaolan.` / `pet.sunpet.` / `pet.fengge.` / `pet.jelly.`；
  全局开关 `hub.relayEnabled`、`hub.linkSize`
- 入口：菜单栏「桌宠」；没有 Dock 图标（`LSUIElement`）
- 自检/诊断模式（`--self-test` / `--chain-test` / `--dump-state` / `--preview`）不做单实例拦截；
  正常启动（含 `--trace`）只允许一个实例。