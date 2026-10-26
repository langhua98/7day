class_name Sleepers
extends RefCounted
## 6d 楼里的睡眠僵尸：玩家第一次走进睡眠区才刷出来，睡着不动；
## 噪音、视线（5 米）、挨打会醒，附近 10 米内同伴 50% 一起醒；清空 3 游戏天后可再刷。

const C = preload("res://scripts/config.gd")
const PATH := "res://assets/poi/sleepers.json"
const META_KEY := "sleeper"

var main: Node3D
var world: World
var spawner: SpawnerSystem
var player_sys: PlayerSystem
var rng: RandomNumberGenerator
var data := {}
## 运行时的睡眠区：[{poi, index, key, base, rot, center, half, group, min, max, spawned, zombies, spawned_count, killed, cleared}]
var volumes: Array[Dictionary] = []
## 已清空的区域："楼名|序号" -> 清空的天数
var cleared_areas := {}
var _built := false


func setup(parent: Node3D, world_ref: World, spawner_ref: SpawnerSystem, player_ref: PlayerSystem,
		rng_ref: RandomNumberGenerator) -> void:
	main = parent
	world = world_ref
	spawner = spawner_ref
	player_sys = player_ref
	rng = rng_ref


func build() -> void:
	if FileAccess.file_exists(PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			data = parsed
	GameState.day_started.connect(_on_day_started)


func reset() -> void:
	cleared_areas.clear()
	for v in volumes:
		_clear_runtime(v)
	_built = false


func update(_delta: float) -> void:
	_ensure_volumes()
	for v in volumes:
		if bool(v.cleared):
			continue
		if bool(v.spawned):
			_check_cleared(v)
			continue
		if not _player_inside(v):
			continue
		if int(v.max) <= 0 or str(v.group) == "":
			v.cleared = true
			continue
		if spawner.alive_count() >= C.ZOMBIE_MAX:
			continue
		_spawn_volume(v)


## 这栋楼的所有睡眠区都清空了吗（给第 7 步任务用）
func cleared(poi_name: String) -> bool:
	var any := false
	for v in volumes:
		if str(v.poi) != poi_name:
			continue
		any = true
		if not cleared_areas.has(str(v.key)):
			return false
	return any


func save_data() -> Dictionary:
	return {"sleeper_cleared": cleared_areas.duplicate()}


func load_data(d: Dictionary) -> void:
	cleared_areas.clear()
	var rows = d.get("sleeper_cleared", {})
	if rows is Dictionary:
		for key in rows:
			cleared_areas[str(key)] = int(rows[key])
	for v in volumes:
		_clear_runtime(v)
		v.cleared = cleared_areas.has(str(v.key))


# —— 内部 ——

func _ensure_volumes() -> void:
	if _built:
		return
	_built = true
	volumes.clear()
	for e in world.poi_instances():
		var name := str(e.get("name", ""))
		if not data.has(name):
			continue
		var rot := float(e.get("rot", 0.0))
		var base: Vector3 = e.far.position
		var it: PoiInterior = null
		for candidate in world.interiors:
			if candidate.name == name:
				it = candidate
				break
		var rows: Array = data[name]
		for i in rows.size():
			var row: Dictionary = rows[i]
			# 方块数据坐标和碰撞格子一样：x 翻负、加上楼的 offset（家具数据已经转好，睡眠区没有）
			var center_local := Vector3(-float(row.get("x", 0.0)), float(row.get("y", 0.0)),
				float(row.get("z", 0.0)))
			if it != null:
				center_local = it.to_local(Vector3(float(row.get("x", 0.0)),
					float(row.get("y", 0.0)), float(row.get("z", 0.0))))
				base = it.origin
			var half := Vector3(float(row.get("sx", 1.0)) * 0.5, float(row.get("sy", 1.0)) * 0.5,
				float(row.get("sz", 1.0)) * 0.5)
			var key := "%s|%d" % [name, i]
			volumes.append({
				"poi": name, "index": i, "key": key, "base": base, "rot": rot,
				"center": center_local, "half": half,
				"group": str(row.get("group", "")), "min": int(row.get("min", 0)),
				"max": int(row.get("max", 0)),
				"spawned": false, "zombies": [], "spawned_count": 0, "killed": 0,
				"cleared": cleared_areas.has(key),
			})


func _clear_runtime(v: Dictionary) -> void:
	v.spawned = false
	v.zombies.clear()
	v.spawned_count = 0
	v.killed = 0


func _player_inside(v: Dictionary) -> bool:
	var p: Vector3 = player_sys.player.position
	var local: Vector3 = Basis(Vector3.UP, -float(v.rot)) * (p - Vector3(v.base))
	var c: Vector3 = v.center
	var h: Vector3 = v.half
	return absf(local.x - c.x) <= h.x + 0.6 and absf(local.z - c.z) <= h.z + 0.6 \
		and local.y >= c.y - h.y - 1.0 and local.y <= c.y + h.y + 1.0


func _spawn_volume(v: Dictionary) -> void:
	var n := rng.randi_range(int(v.min), int(v.max))
	n = mini(n, C.ZOMBIE_MAX - spawner.alive_count())
	if n <= 0:
		return
	v.spawned = true
	v.spawned_count = 0
	v.killed = 0
	v.zombies.clear()
	for i in n:
		var cls := _pick_class(str(v.group))
		if cls == "":
			break
		var st: Dictionary = Zombies.entry(cls)
		if st.is_empty():
			break
		var variant := "radiated" if bool(st.get("radiated", false)) else \
			("feral" if bool(st.get("feral", false)) else "normal")
		var at := _random_point(v)
		var z := spawner.spawn_zombie_at(cls, variant, GameState.day, GameState.is_night(), false, at)
		if z == null:
			continue
		z.brain.state = ZombieBrain.State.SLEEP
		z.brain.can_see = false
		z.set_meta(META_KEY, true)
		z.woke.connect(_on_woke)
		z.died.connect(_on_sleeper_died.bind(v))
		v.zombies.append(z)
		v.spawned_count = int(v.spawned_count) + 1
	if int(v.spawned_count) == 0:
		v.spawned = false


## 从官方刷怪组挑一个模型已下载的僵尸类；组名没有映射就退回普通刷怪组
func _pick_class(group: String) -> String:
	var entries: Array = Data.get_table("entitygroups").get(group, [])
	var classes: Array[String] = []
	var weights: Array[float] = []
	for e in entries:
		var cls := str(e.get("class", ""))
		var st: Dictionary = Zombies.entry(cls)
		if st.is_empty() or not bool(st.get("spawn", true)):
			continue
		if Assets.zombie_key(str(st.get("model", ""))) == "":
			continue
		classes.append(cls)
		weights.append(maxf(0.01, float(e.get("p", 1.0))))
	if classes.is_empty():
		return spawner.pick_class("ZombiesDowntown")
	var total := 0.0
	for w in weights:
		total += w
	var roll := rng.randf() * total
	for i in classes.size():
		roll -= weights[i]
		if roll <= 0.0:
			return classes[i]
	return classes[-1]


func _random_point(v: Dictionary) -> Vector3:
	var c: Vector3 = v.center
	var h: Vector3 = v.half
	var rot := float(v.rot)
	var base: Vector3 = v.base
	var fallback := base + Basis(Vector3.UP, rot) * c
	for i in 10:
		var local := Vector3(c.x + rng.randf_range(-h.x + 0.3, h.x - 0.3),
			c.y - h.y + 0.1, c.z + rng.randf_range(-h.z + 0.3, h.z - 0.3))
		var wp: Vector3 = base + Basis(Vector3.UP, rot) * local
		if world.solid_at(wp + Vector3.UP * 0.5) or world.blocked(wp, 0.3):
			continue
		var found := world.floor_under(wp + Vector3.UP * 0.5, 0.3)
		wp.y = found if found > wp.y - 3.0 else wp.y
		return wp
	fallback.y = maxf(fallback.y, world.floor_under(fallback + Vector3.UP * 0.5, 0.3))
	return fallback


func _check_cleared(v: Dictionary) -> void:
	var alive := 0
	for z in v.zombies:
		if is_instance_valid(z) and not z.dead:
			alive += 1
	if alive > 0:
		return
	if int(v.killed) >= int(v.spawned_count) and int(v.spawned_count) > 0:
		v.cleared = true
		cleared_areas[str(v.key)] = GameState.day
		GameState.poi_cleared.emit(str(v.poi))
	else:
		# 有僵尸被系统回收、但没清空：下次进楼重新刷
		_clear_runtime(v)


func _on_sleeper_died(_z: Zombie, v: Dictionary) -> void:
	v.killed = int(v.killed) + 1


## 一只醒了，10 米内的睡眠同伴 50% 跟着醒
func _on_woke(z: Zombie) -> void:
	for other in spawner.zombie_root.get_children():
		if other == z or not (other is Zombie) or other.dead:
			continue
		if other.brain.state != ZombieBrain.State.SLEEP:
			continue
		if other.global_position.distance_to(z.global_position) > C.SLEEP_WAKE_RADIUS:
			continue
		if rng.randf() < 0.5:
			other.wake()


func _on_day_started(day: int) -> void:
	for key in cleared_areas.keys():
		if day - int(cleared_areas[key]) < C.SLEEPER_RESPAWN_DAYS:
			continue
		cleared_areas.erase(key)
		for v in volumes:
			if str(v.key) == str(key):
				v.cleared = false
				_clear_runtime(v)
