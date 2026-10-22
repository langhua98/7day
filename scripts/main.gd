extends Node3D
## 游戏主逻辑：世界、昼夜、玩家（走、冲刺、跳）、战斗（枪、近战）、僵尸、物品、背包、生存、音乐和音效。

const C = preload("res://scripts/config.gd")

var player := Node3D.new()
var camera := Camera3D.new()
var arms: FpArms
var hud: Hud
var world: World
var music: MusicDirector
var sfx: Sfx
var sun := DirectionalLight3D.new()
var env := Environment.new()
var sky_mat := ProceduralSkyMaterial.new()
var zombie_root := Node3D.new()
var loot_root := Node3D.new()
var fx_root := Node3D.new()
var rng := RandomNumberGenerator.new()

var running := false
var game_hours := C.START_HOUR   # 从第 1 天 0 点起算的小时数
var hp := C.MAX_HP
var food := C.MAX_FOOD
var water := C.MAX_WATER
var stamina := C.MAX_STAMINA
var kills := 0
var headshots := 0
var yaw := 0.0
var pitch := 0.0
var attack_cd := 0.0
var spawn_cd := 0.0
var inventory := {}          # id -> 数量
var pickup_order: Array[String] = []
var equipped := ""
## 每把枪弹匣里还剩几发；身上每种口径的备弹
var mags := {}
var ammo := {}
## 流血剩余秒数；感染程度 0~100
var bleeding := 0.0
var infection := 0.0
var _horde_announced := false
## 正在翻的容器（空字典表示没在翻）、翻了多久、开始翻时站的位置
var _search := {}
var _search_t := 0.0
var _search_from := Vector3.ZERO
var _label_font: SystemFont
var _keys := {}
var _night_announced := -1
var _vy := 0.0
var _on_ground := true
var _exhausted := false
var _sprinting := false
var _step_dist := 0.0
var _reload_t := 0.0
var _reload_id := ""
var _melee_t := -1.0
var _spread := 0.0
var _shake := 0.0
var _nav_t := 0.0
var _dry_t := 0.0
var _heart_t := 0.0
var _spits: Array[Dictionary] = []
var _blood_pools: Array[Node3D] = []
var _blood_mesh: SphereMesh
var _blood_mat: StandardMaterial3D
var _pool_mat: StandardMaterial3D
var _tracer_mat: StandardMaterial3D


func _ready() -> void:
	rng.randomize()
	_setup_buses()
	_build_world()
	_build_player()
	music = MusicDirector.new()
	add_child(music)
	sfx = Sfx.new()
	add_child(sfx)
	hud = Hud.new()
	add_child(hud)
	hud.start_pressed.connect(_start)
	hud.restart_pressed.connect(_start)
	hud.item_used.connect(_use_item)
	hud.action_pressed.connect(_action)
	hud.reload_pressed.connect(_start_reload)
	hud.settings_changed.connect(_apply_settings)
	_apply_settings()
	var info := "素材：物品 %d 个（武器、食物、药品等 %d 个可拾取），僵尸 %d 种，音乐 %d 段" % [
		Assets.items.size(), _count_loot(), Assets.zombie_models.size(),
		Assets.music.values().reduce(func(a, l): return a + l.size(), 0)]
	if not Assets.errors.is_empty():
		info += "\n注意：" + "；".join(Assets.errors)
	hud.set_start_info(info)
	_update_sky()


func _count_loot() -> int:
	var n := 0
	for k in Assets.loot_pool:
		n += Assets.loot_pool[k].size()
	return n


