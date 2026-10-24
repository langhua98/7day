class_name Crafting
extends Node
## 合成：配方全部来自 assets/data/recipes.json（tools/build_data.py 从官方 recipes.xml 生成）。
## 背包和一个工作站各自有队列；工作站队列离开也继续。篝火要木头燃料，锅/烤架放进工具格。

const C = preload("res://scripts/config.gd")
const CATS := [["tool", "工具"], ["weapon", "武器"], ["ammo", "弹药"], ["medical", "医疗"],
	["food", "食物"], ["build", "建造"], ["other", "其他"]]
const AREA_NAMES := {"": "背包", "campfire": "篝火", "workbench": "工作台", "forge": "锻造炉",
	"chemistryStation": "化学台", "cementMixer": "水泥搅拌机"}
const STATION_SFX := {"campfire": "campfire", "forge": "forge",
	"chemistryStation": "chem", "cementMixer": "cement"}

## 当前这一局的合成系统（给 Crafting.near_station 之类的静态调用用）
static var current: Crafting
## 测试用覆盖：func(area: String) -> bool；为空时用当前场景里摆下的工作站
static var station_check := Callable()

var inventory: InventorySystem
var looting: LootingSystem
var player_sys: PlayerSystem
var hud: Hud
var running := false

## key → 配方 {id, count, area, time, tool, tags, cat, zh, learnable, ingredients:[{id,count}]}
var recipes := {}
## 背包队列：每项 {key, n（批数）, done（已完成批数）, t（当前这批已用秒数）}
var queue: Array = []
## 工作站队列：格子 -> 队列；每个工作站独立
var station_queues := {}
## 工作站状态：格子 -> {area, fuel, tool}
var station_states := {}
## 读书学会的配方（第 7 步用）
var unlocked := {}
## 篝火光：格子 -> OmniLight3D
var _lights := {}


func setup(inv: InventorySystem, loot: LootingSystem, player_ref: PlayerSystem, hud_ref: Hud) -> void:
	inventory = inv
	looting = loot
	player_sys = player_ref
	hud = hud_ref
	current = self
	load_recipes()


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
	for cell in _lights:
		if is_instance_valid(_lights[cell]):
			_lights[cell].queue_free()
	_lights.clear()
	queue.clear()
	station_queues.clear()
	station_states.clear()
	unlocked.clear()
	GameState.craft_queue_changed.emit()


# —— 队列和地点 ——

## station = null 是背包；否则是工作站所在方块格子
func queue_for(station = null) -> Array:
	if station == null:
		return queue
	if not station_queues.has(station):
		station_queues[station] = []
	return station_queues[station]


## 工作站状态；不是工作站返回 {}
func station_state(cell = null) -> Dictionary:
	if cell == null:
		return {}
	var area := _station_area(cell)
	if area == "":
		return {}
	if not station_states.has(cell):
		station_states[cell] = {"area": area, "fuel": 0, "tool": ""}
	else:
		station_states[cell]["area"] = area
	return station_states[cell]


func station_pos(cell: Vector3i) -> Vector3:
	return Vector3(cell) + Vector3(0.5, 0.5, 0.5)


func _station_area(cell) -> String:
	if looting == null or looting.world == null:
		return ""
	return looting.world.station_area_at(cell)


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


## 合成地点：area 为空 = 背包随时可做；其他要 workstation 参数
static func near_station(area: String) -> bool:
	if area == "":
		return true
	if station_check.is_valid():
		return bool(station_check.call(area))
	if current != null and current.looting != null and current.player_sys != null and current.player_sys.player != null:
		return current.looting.world.near_station(current.player_sys.player.position, area, C.STATION_REACH)
	return C.TEST_STATIONS_NEAR


## 为什么不能做（空串 = 能做）
func why_not(key: String, n := 1, station = null) -> String:
	var r := recipe(key)
	if r.is_empty():
		return "没有这个配方"
	if not is_unlocked(key):
		return "还没学会"
	var area := str(r.get("area", ""))
	if area != "":
		if station == null:
			return "要在%s旁边用" % AREA_NAMES.get(area, area)
		var st := station_state(station)
		if st.is_empty() or str(st.area) != area:
			return "要在%s旁边用" % AREA_NAMES.get(area, area)
		if not near_station(area):
			return "要在%s旁边" % AREA_NAMES.get(area, area)
	var tool := str(r.get("tool", ""))
	if tool != "":
		var has_tool: bool = inventory.has(tool) if inventory else false
		if area == "campfire" and station != null:
			has_tool = str(station_state(station).get("tool", "")) == tool
		if not has_tool:
			return "需要%s" % Assets.display_name(tool)
	if area == "campfire" and station != null and int(station_state(station).get("fuel", 0)) <= 0:
		return "篝火没燃料"
	if queue_for(station).size() >= C.CRAFT_QUEUE_MAX:
		return "队列满了（%d 项）" % C.CRAFT_QUEUE_MAX
	for ing in ingredients(key, n):
		if ing.have < ing.need:
			return "材料不够"
	return ""


