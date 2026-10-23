class_name SpawnerSystem
extends RefCounted
## 僵尸刷新、回收、击杀统计和掉落。

const C = preload("res://scripts/config.gd")

var main: Node3D
var world: World
var player_sys: PlayerSystem
var hud: Hud
var looting: LootingSystem
var rng: RandomNumberGenerator
var zombie_root := Node3D.new()

var spawn_cd := 0.0
var _flow_t := 0.0
var kills := 0


func setup(parent: Node3D, world_ref: World, player_ref: PlayerSystem, hud_ref: Hud,
		looting_ref: LootingSystem, rng_ref: RandomNumberGenerator) -> void:
	main = parent
	world = world_ref
	player_sys = player_ref
	hud = hud_ref
	looting = looting_ref
	rng = rng_ref


func build() -> void:
	main.add_child(zombie_root)


func reset() -> void:
	for z in zombie_root.get_children():
		z.queue_free()
	spawn_cd = 6.0
	_flow_t = 0.0
	kills = 0


func update(delta: float, day: int, night: bool, horde: bool) -> void:
	_flow_t -= delta
	if _flow_t <= 0.0:
		_flow_t = 0.5
		world.update_flow(player_sys.player.position)
	var alive := 0
	for z in zombie_root.get_children():
		if z.dead:
			continue
		alive += 1
		var dmg: float = z.try_attack()
		if dmg > 0.0:
			player_sys.take_damage(dmg, "zombie", C.BLEED_CHANCE)
		# 离太远的僵尸回收掉，在身边重新刷
		if z.distance_to_target() > C.ZOMBIE_DESPAWN:
			z.queue_free()
		elif night or horde:
			z.speed = max(z.speed, (C.ZOMBIE_HORDE_SPEED if horde else C.ZOMBIE_NIGHT_SPEED) * 0.9)
	var target := 2 + day
	if night:
		target = 5 + day * 2
	if horde:
		target = C.ZOMBIE_MAX
	target = min(target, C.ZOMBIE_MAX)
	spawn_cd -= delta
	if alive < target and spawn_cd <= 0.0 and not Assets.zombie_models.is_empty():
		spawn_cd = 0.6 if horde else (2.0 if night else 5.0)
		spawn_zombie(day, night, horde)


func spawn_zombie(day: int, night: bool, horde: bool, near := Vector3.INF) -> void:
	var z := Zombie.new()
	var model: String = Assets.zombie_models[rng.randi_range(0, Assets.zombie_models.size() - 1)]
	var spd := C.ZOMBIE_HORDE_SPEED if horde else (C.ZOMBIE_NIGHT_SPEED if night else C.ZOMBIE_WALK_SPEED)
	if not z.setup(model, C.ZOMBIE_BASE_HP + C.ZOMBIE_HP_PER_DAY * (day - 1), spd, player_sys.player):
		z.free()
		return
	z.world = world
	if near != Vector3.INF:
		z.position = world.free_point(near, 4.0, 10.0)
	else:
		z.position = world.free_point(player_sys.player.position, 18.0, 32.0) if not horde else world.free_point(player_sys.player.position, 14.0, 24.0)
	z.died.connect(_on_zombie_died)
	z.screamed.connect(_on_scream)
	zombie_root.add_child(z)


func _on_zombie_died(z: Zombie) -> void:
	kills += 1
	Fx.blood_pool(main, z.global_position)
	if rng.randf() < C.ZOMBIE_DROP_CHANCE:
		looting.spawn_loot(z.global_position + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)))
	GameState.zombie_killed.emit(z, "")


## 尖叫者叫一声，附近再冒出几只僵尸
func _on_scream(z: Zombie) -> void:
	hud.toast("尖叫者在叫，附近的僵尸被引过来了！")
	var day := GameState.day
	for i in 3:
		if zombie_root.get_child_count() < C.ZOMBIE_MAX:
			spawn_zombie(day, true, false, z.global_position)


func save_data() -> Dictionary:
	return {"kills": kills}


func load_data(d: Dictionary) -> void:
	kills = int(d.get("kills", 0))
