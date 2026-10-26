extends Node
## 7a 经验、等级、属性和技能。自动加载为 Progression。
## 等级曲线 / 属性 / 技能 passive_effect 来自 assets/data/progression.json（官方 progression.xml）。

const C = preload("res://scripts/config.gd")
const PATH := "res://assets/data/progression.json"
## 手机版经验加倍，升级快一点
const XP_MULT := 2.0
## 测试模式（C.TEST_ALL_ITEMS）开局送的点数
const TEST_POINTS := 20

signal leveled_up(level: int, points: int)
## 等级、点数或加点变化（技能面板刷新）
signal changed

var data := {}
var level := 1
var xp := 0.0
var points := 0
var attributes := {}
var perks := {}


func _ready() -> void:
	_load_table()
	GameState.zombie_killed.connect(_on_zombie_killed)
	GameState.item_crafted.connect(_on_item_crafted)
	reset()


func _load_table() -> void:
	data = {}
	if FileAccess.file_exists(PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			data = parsed


func reset() -> void:
	level = 1
	xp = 0.0
	points = TEST_POINTS if C.TEST_ALL_ITEMS else 0
	attributes.clear()
	for name in _attrs():
		attributes[name] = int(data.attributes[name].get("min", 1))
	perks.clear()
	for name in data.get("skills", {}):
		perks[name] = 0
	changed.emit()


func max_level() -> int:
	var d: Dictionary = data.get("level", {})
	return mini(int(d.get("max_level", 60)), int(d.get("clamp_exp_cost_at_level", 60)))


## 升到下一级需要的经验（等级 1 是 10000，之后 ×1.05）
func xp_to_next() -> float:
	if level >= max_level():
		return 0.0
	var d: Dictionary = data.get("level", {})
	var base := float(d.get("exp_to_level", 10000.0))
	var mult := float(d.get("experience_multiplier", 1.05))
	return base * pow(mult, float(level - 1))


func xp_progress() -> float:
	var need := xp_to_next()
	return 0.0 if need <= 0.0 else clampf(xp / need, 0.0, 1.0)


func add_xp(amount: float, _source := "") -> void:
	if amount <= 0.0:
		return
	var cap := max_level()
	if level >= cap:
		xp = minf(xp, xp_to_next())
		return
	xp += amount * XP_MULT
	var gained := 0
	while level < cap:
		var need := xp_to_next()
		if need <= 0.0 or xp < need:
			break
		xp -= need
		level += 1
		var per := int(data.get("level", {}).get("skill_points_per_level", 1))
		points += per
		gained += per
	if level >= cap:
		xp = 0.0
	if gained > 0:
		leveled_up.emit(level, points)
		changed.emit()


# —— 属性 / 技能 ——

func attr_level(name: String) -> int:
	return int(attributes.get(name, 1))


func perk_level(name: String) -> int:
	return int(perks.get(name, 0))


func attr_max(name: String) -> int:
	return int(data.get("attributes", {}).get(name, {}).get("max", 10))


func perk_max(name: String) -> int:
	return int(data.get("skills", {}).get(name, {}).get("max", 5))


## 属性下一级的点数：基础 1 × 1.14 递增
func attr_cost(name: String) -> int:
	var a: Dictionary = data.get("attributes", {}).get(name, {})
	var base := float(a.get("cost", 1))
	var mult := float(a.get("cost_mult", 1.14))
	return maxi(1, int(ceil(base * pow(mult, float(attr_level(name) - 1)))))


func perk_cost(name: String) -> int:
	var s: Dictionary = data.get("skills", {}).get(name, {})
	var costs: Array = s.get("costs", [])
	var lvl := perk_level(name)
	if lvl < costs.size():
		return int(costs[lvl])
	return 1


func can_buy_attr(name: String) -> bool:
	return attr_level(name) < attr_max(name) and points >= attr_cost(name)


func can_buy_perk(name: String) -> bool:
	return perk_level(name) < perk_max(name) and points >= perk_cost(name)


func buy_attr(name: String) -> bool:
	if not can_buy_attr(name):
		return false
	points -= attr_cost(name)
	attributes[name] = attr_level(name) + 1
	changed.emit()
	return true


func buy_perk(name: String) -> bool:
	if not can_buy_perk(name):
		return false
	points -= perk_cost(name)
	perks[name] = perk_level(name) + 1
	changed.emit()
	return true


func skill_name(name: String) -> String:
	return str(data.get("skills", {}).get(name, {}).get("name", name))


func skill_desc(name: String) -> String:
	return str(data.get("skills", {}).get(name, {}).get("desc", ""))


func skill_rank_text(name: String, target_level: int) -> String:
	var ranks: Dictionary = data.get("skills", {}).get(name, {}).get("ranks", {})
	return str(ranks.get(str(target_level), ""))


func skills_for_attr(attr: String) -> Array:
	return data.get("attributes", {}).get(attr, {}).get("skills", [])


# —— 修正（给其他系统读） ——

## 所有技能里名为 effect 的数值之和；tags 不为空时只要包含它的条目
func value(effect: String, tags := "") -> float:
	var total := 0.0
	for skill in data.get("skills", {}):
		var lvl := perk_level(skill)
		if lvl <= 0:
			continue
		for e in data.skills[skill].get("effects", []):
			if str(e.get("name", "")) != effect:
				continue
			if tags != "" and not str(e.get("tags", "")).contains(tags):
				continue
			total += _effect_at(e, lvl)
	return total


## 手上武器标签里带哪个技能，就乘哪个技能的 EntityDamage（+10%..+50%）
func damage_mult(tags: String) -> float:
	var mult := 1.0
	for skill in data.get("skills", {}):
		if not tags.contains(skill):
			continue
		var lvl := perk_level(skill)
		if lvl <= 0:
			continue
		for e in data.skills[skill].get("effects", []):
			if str(e.get("name", "")) != "EntityDamage" or str(e.get("op", "")) != "perc_add":
				continue
			# 带条件（例如“被击晕的敌人”）的加成不直接算进普通伤害
			if bool(e.get("req", false)):
				continue
			mult += _effect_at(e, lvl)
	return maxf(1.0, mult)


func loot_time_mult() -> float:
	var sub := _skill_effect("perkLuckyLooter", "ScavengingTime", "perc_subtract")
	return clampf(1.0 - sub, 0.2, 1.0)


func loot_stage_mult() -> float:
	return 1.0 + _skill_effect("perkLuckyLooter", "LootStage", "perc_add")


func harvest_mult() -> float:
	var add := _skill_effect("perkMotherLode", "HarvestCount", "perc_add") \
		+ _skill_effect("perkSalvageOperations", "HarvestCount", "perc_add")
	return 1.0 + add


func carry_bonus() -> int:
	return int(round(_skill_effect("perkPackMule", "CarryCapacity", "base_add")))


func stamina_max_bonus() -> float:
	return _skill_effect("perkRuleOneCardio", "StaminaMax", "base_add")


func stamina_regen_mult() -> float:
	return 1.0 + _skill_effect("perkRuleOneCardio", "StaminaChangeOT", "perc_add")


func jump_mult() -> float:
	return 1.0 + _skill_effect("perkParkour", "JumpStrength", "perc_add")


## 潜行：噪声和僵尸看到你的距离都缩小（官方 Light/NoiseMultiplier 是负值）
func noise_mult() -> float:
	return clampf(1.0 + _skill_effect("perkFromTheShadows", "NoiseMultiplier", "perc_add"), 0.2, 1.0)


func sight_mult() -> float:
	return clampf(1.0 + _skill_effect("perkFromTheShadows", "LightMultiplier", "perc_add"), 0.35, 1.0)


func heal_ot() -> float:
	return _skill_effect("perkHealingFactor", "HealthChangeOT", "base_add")


func craft_time_mult() -> float:
	return clampf(1.0 + _skill_effect("perkAdvancedEngineering", "CraftingTime", "perc_add"), 0.4, 1.0)


## 7c 商人用：买价 × buy_mult，卖价 × sell_mult
func buy_mult() -> float:
	return 1.0 - clampf(_skill_effect("perkBetterBarter", "BarteringBuying", "base_add"), 0.0, 0.5)


func sell_mult() -> float:
	return 1.0 + clampf(_skill_effect("perkBetterBarter", "BarteringSelling", "base_add"), 0.0, 0.5)


# —— 存档 ——

func save_data() -> Dictionary:
	return {"progression": {
		"level": level, "xp": xp, "points": points,
		"attributes": attributes.duplicate(), "perks": perks.duplicate(),
	}}


func load_data(d: Dictionary) -> void:
	var s = d.get("progression", {})
	if not (s is Dictionary):
		return
	level = clampi(int(s.get("level", 1)), 1, max_level())
	xp = maxf(0.0, float(s.get("xp", 0.0)))
	points = maxi(0, int(s.get("points", 0)))
	var saved_attrs = s.get("attributes", {})
	for name in _attrs():
		var v := 1
		if saved_attrs is Dictionary:
			v = int(saved_attrs.get(name, 1))
		attributes[name] = clampi(v, int(data.attributes[name].get("min", 1)), attr_max(name))
	var saved_perks = s.get("perks", {})
	for name in data.get("skills", {}):
		var v := 0
		if saved_perks is Dictionary:
			v = int(saved_perks.get(name, 0))
		perks[name] = clampi(v, 0, perk_max(name))
	changed.emit()


# —— 内部 ——

func _attrs() -> Array:
	return data.get("attributes", {}).keys()


func _skill_effect(skill: String, effect: String, op := "") -> float:
	var lvl := perk_level(skill)
	if lvl <= 0:
		return 0.0
	var total := 0.0
	for e in data.get("skills", {}).get(skill, {}).get("effects", []):
		if str(e.get("name", "")) != effect:
			continue
		if op != "" and str(e.get("op", "")) != op:
			continue
		total += _effect_at(e, lvl)
	return total


## 找这一级的值；没有正好这一级就取不高于它的最近一级
func _effect_at(e: Dictionary, lvl: int) -> float:
	var rows: Array = e.get("vals", [])
	var best := 0.0
	var found := false
	for row in rows:
		var l := int(row[0])
		if l <= lvl:
			best = float(row[1])
			found = true
		elif found:
			break
	return best if found else 0.0


func _on_zombie_killed(z, _by_weapon: String) -> void:
	if is_instance_valid(z):
		add_xp(float(z.xp), "zombie")


func _on_item_crafted(_id: String, count: int) -> void:
	add_xp(5.0 * maxi(1, count), "craft")
