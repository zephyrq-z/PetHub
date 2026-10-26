# 平台说明（macOS / Windows / 源码）

「桌宠合集 PetHub 2.0」一次发布里提供三种东西：

| 包 | 适合谁 | 说明 |
| --- | --- | --- |
| `PetHub-2.0.0-macOS-arm64.dmg` | macOS 14+ Apple Silicon 用户 | 原生 Swift/AppKit 版，功能最全，主版本 |
| `PetHub-2.0.0-Windows-x64.exe` | Windows 10/11 x64 用户 | Electron 跨平台版，免安装便携 exe |
| `PetHub-2.0.0-Windows-x64.zip` | Windows 用户（备用） | 解压即用，启动更快，适合长期用 |
| `PetHub-2.0.0-macOS-arm64.zip` | macOS 用户（备用） | 解压后拖进「应用程序」 |
| `PetHub-2.0.0-Source.zip` | 开发者 / 想自己改的人 | macOS + Windows 两套源码、文档、示例；不含 Node 依赖 |

三个包都是「四合一」：薄肌 / 太对了 / 峰哥 / 果冻住在同一个 App 里，四步捧哏链一致。

> **署名**：本项目是整合项目，不是原创角色项目。角色、原声、头像来自
> ShaolanPet / SunPet / FengGe-Desktop-Pet（作者 Ganzhe2028 等，MIT）和 JellyPet
>（作者 aurelius358，仓库未附 LICENSE）。完整说明见 [CREDITS.md](../CREDITS.md)。

## macOS 原生版（推荐 macOS 用户）

- 下载 `.dmg`，把「桌宠合集.app」拖进「应用程序」。
- 第一次打开：右键 App → 打开（ad-hoc 签名，没有 Apple 公证）。
- 完整功能：四只桌宠、四步捧哏链、大小滑块 / 联动、紧凑排列、捧哏排列、绑定相对位置、
  自定义桌宠编辑器（头像 + 多条语音 + 中文）、PetPack 导入、机身摇晃（支持的机型）。
- 要求：Apple Silicon + macOS 14+。

## Windows 跨平台版（Electron）

- 下载 `PetHub-2.0.0-Windows-x64.exe`，双击运行。免安装，解压到临时目录后启动；
  首次运行 Windows SmartScreen 可能提示「未知发布者」，选「更多信息 → 仍要运行」。
- 功能：
  - 四只透明置顶桌宠，点击说话、拖动、右键菜单、字幕；
  - 同一套四步捧哏链：薄肌 → 太对了 → 峰哥 → 太对了；
  - 托盘菜单 + 设置窗口：显示/隐藏、排列、大小滑块、大小联动；
  - 导入 PetPack（把薄肌换成你的角色）；不支持 macOS 那套可视化编辑器，先在 macOS 版或手写
    `petpack.json` 做好再导入；
  - 果冻为简化的 CSS 形变版（不是 macOS 的 CoreImage 逐像素肿起）。
- 与 macOS 版的差异：
  - 没有机身摇晃（Windows 没有对应 SPU 读取）；
  - 没有完整的果冻 CIBumpDistortion / 软限位手感，只保留按压放大、拖动拉伸、松手回弹；
  - 透明窗口的四周仍会接收鼠标，点击穿透不如 macOS 精确；
  - 未在 Windows 实机做过长时间运行测试（构建在 macOS 上交叉完成）；有问题请开 issue。
- 要求：Windows 10/11 x64。

## 源码

`PetHub-2.0.0-Source.zip` 解压后：

- macOS 原生：`./build.sh`（PASS 末行）、`./build.sh --package` 出 dmg；
- Windows：`cd windows && npm install && npm run smoke`，`npm run dist:win` 出 exe；
- 依赖：Xcode Command Line Tools（macOS）、Node.js 22+（Windows 版）。

## 校验

Release 里同时提供 `PetHub-2.0.0-sha256.txt`。下载后可核对：

```bash
shasum -a 256 -c PetHub-2.0.0-sha256.txt      # macOS
certutil -hashfile PetHub-2.0.0-Windows-x64.exe SHA256   # Windows
```

## 许可与素材

- 整合代码 MIT；上游四份许可全文在 [licenses/](../licenses/)。
- 音频、头像、Claude/GPT/Gemini 标志版权归原权利人，**不在 MIT 内、不商用**；
  细节见 [NOTICE.md](../NOTICE.md)。
- 用户自己导入的头像/语音/中文版权归用户；App 不联网、不上传。
- JellyPet 上游无 LICENSE，公开再分发（特别商用）前请先联系原作者。