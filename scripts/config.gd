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
## 僵尸砸玩家方块的伤害倍率
const ZOMBIE_BLOCK_DAMAGE_MULT := 3.0
## 6b 寻路：估算僵尸每秒能打掉多少方块血；拆墙路线的成本权重
const ZOMBIE_FLOW_DPS := 10.0
const BLOCK_PATH_WEIGHT := 0.5
## 官方方块血量在手机上按这个倍率缩放（官方 MaxDamage 100~10000，原样太耐打）
const BLOCK_HP_SCALE := 0.2

const PLAYER_SPEED := 4.2
## 跑步：速度倍数、每秒耗体力、每秒回体力
const SPRINT_MULT := 1.6
const SPRINT_DRAIN := 18.0
const STAMINA_REGEN := 12.0
## 跳跃：重力（米/秒²）和起跳速度
const GRAVITY := 12.0
## 起跳速度 5.2 大约能跳 1.1 米高，刚好跳上一块方块
const JUMP_SPEED := 5.2
## 爬梯子速度（米/秒）
const LADDER_SPEED := 2.4
## 开关门：够得着的距离（米）
const DOOR_REACH := 1.8
const STATION_REACH := 3.0   # 离工作站多近才能用它的配方
const CAMPFIRE_FUEL := "resourceWood"
const COOK_TOOLS := ["toolCookingPot", "toolCookingGrill"]
const PLAYER_EYE_HEIGHT := 1.65
const LOOK_SENSITIVITY := 0.0045
## 第一人称手感：基础视野、冲刺拉宽、开镜 FOV、后坐力回弹、落地压头
const BASE_FOV := 70.0
const SPRINT_FOV_BONUS := 7.0
const AIM_FOV := 55.0
const AIM_SENSITIVITY := 0.6
## 倍镜 FOV：数值越小放得越大
const SCOPE_FOV_RIFLE := 34.0
const SCOPE_FOV_SNIPER := 22.0
## 开镜瞄准辅助：准星离僵尸头这个角度内，视角灵敏度乘这个（只减速，不吸附）
const AIM_ASSIST_ANGLE := 3.0
const AIM_ASSIST_MULT := 0.6
const AIM_ASSIST_RANGE := 50.0
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
const BLOCK_LIMIT := 4000
## 测试模式：僵尸照常出现、追人，但不会抬手打主角。正式玩时改成 false
const TEST_ZOMBIES_NO_ATTACK := true

const MAX_HP := 100.0
const MAX_FOOD := 100.0
const MAX_WATER := 100.0
## 生存数值都按「游戏小时」算，改 DAY_LENGTH_MIN 后节奏不变
## 每游戏小时掉多少饱食、水分；冲刺时再乘 SPRINT_HUNGER_MULT
const FOOD_PER_HOUR := 1.6
const WATER_PER_HOUR := 2.5
const SPRINT_HUNGER_MULT := 2.0
## 饱食 / 水分低于多少算饥饿 / 口渴
const HUNGRY_BELOW := 25.0
const THIRSTY_BELOW := 25.0
## 吃饱喝足（饱食 > 60、水 > 50、没有掉血的状态）时每游戏小时回血
const HP_REGEN_PER_HOUR := 24.0
const REGEN_FOOD_ABOVE := 60.0
const REGEN_WATER_ABOVE := 50.0
## 被僵尸打中后开始流血的几率
const BLEED_CHANCE := 0.3

