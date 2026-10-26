class_name QuestSystem
extends RefCounted
## 7d 商人任务：取货、清剿、挖宝。一次只能接一个，3 天换 5 个。

const C = preload("res://scripts/config.gd")
const KINDS := ["fetch", "clear", "buried"]
const TALK_RADIUS := 4.5
const FETCH_RADIUS := 3.0
const DIG_RADIUS := 2.5

var main: Node3D
var world: World
var trader: TraderSystem
var sleepers: Sleepers
var player_sys: PlayerSystem
var inventory: InventorySystem
var hud: Hud
var rng: RandomNumberGenerator
var data := {}
var offers: Array[Dictionary] = []
var active := {}
var completed := 0
var next_day := 1
var _crate: Node3D
var _dig_marker: Node3D


func setup(parent: Node3D, world_ref: World, trader_ref: TraderSystem, sleeper_ref: Sleepers,
		player_ref: PlayerSystem, inv_ref: InventorySystem, hud_ref: Hud, rng_ref: RandomNumberGenerator) -> void:
	main = parent
	world = world_ref
	trader = trader_ref
	sleepers = sleeper_ref
	player_sys = player_ref
	inventory = inv_ref
	hud = hud_ref
	rng = rng_ref


func build() -> void:
	data = Data.get_table("quests")
	reset()


func reset() -> void:
	_clear_visuals()
	offers.clear()
	active.clear()
	completed = 0
	next_day = GameState.day + 3
	_refresh_offers()
	hud.set_quest_line("")


func update(_delta: float) -> void:
	if GameState.day >= next_day:
		next_day = GameState.day + 3
		_refresh_offers()
		hud.toast("商人的任务换了")
	if active.is_empty():
		hud.set_quest_line("")
		return
	if str(active.get("state", "")) == "go" and str(active.get("kind", "")) == "clear":
		if sleepers.cleared(str(active.get("poi", ""))):
			active.state = "return"
			hud.toast("清剿完成，回商人交任务")
	if _dig_marker:
		_dig_marker.visible = _dig_marker.global_position.distance_to(player_sys.player.position) <= 10.0
	hud.set_quest_line(_line())


func _line() -> String:
	if active.is_empty():
		return ""
	var n := str(active.get("name", "任务"))
	var st := str(active.get("state", "go"))
	if st == "reward":
		return "%s：选一件奖励" % n
	if st == "return":
		return "%s：回商人交任务" % n
	match str(active.get("kind", "")):
		"fetch":
			return "%s：去 %s 拿补给" % [n, _poi_label()]
		"clear":
			return "%s：清剿 %s 的睡眠僵尸" % [n, _poi_label()]
		"buried":
			return "%s：按指南针找到埋藏点，挖 5 下（%d/5）" % [n, int(active.get("progress", 0))]
	return n


func _poi_label() -> String:
	var poi := str(active.get("poi", ""))
	return poi if poi != "" else "目标"


func _refresh_offers() -> void:
	offers.clear()
	var tier := 2 if completed >= 10 else 1
	var tier_data: Dictionary = data.get("tier%d" % tier, {})
	var pois := world.poi_instances()
	for i in 5:
		var kind: String = KINDS[rng.randi_range(0, KINDS.size() - 1)]
		var poi := ""
		var target := Vector3.ZERO
		if kind == "buried":
			target = world.free_point(trader.site, 100.0, 220.0)
			target.y = 0.0
		else:
			var candidates := []
			for e in pois:
				if kind == "clear" and not sleepers.data.has(str(e.get("name", ""))):
					continue
				candidates.append(e)
			if candidates.is_empty():
				kind = "buried"
				target = world.free_point(trader.site, 100.0, 220.0)
				target.y = 0.0
			else:
				var e: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
				poi = str(e.get("name", ""))
				target = _poi_target(e)
		var def: Dictionary = tier_data.get(kind, {})
		var choices := _reward_choices(tier)
		offers.append({
			"kind": kind, "tier": tier, "poi": poi, "target": target,
			"name": str(def.get("name", kind)), "desc": str(def.get("desc", "")).replace("{poi.name}", poi),
			"xp": int(def.get("xp", 1000)), "coins": int(def.get("coins", 100)),
			"choices": choices, "state": "offer", "progress": 0,
		})


func _poi_target(e: Dictionary) -> Vector3:
	var name := str(e.get("name", ""))
	if sleepers.volumes.is_empty():
		sleepers._ensure_volumes()
	for v in sleepers.volumes:
		if str(v.poi) != name:
			continue
		var p: Vector3 = v.base + Basis(Vector3.UP, float(v.rot)) * Vector3(v.center)
		p.y = world.floor_under(p + Vector3.UP * 0.5, 0.3)
		return p
	var far: Vector3 = e.far.position
	return far + Vector3(8.0, 0.0, 8.0)


func _reward_choices(tier: int) -> Array:
	var pool := []
	for id in Assets.items_by_id:
		var kind: int = Assets.items_by_id[id].kind
		if kind in [Assets.Kind.OTHER, Assets.Kind.BLOCK, Assets.Kind.ATTACHMENT, Assets.Kind.VEHICLE]:
			continue
		if int(Data.items.get(id, {}).get("value", 0)) <= 0:
			continue
		pool.append(id)
	var out := []
	for i in 3:
		if pool.is_empty():
			break
		var idx := rng.randi_range(0, pool.size() - 1)
		out.append(str(pool[idx]))
		pool.remove_at(idx)
	return out