func can_craft(key: String, n := 1, station = null) -> bool:
	return n > 0 and why_not(key, n, station) == ""


## 材料够做几批（不看队列）
func max_count(key: String) -> int:
	var best := 999
	for ing in ingredients(key, 1):
		best = mini(best, int(ing.have) / maxi(1, int(ing.need)))
	return maxi(0, best)


# —— 工作站状态 ——

## 打开工作站的音效（由 looting 调）
func station_open(area: String, pos: Vector3) -> void:
	_play_station(area, "open", pos)


func _play_station(area: String, suffix: String, pos: Vector3) -> void:
	var g: String = STATION_SFX.get(area, "")
	if g != "" and Sfx.has(g + "_" + suffix):
		Sfx.play(g + "_" + suffix, pos, -4.0)


## 往篝火加木头；返回是否成功
func add_fuel(cell: Vector3i, amount := 1) -> bool:
	var st := station_state(cell)
	if st.is_empty() or str(st.area) != "campfire":
		return false
	var id: String = C.CAMPFIRE_FUEL
	var n: int = mini(amount, inventory.count(id))
	if n <= 0:
		if hud:
			hud.toast("背包里没有%s" % Assets.display_name(id))
		return false
	inventory.remove(id, n)
	st["fuel"] = int(st.get("fuel", 0)) + n
	inventory.refresh()
	GameState.craft_queue_changed.emit()
	return true


## 放锅/烤架；id 为空 = 取回。返回是否成功
func set_tool(cell: Vector3i, id := "") -> bool:
	var st := station_state(cell)
	if st.is_empty() or str(st.area) != "campfire":
		return false
	if id == "":
		var old := str(st.get("tool", ""))
		if old != "":
			inventory.add(old, 1)
			st["tool"] = ""
			inventory.refresh()
			GameState.craft_queue_changed.emit()
		return true
	if not inventory.has(id):
		return false
	var prev := str(st.get("tool", ""))
	if prev == id:
		return true
	if prev != "":
		inventory.add(prev, 1)
	inventory.remove(id, 1)
	st["tool"] = id
	inventory.refresh()
	GameState.craft_queue_changed.emit()
	return true


## 点一下：有锅就收回来；没有就找背包里的锅/烤架放进去
func toggle_tool(cell: Vector3i) -> bool:
	var st := station_state(cell)
	if st.is_empty():
		return false
	if str(st.get("tool", "")) != "":
		return set_tool(cell, "")
	for id in C.COOK_TOOLS:
		if inventory.has(id):
			return set_tool(cell, id)
	if hud:
		hud.toast("背包里没有锅或烤架")
	return false


# —— 合成 ——

## 扣材料、进队列。station = null 是背包；否则工作站格子
func craft(key: String, n := 1, station = null) -> bool:
	if not can_craft(key, n, station):
		return false
	for ing in ingredients(key, n):
		inventory.remove(ing.id, ing.need)
	queue_for(station).append({"key": key, "n": n, "done": 0, "t": 0.0, "fueled": false})
	inventory.refresh()
	GameState.craft_queue_changed.emit()
	return true


## 取消队列里的一项：没做完的批次退还材料
func cancel(index: int, station = null) -> void:
	var q: Array = queue_for(station)
	if index < 0 or index >= q.size():
		return
	var e: Dictionary = q[index]
	q.remove_at(index)
	var left := int(e.n) - int(e.done)
	if left > 0:
		for ing in ingredients(e.key, left):
			_give(ing.id, ing.need)
	inventory.refresh()
	GameState.craft_queue_changed.emit()


## 队列第一项的进度 0–1（当前这一批）
func progress(station = null) -> float:
	var q: Array = queue_for(station)
	if q.is_empty():
		return 0.0
	return clampf(float(q[0].t) / time_of(q[0].key), 0.0, 1.0)


func _process(delta: float) -> void:
	if not running:
		return
	_tick(queue, delta, null)
	for cell in station_queues.keys():
		var st := station_state(cell)
		if st.is_empty():
			station_queues.erase(cell)
			station_states.erase(cell)
			_set_light(cell, false)
			continue
		_tick(station_queues[cell], delta, cell)


func _tick(q: Array, delta: float, station) -> void:
	if q.is_empty():
		return
	var st := station_state(station) if station != null else {}
	if station != null and str(st.get("area", "")) == "campfire" and not bool(q[0].get("fueled", false)):
		if int(st.get("fuel", 0)) <= 0:
			return
		st["fuel"] = int(st.fuel) - 1
		q[0]["fueled"] = true
	if station != null:
		_set_light(station, str(st.get("area", "")) == "campfire" and int(st.get("fuel", 0)) > 0)
		_station_effects(station, st, delta)
	q[0].t += delta
	var need := time_of(q[0].key)
	if q[0].t < need:
		return
	q[0].t -= need
	q[0].done += 1
	q[0]["fueled"] = false
	var r := recipe(q[0].key)
	var id := str(r.id)
	var count := int(r.get("count", 1))
	_give(id, count)
	hud.toast("合成完成：%s%s" % [Assets.display_name(id), " ×%d" % count if count > 1 else ""])
	Sfx.play("loot", Vector3.INF, -8.0)
	if station != null:
		_play_station(str(st.get("area", "")), "done", station_pos(station))
	GameState.item_crafted.emit(id, count)
	if q[0].done >= int(q[0].n):
		q.pop_front()
	if station != null and q.is_empty():
		_set_light(station, false)
	inventory.refresh()
	GameState.craft_queue_changed.emit()