## 受伤与感染（3b），高度单位米，时间单位游戏小时
## 摔落：超过 FALL_SAFE 米开始掉血，每多 1 米掉 FALL_DAMAGE_PER_M
const FALL_SAFE := 3.0
const FALL_DAMAGE_PER_M := 15.0
## 3–4 米 50% 扭伤；4 米以上必骨折
const SPRAIN_HEIGHT := 3.0
const SPRAIN_CHANCE := 0.5
const FRACTURE_HEIGHT := 4.0
const BIG_HIT_FRACTURE_CHANCE := 0.1
## 被僵尸打中感染几率；感染度从 1% 开始，每游戏小时涨多少，到 100% 死亡
const INFECTION_CHANCE := 0.1
const INFECTION_START := 1
const INFECTION_PER_HOUR := 1.0
const INFECTION_MAX := 100
## 药品降低的感染度（抗生素直接治好）
const HERBAL_ANTIBIOTICS_CURE := 25
const HONEY_INFECTION_CURE := 5

## 状态效果表：id → 定义。所有持续状态都走 scripts/status_effects.gd。
##   zh 中文名  short 图标牌上的字  desc 说明  buff 官方 buffs.xml 名（有就用官方中文名）
##   hours 默认持续游戏小时（0 = 一直有，直到移除）  stack 能否叠加（max_stack 上限）
##   hp / food / water：每游戏小时的增减（叠加时乘层数）  hp_sec：每真实秒（流血）
##   mult：倍率修正 {stat: 倍数}，例如 move_speed、stamina_regen、food_drain、water_drain
##   add：加值修正 {stat: 值}，例如 stamina_max
##   flags：禁止的动作，例如 no_sprint、no_jump（3b 骨折用）
##   bad：坏状态（红牌），否则绿牌
const STATUS := {
	"hungry": {"zh": "饥饿", "short": "饿", "buff": "buffStatusHungry01", "bad": true,
		"desc": "饱食低于 25，体力恢复减半。吃东西解除。", "mult": {"stamina_regen": 0.5}},
	"starving": {"zh": "饿肚子", "short": "饿死", "buff": "buffStatusHungry02", "bad": true,
		"desc": "饱食为 0，每游戏小时掉 6 血。吃东西解除。", "hp": -6.0},
	"thirsty": {"zh": "口渴", "short": "渴", "buff": "buffStatusThirsty01", "bad": true,
		"desc": "水分低于 25，体力上限 −25。喝东西解除。", "add": {"stamina_max": -25.0}},
	"dehydrated": {"zh": "脱水", "short": "脱水", "buff": "buffStatusThirsty02", "bad": true,
		"desc": "水分为 0，每游戏小时掉 10 血。喝东西解除。", "hp": -10.0},
	"bleeding": {"zh": "流血", "short": "血", "buff": "buffInjuryBleeding", "bad": true, "hours": 0.67,
		"desc": "每秒掉 0.7 血。用绷带或急救包止血。", "hp_sec": -0.7},
	"dysentery": {"zh": "腹泻", "short": "泻", "buff": "buffDysenteryMain", "bad": true, "hours": 1.25,
		"desc": "水分掉得快 3.5 倍。喝金棒茶或用急救包治好。", "mult": {"water_drain": 3.5}},
	"near_death_trauma": {"zh": "濒死创伤", "short": "创伤", "buff": "buffNearDeathTrauma", "bad": true, "hours": 24.0,
		"desc": "刚死过一次，体力上限 −20。一个游戏天后消失。", "add": {"stamina_max": -20.0}},
	"caffeine": {"zh": "咖啡因", "short": "咖", "buff": "buffCoffee", "hours": 1.5,
		"desc": "体力恢复 ×2.2。", "mult": {"stamina_regen": 2.2}},
	# 3b 受伤与感染
	"sprain": {"zh": "扭伤", "short": "扭", "buff": "buffLegSprained", "bad": true, "hours": 24.0,
		"desc": "移速 −25%，1 游戏天自己好。用夹板固定好得快。", "mult": {"move_speed": 0.75}},
	"sprain_splinted": {"zh": "扭伤（已固定）", "short": "固定", "buff": "buffLegSplinted", "bad": true, "hours": 6.0,
		"desc": "夹板固定了扭伤，移速 −10%，6 游戏小时后好。", "mult": {"move_speed": 0.9}},
	"fracture": {"zh": "骨折", "short": "骨折", "buff": "buffLegBroken", "bad": true,
		"desc": "移速 −50%，不能冲刺和跳。不会自己好，用夹板或石膏。",
		"mult": {"move_speed": 0.5}, "flags": ["no_sprint", "no_jump"]},
	"fracture_splinted": {"zh": "打夹板", "short": "夹板", "buff": "buffLegSplinted", "bad": true, "hours": 72.0,
		"desc": "骨折打了夹板，移速 −25%，不能冲刺，3 游戏天后好。打石膏只要 1 天。",
		"mult": {"move_speed": 0.75}, "flags": ["no_sprint"]},
	"fracture_cast": {"zh": "打石膏", "short": "石膏", "buff": "buffLegCast", "bad": true, "hours": 24.0,
		"desc": "骨折打了石膏，移速 −15%，1 游戏天后好。", "mult": {"move_speed": 0.85}},
	"infection": {"zh": "感染", "short": "感染", "buff": "buffInfectionMain", "bad": true, "unit": "%",
		"stack": true, "max_stack": 100,
		"desc": "感染度每游戏小时 +1%，到 100% 会死。草药抗生素 −25%，蜂蜜 −5%，抗生素治好。"},
}

