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
## 6a：热量地图、感知轮询位置
var heat := HeatMap.new()
var _sense_i := 0


func setup(parent: Node3D, world_ref: World, player_ref: PlayerSystem, hud_ref: Hud,
		looting_ref: LootingSystem, rng_ref: RandomNumberGenerator) -> void:
	main = parent
	world = world_ref
	player_sys = player_ref
	hud = hud_ref
	looting = looting_ref
	rng = rng_ref
	if not GameState.noise.is_connected(_on_noise):
		GameState.noise.connect(_on_noise)
	heat.connect_signals()
	heat.overflow.connect(_on_heat_overflow)


func build() -> void:
	main.add_child(zombie_root)
	# 先把每种僵尸模型读一遍放进缓存：第一次刷某种僵尸要现读 glb（7~18 毫秒），跑动中会顿一下
	for m in Assets.zombie_models:
		var n := Assets.make_model(m, 0.0)
		if n:
			n.free()


func reset() -> void:
	for z in zombie_root.get_children():
		z.queue_free()
	spawn_cd = 6.0
	_flow_t = 0.0
	kills = 0
	heat.reset()


func update(delta: float, day: int, night: bool, horde: bool) -> void:
	_flow_t -= delta
	if _flow_t <= 0.0:
		_flow_t = 0.5
		world.request_flow(player_sys.player.position)
	# 距离场分几帧算，每帧最多占一点点时间，跑动时不卡
	world.flow_step(C.FLOW_BUDGET_USEC)
	var alive := 0
	for z in zombie_root.get_children():
		if z.dead:
			continue
		alive += 1
		var dmg: float = z.try_attack()
		if dmg > 0.0:
			player_sys.zombie_hit(dmg, z.type, z.big)
		# 离太远的僵尸回收掉，在身边重新刷
		if z.distance_to_target() > C.ZOMBIE_DESPAWN:
			z.queue_free()
		else:
			z.speed = speed_for(z.base_speed, night, horde)
	_sense_round()
	# 血月僵尸由 Horde 负责；普通刷新按游戏阶段
	var target := 0
	if not horde:
		var gs := GameState.gamestage()
		target = 3 + gs / 10
		if night:
			target = int(target * 1.5)
		target = mini(target, 14 if night else 10)
	spawn_cd -= delta
	if alive < target and spawn_cd <= 0.0 and not Assets.zombie_models.is_empty():
		spawn_cd = 2.0 if night else 5.0
		spawn_zombie(day, night, false)


func spawn_zombie(day: int, night: bool, horde: bool, near := Vector3.INF) -> Zombie:
	if Assets.zombie_models.is_empty():
		return null
	var group := "ZombiesNight" if night else "ZombiesDowntown"
	var cls := pick_class(group)
	if cls == "":
		return null
	var model := str(Zombies.entry(cls).get("model", ""))
	var variant := Zombies.pick_variant(model, GameState.gamestage(), rng)
	if near != Vector3.INF:
		return spawn_zombie_at(cls, variant, day, night, horde, world.free_point(near, 4.0, 10.0))
	var at := world.free_point(player_sys.player.position, 18.0, 32.0) if not horde else world.free_point(player_sys.player.position, 14.0, 24.0)
	return spawn_zombie_at(cls, variant, day, night, horde, at)


static func speed_for(base: float, night: bool, horde: bool) -> float:
	var mult := 1.0
	if horde:
		mult = C.ZOMBIE_HORDE_SPEED / C.ZOMBIE_WALK_SPEED
	elif night:
		mult = C.ZOMBIE_NIGHT_SPEED / C.ZOMBIE_WALK_SPEED
	return base * mult


## 从官方刷怪组挑一个普通僵尸类；野性/辐射由 GS 另外决定
func pick_class(group: String) -> String:
	var entries = Data.get_table("entitygroups").get(group, [])
	var classes: Array[String] = []
	var weights: Array[float] = []
	for e in entries:
		var cls := str(e.get("class", ""))
		var st: Dictionary = Zombies.entry(cls)
		if st.is_empty() or not bool(st.get("spawn", true)):
			continue
		if bool(st.get("feral", false)) or bool(st.get("radiated", false)):
			continue
		if Assets.zombie_key(str(st.get("model", ""))) == "":
			continue
		classes.append(cls)
		weights.append(maxf(0.01, float(e.get("p", 1.0))))
	if classes.is_empty():
		for m in Assets.zombie_models:
			var base: Dictionary = Zombies.base_class(m)
			if not base.is_empty() and bool(base.get("spawn", true)):
				return str(base.get("class", ""))
		return ""
	var total := 0.0
	for w in weights:
		total += w
	var roll := rng.randf() * total
	for i in classes.size():
		roll -= weights[i]
		if roll <= 0.0:
			return classes[i]
	return classes[-1]


