extends Node
## 7b 技能杂志和技能书。自动加载为 Books。
## books.json 来自官方 progression.xml（制作技能）+ items.xml（杂志、书）。

signal changed

const PATH := "res://assets/data/books.json"

var data := {}
var levels := {}      # crafting 技能类别 -> 杂志等级
var read_books := {}  # 读过的技能书 id -> true


func _ready() -> void:
	load_table()
	# 杂志/技能书不在物品索引里（云盘只导了图标），先登记进 Assets，背包里能看见名字
	for id in data.get("magazines", {}):
		var row := Assets.ensure_item(id, item_name(id))
		var icon := str(data.magazines[id].get("icon", ""))
		if icon != "":
			row.icon = icon
	for id in data.get("books", {}):
		Assets.ensure_item(id, item_name(id))
	reset()


func load_table() -> void:
	data = {}
	if FileAccess.file_exists(PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			data = parsed


func reset() -> void:
	levels.clear()
	read_books.clear()
	for cat in data.get("categories", {}):
		levels[cat] = 0
	changed.emit()


func is_readable(id: String) -> bool:
	return data.get("magazines", {}).has(id) or data.get("books", {}).has(id)


func is_magazine(id: String) -> bool:
	return data.get("magazines", {}).has(id)


func is_book(id: String) -> bool:
	return data.get("books", {}).has(id)


func item_name(id: String) -> String:
	if data.get("magazines", {}).has(id):
		return str(data.magazines[id].get("zh", id))
	if data.get("books", {}).has(id):
		return str(data.books[id].get("zh", id))
	return id


func category_level(cat: String) -> int:
	return int(levels.get(cat, 0))


func category_name(cat: String) -> String:
	return str(data.get("categories", {}).get(cat, {}).get("name", cat))


## 读一本杂志/书。返回 {ok, text}；书已读过时 ok=false、不消耗。
func read(id: String) -> Dictionary:
	if data.get("magazines", {}).has(id):
		var cat := str(data.magazines[id].get("category", ""))
		var max_level := int(data.get("categories", {}).get(cat, {}).get("max_level", 5))
		var before := category_level(cat)
		levels[cat] = mini(max_level, before + 1)
		changed.emit()
		var name := category_name(cat)
		if before >= max_level:
			return {"ok": true, "text": "%s已经满了（%d 级）" % [name, max_level]}
		return {"ok": true, "text": "%s升到 %d 级" % [name, category_level(cat)]}
	if data.get("books", {}).has(id):
		if read_books.has(id):
			return {"ok": false, "text": "这本《%s》已经读过了" % item_name(id)}
		read_books[id] = true
		changed.emit()
		return {"ok": true, "text": "读完了《%s》：%s" % [item_name(id), _effect_text(id)]}
	return {"ok": false, "text": ""}


## 某条配方需要哪个类别、几级（没有要求返回空字典）
func recipe_requirement(key: String) -> Dictionary:
	for cat in data.get("categories", {}):
		var c: Dictionary = data.categories[cat]
		if c.get("unlocks", {}).has(key):
			return {"category": cat, "level": int(c.unlocks[key]), "name": category_name(cat)}
	return {}


func requirement_text(key: String) -> String:
	var req := recipe_requirement(key)
	if req.is_empty():
		return "还没学会"
	return "需要：%s %d 级（现在 %d 级）" % [req.name, int(req.level), category_level(str(req.category))]


func random_magazine(rng: RandomNumberGenerator) -> String:
	var ids: Array = data.get("magazines", {}).keys()
	if ids.is_empty():
		return ""
	# 优先选还有配方没解锁的类别
	var useful: Array = []
	for id in ids:
		var cat := str(data.magazines[id].get("category", ""))
		var max_lvl := 0
		for k in data.get("categories", {}).get(cat, {}).get("unlocks", {}).values():
			max_lvl = maxi(max_lvl, int(k))
		if category_level(cat) < max_lvl:
			useful.append(id)
	var pool: Array = useful if not useful.is_empty() else ids
	return str(pool[rng.randi_range(0, pool.size() - 1)])


## 技能书的永久小加成
func damage_mult(tags: String) -> float:
	var mult := 1.0
	for id in read_books:
		var e: Dictionary = data.books[id].get("effect", {})
		if str(e.get("type", "")) != "damage":
			continue
		var key := str(e.get("key", ""))
		if key != "" and tags.contains(key):
			mult += float(e.get("value", 0.0))
	return mult


func loot_mult() -> float:
	var mult := 1.0
	for id in read_books:
		var e: Dictionary = data.books[id].get("effect", {})
		if str(e.get("type", "")) == "loot":
			mult += float(e.get("value", 0.0))
	return mult


func harvest_mult() -> float:
	var mult := 1.0
	for id in read_books:
		var e: Dictionary = data.books[id].get("effect", {})
		if str(e.get("type", "")) == "harvest":
			mult += float(e.get("value", 0.0))
	return mult


func stamina_bonus() -> float:
	var add := 0.0
	for id in read_books:
		var e: Dictionary = data.books[id].get("effect", {})
		if str(e.get("type", "")) == "stamina":
			add += float(e.get("value", 0.0))
	return add


func stealth_mult() -> float:
	var sub := 0.0
	for id in read_books:
		var e: Dictionary = data.books[id].get("effect", {})
		if str(e.get("type", "")) == "stealth":
			sub += float(e.get("value", 0.0))
	return clampf(1.0 - sub, 0.5, 1.0)


func save_data() -> Dictionary:
	return {"books": {"levels": levels.duplicate(), "read": read_books.keys()}}


func load_data(d: Dictionary) -> void:
	var s = d.get("books", {})
	if not (s is Dictionary):
		return
	levels.clear()
	var saved_levels = s.get("levels", {})
	for cat in data.get("categories", {}):
		levels[cat] = clampi(int(saved_levels.get(cat, 0)) if saved_levels is Dictionary else 0,
			0, int(data.categories[cat].get("max_level", 5)))
	read_books.clear()
	for id in s.get("read", []):
		if data.get("books", {}).has(str(id)):
			read_books[str(id)] = true
	changed.emit()


func _effect_text(id: String) -> String:
	var e: Dictionary = data.books[id].get("effect", {})
	match str(e.get("type", "")):
		"damage":
			return "这类武器伤害 +%d%%" % int(round(float(e.get("value", 0.0)) * 100.0))
		"loot":
			return "搜刮品质 +%d%%" % int(round(float(e.get("value", 0.0)) * 100.0))
		"harvest":
			return "采集产出 +%d%%" % int(round(float(e.get("value", 0.0)) * 100.0))
		"stamina":
			return "体力上限 +%d" % int(round(float(e.get("value", 0.0))))
		"stealth":
			return "潜行时更不容易被发现"
	return "属性提升"
