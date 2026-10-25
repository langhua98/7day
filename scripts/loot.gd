class_name Loot
extends RefCounted
## 官方掉落表和物品品质（assets/data/loot.json，由 tools/build_data.py 从 loot.xml 生成）。
## 容器名 → 组/物品；品质按 lootqualitytemplate 和游戏阶段（GS）掷。

## 找不到容器名时用的通用组（垃圾桶，基本什么材料都有）
const GENERIC := "garbage"
## 容器没写品质模板时用官方基础模板
const QUALITY_FALLBACK := "qualBaseTemplate"

## 同一个陌生容器名只警告一次
static var _warned := {}
## 楼里有些容器方块没写 LootList（名字像 cntGunSafeWhite），按名字里的关键词猜官方容器
const HINTS := [
	["gunsafe", "gunSafe"], ["wall-safe", "smallSafes"], ["wallsafe", "smallSafes"],
	["desksafe", "smallSafes"], ["safe", "smallSafes"],
	["fridge", "refrigerator"], ["refrigerator", "refrigerator"], ["freezer", "shamwayFreezer"],
	["bookcase", "bookcase"], ["bookshelf", "bookShelves"],
	["medicine", "medicineCabinet"], ["medical", "medicalPileSmall"], ["pill", "medicalPillCase"],
	["cupboard", "cupboard"], ["cabinet", "fileCabinet"], ["drawer", "woodenDesk"],
	["mailbox", "mailbox"], ["mail", "mailbox"], ["dumpster", "dumpster"],
	["garbage", "garbage"], ["trash", "junk"], ["cardboard", "cardboardBox"],
	["cooler", "cooler"], ["sink", "sinks"], ["oven", "oven"], ["microwave", "microwave"],
	["locker", "lockers"], ["ammo", "ammoPileSmall"], ["food", "foodPileMed"],
	["weapon", "weaponsBagSmall"], ["tool", "toolBox"], ["clothes", "clothesRacks"],
	["shoe", "shoes"],
]


## 翻容器：返回 [{id, count, quality}]。没有 loot.json 时返回空数组，调用方退回 Assets.random_loot
static func roll(container: String, gs: int, rng: RandomNumberGenerator) -> Array:
	var table: Dictionary = Data.get_table("loot")
	if table.is_empty():
		return []
	var containers: Dictionary = table.get("containers", {})
	var key := container
	if not containers.has(key):
		var hinted := _hint(key)
		if hinted != "" and containers.has(hinted):
			key = hinted
	if not containers.has(key):
		key = GENERIC
		if not containers.has(key):
			return []
		if not _warned.has(container):
			_warned[container] = true
			push_warning("掉落表里没有容器「%s」，用 %s" % [container, GENERIC])
	var out: Array = []
	var c: Dictionary = containers[key]
	_roll_list(c, str(c.get("quality", "")), table, gs, rng, out)
	return out


## 品质 1–6：按模板和 GS 掷。模板是累计概率（prob 是上限）
static func roll_quality(gs: int, template: String, rng: RandomNumberGenerator) -> int:
	var table: Dictionary = Data.get_table("loot")
	var tpls: Dictionary = table.get("quality", {})
	var rows: Array = tpls.get(template, tpls.get(QUALITY_FALLBACK, []))
	if rows.is_empty():
		return 1
	var chosen: Dictionary = rows[rows.size() - 1]
	for row in rows:
		var lv: Array = row.get("level", [0, 999999])
		if gs >= int(lv[0]) and gs <= int(lv[1]):
			chosen = row
			break
	var r := rng.randf()
	for pair in chosen.get("loot", []):
		if r <= float(pair[1]):
			return clampi(int(pair[0]), 1, 6)
	return clampi(int(chosen.get("default", 1)), 1, 6)


## 物品有没有品质（武器、工具、护甲在 items.json 里有耐久）
static func has_quality(id: String) -> bool:
	var info: Dictionary = Data.items.get(id, {})
	return float(info.get("durability", 0.0)) > 0.0


## 没有 LootList 的容器方块名 → 官方容器（猜不到返回空）
static func _hint(name: String) -> String:
	var low := name.to_lower()
	for pair in HINTS:
		if low.contains(pair[0]):
			return pair[1]
	return ""


## 组和容器是同一种结构：count（数字范围或 "all"）+ items
static func _roll_list(node: Dictionary, quality: String, table: Dictionary, gs: int,
		rng: RandomNumberGenerator, out: Array) -> void:
	var entries: Array = node.get("items", [])
	if entries.is_empty():
		return
	var count = node.get("count", [1, 1])
	if count is String and str(count) == "all":
		for e in entries:
			var p := _weight(e, table, gs)
			if p < 1.0 and rng.randf() >= p:
				continue
			_roll_entry(e, quality, table, gs, rng, out)
		return
	var n := _rand_count(count, rng)
	var weights: Array[float] = []
	var total := 0.0
	for e in entries:
		var w: float = maxf(0.0, _weight(e, table, gs))
		weights.append(w)
		total += w
	if total <= 0.0:
		return
	for i in n:
		var r := rng.randf() * total
		for j in entries.size():
			r -= weights[j]
			if r <= 0.0:
				_roll_entry(entries[j], quality, table, gs, rng, out)
				break


static func _roll_entry(e: Dictionary, quality: String, table: Dictionary, gs: int,
		rng: RandomNumberGenerator, out: Array) -> void:
	var n := _rand_count(e.get("count", [1, 1]), rng)
	if e.has("group"):
		var g: Dictionary = table.get("groups", {}).get(str(e.group), {})
		if g.is_empty():
			return
		for i in n:
			_roll_list(g, quality, table, gs, rng, out)
		return
	var id := str(e.get("item", ""))
	if id == "":
		return
	var q := 0
	if has_quality(id):
		q = roll_quality(gs, quality, rng)
	out.append({"id": id, "count": maxi(1, n), "quality": q})


## 条目权重：有概率模板按 GS 取概率；有 prob 用 prob；否则 1
static func _weight(e: Dictionary, table: Dictionary, gs: int) -> float:
	if e.has("prob_template"):
		return _prob(str(e.prob_template), table, gs)
	return float(e.get("prob", 1.0))


static func _prob(template: String, table: Dictionary, gs: int) -> float:
	var rows: Array = table.get("prob", {}).get(template, [])
	if rows.is_empty():
		return 1.0
	for row in rows:
		if gs >= int(row[0]) and gs <= int(row[1]):
			return float(row[2])
	# GS 比最低档还低用第一档，比最高档还高用最后一档
	if gs < int(rows[0][0]):
		return float(rows[0][2])
	return float(rows[rows.size() - 1][2])


static func _rand_count(count, rng: RandomNumberGenerator) -> int:
	if count is String:
		return 1
	var lo := int(count[0])
	var hi := int(count[1]) if (count as Array).size() > 1 else lo
	return rng.randi_range(mini(lo, hi), maxi(lo, hi))