## 音乐、音效各一条总线，暂停菜单里分别调音量
func _setup_buses() -> void:
	for name in ["Music", "Sfx"]:
		if AudioServer.get_bus_index(name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")


func _apply_settings() -> void:
	for pair in [["Music", hud.settings.music], ["Sfx", hud.settings.sfx]]:
		var i := AudioServer.get_bus_index(pair[0])
		AudioServer.set_bus_volume_db(i, linear_to_db(max(0.001, pair[1])))
		AudioServer.set_bus_mute(i, pair[1] <= 0.01)


# —— 世界 ——

func _build_world() -> void:
	var we := WorldEnvironment.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_density = 0.018
	env.fog_sky_affect = 0.6
	we.environment = env
	add_child(we)

	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	world = World.new()
	add_child(world)
	world.build(rng.randi())
	add_child(zombie_root)
	add_child(loot_root)
	add_child(fx_root)

	_blood_mesh = SphereMesh.new()
	_blood_mesh.radius = 0.025
	_blood_mesh.height = 0.05
	_blood_mesh.radial_segments = 6
	_blood_mesh.rings = 3
	_blood_mat = StandardMaterial3D.new()
	_blood_mat.albedo_color = Color(0.45, 0.02, 0.02)
	_blood_mat.roughness = 0.3
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tracer_mat.albedo_color = Color(1.0, 0.85, 0.5, 0.55)
	# 地上的血泊：有血迹贴花就用，没有就画一个暗红的圆
	_pool_mat = StandardMaterial3D.new()
	_pool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pool_mat.roughness = 0.4
	var decal := world.blood_decal()
	if decal != "":
		_pool_mat.albedo_texture = load(decal)
	else:
		var g := Gradient.new()
		g.set_color(0, Color(0.35, 0.0, 0.0, 0.95))
		g.set_color(1, Color(0.3, 0.0, 0.0, 0.0))
		g.set_offset(0, 0.6)
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_pool_mat.albedo_texture = t


func _build_player() -> void:
	player.name = "Player"
	add_child(player)
	camera.position.y = C.PLAYER_EYE_HEIGHT
	camera.near = 0.03
	camera.far = 260.0
	camera.fov = 70.0
	player.add_child(camera)
	arms = FpArms.new()
	camera.add_child(arms)


# —— 开局 / 结束 ——

func _start() -> void:
	for z in zombie_root.get_children():
		z.queue_free()
	for l in loot_root.get_children():
		l.queue_free()
	for f in fx_root.get_children():
		f.queue_free()
	_spits.clear()
	_blood_pools.clear()
	game_hours = C.START_HOUR
	hp = C.MAX_HP
	food = C.MAX_FOOD
	water = C.MAX_WATER
	stamina = C.MAX_STAMINA
	bleeding = 0.0
	infection = 0.0
	kills = 0
	headshots = 0
	inventory.clear()
	pickup_order.clear()
	mags.clear()
	ammo.clear()
	equipped = ""
	arms.hold("")
	_reload_t = 0.0
	_melee_t = -1.0
	_horde_announced = false
	_night_announced = -1
	player.position = Vector3.ZERO
	_vy = 0.0
	_on_ground = true
	yaw = 0.0
	pitch = 0.0
	spawn_cd = 6.0
	_nav_t = 0.0
	for c in world.containers:
		c.searched = false
	_search = {}
	hud.set_progress(-1.0)
	for i in C.LOOT_COUNT / 2:
		_spawn_loot(world.free_point(Vector3.ZERO, 4.0, 60.0))
	# 开局在面前放一件近战武器，马上就能看到手里的模型
	var weapons: Array = Assets.loot_pool.get(Assets.Kind.MELEE, [])
	if not weapons.is_empty():
		var with_model := weapons.filter(func(id): return Assets.items_by_id[id].model != "")
		var pick: String = (with_model if not with_model.is_empty() else weapons).pick_random()
		_spawn_loot(Vector3(0, 0, -3.0), pick)
	running = true
	hud.set_banner("")
	_refresh_inventory()
	hud.toast("第 1 天。找武器、找吃的喝的，天黑前做好准备。")


func _end(win: bool) -> void:
	running = false
	music.request("Exp" if win else "Sus", 99.0)
	var day := int(game_hours / 24.0) + 1
	var stats := "击杀 %d 只僵尸，爆头 %d 次" % [kills, headshots]
	if win:
		hud.show_end("你活过了第七天的血月！\n" + stats)
	else:
		hud.show_end("你死在了第 %d 天 %02d:00\n%s" % [day, int(fmod(game_hours, 24.0)), stats])


# —— 每帧 ——

func _process(delta: float) -> void:
	if not running:
		_update_sky()
		return
	game_hours += delta * 24.0 / C.DAY_SECONDS
	var day := int(game_hours / 24.0) + 1
	var hour := fmod(game_hours, 24.0)
	var night := hour >= C.NIGHT_START or hour < C.NIGHT_END
	var horde := (day == C.HORDE_DAY and hour >= C.NIGHT_START) or (day == C.HORDE_DAY + 1 and hour < C.NIGHT_END)
	if day > C.HORDE_DAY and hour >= C.NIGHT_END:
		_end(true)
		return

	_update_player(delta)
	_update_weapon(delta)
	_update_sky()
	_update_zombies(delta, day, night, horde)
	_update_spits(delta)
	_update_loot(delta)
	_update_action(delta)
	_update_survival(delta)
	_update_music(delta, night, horde)
	_update_banner(day, hour, night, horde)

	var near := 0
	for z in zombie_root.get_children():
		if not z.dead and z.distance_to_target() < C.TENSION_DISTANCE:
			near += 1
	hud.set_status(day, hour, kills, near, night)
	hud.set_vitals(hp, food, water, stamina, _effects_text())
	var home := Vector2(-player.position.x, -player.position.z)
	hud.set_compass(-yaw, atan2(home.x, -home.y) if home.length() > 12.0 else NAN)
	if hp <= 0.0:
		_end(false)


func _key(k: Key) -> bool:
	return Input.is_physical_key_pressed(k)


## 按下的那一帧
func _key_hit(k: Key) -> bool:
	var down := _key(k)
	var hit: bool = down and not _keys.get(k, false)
	_keys[k] = down
	return hit


func _update_player(delta: float) -> void:
	var look := hud.consume_look()
	yaw -= look.x * C.LOOK_SENSITIVITY
	pitch = clamp(pitch - look.y * C.LOOK_SENSITIVITY, -1.3, 1.3)
	# 电脑上调试：WASD 移动、方向键看、F 攻击、空格跳、Shift 冲刺、R 换弹、E 搜索
	var mv := hud.move
	if _key(KEY_W): mv.y += 1
	if _key(KEY_S): mv.y -= 1
	if _key(KEY_A): mv.x -= 1
	if _key(KEY_D): mv.x += 1
	if _key(KEY_LEFT): yaw += delta * 2.0
	if _key(KEY_RIGHT): yaw -= delta * 2.0
	if _key(KEY_UP): pitch = min(pitch + delta * 1.5, 1.3)
	if _key(KEY_DOWN): pitch = max(pitch - delta * 1.5, -1.3)
	mv = mv.limit_length(1.0)

	# 冲刺：体力耗光后要回到 25 才能再冲
	if stamina <= 0.5:
		_exhausted = true
	elif stamina > 25.0:
		_exhausted = false
	_sprinting = (hud.sprint or _key(KEY_SHIFT)) and mv.y > 0.3 and not _exhausted
	if _sprinting:
		stamina = max(0.0, stamina - C.SPRINT_DRAIN * delta)
	elif _melee_t < 0.0:
		var regen := C.STAMINA_REGEN * (0.4 if food <= 0.0 or water <= 0.0 else 1.0)
		stamina = min(C.MAX_STAMINA, stamina + regen * delta)

	player.rotation.y = yaw
	_shake = max(0.0, _shake - delta * 3.0)
	camera.rotation.x = pitch + sin(Time.get_ticks_msec() * 0.07) * _shake * 0.04
	camera.rotation.z = cos(Time.get_ticks_msec() * 0.05) * _shake * 0.03
	var fwd := -player.global_basis.z
	var right := player.global_basis.x
	var spd := C.PLAYER_SPEED * (C.SPRINT_MULT if _sprinting else 1.0)
	var vel := (fwd * mv.y + right * mv.x) * spd
	var feet := player.position.y
	var p := world.push_out(player.position + vel * delta, 0.35, feet)

	# 跳和重力：矮的杂物（路障、垃圾桶）能站上去
	var jump := hud.consume_jump() or _key_hit(KEY_SPACE)
	if jump and _on_ground and stamina >= C.JUMP_COST:
		_vy = sqrt(2.0 * C.GRAVITY * C.JUMP_HEIGHT)
		_on_ground = false
		stamina -= C.JUMP_COST
	var ground := world.ground_at(p, 0.35, feet)
	_vy -= C.GRAVITY * delta
	feet += _vy * delta
	if feet <= ground:
		if not _on_ground and _vy < -3.0:
			sfx.play("land", -6.0)
			_shake = max(_shake, 0.15)
		feet = ground
		_vy = 0.0
		_on_ground = true
	else:
		_on_ground = false
	player.position = Vector3(p.x, feet, p.z)
	arms.set_meta("walking", mv.length() if _on_ground else 0.0)
	arms.set_meta("sprint", 1.0 if _sprinting and mv.length() > 0.3 else 0.0)

	# 脚步声：冲刺时附近的僵尸听得见
	if _on_ground and mv.length() > 0.1:
		_step_dist += vel.length() * delta
		if _step_dist > (2.2 if _sprinting else 1.7):
			_step_dist = 0.0
			sfx.play("footstep", -10.0 if not _sprinting else -5.0)
			if _sprinting:
				_make_noise(player.position, C.NOISE_SPRINT)

	attack_cd = max(0.0, attack_cd - delta)
	if _key_hit(KEY_E):
		_action()
	if _key_hit(KEY_R):
		_start_reload()
	var attacking := hud.attack_held or _key(KEY_F)
	if attacking and attack_cd <= 0.0:
		_attack()
	# 散布：走动、冲刺、跳的时候准星张开
	var want_spread := 0.0
	if mv.length() > 0.1:
		want_spread = 0.35
	if _sprinting or not _on_ground:
		want_spread = 1.0
	_spread = move_toward(_spread, want_spread, delta * 3.0)
	hud.set_spread(_spread)


# —— 战斗 ——

func _equipped_kind() -> int:
	return Assets.items_by_id.get(equipped, {}).get("kind", -1)


func _attack() -> void:
	if _reload_t > 0.0:
		return
	if _equipped_kind() == Assets.Kind.GUN:
		_fire()
	else:
		_melee_start()


func _melee_start() -> void:
	if _melee_t >= 0.0:
		return
	var row: Dictionary = Assets.items_by_id.get(equipped, {})
	var power: float = row.get("power", C.FIST_DAMAGE) if row.get("kind", -1) == Assets.Kind.MELEE else C.FIST_DAMAGE
	# 重武器挥得慢；体力不够挥得更慢
	var cd := C.MELEE_COOLDOWN * (1.4 if power >= 40.0 else 1.0) * (1.5 if stamina < C.MELEE_STAMINA else 1.0)
	attack_cd = cd
	arms.swing(1.0 / cd * 0.9)
	stamina = max(0.0, stamina - C.MELEE_STAMINA)
	sfx.play("swing", -6.0, 1.2 if power < 20.0 else 0.85)
	# 伤害在挥到前面时才算（和手臂动作对上）
	_melee_t = cd * 0.42


func _melee_resolve() -> void:
	var row: Dictionary = Assets.items_by_id.get(equipped, {})
	var power: float = row.get("power", C.FIST_DAMAGE) if row.get("kind", -1) == Assets.Kind.MELEE else C.FIST_DAMAGE
	if stamina <= 0.0:
		power *= 0.6
	var eye := camera.global_position
	var aim := -camera.global_basis.z
	var best: Zombie = null
	var best_hit := {}
	for z in zombie_root.get_children():
		if z.dead:
			continue
		var h: Dictionary = z.ray_hit(eye, aim, C.MELEE_RANGE + 0.3, 0.6)
		if h.is_empty():
			# 贴脸的时候准星没对准也算打到（手机上不好瞄）
			var to: Vector3 = z.global_position - player.global_position
			to.y = 0.0
			var flat := Vector3(aim.x, 0, aim.z).normalized()
			if to.length() < 1.6 and to.length() > 0.01 and flat.dot(to.normalized()) > 0.5:
				h = {"t": to.length(), "head": false, "point": z.global_position + Vector3.UP * 1.2 - to.normalized() * 0.3}
		if not h.is_empty() and (best == null or h.t < best_hit.t):
			best = z
			best_hit = h
	if best == null:
		return
	var dmg := power * (C.HEADSHOT_MULT * 0.7 if best_hit.head else 1.0)
	var knock := 1.2 + power / 14.0
	_damage_zombie(best, dmg, best_hit, knock)
	_make_noise(player.position, C.NOISE_MELEE)


func _fire() -> void:
	var g := Assets.gun_stats(equipped)
	var mag: int = mags.get(equipped, 0)
	if mag <= 0:
		if ammo.get(g.cal, 0) > 0:
			_start_reload()
		else:
			attack_cd = 0.35
			sfx.play("dry_fire", -4.0)
			if _dry_t <= 0.0:
				hud.toast("没有%s了" % C.CALIBER_NAMES.get(g.cal, "子弹"))
				_dry_t = 2.0
		return
	mags[equipped] = mag - 1
	attack_cd = g.rate
	var is_bow: bool = g.cal in ["arrow", "bolt"]
	arms.swing(7.0 if not is_bow else 4.0)
	if not is_bow:
		arms.muzzle_flash()
	var pellets: int = g.get("pellets", 1)
	match g.cal:
		"shell":
			sfx.play("gun_shotgun", 0.0)
		"762", "rocket":
			sfx.play("gun_rifle", 0.0)
		"arrow", "bolt":
			sfx.play("gun_bow", -2.0)
		_:
			sfx.play("gun_pistol", -1.0)
	_make_noise(player.position, C.NOISE_GUN if not is_bow else C.NOISE_MELEE)
	# 后坐力：镜头往上一跳
	pitch = min(1.3, pitch + C.GUN_RECOIL * (2.5 if pellets > 1 else 1.0) * rng.randf_range(0.7, 1.3))
	yaw += rng.randf_range(-0.004, 0.004)
	var eye := camera.global_position
	var aim := -camera.global_basis.z
	var spread: float = g.get("spread", 0.0) + 0.003 + _spread * 0.035
	var range_m: float = g.get("range", C.GUN_RANGE)
	for i in pellets:
		var dir := aim
		if spread > 0.0:
			var r := camera.global_basis.x * rng.randf_range(-1, 1) + camera.global_basis.y * rng.randf_range(-1, 1)
			dir = (aim + r * spread).normalized()
		_shoot_ray(eye, dir, range_m, g, i == 0 and not is_bow)
	_spread = min(1.0, _spread + 0.25)
	if mags[equipped] <= 0 and ammo.get(g.cal, 0) > 0:
		_start_reload.call_deferred()
	_refresh_ammo()


func _shoot_ray(eye: Vector3, dir: Vector3, range_m: float, g: Dictionary, tracer: bool) -> void:
	var radius := C.AIM_RADIUS if g.get("pellets", 1) == 1 else 0.3
	var best: Zombie = null
	var best_hit := {}
	for z in zombie_root.get_children():
		if z.dead:
			continue
		var h: Dictionary = z.ray_hit(eye, dir, range_m, radius)
		if not h.is_empty() and (best == null or h.t < best_hit.t):
			best = z
			best_hit = h
	var end_t := range_m
	if best:
		end_t = best_hit.t
	# 楼挡子弹
	var bt := world.block_t(eye, eye + dir * end_t)
	if bt < 1.0:
		end_t *= bt
		best = null
	var end := eye + dir * end_t
	if tracer:
		_tracer(camera.global_transform * arms.muzzle(), end)
	if g.has("splash"):
		_explode(end, g.dmg, g.splash)
		return
	if best:
		var dmg: float = g.dmg
		if g.get("pellets", 1) > 1 and best_hit.t > 10.0:
			dmg *= 0.6
		if best_hit.head:
			dmg *= C.HEADSHOT_MULT
		var knock := 1.0 + dmg / 30.0
		_damage_zombie(best, dmg, best_hit, knock)


func _damage_zombie(z: Zombie, dmg: float, h: Dictionary, knock: float) -> void:
	var killed := z.take_hit(dmg, player.global_position, knock * C.KNOCKBACK / 2.6, h.head)
	_blood(h.point, (player.global_position - z.global_position).normalized(), 18 if h.head else 10)
	sfx.play_at("headshot" if h.head else "hit_flesh", h.point, 2.0)
	hud.hit_marker(2 if killed else (1 if h.head else 0))
	if killed and h.head:
		headshots += 1


func _explode(at: Vector3, dmg: float, radius: float) -> void:
	sfx.play_at("explosion", at, 6.0)
	_make_noise(at, C.NOISE_GUN * 1.5)
	_shake = 1.0
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 8.0
	light.omni_range = radius * 3.0
	light.position = at + Vector3.UP
	fx_root.add_child(light)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.5)
	tw.tween_callback(light.queue_free)
	for z in zombie_root.get_children():
		if z.dead:
			continue
		var d: float = z.global_position.distance_to(at)
		if d < radius:
			var k := 1.0 - d / radius
			_damage_zombie(z, dmg * k, {"head": false, "point": z.global_position + Vector3.UP}, 3.0 + 6.0 * k)
	var pd := player.global_position.distance_to(at)
	if pd < radius:
		_hurt_player(dmg * 0.4 * (1.0 - pd / radius), at)