## 死亡与重生（3c）
## true = 老规矩：死了就结算、删档；false = 黑屏后在睡袋（没有就在出生点）醒来
const PERMADEATH := false
## 死后黑屏几秒；醒来时血、饱食、水是满值的多少
const DEATH_BLACKOUT := 2.0
const RESPAWN_STATS := 0.5
## 每死一次存活天数减几天（官方 daysAliveChangeWhenKilled），游戏阶段跟着降
const DAYS_ALIVE_LOST_ON_DEATH := 2
## 睡袋（官方方块 bedroll），同时只能有一个
const BEDROLL_ID := "bedroll"

const FIST_DAMAGE := 8.0
const MELEE_RANGE := 2.3
const MELEE_COOLDOWN := 0.55
const GUN_RANGE := 30.0
const GUN_DAMAGE := 34.0
const GUN_COOLDOWN := 0.45

const ZOMBIE_HEIGHT := 1.85
const ZOMBIE_BASE_HP := 60.0
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

## 手机版僵尸整体倍率（数值来自 assets/data/zombies.json，官方值 × 这些）
const ZOMBIE_HP_SCALE := 0.35
const ZOMBIE_SPEED_SCALE := 0.8
const ZOMBIE_DAMAGE_SCALE := 0.9
## 野性 / 辐射变体：野性血 ×1.5、更快；辐射再 ×2 并且每秒回 2% 血
const ZOMBIE_FERAL_HP := 1.5
const ZOMBIE_FERAL_SPEED := 1.15
const ZOMBIE_RADIATED_HP := 2.0
const ZOMBIE_RADIATED_REGEN := 0.02
## GS 到多少开始出野性 / 辐射；野性几率 = (GS − 30) × 0.01，最多 40%
const ZOMBIE_GS_FERAL := 30
const ZOMBIE_GS_RADIATED := 60
const ZOMBIE_FERAL_CHANCE_PER_GS := 0.01
const ZOMBIE_FERAL_CHANCE := 0.4
const ZOMBIE_RADIATED_CHANCE := 0.15
## 官方血量 ≥ 这个值算大块头（打断腿、体型判定）
const ZOMBIE_BIG_HP := 400.0
const BIG_ZOMBIE_MODELS := ["lumberjack", "soldier", "biker", "cop", "bigmama", "demolition",
	"mutated", "wight", "frostclaw", "hawaiian", "burnt", "chuck", "thug"]

