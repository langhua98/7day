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
## 冲刺：摇杆推到底再往外拖（或电脑上按 Shift）
const SPRINT_MULT := 1.7
const MAX_STAMINA := 100.0
## 冲刺每秒耗体力、不冲刺时每秒回体力；跳一下、挥一下近战各耗多少
const SPRINT_DRAIN := 16.0
const STAMINA_REGEN := 14.0
const JUMP_COST := 10.0
const MELEE_STAMINA := 7.0
## 跳多高（米）。路障、垃圾桶这类矮东西能跳上去、跳过去，僵尸不行
const JUMP_HEIGHT := 1.15
const GRAVITY := 22.0
## 低于这个高度的杂物能站上去
const STEP_MAX := 1.3
const PLAYER_EYE_HEIGHT := 1.65
const LOOK_SENSITIVITY := 0.0045
const MAX_HP := 100.0
const MAX_FOOD := 100.0
## 每真实秒消耗的饱食度
const FOOD_DRAIN := 0.12
## 饱食度为 0 时每秒掉血
const STARVE_DAMAGE := 1.0
## 口渴：每真实秒消耗多少，喝空了每秒掉血
const MAX_WATER := 100.0
const WATER_DRAIN := 0.16
const THIRST_DAMAGE := 1.5
## 吃饱喝足时每秒回血
const HP_REGEN := 0.4
## 被僵尸抓到：流血的概率、流多久、每秒掉血（用任何药品止血）
const BLEED_CHANCE := 0.25
const BLEED_TIME := 25.0
const BLEED_DAMAGE := 0.6
## 感染：被抓到的概率（每过一天 +1%），每秒加重多少，到 100% 后每秒掉血。抗生素、急救包、蜂蜜能治
const INFECT_CHANCE := 0.04
const INFECTION_RATE := 0.12
const INFECTION_DAMAGE := 1.0

const FIST_DAMAGE := 8.0
const MELEE_RANGE := 2.4
const MELEE_COOLDOWN := 0.55
const GUN_RANGE := 45.0
const GUN_DAMAGE := 34.0
const GUN_COOLDOWN := 0.45
## 爆头伤害倍数；头部判定是模型顶上多少米
const HEADSHOT_MULT := 2.5
const HEAD_SIZE := 0.32
## 手机上准星有一点吸附：子弹判定把僵尸当成多粗的圆柱（米）
const AIM_RADIUS := 0.42
## 开枪往上跳多少（弧度）
const GUN_RECOIL := 0.018
## 开枪声音能惊动多远的僵尸；冲刺脚步声；近战
const NOISE_GUN := 45.0
const NOISE_SPRINT := 10.0
const NOISE_MELEE := 7.0

## 枪：按物品名里的关键字匹配（从上往下，先匹配到的算）。
## cal 口径、mag 弹匣、rate 两枪间隔（秒）、dmg 伤害（霰弹是每颗弹丸）、reload 换弹秒数、
## auto 按住连发、pellets 弹丸数、spread 散布（弧度）、range 射程
const GUNS := [
	["crossbow", {"cal": "bolt", "mag": 1, "rate": 0.3, "dmg": 80.0, "reload": 1.8, "range": 50.0}],
	["bow", {"cal": "arrow", "mag": 1, "rate": 0.3, "dmg": 55.0, "reload": 0.9, "range": 40.0}],
	["rocket", {"cal": "rocket", "mag": 1, "rate": 0.5, "dmg": 260.0, "reload": 3.2, "range": 60.0, "splash": 4.5}],
	["pipeshotgun", {"cal": "shell", "mag": 1, "rate": 0.4, "dmg": 13.0, "reload": 1.6, "pellets": 8, "spread": 0.07, "range": 22.0}],
	["doublebarrel", {"cal": "shell", "mag": 2, "rate": 0.3, "dmg": 15.0, "reload": 2.2, "pellets": 8, "spread": 0.065, "range": 24.0}],
	["autoshotgun", {"cal": "shell", "mag": 10, "rate": 0.28, "dmg": 14.0, "reload": 3.0, "pellets": 8, "spread": 0.06, "range": 24.0, "auto": true}],
	["shotgun", {"cal": "shell", "mag": 8, "rate": 0.75, "dmg": 15.0, "reload": 3.0, "pellets": 8, "spread": 0.06, "range": 25.0}],
	["m60", {"cal": "762", "mag": 60, "rate": 0.09, "dmg": 36.0, "reload": 4.0, "auto": true, "spread": 0.02}],
	["pipemachinegun", {"cal": "762", "mag": 18, "rate": 0.14, "dmg": 28.0, "reload": 2.8, "auto": true, "spread": 0.025}],
	["ak47", {"cal": "762", "mag": 30, "rate": 0.11, "dmg": 34.0, "reload": 2.5, "auto": true, "spread": 0.018}],
	["tactical", {"cal": "762", "mag": 30, "rate": 0.1, "dmg": 36.0, "reload": 2.4, "auto": true, "spread": 0.014}],
	["sniper", {"cal": "762", "mag": 10, "rate": 0.6, "dmg": 95.0, "reload": 2.8, "range": 90.0}],
	["lever", {"cal": "762", "mag": 7, "rate": 0.5, "dmg": 72.0, "reload": 2.8, "range": 70.0}],
	["piperifle", {"cal": "762", "mag": 1, "rate": 0.5, "dmg": 70.0, "reload": 2.0, "range": 60.0}],
	["rifle", {"cal": "762", "mag": 1, "rate": 0.5, "dmg": 80.0, "reload": 2.0, "range": 70.0}],
	["smg", {"cal": "9mm", "mag": 30, "rate": 0.075, "dmg": 22.0, "reload": 2.0, "auto": true, "spread": 0.025}],
	["magnum", {"cal": "44", "mag": 6, "rate": 0.4, "dmg": 62.0, "reload": 2.4}],
	["vulture", {"cal": "44", "mag": 7, "rate": 0.3, "dmg": 58.0, "reload": 2.0}],
	["pipepistol", {"cal": "9mm", "mag": 6, "rate": 0.3, "dmg": 24.0, "reload": 1.8}],
	["pistol", {"cal": "9mm", "mag": 15, "rate": 0.22, "dmg": 30.0, "reload": 1.6}],
	["", {"cal": "9mm", "mag": 12, "rate": 0.3, "dmg": 30.0, "reload": 1.8}],
]
## 弹药物品（ammo 开头）按名字里的关键字认口径；捡一盒给多少发
const AMMO := [
	["crossbow", "bolt", 5], ["bolt", "bolt", 5], ["arrow", "arrow", 6], ["rocket", "rocket", 1],
	["shotgun", "shell", 8], ["shell", "shell", 8], ["44", "44", 8], ["762", "762", 15], ["9mm", "9mm", 18],
]
const CALIBER_NAMES := {"9mm": "9mm 子弹", "44": ".44 子弹", "762": "7.62 子弹", "shell": "霰弹", "arrow": "箭", "bolt": "弩箭", "rocket": "火箭弹"}

