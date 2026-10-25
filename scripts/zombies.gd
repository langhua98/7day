class_name Zombies
extends RefCounted
## 官方僵尸数据（assets/data/zombies.json）：基础数值和野性 / 辐射变体。

const C = preload("res://scripts/config.gd")


static func _data() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Data")
	return null


static func table() -> Dictionary:
	var data := _data()
	return data.get_table("zombies") if data else {}


static func entry(cls: String) -> Dictionary:
	return table().get(cls, {})


## 某模型的基础（普通）类；没有普通类就退回任意一个
static func base_class(model: String) -> Dictionary:
	var fallback := {}
	var rows: Dictionary = table()
	for cls in rows:
		var e: Dictionary = rows[cls]
		if str(e.get("model", "")) != model or not bool(e.get("spawn", true)):
			continue
		if not bool(e.get("feral", false)) and not bool(e.get("radiated", false)):
			return e
		if fallback.is_empty():
			fallback = e
	return fallback


static func variant_class(model: String, variant: String) -> Dictionary:
	var rows: Dictionary = table()
	for cls in rows:
		var e: Dictionary = rows[cls]
		if str(e.get("model", "")) != model:
			continue
		var feral := bool(e.get("feral", false))
		var radiated := bool(e.get("radiated", false))
		if variant == "radiated" and radiated:
			return e
		if variant == "feral" and feral and not radiated:
			return e
		if variant == "normal" and not feral and not radiated:
			return e
	return {}


## 按 GS 决定这只僵尸是不是野性 / 辐射
static func pick_variant(model: String, gs: int, rng: RandomNumberGenerator) -> String:
	if not variant_class(model, "radiated").is_empty() and gs >= C.ZOMBIE_GS_RADIATED \
			and rng.randf() < C.ZOMBIE_RADIATED_CHANCE:
		return "radiated"
	var chance := clampf(float(gs - C.ZOMBIE_GS_FERAL) * C.ZOMBIE_FERAL_CHANCE_PER_GS,
		0.0, C.ZOMBIE_FERAL_CHANCE)
	if chance > 0.0 and not variant_class(model, "feral").is_empty() and rng.randf() < chance:
		return "feral"
	return "normal"


## 给 Zombie.setup 用的数值：基础类 × 手机版倍率，再乘变体加成
static func stats(model: String, variant: String) -> Dictionary:
	var base := base_class(model)
	if base.is_empty():
		return {}
	var hp := float(base.get("hp", 100.0)) * C.ZOMBIE_HP_SCALE
	var spd := float(base.get("speed", 1.0)) * C.ZOMBIE_SPEED_SCALE
	var dmg := float(base.get("damage", 0.0))
	if dmg <= 0.0:
		dmg = 10.0
	dmg *= C.ZOMBIE_DAMAGE_SCALE
	var feral := variant == "feral" or variant == "radiated"
	var radiated := variant == "radiated"
	if feral:
		hp *= C.ZOMBIE_FERAL_HP
		spd *= C.ZOMBIE_FERAL_SPEED
	if radiated:
		hp *= C.ZOMBIE_RADIATED_HP
	return {
		"class": str(base.get("class", "")),
		"model": model,
		"name": str(base.get("name", "僵尸")),
		"hp": hp,
		"speed": spd,
		"damage": dmg,
		"xp": int(base.get("xp", 0)),
		"feral": feral,
		"radiated": radiated,
		"special": str(base.get("special", "")),
		"big": float(base.get("hp", 0.0)) >= C.ZOMBIE_BIG_HP,
	}