## 背包 45 格（官方）；超过后每多 1 格移速 −10%，最多 −50%，超重时不能冲刺
const BAG_SLOTS := 45
const BAG_OVERLOAD_SLOTS := 5
const OVERLOAD_PER_SLOT := 0.1
const OVERLOAD_MAX := 0.5
## 玩家储物箱 cntWoodWritableCrate 的格数；容器离开多远自动关面板（米）
const CRATE_SLOTS := 32
const CONTAINER_CLOSE_DIST := 2.0
## 路边容器面板最少几格
const CONTAINER_SLOTS := 9

## 合成：时间 = 官方 craft_time × 0.5，材料 = 官方 × 0.5（向上取整，至少 1），队列最多 4 项
const CRAFT_TIME_MULT := 0.5
const RECIPE_COST_MULT := 0.5
const CRAFT_QUEUE_MAX := 4
## 需要学习（tags 带 learnable）的配方先全开；第 7 步改成 false，靠读书解锁
const RECIPES_ALL_UNLOCKED := true
## 单独跑测试、没有当前场景时，当作所有工作站都在旁边
const TEST_STATIONS_NEAR := true

## 地上零散物品的数量（主要的东西要翻容器找）
const LOOT_COUNT := 8
const LOOT_SIZE := 0.55
## 离物品多近能拾取
const PICKUP_RADIUS := 2.0
## 翻一次容器要几秒（车要久一点）
const SEARCH_TIME := 1.5
const SEARCH_TIME_CAR := 3.0
## 翻容器掉几件东西，翻到空的概率（没有 loot.json 时的旧兜底）
const SEARCH_MIN := 1
const SEARCH_MAX := 3
const SEARCH_EMPTY_CHANCE := 0.15
## 容器翻空后多少游戏天重新刷
const LOOT_RESPAWN_DAYS := 5
## 保险箱：撬锁要几秒、每次断撬锁工具的几率、没有工具时砸开要多少伤害
const SEARCH_TIME_SAFE := 6.0
const LOCKPICK_ID := "resourceLockPick"
const LOCKPICK_BREAK_CHANCE := 0.4
const SAFE_HP := 120.0

# —— 采集和拆解（4b）——
## 街边物件被拆掉后多少游戏天原地刷新
const HARVEST_RESPAWN_DAYS := 5
## 官方采集数量乘这个（手机版收敛一点），单次最多给多少
const HARVEST_DROP_MULT := 0.5
const HARVEST_MAX_DROPS := 15
## 对上官方方块前的默认血量：金属 / 木 / 石 / 垃圾
const HARVEST_HP := {"metal": 120.0, "wood": 40.0, "stone": 100.0, "trash": 20.0}
## 够得着多远打物件
const HARVEST_REACH := 2.4
## 修理包 id（修满当前工具）
const REPAIR_KIT_ID := "resourceRepairKit"
## 背包拆解：耗时（秒）、返还材料的比例
const SALVAGE_TIME := 2.0
const SALVAGE_REFUND := 0.5

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

## 画质档位：省电 / 均衡 / 高清。暂停菜单里切换。
## scale_* 是 3D 渲染分辨率比例（UI 始终按屏幕原生分辨率绘制）。
const QUALITY_PRESETS := [
	{
		"name": "省电", "fps": 30, "scale_min": 0.45, "scale_max": 0.6, "scale_start": 0.55,
		"shadow_distance": 16.0, "shadow_atlas": 1024,
		"poi_shadow_distance": 0.0, "prop_shadow_distance": 0.0,
		"poi_range": 170.0, "car_range": 80.0, "prop_range": 45.0, "small_range": 25.0,
		"deco_range": 35.0, "decal_range": 30.0,
	},
	{
		"name": "均衡", "fps": 60, "scale_min": 0.55, "scale_max": 0.85, "scale_start": 0.7,
		"shadow_distance": 28.0, "shadow_atlas": 2048,
		"poi_shadow_distance": 28.0, "prop_shadow_distance": 18.0,
		"poi_range": 220.0, "car_range": 100.0, "prop_range": 60.0, "small_range": 35.0,
		"deco_range": 50.0, "decal_range": 45.0,
	},
	{
		"name": "高清", "fps": 60, "scale_min": 0.7, "scale_max": 1.0, "scale_start": 0.9,
		"shadow_distance": 40.0, "shadow_atlas": 4096,
		"poi_shadow_distance": 40.0, "prop_shadow_distance": 28.0,
		"poi_range": 260.0, "car_range": 110.0, "prop_range": 70.0, "small_range": 40.0,
		"deco_range": 60.0, "decal_range": 60.0,
	},
]

