class_name Crafting
extends Node
## 合成：配方全部来自 assets/data/recipes.json（tools/build_data.py 从官方 recipes.xml 生成）。
## 检查材料、扣材料、排队（最多 4 项，离开面板也继续）、完成后进背包，满了掉地上。
## 时间和材料按 config.gd 的 CRAFT_TIME_MULT / RECIPE_COST_MULT 打折。

const C = preload("res://scripts/config.gd")
## 合成面板的分类（key 和 build_data.py 的 RECIPE_CATS 一致）
const CATS := [["tool", "工具"], ["weapon", "武器"], ["ammo", "弹药"], ["medical", "医疗"],
	["food", "食物"], ["build", "建造"], ["other", "其他"]]
## 工作站中文名
const AREA_NAMES := {"": "背包", "campfire": "篝火", "workbench": "工作台", "forge": "锻造炉",
	"chemistryStation": "化学台", "cementMixer": "水泥搅拌机"}

## 当前这一局的合成系统（给 Crafting.near_station 之类的静态调用用）
static var current: Crafting
## 4c 工作站接上这个：func(area: String) -> bool，玩家 3 米内有没有这种工作站
static var station_check := Callable()

var inventory: InventorySystem
var looting: LootingSystem
var player_sys: PlayerSystem
var hud: Hud
var running := false

## key → 配方 {id, count, area, time, tool, tags, cat, zh, learnable, ingredients:[{id,count}]}
var recipes := {}
## 队列：每项 {key, n（批数）, done（已完成批数）, t（当前这批已用秒数）}
var queue: Array = []
## 读书学会的配方（第 7 步用）
var unlocked := {}


func setup(inv: InventorySystem, loot: LootingSystem, player_ref: PlayerSystem, hud_ref: Hud) -> void:
	inventory = inv
	looting = loot
	player_sys = player_ref
	hud = hud_ref
	current = self
	load_recipes()


## 读 recipes.json，把成品和材料登记成物品（方块表里的成品，比如篝火，物品索引里没有）
func load_recipes() -> void:
	recipes = Data.get_table("recipes")
	for key in recipes:
		var r: Dictionary = recipes[key]
		Assets.ensure_item(str(r.id), str(r.get("zh", r.id)))
		if str(r.get("tool", "")) != "":
			Assets.ensure_item(str(r.tool), str(r.tool))
		for ing in r.get("ingredients", []):
			Assets.ensure_item(str(ing.id), str(ing.get("zh", ing.id)))


func reset() -> void:
	queue.clear()
	unlocked.clear()
	GameState.craft_queue_changed.emit()


# —— 查询 ——

func recipe(key: String) -> Dictionary:
	return recipes.get(key, {})


## 某个分类下能看到的配方 key（area 不为 null 时只看这个工作站的）
func list(cat := "", area = null) -> Array:
	var out := []
	for key in recipes:
		var r: Dictionary = recipes[key]
		if cat != "" and r.get("cat", "other") != cat:
			continue
		if area != null and str(r.get("area", "")) != str(area):
			continue
		if not is_unlocked(key):
			continue
		out.append(key)
	out.sort_custom(func(a, b): return str(recipes[a].zh) < str(recipes[b].zh))
	return out


func is_unlocked(key: String) -> bool:
	var r := recipe(key)
	if r.is_empty():
		return false
	return C.RECIPES_ALL_UNLOCKED or not r.get("learnable", false) or unlocked.has(key)


## 一批要多少个某材料：官方 × RECIPE_COST_MULT，向上取整，至少 1
static func cost(official: int) -> int:
	return maxi(1, ceili(official * C.RECIPE_COST_MULT))


## 一批要几秒
func time_of(key: String) -> float:
	return maxf(0.2, float(recipe(key).get("time", 1.0)) * C.CRAFT_TIME_MULT)


## 材料清单：[{id, need, have}]，need 是 n 批的总数
func ingredients(key: String, n := 1) -> Array:
	var out := []
	for ing in recipe(key).get("ingredients", []):
		var id := str(ing.id)
		out.append({"id": id, "need": cost(int(ing.count)) * n, "have": inventory.count(id) if inventory else 0})
	return out


## 合成地点：area 为空 = 背包随时可做。其他等 4c 的工作站，没有时测试模式当作在旁边
static func near_station(area: String) -> bool:
	if area == "":
		return true
	if station_check.is_valid():
		return bool(station_check.call(area))
	return C.TEST_STATIONS_NEAR


