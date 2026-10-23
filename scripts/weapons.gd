class_name Weapons
## 枪的数值和子弹：按物品名（七日杀的内部名，如 gunMGT2TacticalAR）判断是哪类枪、用什么子弹。
## 子弹也是物品表里的物品（ammo9mmBulletBall 等），翻容器能翻到。

## [名字里含的词, 子弹名前缀, 弹匣, 射击间隔秒, 每发伤害, 弹丸数, 散布, 射程米, 连发, 换弹秒, 爆炸半径, 枪声, 换弹声]
const TABLE := [
	[["rocket", "explosives"], "ammoRocket", 1, 1.2, 220.0, 1, 0.0, 45.0, false, 3.0, 4.5, "fire_rocket", "reload_rifle"],
	[["crossbow"], "ammoCrossbowBolt", 1, 0.9, 70.0, 1, 0.0, 45.0, false, 1.4, 0.0, "fire_bow", "reload_pistol"],
	[["bow"], "ammoArrow", 1, 0.8, 48.0, 1, 0.004, 40.0, false, 0.6, 0.0, "fire_bow", "reload_pistol"],
	[["doublebarrel"], "ammoShotgun", 2, 0.35, 15.0, 8, 0.07, 20.0, false, 2.2, 0.0, "fire_shotgun", "reload_shotgun"],
	[["autoshotgun"], "ammoShotgun", 10, 0.3, 14.0, 8, 0.07, 20.0, true, 2.6, 0.0, "fire_shotgun", "reload_shotgun"],
	[["shotgun"], "ammoShotgun", 6, 0.8, 15.0, 8, 0.065, 22.0, false, 2.4, 0.0, "fire_shotgun", "reload_shotgun"],
	[["magnum", "desertvulture", "44"], "ammo44Magnum", 6, 0.5, 62.0, 1, 0.006, 40.0, false, 2.2, 0.0, "fire_magnum", "reload_pistol"],
	[["smg"], "ammo9mm", 30, 0.09, 20.0, 1, 0.025, 30.0, true, 1.8, 0.0, "fire_smg", "reload_rifle"],
	[["handgun", "pistol"], "ammo9mm", 12, 0.28, 30.0, 1, 0.012, 35.0, false, 1.4, 0.0, "fire_pistol", "reload_pistol"],
	[["m60"], "ammo762mm", 60, 0.1, 34.0, 1, 0.03, 50.0, true, 3.2, 0.0, "fire_mg", "reload_rifle"],
	[["sniper", "hunting", "lever", "rifle"], "ammo762mm", 5, 0.9, 88.0, 1, 0.002, 70.0, false, 2.4, 0.0, "fire_sniper", "reload_rifle"],
	[["mg", "ak47", "tactical", "ar"], "ammo762mm", 30, 0.12, 32.0, 1, 0.02, 50.0, true, 2.2, 0.0, "fire_rifle", "reload_rifle"],
]


static func stats(id: String) -> Dictionary:
	var low := id.to_lower().trim_prefix("gun")
	var base := _row(TABLE[8])   # 认不出来的当手枪
	for row in TABLE:
		var hit := false
		for word in row[0]:
			if low.contains(word):
				hit = true
				break
		if hit:
			base = _row(row)
			break
	# 官方 items.xml 的弹匣、射速、换弹、弹药类型优先
	var info: Dictionary = Data.items.get(id, {})
	if not info.is_empty():
		var mag := int(info.get("magazine", 0))
		if mag > 0:
			base.mag = mag
		var rpm := float(info.get("rpm", 0.0))
		if rpm > 0.0:
			base.rate = 60.0 / rpm
		var reload := float(info.get("reload", 0.0))
		if reload > 0.0:
			base.reload = reload
		var ammo: String = info.get("ammo", "")
		if ammo != "":
			base.ammo = ammo
	return base


static func _row(r: Array) -> Dictionary:
	return {"ammo": r[1], "mag": r[2], "rate": r[3], "damage": r[4], "pellets": r[5], "spread": r[6],
		"range": r[7], "auto": r[8], "reload": r[9], "blast": r[10], "fire_snd": r[11], "reload_snd": r[12]}


static func is_ammo(id: String) -> bool:
	return id.begins_with("ammo")


## 这把枪能用的子弹（背包里有的），按数量从多到少
static func ammo_in(inventory: Dictionary, gun_id: String) -> Array:
	var prefix: String = stats(gun_id).ammo
	var out := []
	for id in inventory:
		if id.begins_with(prefix) and inventory[id] > 0:
			out.append(id)
	out.sort_custom(func(a, b): return inventory[a] > inventory[b])
	return out


static func ammo_count(inventory: Dictionary, gun_id: String) -> int:
	var n := 0
	for id in ammo_in(inventory, gun_id):
		n += inventory[id]
	return n


## 捡到一盒子弹给几发
static func pickup_count(id: String, rng: RandomNumberGenerator) -> int:
	if id.begins_with("ammoRocket"):
		return rng.randi_range(1, 2)
	if id.begins_with("ammoArrow") or id.begins_with("ammoCrossbow"):
		return rng.randi_range(4, 9)
	if id.begins_with("ammoShotgun"):
		return rng.randi_range(5, 12)
	return rng.randi_range(10, 24)
