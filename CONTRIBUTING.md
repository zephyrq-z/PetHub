# 参与开发

欢迎改代码、加角色、做内容包。先读这几份，能省掉大半沟通：

- [README](README.md)：这个 App 是什么、怎么玩；
- [TECHNICAL](TECHNICAL.md)：成品 App 的实现细节；
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)：PetKit / PetHub 分层与扩展点；
- [docs/PETPACK.md](docs/PETPACK.md)：用户内容包格式；
- [AGENTS.md](AGENTS.md)：这个仓库不能破的约束；
- [NOTICE.md](NOTICE.md)：哪些素材不能进 MIT。

## 环境

- Apple Silicon（arm64）+ macOS 14 或更新；
- Xcode Command Line Tools（`xcode-select --install`），只需要 `swiftc`，不需要完整 Xcode；
- 没有 npm / pip / Homebrew 依赖，构建不联网。

## 构建与测试

```bash
./build.sh                 # 编译 + 自检，最后一行必须是 PASS
./build.sh --package       # 另出 dist/PetHub-2.0.0.{zip,dmg,sha256}
./install.sh --build       # 装进「应用程序」并启动
```

发布前至少跑完下面四项：

```bash
# 1) 全量自检：四只 + 菜单 + 布局 + 大小联动 + 自定义内容包，默认内置四只时 222 项，
#    装了自定义内容包后总数会随语音条数变化；最后一行必须是 PASS
./build/桌宠合集.app/Contents/MacOS/PetHub --self-test

# 2) 四步捧哏链实测（约 21 秒；偶发丢句会自动重试一次，最长约 42 秒）
./build/桌宠合集.app/Contents/MacOS/PetHub --chain-test

# 3) 画面：4 张单图 + preview-all.png（一排）+ preview-stage.png（合影），共 6 张
./build/桌宠合集.app/Contents/MacOS/PetHub --preview /tmp/pethub-preview

# 4) 状态快照（只读）
./build/桌宠合集.app/Contents/MacOS/PetHub --dump-state
```

补充说明：

- `--self-test` / `--chain-test` / `--dump-state` / `--preview` 是**只读诊断**，不做单实例拦截，
  不写偏好、不自动开机身摇晃；
- `--trace` 是**正常启动**加日志，会受单实例限制、写偏好、按正常启动开机身摇晃，不要当只读诊断用；
- `--probe-sensor` 只检查本机有没有 SPU 运动传感器；
- 自检不测真实播放和联动节奏，别用 `--self-test` 的 PASS 代替 `--chain-test`。

## 代码组织

- `Sources/PetKit/`：可复用内核（协议、联动、偏好、语音引擎、果冻引擎、内容包、大小滑块）。
  放“任何桌宠 App 都用得上”的东西。
- `Sources/PetHub/`：成品 App（`main`、`PetHubApp`、`PetLayout`、`CustomHeadImporter`）。
  放“这个产品”的决定：菜单栏、四只的装配、默认站位、CLI、自定义编辑器。
- `build.sh` 把 `Sources/**/*.swift` 一起编成一个 `PetHub` 可执行文件；目前没有 `Package.swift`。
- 依赖方向只能是 **PetHub → PetKit**。已知三处耦合（`PetLayout`、内容包默认目录、bundle 资源目录）
  写在 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 和 [Sources/PetKit/README.md](Sources/PetKit/README.md)；
  不要新增 PetKit → PetHub 的依赖；要动这三处，先更新那两份文档。

### 代码风格

- Swift 5 语法，AppKit；4 空格缩进，文件内用 `// MARK: -` 分段。
- 注释写“为什么”，中文和仓库现有风格保持一致；公开类型/方法写短文档注释。
- 不加第三方依赖、不联网、不申请额外权限（摇晃 helper 的 127.0.0.1 回环 UDP 除外）。
- 不改 `PetHost` / `PetHubContext` 的签名来“顺手方便”；它们是对外扩展边界，改动要同步四只实现和文档。
- 新增 CLI 参数要谨慎：对外只保留 `--self-test` / `--chain-test` / `--dump-state` /
  `--preview` / `--trace` / `--probe-sensor` / `-h`。自定义桌宠走 GUI 菜单，不加 CLI。

## 加一个内置角色

