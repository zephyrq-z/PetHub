# PetPack 内容包格式（v1）

PetPack 是「桌宠合集 2.0」的用户内容格式：一个文件夹、一个 `petpack.json`、一张头像、若干条语音。
用户可以用它把薄肌槽位换成自己的角色（例如「我的老师」），不需要改代码。

- 普通用户怎么用：[MAKE_YOUR_OWN_PET](MAKE_YOUR_OWN_PET.md)
- 现成模板：[Examples/MyTeacher](../Examples/MyTeacher/)
- 实现在：`Sources/PetKit/PetPack.swift`

## 1. 目录结构

```
MyTeacher/
├── petpack.json
├── avatar.png
└── clips/
    ├── 01.m4a
    ├── 02.m4a
    └── 03.aiff
```

- `petpack.json`：必需，放在包根目录，UTF-8 编码。
- 头像和音频：路径都**相对包根目录**，可以用子目录（推荐把音频放 `clips/`）。
- 文件名随意，只要 `petpack.json` 里的 `file` 字段和实际文件一一对应。

## 2. 字段

`petpack.json` 是一个对象：

| 字段 | 类型 | 必需 | 说明 |
| --- | --- | --- | --- |
| `format` | Int | 是 | 格式版本，目前必须是 `1`；将来加字段会升版本 |
| `name` | String | 是 | 桌宠名字，例如 `我的老师`；去掉首尾空白后不能为空；菜单/关于面板显示它 |
| `author` | String | 否 | 作者署名；导入时原样保留，编辑器保存时写当前 macOS 用户名 |
| `avatar` | String | 是 | 头像文件相对路径，例如 `avatar.png` |
| `clips` | Array | 是 | 语音列表，**1–200 条**，数组顺序就是「挑一句」里的编号顺序 |
| `clips[].file` | String | 是 | 音频文件相对路径，例如 `clips/01.m4a` |
| `clips[].label` | String | 是 | 这句语音对应的中文，字幕显示；去掉首尾空白后不能为空 |

没有 `id` 字段：播放器按数组顺序给每条分配 1、2、3……，和「挑一句」「轮播内容」的编号一致。

### 最小示例

```json
{
  "format": 1,
  "name": "我的老师",
  "author": "你的名字",
  "avatar": "avatar.png",
  "clips": [
    { "file": "clips/01.m4a", "label": "同学们好" },
    { "file": "clips/02.m4a", "label": "这道题我再讲一遍" },
    { "file": "clips/03.aiff", "label": "下课" }
  ]
}
```

完整模板见 [Examples/MyTeacher/petpack.json](../Examples/MyTeacher/petpack.json)。

## 3. 校验规则

导入、安装、启动读取时都会走同一套校验（`PetPack.validate`）：

1. `format` 必须等于 `1`，否则报「格式不对」。
2. `name` 去掉首尾空白后不能为空。
3. `avatar`：
   - 必须是相对路径：不能以 `/` 开头，不能含 `..` 路径段，不能为空；
   - 文件必须存在；
   - 必须能被 `NSImage` 解码，且宽度 > 0。
4. `clips`：
   - 至少 1 条，最多 200 条；
   - 每条 `file` 同样必须是安全相对路径、文件存在；
   - 每条 `label` 去掉首尾空白后不能为空（建议写中文，字幕原样显示）；
   - 每条音频必须能被 `AVAudioPlayer` 打开，且时长 **> 0.1 秒**。
   - `--self-test` 对自定义薄肌的音频也用同样的 >0.1s 标准（内置素材仍是 0.25–8s）。

路径分隔符用 `/`。绝对路径、`..`、网络 URL 都不接受；校验按本地相对路径处理，找不到文件就报错。

## 4. 音频和头像

### 音频

- 编辑器文件选择器里给的类型：`wav`、`m4a`（mpeg4Audio）、`mp3`、`aiff`。
- 实际校验用的是 `AVAudioPlayer(contentsOf:)` + 时长 > 0.1 秒：能解码就能通过，不强制扩展名。
- 不做变声、转码或重采样，装进 App 时保留原扩展名（统一转小写，复制为 `clips/NN.<扩展名>`）。
- 单条时长没有安装上限，但太长会影响捧哏节奏（捧哏句会抢占后续接话）。
  `--self-test` 的健康检查上限是 1 小时；正常内容碰不到这个边界。

### 头像

- 编辑器里可选 `png`、`jpeg`、`tiff`、`heic`、`gif`；校验只要求 `NSImage` 能解码。
- 推荐透明底 PNG、方形、脸部居中的图片；App 不做裁剪/抠图，按原图比例显示。
- 头像比例会参与窗口高度计算：特别高或特别宽的图会让悬浮窗变高或变宽。

## 5. 安装到哪、怎么装

### 应用内安装（推荐给普通用户）

1. 菜单栏「桌宠」→「自定义桌宠」：
   - 「换成我的角色…（替换薄肌）」：在编辑器里填名字、选头像、添加语音、逐条填中文，
     点「保存并应用」。
   - 「导入 petpack.json 文件夹…」：选一个**包含 `petpack.json` 的文件夹**，直接导入现成的包。
