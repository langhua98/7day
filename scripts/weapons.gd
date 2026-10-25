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


## 没有倍镜时用机瞄；装了倍镜按倍镜 FOV
static func scope_fov(_gun_id: String, scope_id := "") -> float:
	if Attachments.is_scope(scope_id):
		return Attachments.scope_fov(scope_id)
	return GameConfig.AIM_FOV


static func scope_level(_gun_id: String, scope_id := "") -> int:
	if Attachments.is_scope(scope_id):
		return int(Attachments.DEFS[scope_id].get("level", 1))
	return 1


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


## 弹匣默认装的普通弹
static func default_ammo(gun_id: String) -> String:
	var prefix: String = stats(gun_id).ammo
	match prefix:
		"ammoShotgun":
			return "ammoShotgunShell"
		"ammoRocket":
			return "ammoRocketHE"
		"ammoArrow":
			return "ammoArrowStone"
		"ammoCrossbowBolt":
			return "ammoCrossbowBoltStone"
	if prefix == "":
		return ""
	return prefix + "BulletBall"


## 弹药变体的伤害倍率（entity）和破块倍率（block）
static func ammo_mods(ammo_id: String) -> Dictionary:
	if "BreachingSlug" in ammo_id:
		return {"label": "破门", "entity": 0.9, "block": 2.5}
	if "Slug" in ammo_id:
		return {"label": "独头", "entity": 1.5, "block": 0.8}
	if "BulletHP" in ammo_id or ammo_id.ends_with("HP"):
		return {"label": "HP", "entity": 1.25, "block": 0.8}
	if "SteelAP" in ammo_id:
		return {"label": "钢AP", "entity": 1.0, "block": 2.0}
	if "BulletAP" in ammo_id or ammo_id.ends_with("AP"):
		return {"label": "AP", "entity": 0.9, "block": 2.0}
	if "Flaming" in ammo_id:
		return {"label": "燃烧", "entity": 1.1, "block": 1.0}
	if "Exploding" in ammo_id:
		return {"label": "爆炸", "entity": 1.0, "block": 1.5}
	if "Iron" in ammo_id:
		return {"label": "铁", "entity": 1.2, "block": 1.0}
	return {"label": "普通", "entity": 1.0, "block": 1.0}


static func ammo_label(ammo_id: String) -> String:
	if ammo_id == "":
		return ""
	var caliber := "子弹"
	if "9mm" in ammo_id:
		caliber = "9mm"
	elif "762" in ammo_id:
		caliber = "7.62"
	elif "44Magnum" in ammo_id:
		caliber = ".44"
	elif "Shotgun" in ammo_id:
		caliber = "12号"
	elif "CrossbowBolt" in ammo_id:
		caliber = "弩箭"
	elif "Arrow" in ammo_id:
		caliber = "箭"
	elif "Rocket" in ammo_id:
		caliber = "火箭"
	var mods := ammo_mods(ammo_id)
	return caliber + " " + str(mods.get("label", "普通"))


## 品质 1–6：武器/工具伤害和耐久 ×(1 + 0.1×(品质−1))
static func quality_mult(quality: int) -> float:
	return 1.0 + 0.1 * (clampi(quality, 1, 6) - 1)


## 按游戏阶段掷品质：第 1 天大多 1 级，GS 60 能到 5–6 级
static func roll_quality(gs: int, rng: RandomNumberGenerator) -> int:
	var maxq := clampi(1 + int(gs / 10.0), 1, 6)
	return rng.randi_range(1, maxq)


## 捡到一盒子弹给几发
static func pickup_count(id: String, rng: RandomNumberGenerator) -> int:
	if id.begins_with("ammoRocket"):
		return rng.randi_range(1, 2)
	if id.begins_with("ammoArrow") or id.begins_with("ammoCrossbow"):
		return rng.randi_range(4, 9)
	if id.begins_with("ammoShotgun"):
		return rng.randi_range(5, 12)
	return rng.randi_range(10, 24)
