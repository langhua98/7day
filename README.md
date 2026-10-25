# 七日杀 · 口袋版

个人自用的 iPhone 小游戏，用开源引擎 [Godot 4.7](https://godotengine.org) 写成，素材全部来自自己《七日杀》客户端导出的模型、贴图、图标和音乐。**素材只放在本地 `assets/`，不进仓库，游戏不分享、不发布。**

## 玩法

- 第一人称。左半屏拖动移动，右半屏拖动转视角，按住「攻击」挥武器。
- 背包 45 格，每格按官方叠加上限堆叠；超过 45 格每多 1 格慢 10%（最多 50%），超重不能冲刺。点「背包」里的格子可以使用/装备或丢弃；右上「整理」会合并同类、去掉测试模式的重复物品并排序。
- 翻完容器会打开容器面板：点一下在容器和背包之间转移，「全部拿走」一键收，离开 2 米自动关，没拿完的东西会留在容器里。背包里的「可写木箱（储物箱）」可以像方块一样摆下，32 格，存档会保存。
- 走近地上的物品自动捡起。捡到更好的武器会自动换上；食物、饮料、药品在底部快捷栏或「背包」里点一下使用。
- **现在是测试模式**：背包里就有全部武器、吃的、喝的、药、建造方块和工作站，每种子弹 300 发，读旧存档也会补齐；子弹和方块用不完。点「背包」随便换着试，点子弹会换上用这种子弹的枪。正式玩时把 `scripts/config.gd` 里的 `TEST_ALL_ITEMS` 和 `TEST_INFINITE` 改成 `false`。
- 合成：点右上「合成」。配方全部来自官方 recipes.xml（`tools/build_data.py` 生成 `assets/data/recipes.json`），时间和材料都是官方的一半；队列最多 4 项，关掉面板也继续做，存档会记住。
- 工作站：篝火、工作台、锻造炉、化学台、水泥搅拌机可以像方块一样摆下。走到 3 米内，右下会出现「使用」，点开只看这个工作站的配方；每个工作站独立排队，离开也继续。篝火要放木头当燃料，锅或烤架放进工具格才能煮东西；拆掉工作站就不能再用。
- 建造：在背包里点一种方块（木框、木块、圆石、石板、混凝土、钢）拿在手上，准星对着地面或别的方块，会出现一个白框，点「攻击」就摆一块 1 米的方块。测试模式背包里每种方块有整块、半块、斜坡、楼梯、柱、板六个独立物品；拿在手上可用「旋转」转 90°。空手或拿近战武器打方块能拆掉。方块能挡僵尸，也能跳上去往高处搭。
- 一天 24 分钟。白天 04:00–22:00，夜里僵尸会跑；每 7 天一次血月（22:00–04:00），活过之后游戏继续，无尽生存。
- 音乐跟着局势切换：探索 Exp、紧张 Sus、战斗 Cbt、血月 Bld。

数值（一天多长、僵尸血量、伤害等）都在 `scripts/config.gd`，第一人称手臂的摆放在 `scripts/fp_arms.gd` 顶部。

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

物品表里的模型名是 prefab 名（如 `chainsawPrefab`），导出的文件名是网格名（如 `Chainsaw_LOD0.glb`），游戏会去掉 `Prefab`、`_LOD0`、`Mesh` 后再比对。

### 从小桔云盘同步素材

```bash
export XIAOJU_TOKEN=你的令牌      # 只放环境变量，别写进任何文件
python3 tools/fetch_assets.py      # 默认 8 种僵尸、每类 6 段音乐
python3 tools/fetch_assets.py --zombies all --music 12   # 想要更多
```

脚本只用 Python 自带库，会把云盘 `/7day` 下的图标包、僵尸包、样例模型、音乐整理成上面的结构；已经下载过的会跳过。

> 目前云盘上还没有物品模型所在的 `items` 资源包（约 540MB），所以大部分物品在地上和手里显示的是它的图标；样例里有模型的（电锯、电击棒、复合弓）会用 3D 模型。以后把导出的物品 `.glb` 放进 `assets/models/` 就会自动用上。

## 装到 iPhone 上

需要一台 Mac。

1. 安装 [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/)（标准版，不是 .NET 版）和 Xcode。
2. 按上一节把素材同步到 `assets/`。
3. 用 Godot 打开本项目（第一次会导入素材，几分钟）。可以先按 F5 在电脑上试玩：WASD 移动、方向键看、空格攻击，鼠标点拖模拟触屏。
4. 菜单「编辑器 → 管理导出模板」，下载 4.7.2 的导出模板。
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
scenes/boot.tscn       开局载入页
scenes/main.tscn       主场景
scripts/asset_db.gd    读取素材、物品分类（自动加载为 Assets）
scripts/data.gd        读取官方配置 JSON（自动加载为 Data）
scripts/game_state.gd  全局信号和共享状态（自动加载为 GameState）
scripts/main.gd        组装世界和系统，连接信号
scripts/time_of_day.gd 昼夜推进、无尽时间和血月周期
scripts/horde.gd       血月刷怪阶段、总数和同时上限
scripts/weapons.gd     枪械弹匣/射速/换弹，官方 items.xml 优先
scripts/player.gd      移动、视角、体力、生存数值
scripts/status_effects.gd 状态效果（自动加载为 Status）：饥饿、口渴、流血、腹泻、咖啡因，按游戏小时
scripts/inventory.gd   背包、装备、弹匣
scripts/combat.gd      近战、枪械、换弹、爆炸、摆放/拆方块
scripts/spawner.gd     僵尸刷新、回收、击杀
scripts/looting.gd     地上物品、翻容器
scripts/crafting.gd    合成：配方（assets/data/recipes.json）、材料、队列、工作站判定
scripts/ui/craft_panel.gd 合成面板（HUD「合成」按钮）
scripts/atmosphere.gd  天空、太阳、环境光、音乐、血月横幅
scripts/save_game.gd   存档和读档
scripts/zombie.gd      僵尸（代码驱动骨骼走路）
scripts/fp_arms.gd     第一人称手臂和手持武器
scripts/blocks.gd      建造方块（种类、耐久、贴图）
scripts/hud.gd         界面和触屏操作
scripts/music.gd       音乐切换
scripts/attachments.gd 可拆装倍镜
scripts/boot.gd        载入页
scripts/config.gd      数值
tools/fetch_assets.py  从云盘同步素材
tools/build_data.py    官方 Data_Config.zip → assets/data/*.json
```