## 枪口到命中点的一道亮线，一闪就没
func _tracer(from: Vector3, to: Vector3) -> void:
	var len := from.distance_to(to)
	if len < 0.5:
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.012, 0.012, len)
	mi.mesh = box
	mi.material_override = _tracer_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_root.add_child(mi)
	mi.look_at_from_position((from + to) * 0.5, to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	get_tree().create_timer(0.04).timeout.connect(mi.queue_free)


## 喷血：一小团血珠往打来的方向溅
func _blood(at: Vector3, toward: Vector3, amount: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.6
	p.explosiveness = 0.95
	p.mesh = _blood_mesh
	p.material_override = _blood_mat
	# 大部分从背后喷出去，少量溅向打来的方向
	p.direction = (-toward * 0.6 + Vector3.UP * 0.5).normalized()
	p.spread = 70.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -12.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	p.position = at
	fx_root.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func _blood_pool(at: Vector3, size: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	mi.mesh = pm
	mi.material_override = _pool_mat
	mi.position = Vector3(at.x, 0.04 + rng.randf() * 0.004, at.z)
	mi.rotation.y = rng.randf() * TAU
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_root.add_child(mi)
	_blood_pools.append(mi)
	if _blood_pools.size() > 40:
		_blood_pools.pop_front().queue_free()


func _start_reload() -> void:
	if not running or _reload_t > 0.0 or _equipped_kind() != Assets.Kind.GUN:
		return
	var g := Assets.gun_stats(equipped)
	if mags.get(equipped, 0) >= g.mag:
		return
	if ammo.get(g.cal, 0) <= 0:
		hud.toast("没有%s了" % C.CALIBER_NAMES.get(g.cal, "子弹"))
		return
	_reload_t = g.reload
	_reload_id = equipped
	arms.reload(g.reload)
	sfx.play("reload", -4.0, 1.6 / g.reload)
	_refresh_ammo()


func _update_weapon(delta: float) -> void:
	_dry_t -= delta
	if _melee_t >= 0.0:
		_melee_t -= delta
		if _melee_t < 0.0:
			_melee_resolve()
	if _reload_t > 0.0:
		if equipped != _reload_id:
			_reload_t = 0.0
			arms.cancel_reload()
		else:
			_reload_t -= delta
			if _reload_t <= 0.0:
				var g := Assets.gun_stats(equipped)
				var have: int = mags.get(equipped, 0)
				var take: int = min(g.mag - have, ammo.get(g.cal, 0))
				mags[equipped] = have + take
				ammo[g.cal] = ammo.get(g.cal, 0) - take
			_refresh_ammo()


func _refresh_ammo() -> void:
	if _equipped_kind() != Assets.Kind.GUN:
		hud.set_weapon(false, "", false)
		return
	var g := Assets.gun_stats(equipped)
	var mag: int = mags.get(equipped, 0)
	var spare: int = ammo.get(g.cal, 0)
	var text := "换弹中…" if _reload_t > 0.0 else "%d / %d" % [mag, spare]
	hud.set_weapon(true, text, _reload_t <= 0.0 and mag < g.mag and spare > 0)


## 声音惊动附近闲逛的僵尸
func _make_noise(at: Vector3, radius: float) -> void:
	for z in zombie_root.get_children():
		z.hear(at, radius)


func _hurt_player(dmg: float, from: Vector3) -> void:
	hp -= dmg
	_shake = max(_shake, 0.5)
	sfx.play("player_hurt", -2.0)
	var d := from - player.global_position
	var rel := NAN
	if Vector2(d.x, d.z).length() > 0.1:
		rel = wrapf(atan2(d.x, -d.z) - (-yaw), -PI, PI)
	hud.hurt(rel)


# —— 僵尸 ——

func _update_zombies(delta: float, day: int, night: bool, horde: bool) -> void:
	_nav_t -= delta
	if _nav_t <= 0.0:
		_nav_t = C.NAV_INTERVAL
		world.update_flow(player.position)
	var alive := 0
	var list: Array[Zombie] = []
	for z in zombie_root.get_children():
		if z.dead:
			continue
		alive += 1
		list.append(z)
		z.aggressive = night or horde
		var dmg: float = z.take_pending_damage()
		if dmg > 0.0:
			_hurt_player(dmg, z.global_position)
			# 被抓伤：可能流血，少数会感染
			if rng.randf() < C.BLEED_CHANCE:
				if bleeding <= 0.0:
					hud.toast("流血了！用绷带或药止血")
				bleeding = C.BLEED_TIME
			if infection <= 0.0 and rng.randf() < C.INFECT_CHANCE + day * 0.01:
				infection = 1.0
				hud.toast("你被感染了！找抗生素、急救包或蜂蜜")
		# 离太远的僵尸回收掉，在身边重新刷
		if z.distance_to_target() > C.ZOMBIE_DESPAWN:
			z.queue_free()
		elif night or horde:
			z.speed = max(z.speed, (C.ZOMBIE_HORDE_SPEED if horde else C.ZOMBIE_NIGHT_SPEED) * 0.9)
	_separate(list)
	var target := 2 + day
	if night:
		target = 5 + day * 2
	if horde:
		target = C.ZOMBIE_MAX
	target = min(target, C.ZOMBIE_MAX)
	spawn_cd -= delta
	if alive < target and spawn_cd <= 0.0 and not Assets.zombie_models.is_empty():
		spawn_cd = 0.6 if horde else (2.0 if night else 5.0)
		var near := horde
		_spawn_zombie(day, night, horde, world.free_point(player.position, 14.0 if near else 18.0, 24.0 if near else 32.0))


## 僵尸之间互相推开，不会叠在一起
func _separate(list: Array[Zombie]) -> void:
	for i in list.size():
		var a := list[i]
		for j in range(i + 1, list.size()):
			var b := list[j]
			var d := b.position - a.position
			d.y = 0.0
			var l := d.length()
			if l < 0.7 and l > 0.001:
				var push := d / l * (0.7 - l) * 0.5
				a.position = world.push_out(a.position - push, 0.35)
				b.position = world.push_out(b.position + push, 0.35)


func _pick_zombie_model() -> String:
	var total := 0.0
	for m in Assets.zombie_models:
		total += Assets.zombie_type(m).get("weight", 1.0)
	var r := rng.randf() * total
	for m in Assets.zombie_models:
		r -= Assets.zombie_type(m).get("weight", 1.0)
		if r <= 0.0:
			return m
	return Assets.zombie_models[0]


func _spawn_zombie(day: int, night: bool, horde: bool, at: Vector3) -> Zombie:
	var z := Zombie.new()
	var spd := C.ZOMBIE_HORDE_SPEED if horde else (C.ZOMBIE_NIGHT_SPEED if night else C.ZOMBIE_WALK_SPEED)
	if not z.setup(_pick_zombie_model(), C.ZOMBIE_BASE_HP + C.ZOMBIE_HP_PER_DAY * (day - 1), spd, player):
		z.free()
		return null
	z.world = world
	z.aggressive = night or horde
	z.died.connect(_on_zombie_died)
	z.noise.connect(_on_zombie_noise)
	z.spit.connect(_on_spit)
	z.screamed.connect(_on_screamed)
	zombie_root.add_child(z)
	z.place_at(at)
	return z


func _on_zombie_died(z: Zombie) -> void:
	kills += 1
	_blood_pool(z.global_position, rng.randf_range(1.3, 2.0))
	if rng.randf() < C.ZOMBIE_DROP_CHANCE:
		_spawn_loot(z.global_position + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)))
	elif rng.randf() < 0.15:
		_drop_ammo(z.global_position)


func _on_zombie_noise(z: Zombie, sound: String) -> void:
	var vol: float = {"groan": -4.0, "attack": 0.0, "scream": 6.0, "death": -2.0, "spit": 0.0}.get(sound, 0.0)
	sfx.play_at(sound, z.global_position + Vector3.UP * (z.height - 0.2), vol)


func _on_screamed(z: Zombie) -> void:
	hud.toast("%s在尖叫！附近的僵尸都被引过来了" % z.kind_name)
	_make_noise(z.global_position, 60.0)
	var day := int(game_hours / 24.0) + 1
	var alive := zombie_root.get_children().filter(func(n): return not n.dead).size()
	for i in C.SCREAM_SPAWN:
		if alive >= C.ZOMBIE_MAX + 6:
			break
		var nz := _spawn_zombie(day, true, false, world.free_point(z.global_position, 6.0, 14.0))
		if nz:
			nz.state = Zombie.State.CHASE
			alive += 1


## 胖警察吐的酸液：一团绿光，带一点弧线飞过来
func _on_spit(_z: Zombie, from: Vector3, to: Vector3) -> void:
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	ball.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.9, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.9, 0.1)
	mat.emission_energy_multiplier = 2.0
	ball.material_override = mat
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 1.0, 0.2)
	light.light_energy = 1.2
	light.omni_range = 3.0
	ball.add_child(light)
	ball.position = from
	fx_root.add_child(ball)
	var flight := from.distance_to(to) / C.SPIT_SPEED
	var v := (to - from) / flight
	v.y += 0.5 * C.GRAVITY * 0.25 * flight   # 抵消下落，让它正好飞到目标
	_spits.append({"node": ball, "v": v, "t": 0.0})


