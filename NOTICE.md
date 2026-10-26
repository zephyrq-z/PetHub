# 素材与第三方许可

这个仓库是「桌宠合集」：把薄肌、太对了、峰哥、果冻四只桌宠并进一个 App。
**代码用 MIT，音频和头像不属于 MIT。** 这一页写清楚哪些能随便改、哪些不能。

## 音频和头像

`Assets/shaolan/`、`Assets/sun/`、`Assets/fengge/` 里的音频和 `face.png` 头像，
都不在 MIT 许可范围内，版权归原权利人。这个项目只做学习交流和玩梗，**不商用**。
权利人如果觉得不合适，开个 issue，会立刻移除。

- 薄肌：B 站《为什么我劝所有男人练薄肌？》（BV1xa4k6vEpp）和《如何练出薄肌？》（BV1httT6LEfy）里逐句截取的原声；头像来自视频封面，去背景处理。37 句，时间码在 `Assets/shaolan/clips.json` 的 `source` 字段。
- 太对了：B 站《对话孙宇晨：年轻人如何抓住 AI 时代的机会？》（BV1fcHD6cEw3）里 28 个时间点逐句截取，原声，没做变声或语音克隆；头像来自公开照片，去背景处理。时间码在 `Assets/sun/clips.json`。
- 峰哥：两份峰哥语录 MP3 里切出的 11 句原声；头像来自公开照片，去背景处理。裁剪时间记录在上游仓库的 `Work/audio-cut-notes.md`。

`Assets/jelly/` 里的 Claude、GPT、Gemini 标志是各自公司的商标，只用于个人桌面装饰；
标志文件由上游 JellyPet 从 Simple Icons 和 Wikimedia Commons 的 SVG 渲染而来。
商用需要各自权利人授权，本仓库不授予任何商标使用权。

## 代码许可

合并版代码采用根目录 [LICENSE](LICENSE) 里的标准 MIT 许可（Copyright © 2026 桌宠合集 contributors）。
素材权利只写在这里，不往 LICENSE 里追加例外 —— 追加会让 GitHub 把仓库判成 `NOASSERTION`。

三个上游仓库的代码是 MIT：

| 上游仓库 | 许可 | 版权 |
| --- | --- | --- |
| [Ganzhe2028/ShaolanPet](https://github.com/Ganzhe2028/ShaolanPet) | MIT | Copyright (c) 2026 Ganzhe2028 |
| [Ganzhe2028/SunPet](https://github.com/Ganzhe2028/SunPet) | MIT | Copyright (c) 2026 Ganzhe2028 |
| [Ganzhe2028/FengGe-Desktop-Pet](https://github.com/Ganzhe2028/FengGe-Desktop-Pet) | MIT | Copyright (c) 2026 好事桌宠 contributors |

许可全文保留在 [`licenses/`](licenses/) 下。

**JellyPet 例外**：[aurelius358/JellyPet](https://github.com/aurelius358/JellyPet) 仓库里没有 LICENSE 文件。
这里只按它 README 里「代码可自由修改」的声明合并了果冻的代码，并保留出处。
如果要公开再分发这个合集（尤其是商业用途），请先联系原作者取得明确许可。
果冻的形变参数与界面手感来自该仓库，未做声索。

## 设计致谢

薄肌、太对了、峰哥三只共用一套「捧哏」联动设计：`hop`（跳数）和 `root`（链头）防环、接话时机与重叠、
捧哏句预解码和开头静音测量。这套交互与播放设计参考了 [SunPet](https://github.com/Ganzhe2028/SunPet)，
其 MIT 许可全文见 [`licenses/SunPet-MIT.txt`](licenses/SunPet-MIT.txt)。

合集把原来三份 `Bridge.swift` 的跨进程通知改成了单进程内的 `PetRelay`，
四步链的跳数、root 条件和接话策略没有改。上游来源与合并时对应的 commit 见 [`docs/UPSTREAM.md`](docs/UPSTREAM.md)。