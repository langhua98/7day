class_name GameConfig
## 游戏数值都集中在这里，想调难度改这个文件就行。

## 一整天（24 小时）对应的真实分钟数（官方默认 60，手机 24）
const DAY_LENGTH_MIN := 24.0
## 测试模式：一天 3 分钟
const TEST_FAST_TIME := false
const FAST_DAY_SECONDS := 180.0
## 开局时间（小时）
const START_HOUR := 7.0
## 日出、日落（小时，只影响太阳和天色）
const SUNRISE := 5.5
const SUNSET := 20.5
## 白天 / 夜晚：04:00–22:00
const DAWN_HOUR := 4.0
const DUSK_HOUR := 22.0
## 每 7 天一次血月，夜里 22:00 到次日 04:00
const BLOOD_MOON_EVERY := 7
## 手机版血月：官方总数乘 0.5，同时存活上限 8 + 2 × 第几次血月（最多 16）
const HORDE_COUNT_MULT := 0.5
const HORDE_MAX_ALIVE := 16

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
## 起跳速度 5.2 大约能跳 1.1 米高，刚好跳上一块方块
const JUMP_SPEED := 5.2
const PLAYER_EYE_HEIGHT := 1.65
const LOOK_SENSITIVITY := 0.0045
## 第一人称手感：基础视野、冲刺拉宽、开镜 FOV、后坐力回弹、落地压头
const BASE_FOV := 70.0
const SPRINT_FOV_BONUS := 7.0
const AIM_FOV := 55.0
const AIM_SENSITIVITY := 0.6
const RECOIL_RECOVERY := 12.0
const RECOIL_AIM_SHARE := 0.16
const LAND_DIP_MAX := 0.06
## 测试模式：背包里就有全部武器、吃的喝的、药、建造方块，每种子弹 300 发，不用去捡（读档时也会补齐）。正式玩时改成 false
const TEST_ALL_ITEMS := true
const TEST_AMMO := 300
## 测试模式：子弹和建造方块用不完（换弹不扣背包里的子弹，摆方块不扣数量）。正式玩时改成 false
const TEST_INFINITE := true
## 测试模式：每种建造方块给多少块
const TEST_BLOCKS := 999
## 正式模式开局给多少发手枪/步枪子弹
const STARTER_AMMO := 120
## 建造：离多远能摆 / 拆方块（米），两次摆方块的间隔（秒）
const BUILD_REACH := 5.0
const BUILD_COOLDOWN := 0.22
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


# —— 僵尸 AI（6a）：感官、噪音、热量、蹲伏、AI 预算 ——
## 视野：前方扇形角度，白天/夜里看多远（米）；蹲下时视距乘这个
const ZOMBIE_SIGHT_FOV := 120.0
const ZOMBIE_SIGHT_DAY := 25.0
const ZOMBIE_SIGHT_NIGHT := 15.0
const ZOMBIE_SIGHT_CROUCH_MULT := 0.5
## 贴身（米）时不看朝向也能察觉
const ZOMBIE_SENSE_TOUCH := 1.6
## 追击丢失目标几秒后转为调查；调查点停留几秒后回到游荡
const ZOMBIE_LOSE_TARGET := 8.0
const ZOMBIE_INVESTIGATE_LINGER := 10.0
## 游荡：走多远、速度是基础步速的倍数
const ZOMBIE_WANDER_RADIUS := 8.0
const ZOMBIE_WANDER_SPEED_MULT := 0.5
## 噪音半径（米），GameState.noise(pos, radius, kind) 的 kind
const NOISE := {
	"pistol": 45.0, "rifle": 60.0, "shotgun": 50.0, "explosion": 80.0,
	"melee_hit": 6.0, "sprint": 8.0, "walk": 4.0, "crouch": 1.5, "block_break": 15.0,
}
## 热量：按 32 米分格累计，到 100 刷尖叫者；每游戏小时衰减 30%
const HEAT_CELL := 32.0
const HEAT_SCREAMER := 100.0
const HEAT_DECAY_PER_HOUR := 0.3
const HEAT := {"shot": 1.0, "craft_per_sec": 0.2, "campfire_per_sec": 0.5}
## 测试：热量倍率（调大可以很快看到尖叫者）
const TEST_HEAT_MULT := 1.0
## 蹲伏：视角降低多少米、移速倍率
const CROUCH_DROP := 0.6
const CROUCH_SPEED_MULT := 0.5
## AI 预算：每帧最多更新几只的感知；多远开始骨骼隔帧、多远停骨骼
const AI_SENSE_PER_FRAME := 6
const ZOMBIE_ANIM_HALF_DIST := 30.0
const ZOMBIE_ANIM_OFF_DIST := 50.0