func _update_spits(delta: float) -> void:
	for s in _spits.duplicate():
		var n: Node3D = s.node
		var prev := n.position
		var v: Vector3 = s.v
		v.y -= C.GRAVITY * 0.25 * delta
		s.v = v
		n.position += v * delta
		s.t += delta
		var hit_player := n.position.distance_to(player.global_position + Vector3.UP * 1.0) < 0.9
		var done: bool = hit_player or s.t > 3.0 or n.position.y < 0.05 or world.line_blocked(prev, n.position)
		if hit_player:
			_hurt_player(C.SPIT_DAMAGE, n.position)
			sfx.play("acid", 0.0)
			hud.toast("被酸液泼中了！")
			if infection <= 0.0 and rng.randf() < 0.25:
				infection = 1.0
		elif done:
			sfx.play_at("acid", n.position, -4.0)
		if done:
			n.queue_free()
			_spits.erase(s)


# —— 物品 ——

func _spawn_loot(pos: Vector3, id := "") -> void:
	if id == "":
		id = Assets.random_loot(rng)
	if id == "":
		return
	var vis := Assets.make_item_visual(id, C.LOOT_SIZE)
	if vis == null:
		return
	var holder := Node3D.new()
	holder.set_meta("item", id)
	holder.position = pos
	var spin := Node3D.new()
	spin.name = "Spin"
	spin.position.y = 0.15
	spin.add_child(vis)
	holder.add_child(spin)
	# 物品名字，走近才显示
	var label := Label3D.new()
	label.text = Assets.display_name(id)
	label.font = _cjk_font()
	label.font_size = 36
	label.outline_size = 10
	# 固定在屏幕上的大小，走近不会变得很大
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = 0.95
	label.visibility_range_end = 7.0
	label.modulate = Color(1, 0.95, 0.8)
	holder.add_child(label)
	# 地上一圈淡淡的光，远处也能看到
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.8, 0.4)
	glow.light_energy = 0.6
	glow.omni_range = 1.4
	glow.position.y = 0.5
	holder.add_child(glow)
	loot_root.add_child(holder)


