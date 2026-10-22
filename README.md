# 七日杀 · 口袋版

个人自用的 iPhone 小游戏，用开源引擎 [Godot 4.4](https://godotengine.org) 写成，素材全部来自自己《七日杀》客户端导出的模型、贴图、图标和音乐。**素材只放在本地 `assets/`，不进仓库，游戏不分享、不发布。**

## 玩法

- 第一人称，开局站在市中心十字路口。地图是 4×4 个街区，楼会挡路也会挡子弹。
- 左半屏拖动移动，**推到底再往外拖是冲刺**（耗体力）；右半屏拖动转视角；按住「攻击 / 开火」；「跳」能跳上路障、垃圾桶这种矮东西，僵尸上不来。
- 走近垃圾桶、车、箱子按「搜索」，地上的东西按「拾取」。捡到更好的武器会自动换上；吃的、喝的、药在快捷栏或「背包」里点一下用。子弹走过去自动捡。
- 枪有弹匣和备弹，不同枪用不同口径（9mm、.44、7.62、霰弹、箭、弩箭、火箭弹）。打空了自动换弹，也可以按「换弹」。**打头伤害 2.5 倍**。枪声会把附近的僵尸引过来。
- 8 种僵尸：士兵（有护甲）、护士、胖警察（会远远吐酸）、飞车党、伐木工（血厚、下手重）、乔、阿琳、尖叫者（看到你就叫，会叫来别的僵尸）。白天在附近闲逛，看见或听见你才追；夜里一直追，而且会跑。会绕着楼和车走。
- 僵尸先抬手再砍，看到抬手赶紧退开就能躲过去。被抓到可能流血（任何药都能止血）或者感染（抗生素、急救包、蜂蜜能治）。
- 要吃也要喝：饿了、渴了都会掉血；吃饱喝足会慢慢回血。
- 一天 5 分钟。第 7 天夜里是血月尸潮，撑到第 8 天早上 6 点就赢。
- 音乐跟着局势切换：探索 Exp、紧张 Sus、战斗 Cbt、血月 Bld。右上角「暂停」里能调视角灵敏度、音乐和音效音量。

数值（一天多长、僵尸血量、每把枪的弹匣和伤害、每种僵尸的能力等）都在 `scripts/config.gd`，第一人称手臂的摆放在 `scripts/fp_arms.gd` 顶部。

## 素材从哪来

物品列表只读 `assets/index/icon_to_model.json`（每项 `[物品名, 中文名, 英文名, 模型名]`），代码里不写死任何物品。物品按名字前缀分类：`melee*` 近战、`gun*` 远程、`food*` / `drink*` / `medical*` 消耗品、`resource*` / `ammo*` 材料。

| 目录 | 内容 |
| --- | --- |
| `assets/index/icon_to_model.json` | 物品表 |
| `assets/icons/<物品名>.png` | 物品图标（地上没模型的物品也用图标显示） |
| `assets/models/zombie_*.glb` + 同名 `.png` | 带骨骼的僵尸，走路动作由代码驱动 |
| `assets/models/<模型名>.glb` 或 `.obj` + 同名 `.png` | 物品模型、第一人称手臂 `FP_ARM_M` |
| `assets/props/*.glb` | 场景里摆的车辆、家具 |
| `assets/textures/*.png` | 地面贴图、手臂贴图 |
| `assets/music/*.wav` | 文件名含 Exp / Cbt / Sus / Bld |
| `assets/sounds/<名字>_<序号>.wav/.ogg` | 音效（可选）。名字是 gun_pistol、gun_rifle、gun_shotgun、groan、scream、footstep 等，见 `scripts/sfx.gd`；没有的用代码合成的声音 |

物品表里的模型名是 prefab 名（如 `chainsawPrefab`），导出的文件名是网格名（如 `Chainsaw_LOD0.glb`），游戏会去掉 `Prefab`、`_LOD0`、`Mesh` 后再比对。

### 从小桔云盘同步素材

```bash
export XIAOJU_TOKEN=你的令牌      # 只放环境变量，别写进任何文件
python3 tools/fetch_assets.py      # 默认 8 种僵尸、每类 6 段音乐
python3 tools/fetch_assets.py --zombies all --music 12   # 想要更多
```

脚本只用 Python 自带库，会把云盘 `/7day` 下的图标包、僵尸包、样例模型、音乐整理成上面的结构；已经下载过的会跳过。

> 目前云盘上还没有物品模型所在的 `items` 资源包（约 540MB），所以大部分物品在地上和手里显示的是它的图标；样例里有模型的（电锯、电击棒、复合弓）会用 3D 模型。以后把导出的物品 `.glb` 放进 `assets/models/` 就会自动用上。

## 素材放哪：安装包里 + 云盘素材包

为了让安装包小一点，编译时（`tools/cloud_pack.py`）把大素材打成一个 Godot 素材包（`.pck`）传到云盘 `/7day/素材包/`，游戏第一次打开时显示进度条下载，存在手机里，以后直接用：

- **安装包里**：第一人称手臂、物品和图标、乔 / 阿琳 / 护士三种僵尸。不联网也能玩。
- **云盘素材包**：市中心的楼、车和杂物、地面贴图、音乐、音效，士兵 / 胖警察 / 飞车党 / 伐木工 / 尖叫者五种僵尸。

素材内容没变时素材包文件名不变，手机上不会重复下载。下载失败可以重试，也可以先不下载直接玩（没有楼、车和音乐）；手机里有旧版本的素材包时会先用旧的。素材包的分享链接 7 天后过期，过期后已经下载过的手机不受影响，新装的要用新编译的安装包。上传素材包失败时，这一版会自动把素材打回安装包。

## 装到 iPhone 上

需要一台 Mac。

1. 安装 [Godot 4.4.1](https://godotengine.org/download/archive/4.4.1-stable/)（标准版，不是 .NET 版）和 Xcode。
2. 按上一节把素材同步到 `assets/`。
3. 用 Godot 打开本项目（第一次会导入素材，几分钟）。可以先按 F5 在电脑上试玩：WASD 移动、方向键看、F 攻击、空格跳、Shift 冲刺、R 换弹、E 搜索/拾取，鼠标点拖模拟触屏。
4. 菜单「编辑器 → 管理导出模板」，下载 4.4.1 的导出模板。
5. 菜单「项目 → 导出」，选 iOS：
   - `App Store Team ID` 填你的 Apple 开发者 Team ID（免费 Apple ID 也行，在 Xcode → Settings → Accounts 里能看到）。
   - `Bundle Identifier` 已经填了 `com.langhua98.sevenday`，如果冲突改成别的。
   - 点「导出项目」，选 `build/ios/` 目录，会生成一个 Xcode 工程。
6. 用 Xcode 打开 `build/ios/7day.xcodeproj`，Signing 里选你的 Team，连上 iPhone，点运行。
   - iPhone 上要打开「设置 → 隐私与安全性 → 开发者模式」。
   - 用免费 Apple ID 签名的应用 7 天后会过期，重新从 Xcode 运行一次即可。

## 目录

```
project.godot          Godot 项目
scenes/main.tscn       主场景
scripts/asset_db.gd    读取素材、物品分类、枪和僵尸的数值（自动加载为 Assets）
scripts/main.gd        昼夜、刷怪、走跑跳、战斗、背包、生存
scripts/world.gd       市中心：街道、楼、车和杂物、碰撞、僵尸寻路
scripts/zombie.gd      僵尸（代码驱动骨骼的走、跑、抬手、踉跄、倒地）
scripts/sfx.gd         音效（有文件用文件，没有就合成）
scripts/cloud.gd       开局从云盘下载、加载素材包
scripts/fp_arms.gd     第一人称手臂和手持武器
scripts/hud.gd         界面和触屏操作
scripts/music.gd       音乐切换
scripts/config.gd      数值
tools/fetch_assets.py  从云盘同步素材
tools/build_poi.gd     把游戏的楼（远景网格）转成 Godot 网格
tools/cloud_pack.py    编译时把大素材打包传云盘
```
