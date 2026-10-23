class_name Horde
extends RefCounted
## 血月尸潮：按官方 gamestages.xml 选择阶段，控制总数、同时上限和批次。
## 普通刷怪由 SpawnerSystem 负责；血月期间 Spawner 不刷普通僵尸。

const C = preload("res://scripts/config.gd")

var main: Node3D
var spawner: SpawnerSystem
var world: World
var player_sys: PlayerSystem
var time_sys: TimeOfDay
var rng: RandomNumberGenerator

var started := false
var active := false
var stage_number := 0
var remaining := 0
var spawned := 0
var max_alive := 8
var interval := 5.0
var _timer := 0.0
var _pool: Array = []
var _stage: Dictionary = {}


func setup(parent: Node3D, spawner_ref: SpawnerSystem, world_ref: World, player_ref: PlayerSystem,
		time_ref: TimeOfDay, rng_ref: RandomNumberGenerator) -> void:
	main = parent
	spawner = spawner_ref
	world = world_ref
	player_sys = player_ref
	time_sys = time_ref
	rng = rng_ref


func reset() -> void:
	started = false
	active = false
	stage_number = 0
	remaining = 0
	spawned = 0
	max_alive = 8
	interval = 5.0
	_timer = 0.0
	_pool.clear()
	_stage = {}


func update(delta: float, blood_moon: bool, day: int) -> void:
	if blood_moon and not started:
		start()
	elif not blood_moon and started:
		end()
	if not started:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	var alive := spawner.horde_alive()
	if remaining > 0:
		if alive < max_alive:
			var batch := mini(max_alive - alive, remaining)
			for i in batch:
				if not _spawn(day):
					break
				remaining -= 1
				spawned += 1
			_timer = interval
		else:
			_timer = 0.5
	elif alive < 1:
		# 官方最后阶段：04:00 前一直留 1 只骚扰
		_spawn(day)
		_timer = 5.0
	else:
		_timer = 1.0


func start() -> void:
	var table = Data.get_table("gamestages").get("BloodMoonHorde", [])
	if not (table is Array) or table.is_empty():
		return
	var gs := GameState.gamestage()
	_stage = _select_stage(table, gs)
	stage_number = int(_stage.get("stage", 1))
	var total := 0
	for s in _stage.get("spawns", []):
		if int(s.get("num", 1)) < 999:
			total += int(s.get("num", 1))
	remaining = maxi(1, int(total * C.HORDE_COUNT_MULT))
	max_alive = mini(8 + 2 * (time_sys.blood_moons_survived + 1), C.HORDE_MAX_ALIVE)
	interval = 5.0
	for s in _stage.get("spawns", []):
		if float(s.get("interval", 0.0)) > 0.0:
			interval = float(s.get("interval", 5.0))
			break
	_pool = _build_pool(_stage)
	if _pool.is_empty():
		for id in Assets.zombie_models:
			_pool.append({"id": id, "p": 1.0})
	started = true
	active = true
	_timer = 0.0


func end() -> void:
	started = false
	active = false
	remaining = 0
	if spawner == null:
		return
	for z in spawner.zombie_root.get_children():
		if z.get_meta("horde", false):
			z.set_meta("horde", false)


func plan() -> Dictionary:
	return {"stage": stage_number, "total": remaining + spawned, "remaining": remaining,
		"max_alive": max_alive, "interval": interval, "pool": _pool.size()}


func _select_stage(table: Array, gs: int) -> Dictionary:
	var chosen: Dictionary = table[0]
	for stage in table:
		if int(stage.get("stage", 1)) <= gs:
			chosen = stage
		else:
			break
	return chosen


func _build_pool(stage: Dictionary) -> Array:
	var groups := Data.get_table("entitygroups")
	var pool := []
	for s in stage.get("spawns", []):
		var entries = groups.get(s.get("group", ""), [])
		for e in entries:
			var id: String = e.get("id", "")
			if id != "" and Assets.zombie_models.has(id):
				pool.append({"id": id, "p": maxf(0.01, float(e.get("p", 1.0)))})
	return pool


func _spawn(day: int) -> bool:
	if _pool.is_empty():
		return false
	var total := 0.0
	for e in _pool:
		total += float(e.get("p", 1.0))
	var roll := rng.randf() * total
	var model: String = _pool[0].get("id", "")
	for e in _pool:
		roll -= float(e.get("p", 1.0))
		if roll <= 0.0:
			model = e.get("id", "")
			break
	var base := player_sys.player.global_position
	var at := world.free_point(base, 35.0, 50.0)
	for i in 12:
		var p := world.free_point(base, 35.0, 50.0)
		# 看不见的位置：玩家眼睛到刷新点的线被楼/车挡住
		if world.line_blocked(base + Vector3.UP * 1.6, p + Vector3.UP * 1.2):
			at = p
			break
	var z = spawner.spawn_zombie_at(model, day, true, true, at)
	if z == null:
		return false
	z.set_meta("horde", true)
	return true


func save_data() -> Dictionary:
	return {"horde_started": started, "horde_remaining": remaining, "horde_spawned": spawned}


func load_data(d: Dictionary) -> void:
	if not bool(d.get("horde_started", false)):
		return
	start()
	remaining = int(d.get("horde_remaining", remaining))
	spawned = int(d.get("horde_spawned", spawned))
