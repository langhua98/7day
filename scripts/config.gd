class_name GameConfig
## 游戏数值都集中在这里，想调难度改这个文件就行。

## 一整天（24 小时）对应的真实秒数
const DAY_SECONDS := 300.0
## 开局时间（小时）
const START_HOUR := 8.0
## 夜晚：22:00 到 06:00
const NIGHT_START := 22.0
const NIGHT_END := 6.0
## 第几天夜里是血月尸潮，撑到第二天早上就赢
const HORDE_DAY := 7

## 地图半径（米）
const WORLD_RADIUS := 90.0

const PLAYER_SPEED := 4.2
const PLAYER_EYE_HEIGHT := 1.65
const LOOK_SENSITIVITY := 0.0045
const MAX_HP := 100.0
const MAX_FOOD := 100.0
## 每真实秒消耗的饱食度
const FOOD_DRAIN := 0.12
## 饱食度为 0 时每秒掉血
const STARVE_DAMAGE := 1.0

const FIST_DAMAGE := 8.0
const MELEE_RANGE := 2.3
const MELEE_COOLDOWN := 0.55
const GUN_RANGE := 30.0
const GUN_DAMAGE := 34.0
const GUN_COOLDOWN := 0.45

const ZOMBIE_HEIGHT := 1.85
const ZOMBIE_BASE_HP := 60.0
const ZOMBIE_HP_PER_DAY := 12.0
const ZOMBIE_DAMAGE := 9.0
const ZOMBIE_REACH := 1.5
const ZOMBIE_ATTACK_COOLDOWN := 1.2
const ZOMBIE_WALK_SPEED := 1.1
## 夜里僵尸会跑
const ZOMBIE_NIGHT_SPEED := 2.9
const ZOMBIE_HORDE_SPEED := 3.3
const ZOMBIE_MAX := 28
## 僵尸模型正面朝 +Z；如果倒着走过来，把它改成 PI
const ZOMBIE_FACING_OFFSET := 0.0
const ZOMBIE_DROP_CHANCE := 0.35

const LOOT_COUNT := 45
const LOOT_SIZE := 0.55
const PICKUP_RADIUS := 1.7

## 音乐判定距离
const COMBAT_DISTANCE := 11.0
const TENSION_DISTANCE := 26.0
const MUSIC_FADE := 2.5
const MUSIC_VOLUME_DB := -6.0

## 手上武器模型的长度（米）
const HELD_SIZE := 0.7
## 第一人称手臂模型（assets/models/ 里的文件名，不含扩展名）
const FP_ARMS_MODEL := "FP_ARM_M"
## 手臂模型没带贴图时，依次尝试 assets/textures/ 里这些贴图
const FP_ARMS_TEXTURES := ["playerMale_Hand.png", "HD_Hands_Male.png"]

## 贴图 alpha 当成镂空（头发、树叶）。如果模型出现奇怪的洞，改成 false
const ALPHA_CUTOUT := false

## 地面贴图（assets/textures/ 里按顺序找第一个存在的）
const GROUND_TEXTURES := ["desert_debris.png", "rubble.png"]
## 地面贴图每块多少米
const GROUND_TILE := 6.0
## 场景摆设（assets/props/ 里的车辆、家具）数量
const PROP_COUNT := 26