完整说明见 [ARCHITECTURE 第 8 节](docs/ARCHITECTURE.md#8-加一个内置角色)。检查顺序：

1. `PetID` 加 case + `title` / `fullName` / `assetsFolder` / `isAudio`；
2. `AudioPetProfiles` 加 profile 并在 `profile(for:)` 返回；reaction / 捧哏池按联动规则写；
3. `PetLayout` 的 `order` / `slotWidth` 加位置；
4. `Assets/<assetsFolder>/` 放 `face.png`、`clips.json`、`Clips/`；
5. `build.sh` 的素材检查与 `cp -R Assets/...` 列表加目录；
6. `Tools/make-icon.swift` 图标排布加一张脸，重生成 `Assets/AppIcon.icns`；
7. 如果改变四步链，改 `--chain-test` 的期望序列 + `TECHNICAL.md` 第 4 节；
8. 第三方素材按 `NOTICE.md` 处理，新许可放 `licenses/`。

只是想让用户换个角色的话，**不要加内置角色**：做一个 PetPack 内容包更轻，见
[docs/PETPACK.md](docs/PETPACK.md)。

## 改内容包 / 自定义桌宠

涉及文件：`PetKit/PetPack.swift`、`PetHub/CustomHeadImporter.swift`、`PetHub/PetHubApp.swift`、
`PetKit/Audio/AudioPetController.swift`。

- `petpack.json` 的 `format` 是兼容性开关。加字段可以，但**旧的 `format: 1` 包必须继续能读**；
  不兼容的改动要升 `format` 并在 `docs/PETPACK.md` 写清迁移方式。
- 校验规则（1–200 条、相对路径、禁止 `..`、中文非空、头像/音频可解码）是安全边界，
  不要为了“方便”放宽；放宽要同步 `docs/PETPACK.md` 和自检。
- 安装必须保持「临时目录完整校验 → 原子替换 → 失败回滚」，不能直接覆盖用户正在用的内容。
- 内容变了要重置播放勾选/固定句（内容指纹 `contentSignature`），音量/大小/位置保留。
- 自定义内容只替换薄肌槽位；`PetID` / `root` 必须保持 `.shaolan`，否则捧哏链会断。
- 自检涉及自定义内容包时只能用临时目录 + 独立 `UserDefaults` suite，不能碰用户真实的
  `~/Library/Application Support/PetHub/HeadPet/`。

## 素材与许可边界

- 代码 MIT（见 [LICENSE](LICENSE)）；**音频、头像、Claude/GPT/Gemini 标志不在 MIT 里**，
  版权归原权利人，不商用。
- 不要往仓库提交来源不明的图片、录音、视频截图；`Examples/` 只放模板和文字，不放二进制素材。
- 不要在 `LICENSE` 末尾追加例外（会让 GitHub 判成 `NOASSERTION`）；素材权利写 `NOTICE.md`。
- JellyPet 没有 LICENSE 文件，果冻代码按原作者 README「代码可自由修改」合并；
  公开再分发前先联系原作者，别把它描述成 MIT。
- 新增第三方代码/素材：更新 `NOTICE.md`、`docs/UPSTREAM.md`，许可全文放 `licenses/`。

## 文档同步

改了行为就改文档，不要留旧路径/旧版本：

| 改动 | 要同步的文档 |
| --- | --- |
| 构建、打包、CLI、偏好键 | `TECHNICAL.md`、`AGENTS.md` |
| 分层、协议、扩展点 | `docs/ARCHITECTURE.md`、`Sources/PetKit/README.md` |
| 内容包格式/校验/限制 | `docs/PETPACK.md`、`Examples/MyTeacher/README.md` |
| 用户可见的换角色流程 | `README.md`、`docs/MAKE_YOUR_OWN_PET.md` |
| 素材/许可 | `NOTICE.md`、`docs/UPSTREAM.md`、`licenses/` |
| 版本号/产物名 | `README.md`、`TECHNICAL.md`、`AGENTS.md`、`docs/DESIGN.md` |

历史验收记录 `docs/QA-REPORT.md` 是流水账，不要改。

## PR 检查清单

- [ ] `./build.sh` 成功，最后一行 `PASS`
- [ ] `--self-test` PASS（没有减少原有断言；新增行为有对应断言）
- [ ] 改了联动/接话就跑了 `--chain-test`，四步链仍 PASS
- [ ] `--preview /tmp/pethub-preview` 出 6 张图，肉眼确认四只和自定义角色正常
- [ ] 没有引入第三方依赖、没有联网、没有新增系统权限
- [ ] 没有提交 `build/`、`dist/`、二进制、素材大文件
- [ ] 素材权利清楚；没有把非 MIT 素材说成 MIT
- [ ] 文档和实现一致，旧目录名/旧版本号已清理
- [ ] 内容包改动向后兼容 `format: 1`，或已明确写迁移说明
- [ ] PR 描述写清“改了什么、怎么验证的”，贴 `--self-test` / `--chain-test` 最后一行

提交信息用中文一句话概括改动；发版本时由维护者统一改版本号、跑打包。

## Windows（Electron）版

Windows 版在 [`windows/`](windows/) 目录，复用同一批 `Assets/` 和同一套 PetPack 格式：

```bash
cd windows
export HTTPS_PROXY=http://127.0.0.1:7897 HTTP_PROXY=http://127.0.0.1:7897  # 如果你在墙内
npm install
npm run smoke        # 无人工交互跑四窗口 + 四步链 + 设置窗，最后一行必须是 PASS
./build-win.sh       # 产出 dist/windows/PetHub-<版本>-Windows-x64.exe / .zip / .sha256
```

- 只在 macOS 上交叉构建过；Windows 实机行为（透明窗口/置顶/DPI/托盘）需要真机复核。
- 依赖只有 `electron` / `electron-builder`，不要引入框架或联网运行时。
- 改动联动逻辑时，`npm run smoke` 里要能看到 `step 1/4 … step 4/4` 且 root 正确。
- 用户文档：[docs/WINDOWS.md](docs/WINDOWS.md)；开发细节：[windows/README.md](windows/README.md)。
