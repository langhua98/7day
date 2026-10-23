class_name SaveGame
extends RefCounted
## 集中存档：每 30 秒、切后台、回标题、开局时保存；读档时恢复各系统。

const SAVE_PATH := "user://save.json"

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


static func read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return d if d is Dictionary else {}


func reset_timer() -> void:
	_save_t = 0.0


func update(delta: float) -> void:
	_save_t += delta
	if _save_t > 30.0:
		_save_t = 0.0
		save()


func save() -> void:
	var searched := []
	for i in world.containers.size():
		if world.containers[i].searched:
			searched.append(i)
	var d := {
		"version": 2,
		"seed": main.world_seed,
		"searched": searched,
		"blocks": world.voxel_save(),
	}
	d.merge(time_sys.save_data())
	d.merge(player_sys.save_data())
	d.merge(Status.save_data())
	d.merge(horde.save_data())
	d.merge(inventory.save_data())
	d.merge(main.looting.save_data())
	d.merge(main.respawn.save_data())
	d["kills"] = spawner.kills
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.close()


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func continue_game() -> void:
	var d := read_save()
	if not d.has("hours"):
		main.start()
		return
	main.start(false)
	time_sys.load_data(d)
	for i in d.get("searched", []):
		if int(i) < world.containers.size():
			world.containers[int(i)].searched = true
	world.voxel_load(d.get("blocks", []))
	main.looting.load_data(d)
	main.respawn.load_data(d)
	player_sys.load_data(d)
	Status.load_data(d, time_sys.seconds_per_hour())
	inventory.load_data(d)
	spawner.load_data(d)
	horde.load_data(d)
	atmosphere.set_night_announced(time_sys.day, fmod(time_sys.hours, 24.0))
	atmosphere.update_sky(time_sys.hours)
	hud.toast("继续第 %d 天" % time_sys.day)
