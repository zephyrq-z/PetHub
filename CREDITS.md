# 来源、署名与许可（CREDITS）

**「桌宠合集 / PetHub」是一个整合项目，不是原创角色项目。**

四个角色、原声、头像、原始玩法来自下面四个独立开源仓库。本项目做的是：把四份代码合并成
一个进程 / 一个 App、统一架构、加自定义内容包和跨平台封装；**没有声索角色、音频、头像或原始创意的版权**。

| 上游项目 | 作者 | 许可 | 本项目用到的内容 | 合并时 commit |
| --- | --- | --- | --- | --- |
| [ShaolanPet / 薄肌桌宠](https://github.com/Ganzhe2028/ShaolanPet) | Ganzhe2028 | MIT（代码） | 薄肌 37 句原声、头像、语音引擎基础、竖向压扁动画、轮播/挑一句 | `7ce7e2b` |
| [SunPet / 太对了](https://github.com/Ganzhe2028/SunPet) | Ganzhe2028 | MIT（代码） | 太对了 28 句原声、头像、机身摇晃（SPU 加速度计）、捧哏预解码/开头静音补偿 | `9b68d09` |
| [FengGe-Desktop-Pet / 好事桌宠](https://github.com/Ganzhe2028/FengGe-Desktop-Pet) | 好事桌宠 contributors | MIT（代码） | 峰哥 11 句原声、头像、hop/root 四步捧哏联动语义、菜单/轮播实现 | `d3336de` |
| [JellyPet / 果冻桌宠](https://github.com/aurelius358/JellyPet) | aurelius358 | **仓库未附 LICENSE** | 果冻弹簧模型、560 透明窗口、CIBumpDistortion、Claude/GPT/Gemini 标志 | `7306d4e` |

四个仓库合并时的完整 commit 与逐项贡献见 [docs/UPSTREAM.md](docs/UPSTREAM.md)。

## 声明

- **代码**：本项目新增的整合代码采用根目录 [LICENSE](LICENSE) 的标准 MIT。
  三个上游仓库的代码是 MIT，许可全文保留在 [licenses/](licenses/)。
- **JellyPet**：上游仓库里没有 LICENSE 文件，不能标成 MIT。本项目只按它 README 里
  「代码可自由修改」的声明合并了果冻代码并保留出处。**公开再分发（尤其商业用途）前，应先联系原作者
  [aurelius358](https://github.com/aurelius358) 取得明确许可。**
- **音频 / 头像 / 标志**：版权归原权利人，**不在 MIT 范围内**，本项目只做学习交流和玩梗、不商用。
  权利人如果觉得不合适，开 issue 会立刻移除。细节见 [NOTICE.md](NOTICE.md)。
- **设计致谢**：捧哏联动的 hop/root、接话时机、预解码和静音补偿设计来自 SunPet，
  其 MIT 许可全文见 [licenses/SunPet-MIT.txt](licenses/SunPet-MIT.txt)。
- **本项目角色**：仅做了「四合一 App、PetKit/PetHub 分层、自定义 PetPack、跨平台封装」。
  如果你要引用/二次分发，请同时保留本文件和四个上游链接。
- **联系方式**：对署名、删除素材、许可证有任何问题，请在 GitHub issue 里说明；会尽快处理。

## 引用格式

如果你在文章/视频/项目里引用本项目，建议写成：

> 桌宠合集 PetHub，整合自 ShaolanPet、SunPet、FengGe-Desktop-Pet（作者 Ganzhe2028 / 好事桌宠
> contributors，MIT）与 JellyPet（作者 aurelius358）。本项目只做整合与跨平台封装，
> 角色、音频、头像版权归原作者。https://github.com/zephyrq-z/PetHub

（仓库地址以实际发布地址为准。）