func spawn_zombie_at(cls: String, variant: String, day: int, night: bool, horde: bool, at: Vector3) -> Zombie:
	var model := str(Zombies.entry(cls).get("model", ""))
	var st := Zombies.stats(model, variant)
	if st.is_empty() or Assets.zombie_key(model) == "":
		return null
	var z := Zombie.new()
	if not z.setup(model, st, player_sys.player):
		z.free()
		return null
	z.player_sys = player_sys
	z.speed = speed_for(z.base_speed, night, horde)
	z.world = world
	z.position = at
	z.died.connect(_on_zombie_died)
	z.screamed.connect(_on_scream)
	zombie_root.add_child(z)
	return z


func alive_count() -> int:
	var n := 0
	for z in zombie_root.get_children():
		if not z.dead:
			n += 1
	return n


func horde_alive() -> int:
	var n := 0
	for z in zombie_root.get_children():
		if not z.dead and z.get_meta("horde", false):
			n += 1
	return n


func _on_zombie_died(z: Zombie) -> void:
	kills += 1
	Fx.blood_pool(main, z.global_position)
	if rng.randf() < C.ZOMBIE_DROP_CHANCE:
		looting.spawn_loot(z.global_position + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)))
	GameState.zombie_killed.emit(z, "")


## AI 预算：每帧轮流给最多 AI_SENSE_PER_FRAME 只僵尸做视觉判断
func _sense_round() -> void:
	var n := zombie_root.get_child_count()
	if n == 0:
		return
	var budget := mini(C.AI_SENSE_PER_FRAME, n)
	for i in budget:
		_sense_i = (_sense_i + 1) % n
		var z = zombie_root.get_child(_sense_i)
		if not z.dead:
			z.brain.sense(z, z.target, world)


## 噪音：半径内的僵尸走过去查看
func _on_noise(pos: Vector3, radius: float, _kind: String) -> void:
	var r2 := radius * radius
	for z in zombie_root.get_children():
		if z.dead:
			continue
		var d: Vector3 = z.global_position - pos
		d.y = 0.0
		if d.length_squared() <= r2:
			z.brain.hear(pos, _kind)


## 热量满了：在那一格附近刷一只尖叫者，走过来查看
func _on_heat_overflow(center: Vector3) -> void:
	if Assets.zombie_models.is_empty() or zombie_root.get_child_count() >= C.ZOMBIE_MAX:
		return
	var rows: Dictionary = Zombies.table()
	var cls := ""
	for c in rows:
		var e: Dictionary = rows[c]
		if str(e.get("model", "")) == "screamer" and bool(e.get("spawn", true)) \
				and not bool(e.get("feral", false)) and not bool(e.get("radiated", false)):
			cls = str(e.get("class", ""))
			break
	if cls == "":
		return
	var z := spawn_zombie_at(cls, "normal", GameState.day, GameState.is_night(), false, world.free_point(center, 18.0, 30.0))
	if z:
		z.brain.investigate(center)
		hud.toast("这里动静太大，引来了尖叫者！")


## 尖叫者叫一声，附近再冒出几只僵尸
func _on_scream(z: Zombie) -> void:
	hud.toast("尖叫者在叫，附近的僵尸被引过来了！")
	var day := GameState.day
	for i in 3:
		if zombie_root.get_child_count() < C.ZOMBIE_MAX:
			var nz := spawn_zombie(day, true, false, z.global_position)
			if nz:
				nz.brain.chase()


func save_data() -> Dictionary:
	return {"kills": kills, "heat": heat.save_data()}


func load_data(d: Dictionary) -> void:
	kills = int(d.get("kills", 0))
	heat.load_data(d.get("heat", {}))