## 掉一盒子弹：优先掉你手上枪能用的口径。素材里没有弹药物品时直接给子弹
func _drop_ammo(at: Vector3) -> void:
	var cal := _wanted_caliber()
	var id := Assets.ammo_item(cal)
	if id != "":
		_spawn_loot(world.push_out(at, 0.2), id)
	else:
		_grant_ammo(cal, int(_ammo_per_box(cal) * rng.randf_range(0.6, 1.2)))


func _wanted_caliber() -> String:
	var cals := []
	for id in inventory:
		if Assets.items_by_id[id].kind == Assets.Kind.GUN:
			cals.append(Assets.gun_stats(id).cal)
	if cals.is_empty() or rng.randf() < 0.25:
		cals = ["9mm", "9mm", "762", "shell", "44", "arrow"]
	return cals.pick_random()


func _ammo_per_box(cal: String) -> int:
	for a in C.AMMO:
		if a[1] == cal:
			return a[2]
	return 10


func _grant_ammo(cal: String, n: int) -> void:
	n = max(1, n)
	ammo[cal] = ammo.get(cal, 0) + n
	hud.toast("捡到：%s ×%d" % [C.CALIBER_NAMES.get(cal, cal), n])
	sfx.play("pickup", -6.0)
	_refresh_ammo()