## 性能面板和远处阴影的刷新间隔（秒）
const PERF_UPDATE_INTERVAL := 0.5
const SKY_UPDATE_INTERVAL := 0.1
const LOD_UPDATE_INTERVAL := 0.5
## 僵尸寻路距离场每帧最多算多久（微秒）。一次算完要 20 多毫秒，会让画面每 0.5 秒顿一下
const FLOW_BUDGET_USEC := 1500
## 地上最多留多少摊血
const BLOOD_POOL_MAX := 24
## 地上贴花数量
const DECAL_COUNT := 140

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
	"door": 5.0,
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
## AI 预算：每帧最多更新几只的感知；多远停骨骼（近处按距离降帧见 zombie_body.gd）
const AI_SENSE_PER_FRAME := 6
const ZOMBIE_ANIM_OFF_DIST := 50.0

# —— 载具（基础驾驶）——
## 物品 id → 载具定义。model 是 assets/vehicles/ 下的文件名；"4x4" 表示用分件拼。
## yaw 用来把车头转到 -Z（Godot 的前方）；speed 米/秒，accel 米/秒²，radius 碰撞半径
const VEHICLES := {
	"vehicleBicyclePlaceable": {"zh": "自行车", "model": "bike.glb", "yaw": PI,
		"speed": 6.0, "accel": 4.0, "radius": 0.7, "tint": Color(0.55, 0.25, 0.2)},
	"vehicleMinibikePlaceable": {"zh": "小型机车", "model": "minibike.obj", "yaw": PI,
		"speed": 12.0, "accel": 6.0, "radius": 0.85},
	"vehicleTruck4x4Placeable": {"zh": "4x4 卡车", "model": "4x4", "yaw": PI,
		"speed": 13.0, "accel": 6.5, "radius": 1.5},
	"vehicleGyrocopterPlaceable": {"zh": "旋翼机", "model": "gyrocopter.glb", "yaw": PI,
		"speed": 10.0, "accel": 5.0, "radius": 1.2, "tint": Color(0.45, 0.5, 0.4)},
}
## 倒车最高速度 = 前进最高速度 × 这个
const VEHICLE_REVERSE_MULT := 0.4
## 刹车减速度、松油门后的摩擦减速（米/秒²）
const VEHICLE_BRAKE := 12.0
const VEHICLE_FRICTION := 2.5
## 转向角速度（弧度/秒），速度越快转得越顺
const VEHICLE_TURN_RATE := 1.6
const VEHICLE_TURN_SPEED_REF := 4.0
## 离载具多近能上车、最多同时摆几辆、摆车时车头离人至少多远
const VEHICLE_MOUNT_DIST := 3.0
const VEHICLE_LIMIT := 4
const VEHICLE_PLACE_DIST := 4.0
## 驾驶时第三人称相机：高度、车后距离、俯角（弧度）
const VEHICLE_CAM_HEIGHT := 3.6
const VEHICLE_CAM_BACK := 7.0
const VEHICLE_CAM_PITCH := 0.18

# —— 6d 睡眠僵尸 ——
## 睡眠时能发现玩家的距离（蹲下乘这个）；被吵醒的半径；清空后几天再刷
const SLEEP_SIGHT := 5.0
const SLEEP_SIGHT_CROUCH_MULT := 0.5
const SLEEP_WAKE_RADIUS := 10.0
const SLEEPER_RESPAWN_DAYS := 3