func accept(index: int) -> bool:
	if index < 0 or index >= offers.size() or not active.is_empty():
		return false
	active = offers[index].duplicate(true)
	offers.remove_at(index)
	active["state"] = "go"
	active["progress"] = 0
	var kind := str(active.kind)
	if kind == "fetch":
		_crate = _make_crate(active.target)
	elif kind == "buried":
		_dig_marker = _make_marker(active.target)
	elif kind == "clear":
		sleepers.reset_poi(str(active.get("poi", "")))
		hud.toast("去了先清楼里的睡眠僵尸")
	return true


func abandon() -> void:
	if active.is_empty():
		return
	_clear_visuals()
	active.clear()
	hud.toast("任务已放弃")
	hud.set_quest_line("")


func interact_label(p: Vector3) -> String:
	if active.is_empty() or str(active.get("state", "")) != "go":
		return ""
	match str(active.get("kind", "")):
		"fetch":
			if _crate and _crate.global_position.distance_to(p) <= FETCH_RADIUS:
				return "拿取\n补给箱"
		"buried":
			if _dig_marker and _dig_marker.global_position.distance_to(p) <= 10.0:
				return "挖宝\n%d/5" % int(active.get("progress", 0))
	return ""


func interact(p: Vector3) -> bool:
	if active.is_empty() or str(active.get("state", "")) != "go":
		return false
	match str(active.get("kind", "")):
		"fetch":
			if _crate and _crate.global_position.distance_to(p) <= FETCH_RADIUS:
				active.state = "return"
				_clear_visuals()
				hud.toast("拿到补给了，回商人交任务")
				return true
		"buried":
			if _dig_marker and _dig_marker.global_position.distance_to(p) <= DIG_RADIUS:
				active.progress = int(active.get("progress", 0)) + 1
				if int(active.progress) >= 5:
					active.state = "return"
					_clear_visuals()
					hud.toast("挖到了补给，回商人交任务")
				else:
					hud.toast("挖 %d/5" % int(active.progress))
				return true
	return false


func can_turn_in(p: Vector3) -> bool:
	return not active.is_empty() and str(active.get("state", "")) == "return" \
		and trader.is_near(p, TALK_RADIUS)


func turn_in() -> bool:
	if not can_turn_in(player_sys.player.position):
		return false
	active.state = "reward"
	hud.toast("选一件奖励")
	return true


func choose_reward(id: String) -> bool:
	if active.is_empty() or str(active.get("state", "")) != "reward":
		return false
	var choices: Array = active.get("choices", [])
	if not choices.has(id):
		return false
	inventory.add(id, 1)
	inventory.add(trader.currency(), int(active.get("coins", 0)))
	Progression.add_xp(float(active.get("xp", 0)), "quest")
	completed += 1
	active.clear()
	hud.toast("任务完成，奖励已到手")
	return true


func _make_crate(pos: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.position = pos
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.8, 0.6, 0.8)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.38, 0.18)
	mi.material_override = mat
	mi.position.y = 0.3
	holder.add_child(mi)
	var label := Label3D.new()
	label.text = "补给"
	label.font_size = 48
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 1.0
	holder.add_child(label)
	main.add_child(holder)
	return holder


func _make_marker(pos: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.position = pos
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.6
	mesh.bottom_radius = 0.8
	mesh.height = 0.15
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.45, 0.25)
	mi.material_override = mat
	holder.add_child(mi)
	var label := Label3D.new()
	label.text = "挖"
	label.font_size = 48
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 0.8
	holder.add_child(label)
	holder.visible = true
	main.add_child(holder)
	return holder


func _clear_visuals() -> void:
	if _crate and is_instance_valid(_crate):
		_crate.queue_free()
	_crate = null
	if _dig_marker and is_instance_valid(_dig_marker):
		_dig_marker.queue_free()
	_dig_marker = null


func save_data() -> Dictionary:
	return {
		"quests": {
			"offers": _pack(offers), "active": _pack_one(active), "completed": completed,
			"next_day": next_day,
		},
	}


func load_data(d: Dictionary) -> void:
	var q = d.get("quests", {})
	if not (q is Dictionary):
		return
	_clear_visuals()
	offers.clear()
	for e in q.get("offers", []):
		if e is Dictionary:
			offers.append(_unpack(e))
	active = _unpack(q.get("active", {})) if q.get("active", {}) is Dictionary else {}
	if not active.is_empty():
		active.state = str(active.get("state", "go"))
		if str(active.kind) == "fetch":
			_crate = _make_crate(active.target)
		elif str(active.kind) == "buried":
			_dig_marker = _make_marker(active.target)
	completed = int(q.get("completed", 0))
	next_day = maxi(GameState.day, int(q.get("next_day", GameState.day + 3)))


func _pack(list: Array) -> Array:
	var out := []
	for e in list:
		out.append(_pack_one(e))
	return out


func _pack_one(e: Dictionary) -> Dictionary:
	if e.is_empty():
		return {}
	var d := e.duplicate(true)
	if d.get("target") is Vector3:
		d.target = [d.target.x, d.target.y, d.target.z]
	return d


func _unpack(e: Dictionary) -> Dictionary:
	if not (e is Dictionary) or e.is_empty():
		return {}
	var d := e.duplicate(true)
	var t = d.get("target")
	if t is Array and t.size() >= 3:
		d.target = Vector3(float(t[0]), float(t[1]), float(t[2]))
	return d