func _update_loot(delta: float) -> void:
	var count := 0
	for l in loot_root.get_children():
		if l.is_queued_for_deletion():
			continue
		count += 1
		# 子弹走过去就自动捡
		if Assets.items_by_id[l.get_meta("item")].kind == Assets.Kind.AMMO:
			if Vector2(l.position.x - player.position.x, l.position.z - player.position.z).length() < 1.2:
				_pickup(l.get_meta("item"))
				l.queue_free()
				continue
		var spin: Node3D = l.get_node("Spin")
		spin.rotation.y += delta * 1.2
		spin.position.y = 0.15 + sin(Time.get_ticks_msec() / 400.0 + l.position.x) * 0.05
	if count < C.LOOT_COUNT and rng.randf() < delta * 0.2:
		_spawn_loot(world.free_point(player.position, 15.0, 45.0))


func _cjk_font() -> SystemFont:
	if _label_font == null:
		_label_font = SystemFont.new()
		_label_font.font_names = PackedStringArray(["PingFang SC", "Hiragino Sans GB", "Heiti SC", "Noto Sans CJK SC", "Microsoft YaHei", "sans-serif"])
	return _label_font


## 离玩家最近、能拾取的地上物品（优先看准星对着的）
func _nearest_loot() -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var aim := -player.global_basis.z
	for l in loot_root.get_children():
		if l.is_queued_for_deletion():
			continue
		var to: Vector3 = l.position - player.position
		to.y = 0.0
		var d := to.length()
		if d > C.PICKUP_RADIUS:
			continue
		var score := d - (aim.dot(to / d) if d > 0.01 else 1.0) * 0.8
		if score < best_score:
			best_score = score
			best = l
	return best