2. 安装位置固定为：

```
~/Library/Application Support/PetHub/HeadPet/
├── petpack.json
├── avatar.<扩展名>
└── clips/
    ├── 01.<扩展名>
    └── ...
```

3. 应用会把文件**复制**进上面这个目录（源文件夹可以之后删掉/移动）。
4. 安装采用「临时目录完整校验 → 原子替换」：先写 `HeadPet.tmp-<UUID>`，全部通过才替换
   `HeadPet/`，旧目录作备份、失败回滚。坏包不会把已经在用的角色弄没。
5. 「打开内容包文件夹」会打开 `~/Library/Application Support/PetHub/`（`HeadPet` 的上级目录）。
6. 安装成功后不用重启，薄肌槽位立即换成新角色；「恢复原版薄肌」会删掉 `HeadPet/` 并切回内置 37 句。

### 手工安装

如果不想用界面，也可以把合法的包直接放到上面的 `HeadPet/` 目录（先退出 App）。
应用启动时读取；包损坏会启动失败并弹窗，删掉 `HeadPet/` 即可恢复原版。

## 6. 分发

- 把整个包文件夹打成 zip 发出去；对方解压后，用「导入 petpack.json 文件夹…」选中解压出来的
  **那一层包含 `petpack.json` 的文件夹**。
- 已经在 App 里安装的内容本身就是标准 PetPack：把 `~/Library/Application Support/PetHub/HeadPet/`
  整个拷出来，改名后就是可分发的包（里面带 `petpack.json`）。
- 重新导入会覆盖当前自定义内容；同名/不同名都只保留一份（薄肌槽位只能放一个角色）。
- 分发前确认头像、语音、文字的权利：别人的照片/录音/课程内容要获得授权，见
  [NOTICE](../NOTICE.md)。

## 7. 限制与已知行为

- **只替换薄肌槽位**：太对了、峰哥、果冻不受影响。四步捧哏链的 `root` 仍是 `.shaolan`，
  所以太对了/峰哥的接话策略不用改。
- **一次一个包**：再安装/导入会覆盖前一个；没有「多角色切换」。
- **1–200 条**：0 条或超过 200 条直接拒绝。
- **没有排序界面**：编辑器按添加顺序，导入按 `clips` 数组顺序；想调顺序就改 JSON 再导入。
- **中文只校验非空**：任何非空字符串都能当字幕，但建议写中文。
- **不上传、不联网**：App 只读本地文件，不会把内容发到任何地方。
- **不是插件**：PetPack 只提供数据（头像/音频/文字），不能携带或执行代码。
- **内容变了会重置播放勾选**：安装包里文件的 `name`/`avatar`/`author`/每条
  `file`+`label`+文件大小组成内容指纹，存在 `pet.shaolan.contentSignature`；
  指纹一变，旧的「轮播内容」勾选和固定句会重置（避免 id 对不上），音量/大小/位置保留。
- **App 不做版权审核**：用户对自己导入的内容负责。

## 8. 常见错误

| 提示 | 原因 |
| --- | --- |
| 找不到桌宠包：… | 选中的文件夹里没有 `petpack.json` |
| 桌宠包格式不对：… | JSON 语法错、缺必需字段、`format` 不是 1 |
| 桌宠包里有不安全的相对路径：… | 路径以 `/` 开头或含 `..` |
| 桌宠包缺少文件：… | `avatar` 或 `clips[].file` 指向的文件不存在 |
| 头像读不出来：… | 图片损坏或不是 `NSImage` 能解码的格式 |
| 语音读不出来（支持 wav / m4a / mp3 / aiff）：… | 音频损坏，或时长 ≤ 0.1 秒 |
| 至少要放一条语音，不然桌宠没话说。 | `clips` 为空 |
| 语音太多了（N 条），上限 200 条。 | `clips` 超过 200 条 |
| 每条语音都要配一句中文。 | 某条 `label` 为空或只有空白 |
| 给桌宠起个名字吧。 | `name` 为空或只有空白 |
| 保存桌宠包失败：… | 写 `~/Library/Application Support/PetHub/` 失败（磁盘/权限） |

## 9. 开发者最小示例

```bash
mkdir -p MyTeacher/clips
cp ~/Pictures/teacher.png MyTeacher/avatar.png
cp ~/Recordings/hello.m4a MyTeacher/clips/01.m4a
cp ~/Recordings/bye.aiff MyTeacher/clips/02.aiff

cat > MyTeacher/petpack.json <<'JSON'
{
  "format": 1,
  "name": "我的老师",
  "author": "你的名字",
  "avatar": "avatar.png",
  "clips": [
    { "file": "clips/01.m4a", "label": "同学们好" },
    { "file": "clips/02.aiff", "label": "下课" }
  ]
}
JSON

# 用应用菜单导入 MyTeacher/ 文件夹，或直接检查：
plutil -lint MyTeacher/petpack.json 2>/dev/null || python3 -m json.tool MyTeacher/petpack.json
```

想让包内编号和文件名对应得更直观，按 `01`、`02`… 命名即可；编号只由数组顺序决定，文件名不参与。