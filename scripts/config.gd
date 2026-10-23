class_name GameConfig
## 游戏数值都集中在这里，想调难度改这个文件就行。

## 一整天（24 小时）对应的真实秒数
const DAY_SECONDS := 300.0
## 开局时间（小时）
const START_HOUR := 7.0
## 日出、日落（小时）
const SUNRISE := 5.5
const SUNSET := 20.5
## 夜晚：22:00 到 06:00
const NIGHT_START := 22.0
const NIGHT_END := 6.0
## 第几天夜里是血月尸潮，撑到第二天早上就赢
const HORDE_DAY := 7

## 夜里的亮度：月光强度、环境光颜色和强度。嫌夜里太黑就调大
const MOON_LIGHT := 0.55
const NIGHT_AMBIENT := Color(0.42, 0.48, 0.66)
const NIGHT_AMBIENT_ENERGY := 0.75

## 僵尸离玩家超过这个距离（米）就回收，在附近重新刷
const ZOMBIE_DESPAWN := 110.0

const PLAYER_SPEED := 4.2
## 跑步：速度倍数、每秒耗体力、每秒回体力
const SPRINT_MULT := 1.6
const SPRINT_DRAIN := 18.0
const STAMINA_REGEN := 12.0
## 跳跃：重力（米/秒²）和起跳速度
const GRAVITY := 12.0
const JUMP_SPEED := 4.5
const PLAYER_EYE_HEIGHT := 1.65
const LOOK_SENSITIVITY := 0.0045
## 测试模式：开局背包里就有全部武器、吃的喝的、药，每种子弹 300 发，不用去捡。正式玩时改成 false
const TEST_ALL_ITEMS := true
const TEST_AMMO := 300
## 测试模式：僵尸照常出现、追人，但不会抬手打主角。正式玩时改成 false
const TEST_ZOMBIES_NO_ATTACK := true

const MAX_HP := 100.0
const MAX_FOOD := 100.0
## 每真实秒消耗的饱食度
const FOOD_DRAIN := 0.12
## 饱食度为 0 时每秒掉血
const STARVE_DAMAGE := 1.0
const MAX_WATER := 100.0
## 每真实秒消耗的水分（比饿得快）
const WATER_DRAIN := 0.17
## 水分为 0 时每秒掉血
const THIRST_DAMAGE := 1.4
## 被僵尸打中后开始流血的几率、流血每秒掉血、流血多久自己止住（秒）
const BLEED_CHANCE := 0.3
const BLEED_DAMAGE := 0.7
const BLEED_TIME := 40.0
## 腹泻持续秒数，期间水分掉得快几倍
const SICK_TIME := 75.0
const SICK_WATER_MULT := 3.5
## 咖啡因：体力恢复倍数
const BUFF_STAMINA_MULT := 2.2

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
## 僵尸出手到打中要多久（秒），这段时间里躲开就不掉血
const ZOMBIE_WINDUP := 0.45
## 被打中后硬直多久（秒），爆头更久
const ZOMBIE_STAGGER := 0.25
const ZOMBIE_HEADSHOT_STAGGER := 0.6
## 爆头伤害倍数
const HEADSHOT_MULT := 2.2

## 8 种僵尸（按模型文件名 zombie_<名字>），血量、速度、伤害是基础值的倍数
const ZOMBIE_TYPES := {
	"soldier": {"name": "士兵僵尸", "hp": 1.5, "speed": 0.9, "damage": 1.2},
	"cop": {"name": "胖警察", "hp": 1.9, "speed": 0.8, "damage": 1.3},
	"nurse": {"name": "护士僵尸", "hp": 0.8, "speed": 1.15, "damage": 0.9},
	"biker": {"name": "飞车党僵尸", "hp": 1.3, "speed": 1.0, "damage": 1.3},
	"lumberjack": {"name": "伐木工僵尸", "hp": 1.7, "speed": 0.9, "damage": 1.5},
	"joe": {"name": "乔", "hp": 1.0, "speed": 1.0, "damage": 1.0},
	"arlene": {"name": "阿琳", "hp": 0.9, "speed": 1.1, "damage": 0.9},
	"screamer": {"name": "尖叫者", "hp": 0.7, "speed": 1.2, "damage": 0.8, "screams": true},
}

## 地上零散物品的数量（主要的东西要翻容器找）
const LOOT_COUNT := 24
const LOOT_SIZE := 0.55
## 离物品多近能拾取
const PICKUP_RADIUS := 2.0
## 翻一次容器要几秒（车要久一点）
const SEARCH_TIME := 1.6
const SEARCH_TIME_CAR := 2.6
## 翻容器掉几件东西，翻到空的概率
const SEARCH_MIN := 1
const SEARCH_MAX := 3
const SEARCH_EMPTY_CHANCE := 0.15

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
const FP_ARMS_TEXTURES := ["fp_arms_skin.png", "HD_Hands_Male.png"]

## 贴图 alpha 当成镂空（头发、树叶）。如果模型出现奇怪的洞，改成 false
const ALPHA_CUTOUT := false