## 每帧决定「搜索 / 拾取」按钮显示什么，推进翻找进度
func _update_action(delta: float) -> void:
	if not _search.is_empty():
		var c: Dictionary = _search
		var need: float = C.SEARCH_TIME_CAR if c.kind == "car" else C.SEARCH_TIME
		if Vector2(player.position.x - _search_from.x, player.position.z - _search_from.z).length() > 0.8:
			_search = {}
			hud.set_progress(-1.0)
			hud.toast("走开了，没翻完")
		else:
			_search_t += delta
			hud.set_progress(_search_t / need, "正在翻%s…" % c.name)
			hud.set_action("")
			if _search_t >= need:
				_finish_search(c)
			return
	var loot := _nearest_loot()
	if loot:
		hud.set_action("拾取\n%s" % Assets.display_name(loot.get_meta("item")))
		return
	var c := world.nearest_container(player.position)
	if c.is_empty():
		hud.set_action("")
	elif c.searched:
		hud.set_action("%s\n已翻过" % c.name, false)
	else:
		hud.set_action("搜索\n%s" % c.name)


func _action() -> void:
	if not running or not _search.is_empty():
		return
	var loot := _nearest_loot()
	if loot:
		_pickup(loot.get_meta("item"))
		loot.queue_free()
		return
	var c := world.nearest_container(player.position)
	if c.is_empty() or c.searched:
		return
	_search = c
	_search_t = 0.0
	_search_from = player.position
	sfx.play("search", -6.0)


func _finish_search(c: Dictionary) -> void:
	_search = {}
	hud.set_progress(-1.0)
	c.searched = true
	# 武器包、警车里常有子弹
	var ammo_chance: float = {"weapon": 0.6, "any": 0.15, "tool": 0.1}.get(c.loot, 0.0)
	if rng.randf() < ammo_chance:
		_drop_ammo(c.pos + (player.position - c.pos).normalized() * (c.r + 0.5))
	if rng.randf() < C.SEARCH_EMPTY_CHANCE:
		hud.toast("%s里什么也没有" % c.name)
		return
	var n := rng.randi_range(C.SEARCH_MIN, C.SEARCH_MAX)
	var names := []
	for i in n:
		var id := Assets.random_loot(rng, c.loot)
		if id == "":
			continue
		# 掉在容器和玩家之间的地上
		var dir: Vector3 = player.position - c.pos
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
		var p: Vector3 = c.pos + dir * (c.r + 0.5) + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
		_spawn_loot(world.push_out(p, 0.2), id)
		names.append(Assets.display_name(id))
	hud.toast("翻到：" + "、".join(names) if not names.is_empty() else "%s里什么也没有" % c.name)


func _pickup(id: String) -> void:
	var row: Dictionary = Assets.items_by_id[id]
	# 子弹不进背包，直接算备弹
	if row.kind == Assets.Kind.AMMO:
		_grant_ammo(row.cal, int(row.power * rng.randf_range(0.7, 1.3)))
		return
	inventory[id] = inventory.get(id, 0) + 1
	if not pickup_order.has(id):
		pickup_order.append(id)
	hud.toast("捡到：%s" % Assets.display_name(id))
	sfx.play("pickup", -6.0)
	if row.kind == Assets.Kind.GUN and not mags.has(id):
		# 捡到的枪里多少有几发
		var g := Assets.gun_stats(id)
		mags[id] = rng.randi_range(int(ceil(g.mag * 0.3)), g.mag)
	# 捡到更好的武器自动换上
	if row.kind in [Assets.Kind.MELEE, Assets.Kind.GUN]:
		var cur: Dictionary = Assets.items_by_id.get(equipped, {})
		if cur.is_empty() or _weapon_score(id) > _weapon_score(equipped):
			_equip(id)
	_refresh_inventory()


## 比较武器好坏：枪按每秒伤害，近战按威力
func _weapon_score(id: String) -> float:
	var row: Dictionary = Assets.items_by_id.get(id, {})
	if row.get("kind", -1) == Assets.Kind.GUN:
		var g := Assets.gun_stats(id)
		return 40.0 + g.dmg * g.get("pellets", 1) / max(g.rate, 0.1) * 0.05
	return row.get("power", 0.0)


func _use_item(id: String) -> void:
	if not inventory.has(id):
		return
	var row: Dictionary = Assets.items_by_id[id]
	var low := id.to_lower()
	match row.kind:
		Assets.Kind.MELEE, Assets.Kind.GUN:
			_equip("" if equipped == id else id)
		Assets.Kind.FOOD:
			food = min(C.MAX_FOOD, food + row.power)
			water = min(C.MAX_WATER, water + row.power * 0.15)
			if low.contains("honey"):
				_cure_infection(30.0)
			sfx.play("eat", -4.0)
			_consume(id, "吃了%s" % Assets.display_name(id))
		Assets.Kind.DRINK:
			water = min(C.MAX_WATER, water + row.power * 1.6)
			food = min(C.MAX_FOOD, food + row.power * 0.2)
			hp = min(C.MAX_HP, hp + 5.0)
			sfx.play("drink", -4.0)
			_consume(id, "喝了%s" % Assets.display_name(id))
		Assets.Kind.MEDICAL:
			hp = min(C.MAX_HP, hp + row.power)
			var msg := "用了%s" % Assets.display_name(id)
			if bleeding > 0.0:
				bleeding = 0.0
				msg += "，血止住了"
			for w in ["antibiotic", "firstaidkit", "herbal", "kit"]:
				if low.contains(w):
					_cure_infection(100.0 if w == "antibiotic" or w == "firstaidkit" else 40.0)
					msg += "，感染好转了" if infection > 0.0 else "，感染治好了"
					break
			_consume(id, msg)
		_:
			hud.toast("%s：材料，留着吧" % Assets.display_name(id))
	_refresh_inventory()


func _cure_infection(amount: float) -> void:
	infection = max(0.0, infection - amount)


func _consume(id: String, msg: String) -> void:
	inventory[id] -= 1
	if inventory[id] <= 0:
		inventory.erase(id)
		pickup_order.erase(id)
	hud.toast(msg)


func _equip(id: String) -> void:
	equipped = id
	arms.hold(id)
	_melee_t = -1.0
	if id != "":
		hud.toast("装备：%s" % Assets.display_name(id))
	_refresh_ammo()