## 篝火燃烧时的橙光；只亮一盏、不投影，手机省性能
func _set_light(cell: Vector3i, on: bool) -> void:
	if on:
		if _lights.has(cell) and is_instance_valid(_lights[cell]):
			_lights[cell].visible = true
			return
		if looting == null or looting.world == null:
			return
		var lamp := OmniLight3D.new()
		lamp.position = station_pos(cell) + Vector3.UP * 0.4
		lamp.light_color = Color(1.0, 0.55, 0.2)
		lamp.light_energy = 1.4
		lamp.omni_range = 6.0
		lamp.shadow_enabled = false
		looting.world.add_child(lamp)
		_lights[cell] = lamp
	elif _lights.has(cell):
		if is_instance_valid(_lights[cell]):
			_lights[cell].queue_free()
		_lights.erase(cell)


## 篝火/锻造炉工作时发噪音和热量（6a 会订阅热量）
func _station_effects(cell: Vector3i, st: Dictionary, delta: float) -> void:
	var area := str(st.get("area", ""))
	if area != "campfire" and area != "forge":
		return
	st["effect_t"] = float(st.get("effect_t", 0.0)) + delta
	if st.effect_t < 1.0:
		return
	st["effect_t"] = 0.0
	var pos := station_pos(cell)
	GameState.make_noise(pos, area, 6.0)
	GameState.heat.emit(pos, 0.5 if area == "campfire" else 1.0, area)


## 放进背包，放不下的掉在脚边
func _give(id: String, count: int) -> void:
	var left := inventory.add(id, count)
	if left > 0 and looting and player_sys and player_sys.player:
		looting.spawn_loot(player_sys.player.position + Vector3(0, 0.2, 0), id, 0, left)
		hud.toast("背包满了，%s 掉在脚边" % Assets.display_name(id))


# —— 存档 ——

func save_data() -> Dictionary:
	var sq := {}
	for cell in station_queues:
		var st := station_state(cell)
		if st.is_empty():
			continue
		var q := []
		for e in station_queues[cell]:
			q.append({"key": e.key, "n": e.n, "done": e.done, "t": e.t, "fueled": bool(e.get("fueled", false))})
		sq[_cell_key(cell)] = q
	var ss := {}
	for cell in station_states:
		var st := station_state(cell)
		if st.is_empty():
			continue
		ss[_cell_key(cell)] = {"fuel": int(st.get("fuel", 0)), "tool": str(st.get("tool", ""))}
	var out_queue := []
	for e in queue:
		out_queue.append({"key": e.key, "n": e.n, "done": e.done, "t": e.t})
	return {"craft_queue": out_queue, "recipes_unlocked": unlocked.keys(), "station_queues": sq, "station_state": ss}


func load_data(d: Dictionary) -> void:
	queue.clear()
	for e in d.get("craft_queue", []):
		if e is Dictionary and recipes.has(str(e.get("key", ""))):
			queue.append({"key": str(e.key), "n": maxi(1, int(e.get("n", 1))), "done": int(e.get("done", 0)),
				"t": float(e.get("t", 0.0)), "fueled": false})
	station_queues.clear()
	station_states.clear()
	for key in d.get("station_queues", {}):
		var cell := _parse_cell(str(key))
		var q := []
		for e in d["station_queues"][key]:
			if e is Dictionary and recipes.has(str(e.get("key", ""))):
				q.append({"key": str(e.key), "n": maxi(1, int(e.get("n", 1))), "done": int(e.get("done", 0)),
					"t": float(e.get("t", 0.0)), "fueled": bool(e.get("fueled", false))})
		if not q.is_empty():
			station_queues[cell] = q
	for key in d.get("station_state", {}):
		var cell := _parse_cell(str(key))
		var st := station_state(cell)
		if st.is_empty():
			continue
		var raw: Dictionary = d["station_state"][key] if d["station_state"][key] is Dictionary else {}
		st["fuel"] = int(raw.get("fuel", 0))
		st["tool"] = str(raw.get("tool", ""))
	unlocked.clear()
	for k in d.get("recipes_unlocked", []):
		unlocked[str(k)] = true
	GameState.craft_queue_changed.emit()


func _cell_key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]


func _parse_cell(s: String) -> Vector3i:
	var p := s.split(",")
	if p.size() != 3:
		return Vector3i.ZERO
	return Vector3i(int(p[0]), int(p[1]), int(p[2]))
