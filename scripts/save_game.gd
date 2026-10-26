class_name SaveGame
extends RefCounted
## 集中存档：每 30 秒、切后台、回标题、开局时保存；读档时恢复各系统。

const SAVE_PATH := "user://save.json"
const BACKUP_PATH := "user://save.bak"
## 存档版本：3 = PR #20–#50 之后的字段（耐久、载具、容器天数/血量、采集等）
const SAVE_VERSION := 3

var main: Node3D
var world: World
var player_sys: PlayerSystem
var inventory: InventorySystem
var combat: CombatSystem
var spawner: SpawnerSystem
var horde: Horde
var atmosphere: Atmosphere
var hud: Hud
var time_sys: TimeOfDay
var _save_t := 0.0
## 后台写存档的任务（-1 = 没有）。测试模式背包里东西多，存档转成文字要 20 多毫秒，
## 放在主线程做会让画面每 30 秒顿一下
var _write_task := -1


func setup(parent: Node3D, world_ref: World, player_ref: PlayerSystem, inv_ref: InventorySystem,
		combat_ref: CombatSystem, spawner_ref: SpawnerSystem, horde_ref: Horde,
		atmosphere_ref: Atmosphere, hud_ref: Hud, time_ref: TimeOfDay) -> void:
	main = parent
	world = world_ref
	player_sys = player_ref
	inventory = inv_ref
	combat = combat_ref
	spawner = spawner_ref
	horde = horde_ref
	atmosphere = atmosphere_ref
	hud = hud_ref
	time_sys = time_ref


static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	var d = json.data
	return d if d is Dictionary else {}


static func read_save_from(path: String, backup_path: String) -> Dictionary:
	var d := read_file(path)
	if not d.is_empty():
		return d
	return read_file(backup_path)


static func read_save() -> Dictionary:
	return read_save_from(SAVE_PATH, BACKUP_PATH)


## 按版本逐级迁移旧档：只补字段和默认值，不动旧数据
static func migrate(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	var version := int(out.get("version", 1))
	if version < 2:
		if not (out.get("bag") is Array):
			out["bag"] = []
		if not (out.get("bag_cap") is int or out.get("bag_cap") is float):
			out["bag_cap"] = 45
		for key in ["inventory", "mags", "mags_type", "ammo_choice", "gun_scopes", "qualities", "container_items"]:
			if not (out.get(key) is Dictionary):
				out[key] = {}
		for key in ["order", "searched", "blocks", "doors"]:
			if not (out.get(key) is Array):
				out[key] = []
		if not (out.get("equipped") is String):
			out["equipped"] = ""
		version = 2
	if version < 3:
		for key in ["durabilities", "container_days", "container_hp", "status", "heat",
				"station_queues", "station_state"]:
			if not (out.get(key) is Dictionary):
				out[key] = {}
		for key in ["vehicles", "harvest_dead", "crates", "corpse_bags", "craft_queue", "recipes_unlocked"]:
			if not (out.get(key) is Array):
				out[key] = []
		var defaults := {"horde_started": false, "horde_remaining": 0, "horde_spawned": 0,
			"days_alive_lost": 0, "blood_moons_survived": 0, "kills": 0}
		for key in defaults:
			if not out.has(key):
				out[key] = defaults[key]
		version = 3
	out["version"] = version
	return out


func reset_timer() -> void:
	_save_t = 0.0


func update(delta: float) -> void:
	_save_t += delta
	if _save_t > 30.0:
		_save_t = 0.0
		save(true)


## background = true：数据在这一帧收好，转文字和写文件放到后台线程（定时自动存档用）。
## 切后台、回标题、死亡这些时候用默认的立刻写完，免得 App 被挂起时还没写进去。
func save(background := false) -> void:
	var searched := []
	for i in world.containers.size():
		if world.containers[i].searched:
			searched.append(i)
	var d := {
		"version": SAVE_VERSION,
		"seed": main.world_seed,
		"searched": searched,
		"blocks": world.voxel_save(),
		"doors": world.door_save(),
	}
	d.merge(time_sys.save_data())
	d.merge(player_sys.save_data())
	d.merge(Progression.save_data())
	d.merge(Books.save_data())
	d.merge(Status.save_data())
	d.merge(horde.save_data())
	d.merge(inventory.save_data())
	d.merge(main.looting.save_data())
	d.merge(world.harvest_save())
	d.merge(main.respawn.save_data())
	d.merge(main.crafting.save_data())
	d.merge(main.vehicles.save_data())
	d.merge(main.sleepers.save_data())
	d.merge(main.trader.save_data())
	d.merge(main.quests.save_data())
	d.merge(spawner.save_data())
	wait_pending()
	if background:
		# 深拷贝一份：后台转文字时游戏还在改背包等数据
		_write_task = WorkerThreadPool.add_task(_write.bind(d.duplicate(true)), false, "save")
	else:
		_write(d)


## 等后台那次写完（再写或删存档前调用，免得旧数据后写完把新的盖掉）
func wait_pending() -> void:
	if _write_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_write_task)
		_write_task = -1


static func write_to(path: String, backup_path: String, d: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d))
	f.flush()
	var write_err := f.get_error()
	f.close()
	if write_err != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return false
	if FileAccess.file_exists(path) and backup_path != "":
		_copy_file(path, backup_path)
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	if FileAccess.file_exists(path):
		dir.remove(path.get_file())
	var err := dir.rename(tmp.get_file(), path.get_file())
	if err != OK:
		if FileAccess.file_exists(tmp):
			dir.remove(tmp.get_file())
		if backup_path != "" and FileAccess.file_exists(backup_path):
			_copy_file(backup_path, path)
		return false
	return true


static func _copy_file(from: String, to: String) -> bool:
	if not FileAccess.file_exists(from):
		return false
	var data := FileAccess.get_file_as_bytes(from)
	var f := FileAccess.open(to, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(data)
	f.flush()
	var err := f.get_error()
	f.close()
	return err == OK


static func _write(d: Dictionary) -> void:
	write_to(SAVE_PATH, BACKUP_PATH, d)


func delete_save() -> void:
	wait_pending()
	for p in [SAVE_PATH, BACKUP_PATH, SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func continue_game() -> void:
	var d := read_save()
	if not d.has("hours"):
		main.start()
		return
	d = migrate(d)
	main.start(false)
	time_sys.load_data(d)
	for i in d.get("searched", []):
		if int(i) < world.containers.size():
			world.containers[int(i)].searched = true
	world.voxel_load(d.get("blocks", []))
	world.door_load(d.get("doors", []))
	main.looting.load_data(d)
	world.harvest_load(d.get("harvest_dead", []))
	main.respawn.load_data(d)
	player_sys.load_data(d)
	Status.load_data(d, time_sys.seconds_per_hour())
	Progression.load_data(d)
	Books.load_data(d)
	inventory.load_data(d)
	main.crafting.load_data(d)
	main.vehicles.load_data(d)
	main.sleepers.load_data(d)
	main.trader.load_data(d)
	main.quests.load_data(d)
	spawner.load_data(d)
	horde.load_data(d)
	atmosphere.set_night_announced(time_sys.day, fmod(time_sys.hours, 24.0))
	atmosphere.update_sky(time_sys.hours)
	hud.toast("继续第 %d 天" % time_sys.day)