func _refresh_inventory() -> void:
	var list := []
	for id in pickup_order:
		list.append({"id": id, "count": inventory.get(id, 0), "equipped": id == equipped})
	# 快捷栏：当前武器 + 能吃能用的，最多 6 格
	var bar: Array[String] = []
	if equipped != "":
		bar.append(equipped)
	for id in pickup_order:
		if bar.size() >= 6:
			break
		var k: int = Assets.items_by_id[id].kind
		if id != equipped and k in [Assets.Kind.FOOD, Assets.Kind.DRINK, Assets.Kind.MEDICAL, Assets.Kind.MELEE, Assets.Kind.GUN]:
			bar.append(id)
	hud.set_inventory(list, bar)
	_refresh_ammo()


# —— 生存、昼夜、音乐 ——

func _update_survival(delta: float) -> void:
	food = max(0.0, food - C.FOOD_DRAIN * delta * (1.5 if _sprinting else 1.0))
	water = max(0.0, water - C.WATER_DRAIN * delta * (1.8 if _sprinting else 1.0))
	if food <= 0.0:
		hp -= C.STARVE_DAMAGE * delta
	if water <= 0.0:
		hp -= C.THIRST_DAMAGE * delta
	if bleeding > 0.0:
		bleeding = max(0.0, bleeding - delta)
		hp -= C.BLEED_DAMAGE * delta
		if rng.randf() < delta * 1.5:
			_blood_pool(player.position + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)), 0.35)
	if infection > 0.0:
		infection = min(100.0, infection + C.INFECTION_RATE * delta)
		if infection >= 100.0:
			hp -= C.INFECTION_DAMAGE * delta
	if food > 60.0 and water > 60.0 and bleeding <= 0.0 and infection < 50.0:
		hp = min(C.MAX_HP, hp + C.HP_REGEN * delta)
	# 血少时心跳声
	_heart_t -= delta
	if hp < 30.0 and _heart_t <= 0.0:
		_heart_t = 0.6 + hp / 30.0 * 0.5
		sfx.play("heartbeat", -2.0)


func _effects_text() -> String:
	var e := []
	if bleeding > 0.0:
		e.append("流血")
	if infection > 0.0:
		e.append("感染 %d%%" % int(infection))
	if food < 20.0:
		e.append("饿" if food > 0.0 else "饿得掉血")
	if water < 20.0:
		e.append("渴" if water > 0.0 else "渴得掉血")
	if _exhausted:
		e.append("累")
	return "  ".join(e)


func _update_sky() -> void:
	var hour := fmod(game_hours, 24.0)
	# 太阳高度：6 点日出、20 点日落，中午最高；夜里是负数
	var elev: float
	if hour >= C.SUNRISE and hour <= C.SUNSET:
		elev = sin(PI * (hour - C.SUNRISE) / (C.SUNSET - C.SUNRISE))
	else:
		var night_len := 24.0 - (C.SUNSET - C.SUNRISE)
		var t := fmod(hour - C.SUNSET + 24.0, 24.0) / night_len
		elev = -sin(PI * t) * 0.6
	var light: float = smoothstep(-0.12, 0.3, elev)
	var dusk: float = clamp(1.0 - abs(elev) * 4.0, 0.0, 1.0)
	var sun_up: float = max(elev, 0.12)
	# 夜里这盏灯当月光用，从另一侧照过来
	sun.rotation = Vector3(-asin(sun_up) - 0.05, deg_to_rad(35.0 if elev > 0.0 else 215.0), 0)
	sun.light_energy = lerp(C.MOON_LIGHT, 1.0, light)
	sun.light_color = Color(0.62, 0.7, 1.0).lerp(Color(1.0, 0.96, 0.88), light).lerp(Color(1.0, 0.62, 0.4), dusk * light)
	var day_sky := Color(0.30, 0.50, 0.80)
	var night_sky := Color(0.07, 0.1, 0.2)
	var day := int(game_hours / 24.0) + 1
	var horde := (day == C.HORDE_DAY and hour >= C.NIGHT_START) or (day == C.HORDE_DAY + 1 and hour < C.NIGHT_END)
	if horde:
		night_sky = Color(0.35, 0.05, 0.04)
	sky_mat.sky_top_color = night_sky.lerp(day_sky, light)
	var horizon := Color(0.16, 0.19, 0.28).lerp(Color(0.66, 0.70, 0.74), light).lerp(Color(0.95, 0.6, 0.4), dusk * 0.6)
	if horde:
		horizon = horizon.lerp(Color(0.5, 0.08, 0.05), 1.0 - light)
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = Color(0.12, 0.12, 0.13).lerp(Color(0.25, 0.22, 0.18), light)
	env.fog_light_color = horizon
	# 环境光不跟天空走，夜里也保证能看清地面和僵尸
	env.ambient_light_color = C.NIGHT_AMBIENT.lerp(Color(0.78, 0.75, 0.7), light)
	if horde:
		env.ambient_light_color = env.ambient_light_color.lerp(Color(0.6, 0.25, 0.22), 1.0 - light)
	env.ambient_light_energy = lerp(C.NIGHT_AMBIENT_ENERGY, 0.45, light)
	env.fog_density = lerp(0.014, 0.0045, light)


func _update_music(delta: float, night: bool, horde: bool) -> void:
	var nearest := INF
	var chased := false
	for z in zombie_root.get_children():
		if not z.dead:
			nearest = min(nearest, z.distance_to_target())
			chased = chased or z.state != Zombie.State.WANDER
	var want := "Exp"
	if horde and not Assets.music["Bld"].is_empty():
		want = "Bld"
	elif nearest < C.COMBAT_DISTANCE and chased:
		want = "Cbt"
	elif night or nearest < C.TENSION_DISTANCE:
		want = "Sus"
	music.request(want, delta)


func _update_banner(day: int, hour: float, night: bool, horde: bool) -> void:
	if horde:
		hud.set_banner("血月尸潮！撑到天亮！")
		if not _horde_announced:
			_horde_announced = true
	elif day == C.HORDE_DAY and hour >= 18.0:
		hud.set_banner("今晚是血月……")
	elif night:
		if _night_announced != day:
			_night_announced = day
			hud.toast("天黑了，僵尸会跑起来")
		hud.set_banner("")
	else:
		hud.set_banner("")
