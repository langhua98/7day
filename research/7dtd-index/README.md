# 七日杀（7 Days to Die）素材对应表

研究参考用的**索引**。这里只有名字、编号、资源包路径和云盘路径，**不包含任何游戏文件**（图片、模型、音频、动画、XML 原文都不放进仓库，版权归 The Fun Pimps）。素材本体都在小桔云盘 `/7day/` 下。

数据来源：客户端 buildid 25661859、服务器版 buildid 25661908，2026-10-22 提取。

## 怎么查

| 想找 | 看哪个表 | 关键列 |
|---|---|---|
| 某个物品/方块的模型、图标在哪 | `items.csv` | `item_id`、`name_zh`、`model_bundle`、`drive_zip` |
| 玩家装备、发型、脸、僵尸 | `characters.csv` | `bundle`、`drive_zip`、`animation_drive_zip` |
| 护甲套装对应哪套穿戴模型 | `armor_sets.csv` | `armor_set`、`bundle` |
| 建筑（POI）的分区、难度、尺寸 | `pois.csv` | `poi_file`、`zoning`、`difficulty_tier` |
| 每个资源包里有什么、导出了没有 | `bundles.csv` | `mesh_count`、`texture_count`、`drive_status` |
| 音乐、图标包、样例、预览页 | `drive_other.csv` | `drive_path` |

在 GitHub 网页上打开 CSV 可以直接搜索。本地可以用 Excel 打开（UTF-8 编码）。

## 云盘位置规则

- 每个资源包导出成一个 zip：`/7day/<文件夹>/<资源包路径去掉 .bundle>.zip`，例如
  `player_assets_entities/player/male/gear/biker.bundle` → `/7day/小橘素材库/player_assets_entities/player/male/gear/biker.zip`。
  全部放在 `小橘素材库/`；`drive_zip` 列写的是按云盘实际目录找到的位置，以它为准。
  zip 里有 `textures/`（贴图）、`meshes/`（模型）、`audio/`、`animations/`、`rigged/`（带骨骼的模型）和 `stats.json`。
- 所有物品图标打包在 `/7day/物品图标/item_icons_5188.zip`，文件名就是 `icon` 列。
- 僵尸动画都在 `animations_assets_animations/zombie.zip` 一个包里。
- `drive_status`：`uploaded` 表示云盘上已有；`empty` 表示这个资源包没有可导出的内容（只有着色器、混音器、配置等），所以没有 zip。2026-10-22 16:39 UTC 核对：283 个已上传，4 个为空。
- 方块贴图图集 `blocktextureatlases_assets_all.zip`：`ta_opaque_0`（颜色）、`ta_opaque_n_0`（法线）、`ta_opaque_s_0`（高光）三个文件夹，各 407 张 512px PNG，文件名 `<图集>_<序号 000-406>`。
- 地形贴图：`terraintextures_assets_all.zip` 是 83 张普通贴图；另有 `terraintextures_arrays.zip`（`bundles.csv` 的 `extra_drive_zip` 列），含 MicroSplat 的颜色、法线、光滑度/AO 三组各 24 张 2048px PNG。
- 建筑 POI 原始文件在 `/7day/建筑POI/`：`POIs_all_1575.zip`（全部）、`POIs_downtown_67.zip`（市中心），`pois.csv` 的 `drive_zip` 列指向全部包。
- 刻意没导出的类型：Shader、Font、Cubemap（天空盒、反射探针）、TextAsset。

## 各列说明

**items.csv**（6025 行，物品 + 方块图标）
- `item_id` 游戏内部名；`name_zh` / `name_en` 中英文名（来自游戏本地化，部分为空）
- `icon` 图标文件名；`icon_tint` 图标染色（十六进制，空表示不染色）
- `mesh_path` items.xml 里的 Meshfile（已处理 Extends 继承，`@:` 开头是 Addressables 路径）
- `preview_model` 预览页里的模型名；`gear_<套装>_<来源>` 表示整套穿戴装备
- `model_bundle` 模型所在资源包；`drive_zip` 对应云盘 zip；`drive_icon_zip` 图标包

**characters.csv**：`kind` 为 `female_player_gear`、`zombie`、`player_male_gear`、`player_female_hair` 等；`mesh_count` / `texture_count` 是包内模型和贴图数量。

**armor_sets.csv**：`source` 为 `male`（男玩家装备包）、`dlc`/`dlc2`（DLC 外观包）、`tw`/`twout`/`twhat`（推广掉落包）。

**pois.csv**：建筑来自服务器版 `Data/Prefabs`，不在客户端资源包里；游戏没有中文名。`prefab_size_xyz` 为“长, 高, 宽”。

## 原始数据和重新生成

`raw/` 是提取线程导出的原始映射（JSON/JSONL/TSV），CSV 都由它生成：

```
python3 tools/build_7dtd_index.py
```

`raw/drive_paths.tsv` 是云盘 `/7day/` 的文件清单（路径<TAB>字节数）。上传有变化时，重新列一次 `/7day/` 覆盖它，再跑脚本即可更新 `drive_zip` 和 `drive_status`。

- `cab_to_bundle.json`：CAB 名 → 资源包路径（相对 `Data/Addressables/Standalone/`），用于查跨包依赖
- `bundle_inventory.jsonl`：每个资源包的 Unity 类型统计、贴图名和尺寸、模型名和顶点数

## 名字不一致的护甲套装

| 套装 | 资源包名 |
|---|---|
| Athletic | fitness |
| Primitive | fiber |
| Rogue | stealth |
| KegBreaker（DLC） | oktoberfestcosmetic |

女装同名规则一样（`player/female/gear/` 下的 fitness、fiber、stealth）。

## 已知缺口

- 物品没有单独的动画对应；物品动画在玩家动画控制器里，尚未拆出。