const ZOMBIE_HEIGHT := 1.85
const ZOMBIE_BASE_HP := 60.0
const ZOMBIE_HP_PER_DAY := 12.0
const ZOMBIE_DAMAGE := 9.0
const ZOMBIE_REACH := 1.5
const ZOMBIE_ATTACK_COOLDOWN := 1.2
## 抬手到砍下来要多久（这段时间退开就躲过去了）
const ZOMBIE_WINDUP := 0.42
## 白天僵尸在附近闲逛，多近会发现你（看得见时更远）
const ZOMBIE_NOTICE := 9.0
const ZOMBIE_SIGHT := 22.0
## 尸体躺多久
const CORPSE_TIME := 9.0
## 被打中后退多远（米/秒的冲量）、伤害多大会踉跄
const KNOCKBACK := 2.6
const STAGGER_DAMAGE := 28.0

## 8 种僵尸：按模型文件名里的关键字匹配。hp、speed 是倍数，dmg 是每下伤害，
## armor 身体减伤（爆头无视），weight 出现的权重，special 特殊能力
const ZOMBIE_TYPES := [
	["soldier", {"name": "士兵", "hp": 1.6, "speed": 1.0, "dmg": 12.0, "armor": 0.3, "weight": 0.8}],
	["nurse", {"name": "护士", "hp": 0.9, "speed": 1.15, "dmg": 8.0, "weight": 1.0}],
	["cop", {"name": "胖警察", "hp": 2.1, "speed": 0.85, "dmg": 14.0, "weight": 0.6, "special": "spit"}],
	["biker", {"name": "飞车党", "hp": 1.6, "speed": 1.0, "dmg": 13.0, "armor": 0.15, "weight": 0.8}],
	["lumberjack", {"name": "伐木工", "hp": 2.5, "speed": 0.9, "dmg": 17.0, "weight": 0.5, "cooldown": 1.6}],
	["joe", {"name": "乔", "hp": 1.0, "speed": 1.0, "dmg": 9.0, "weight": 1.2}],
	["arlene", {"name": "阿琳", "hp": 0.85, "speed": 1.05, "dmg": 8.0, "weight": 1.2}],
	["screamer", {"name": "尖叫者", "hp": 0.8, "speed": 1.15, "dmg": 7.0, "weight": 0.35, "special": "scream"}],
	["", {"name": "僵尸", "hp": 1.0, "speed": 1.0, "dmg": 9.0, "weight": 1.0}],
]
## 胖警察吐酸：多远开始吐、间隔、伤害
const SPIT_RANGE := Vector2(4.0, 16.0)
const SPIT_COOLDOWN := 7.0
const SPIT_DAMAGE := 14.0
const SPIT_SPEED := 13.0
## 尖叫者：看到你就叫，叫来几只、间隔多久
const SCREAM_RANGE := 28.0
const SCREAM_SPAWN := 3
const SCREAM_COOLDOWN := 45.0
const ZOMBIE_WALK_SPEED := 1.1
## 夜里僵尸会跑
const ZOMBIE_NIGHT_SPEED := 2.9
const ZOMBIE_HORDE_SPEED := 3.3
const ZOMBIE_MAX := 28
## 寻路：以玩家为中心多大范围（米）算绕楼的路；多久重算一次
const NAV_RADIUS := 48
const NAV_INTERVAL := 0.6
## 僵尸模型正面朝 +Z；如果倒着走过来，把它改成 PI
const ZOMBIE_FACING_OFFSET := 0.0
const ZOMBIE_DROP_CHANCE := 0.35

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