## 为什么不能做（空串 = 能做）
func why_not(key: String, n := 1) -> String:
	var r := recipe(key)
	if r.is_empty():
		return "没有这个配方"
	if not is_unlocked(key):
		return "还没学会"
	var area := str(r.get("area", ""))
	if not near_station(area):
		return "要在%s旁边" % AREA_NAMES.get(area, area)
	var tool := str(r.get("tool", ""))
	if tool != "" and not inventory.has(tool):
		return "需要%s" % Assets.display_name(tool)
	if queue.size() >= C.CRAFT_QUEUE_MAX:
		return "队列满了（%d 项）" % C.CRAFT_QUEUE_MAX
	for ing in ingredients(key, n):
		if ing.have < ing.need:
			return "材料不够"
	return ""


func can_craft(key: String, n := 1) -> bool:
	return n > 0 and why_not(key, n) == ""


## 材料够做几批（不看队列）
func max_count(key: String) -> int:
	var best := 999
	for ing in ingredients(key, 1):
		best = mini(best, int(ing.have) / maxi(1, int(ing.need)))
	return maxi(0, best)


# —— 合成 ——

## 扣材料、进队列。返回是否成功
func craft(key: String, n := 1) -> bool:
	if not can_craft(key, n):
		return false
	for ing in ingredients(key, n):
		inventory.remove(ing.id, ing.need)
	queue.append({"key": key, "n": n, "done": 0, "t": 0.0})
	inventory.refresh()
	GameState.craft_queue_changed.emit()
	return true


## 取消队列里的一项：没做完的批次退还材料
func cancel(index: int) -> void:
	if index < 0 or index >= queue.size():
		return
	var q: Dictionary = queue[index]
	queue.remove_at(index)
	var left := int(q.n) - int(q.done)
	if left > 0:
		for ing in ingredients(q.key, left):
			_give(ing.id, ing.need)
	inventory.refresh()
	GameState.craft_queue_changed.emit()


## 队列第一项的进度 0–1（当前这一批）
func progress() -> float:
	if queue.is_empty():
		return 0.0
	return clampf(float(queue[0].t) / time_of(queue[0].key), 0.0, 1.0)


func _process(delta: float) -> void:
	if not running or queue.is_empty():
		return
	var q: Dictionary = queue[0]
	if recipe(q.key).is_empty():
		queue.pop_front()
		GameState.craft_queue_changed.emit()
		return
	q.t += delta
	var need := time_of(q.key)
	if q.t < need:
		return
	q.t -= need
	q.done += 1
	var r := recipe(q.key)
	var id := str(r.id)
	var count := int(r.get("count", 1))
	_give(id, count)
	hud.toast("合成完成：%s%s" % [Assets.display_name(id), " ×%d" % count if count > 1 else ""])
	Sfx.play("loot", Vector3.INF, -8.0)
	GameState.item_crafted.emit(id, count)
	if q.done >= int(q.n):
		queue.pop_front()
	inventory.refresh()
	GameState.craft_queue_changed.emit()


## 放进背包，放不下的掉在脚边
func _give(id: String, count: int) -> void:
	var left := inventory.add(id, count)
	if left > 0 and looting and player_sys and player_sys.player:
		looting.spawn_loot(player_sys.player.position + Vector3(0, 0.2, 0), id, 0, left)
		hud.toast("背包满了，%s 掉在脚边" % Assets.display_name(id))


# —— 存档 ——

func save_data() -> Dictionary:
	var q := []
	for e in queue:
		q.append({"key": e.key, "n": e.n, "done": e.done, "t": e.t})
	return {"craft_queue": q, "recipes_unlocked": unlocked.keys()}


func load_data(d: Dictionary) -> void:
	queue.clear()
	for e in d.get("craft_queue", []):
		if e is Dictionary and recipes.has(str(e.get("key", ""))):
			queue.append({"key": str(e.key), "n": maxi(1, int(e.get("n", 1))), "done": int(e.get("done", 0)),
				"t": float(e.get("t", 0.0))})
	unlocked.clear()
	for k in d.get("recipes_unlocked", []):
		unlocked[str(k)] = true
	GameState.craft_queue_changed.emit()
