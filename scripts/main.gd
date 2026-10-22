extends Node3D
## 游戏主逻辑：世界、昼夜、玩家、僵尸、物品、背包、音乐。

const C = preload("res://scripts/config.gd")

var player := Node3D.new()
var camera := Camera3D.new()
var arms: FpArms
var hud: Hud
var world: World
var music: MusicDirector
var sun := DirectionalLight3D.new()
var env := Environment.new()
var sky_mat := ProceduralSkyMaterial.new()
var zombie_root := Node3D.new()
var loot_root := Node3D.new()
var rng := RandomNumberGenerator.new()

var running := false
var game_hours := C.START_HOUR   # 从第 1 天 0 点起算的小时数
var hp := C.MAX_HP
var food := C.MAX_FOOD
var kills := 0
var yaw := 0.0
var pitch := 0.0
var attack_cd := 0.0
var spawn_cd := 0.0
var inventory := {}          # id -> 数量
var pickup_order: Array[String] = []
var equipped := ""
var _horde_announced := false
## 正在翻的容器（空字典表示没在翻）、翻了多久、开始翻时站的位置
var _search := {}
var _search_t := 0.0
var _search_from := Vector3.ZERO
var _label_font: SystemFont
var _e_down := false
## 枪：每把枪弹匣里还剩几发；正在换弹的剩余时间
var mags := {}
var _reload_left := 0.0
## 体力、跳跃
var stamina := 100.0
var _vy := 0.0
var _flow_t := 0.0
var _recoil := 0.0
var _night_announced := -1


func _ready() -> void:
	rng.randomize()
	_build_world()
	_build_player()
	music = MusicDirector.new()
	add_child(music)
	hud = Hud.new()
	add_child(hud)
	hud.start_pressed.connect(_start)
	hud.restart_pressed.connect(_start)
	hud.item_used.connect(_use_item)
	hud.action_pressed.connect(_action)
	hud.reload_pressed.connect(_reload)
	hud.jump_pressed.connect(_jump)
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
	game_hours = C.START_HOUR
	hp = C.MAX_HP
	food = C.MAX_FOOD
	kills = 0
	inventory.clear()
	pickup_order.clear()
	equipped = ""
	arms.hold("")
	_horde_announced = false
	_night_announced = -1
	player.position = Vector3.ZERO
	yaw = 0.0
	pitch = 0.0
	spawn_cd = 6.0
	for c in world.containers:
		c.searched = false
	_search = {}
	hud.set_progress(-1.0)
	mags.clear()
	_reload_left = 0.0
	stamina = 100.0
	_vy = 0.0
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
	hud.toast("第 1 天。找武器、找吃的，天黑前做好准备。")


func _end(win: bool) -> void:
	running = false
	music.request("Exp" if win else "Sus", 99.0)
	var day := int(game_hours / 24.0) + 1
	if win:
		hud.show_end("你活过了第七天的血月！\n击杀 %d 只僵尸" % kills)
	else:
		hud.show_end("你死在了第 %d 天\n击杀 %d 只僵尸" % [day, kills])


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
	_update_sky()
	_update_zombies(delta, day, night, horde)
	_update_loot(delta)
	_update_action(delta)
	_update_survival(delta)
	_update_music(delta, night, horde)
	_update_banner(day, hour, night, horde)

	var near := 0
	for z in zombie_root.get_children():
		if not z.dead and z.distance_to_target() < C.TENSION_DISTANCE:
			near += 1
	hud.set_status(day, hour, hp, food, kills, near, night)
	if hp <= 0.0:
		_end(false)


func _update_player(delta: float) -> void:
	var look := hud.consume_look()
	yaw -= look.x * C.LOOK_SENSITIVITY
	pitch = clamp(pitch - look.y * C.LOOK_SENSITIVITY, -1.3, 1.3)
	# 电脑上调试：WASD 移动、方向键看、空格攻击
	var mv := hud.move
	if Input.is_physical_key_pressed(KEY_W): mv.y += 1
	if Input.is_physical_key_pressed(KEY_S): mv.y -= 1
	if Input.is_physical_key_pressed(KEY_A): mv.x -= 1
	if Input.is_physical_key_pressed(KEY_D): mv.x += 1
	if Input.is_physical_key_pressed(KEY_LEFT): yaw += delta * 2.0
	if Input.is_physical_key_pressed(KEY_RIGHT): yaw -= delta * 2.0
	if Input.is_physical_key_pressed(KEY_UP): pitch = min(pitch + delta * 1.5, 1.3)
	if Input.is_physical_key_pressed(KEY_DOWN): pitch = max(pitch - delta * 1.5, -1.3)
	mv = mv.limit_length(1.0)
	# 冲刺：摇杆推到底往前，或者按 Shift；耗体力
	var sprint := (mv.length() > 0.92 and mv.y > 0.6) or Input.is_physical_key_pressed(KEY_SHIFT)
	sprint = sprint and stamina > 1.0 and mv.y > 0.3
	if sprint:
		stamina = max(0.0, stamina - C.SPRINT_DRAIN * delta)
	else:
		stamina = min(100.0, stamina + C.STAMINA_REGEN * delta * (0.5 if mv.length() > 0.1 else 1.0))
	hud.set_stamina(stamina)
	# 跳：简单的竖直速度和重力
	if Input.is_physical_key_pressed(KEY_C):
		_jump()
	_vy -= C.GRAVITY * delta
	player.position.y = max(0.0, player.position.y + _vy * delta)
	if player.position.y <= 0.0:
		_vy = 0.0
	# 后坐力：镜头往上一跳，慢慢回落
	if _recoil > 0.0:
		var r := minf(_recoil, delta * 1.6)
		_recoil -= r
		pitch = clamp(pitch + r, -1.3, 1.3)
	player.rotation.y = yaw
	camera.rotation.x = pitch
	var fwd := -player.global_basis.z
	var right := player.global_basis.x
	var vel := (fwd * mv.y + right * mv.x) * C.PLAYER_SPEED * (C.SPRINT_MULT if sprint else 1.0)
	player.position = world.push_out(player.position + vel * delta, 0.35)
	arms.set_meta("walking", mv.length() * (1.6 if sprint else 1.0))
	# 换弹
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
	if Input.is_physical_key_pressed(KEY_R):
		_reload()
	_update_ammo_hud()

	attack_cd = max(0.0, attack_cd - delta)
	if Input.is_physical_key_pressed(KEY_E) and not _e_down:
		_action()
	_e_down = Input.is_physical_key_pressed(KEY_E)
	var attacking := hud.attack_held or Input.is_physical_key_pressed(KEY_SPACE)
	if attacking and attack_cd <= 0.0:
		_attack()


func _attack() -> void:
	var row: Dictionary = Assets.items_by_id.get(equipped, {})
	var kind: int = row.get("kind", -1)
	if kind == Assets.Kind.GUN:
		_fire(row)
		return
	attack_cd = C.MELEE_COOLDOWN
	arms.swing(1.0 / C.MELEE_COOLDOWN * 0.9)
	var dmg: float = row.get("power", C.FIST_DAMAGE) if kind == Assets.Kind.MELEE else C.FIST_DAMAGE
	var aim := -camera.global_basis.z
	var flat_aim := Vector3(aim.x, 0, aim.z).normalized()
	var best: Zombie = null
	var best_d := INF
	for z in zombie_root.get_children():
		if z.dead:
			continue
		var to: Vector3 = z.global_position - player.global_position
		to.y = 0
		var d := to.length()
		if d > C.MELEE_RANGE or d < 0.001:
			continue
		if flat_aim.dot(to / d) < 0.6 and d > 0.9:
			continue
		if d < best_d:
			best_d = d
			best = z
	if best:
		# 近战往上瞄着打算爆头
		var head := pitch > 0.12
		_hit_zombie(best, dmg * (C.HEADSHOT_MULT if head else 1.0), head,
			best.global_position + Vector3.UP * (best.height() * (0.88 if head else 0.6)), flat_aim)


## 开枪：每颗弹丸从镜头沿准星方向射出，先打中的是僵尸还是墙
func _fire(row: Dictionary) -> void:
	var st := Weapons.stats(equipped)
	if _reload_left > 0.0:
		return
	var left: int = mags.get(equipped, 0)
	if left <= 0:
		attack_cd = 0.35
		if Weapons.ammo_count(inventory, equipped) > 0:
			_reload()
		else:
			hud.toast("没子弹了，翻翻警车和武器包")
		return
	mags[equipped] = left - 1
	attack_cd = st.rate
	arms.swing(7.0)
	Fx.muzzle(arms, arms.muzzle_position())
	_recoil += 0.012 + st.damage * 0.0004 * st.pellets
	var eye := camera.global_position
	var aim := -camera.global_basis.z
	for p in st.pellets:
		var dir := (aim + camera.global_basis.x * rng.randfn(0.0, st.spread) + camera.global_basis.y * rng.randfn(0.0, st.spread)).normalized()
		_shoot_ray(eye, dir, st)


func _shoot_ray(eye: Vector3, dir: Vector3, st: Dictionary) -> void:
	var reach: float = st.range
	# 墙：沿射线每 0.25 米查一次楼的占地图；地面：y < 0
	var wall_t := reach
	var t := 0.5
	while t < reach:
		var p := eye + dir * t
		if p.y < 0.0 or (p.y < 30.0 and world.line_blocked(p, p)):
			wall_t = t
			break
		if world.blocked(Vector3(p.x, 0, p.z), 0.0) and p.y < 1.4:
			wall_t = t   # 车、箱子这种矮的东西
			break
		t += 0.25
	# 僵尸：当成竖着的胶囊
	var best: Zombie = null
	var best_t := wall_t
	var best_y := 0.0
	for z in zombie_root.get_children():
		if z.dead:
			continue
		var zp: Vector3 = z.global_position
		var oc := Vector2(zp.x - eye.x, zp.z - eye.z)
		var d2 := Vector2(dir.x, dir.z)
		var dd := d2.length_squared()
		if dd < 1e-6:
			continue
		var tt := oc.dot(d2) / dd
		if tt <= 0.0 or tt >= best_t:
			continue
		var miss := (Vector2(eye.x, eye.z) + d2 * tt - Vector2(zp.x, zp.z)).length()
		var y := eye.y + dir.y * tt
		if miss < 0.38 and y > zp.y + 0.1 and y < zp.y + z.height() * 1.02:
			best = z
			best_t = tt
			best_y = y
	var hit := eye + dir * best_t
	if st.blast > 0.0:
		_explode(hit, st)
		return
	if best:
		var head := best_y > best.head_height() - 0.12
		_hit_zombie(best, st.damage * (C.HEADSHOT_MULT if head else 1.0), head, hit, dir)
	elif best_t < reach:
		Fx.impact(self, hit - dir * 0.05, -dir)


func _explode(at: Vector3, st: Dictionary) -> void:
	Fx.impact(self, at, Vector3.UP)
	Fx.blood(self, at, Vector3.UP, true)
	for z in zombie_root.get_children():
		if z.dead:
			continue
		var d: float = z.global_position.distance_to(Vector3(at.x, 0, at.z))
		if d < st.blast:
			_hit_zombie(z, st.damage * (1.0 - d / st.blast * 0.6), false, z.global_position + Vector3.UP, (z.global_position - at).normalized())
	if player.position.distance_to(Vector3(at.x, 0, at.z)) < st.blast * 0.6:
		hp -= 25.0
		hud.hurt()


func _hit_zombie(z: Zombie, dmg: float, head: bool, at: Vector3, dir: Vector3) -> void:
	z.take_hit(dmg, player.global_position, head)
	Fx.blood(self, at, dir.normalized() + Vector3.UP * 0.2, head)
	if head:
		hud.toast("爆头！")


func _reload() -> void:
	var row: Dictionary = Assets.items_by_id.get(equipped, {})
	if row.get("kind", -1) != Assets.Kind.GUN or _reload_left > 0.0:
		return
	var st := Weapons.stats(equipped)
	if mags.get(equipped, 0) >= st.mag:
		return
	if Weapons.ammo_count(inventory, equipped) <= 0:
		hud.toast("没有这把枪的子弹")
		return
	_reload_left = st.reload
	arms.reload(st.reload)


func _finish_reload() -> void:
	var st := Weapons.stats(equipped)
	var need: int = st.mag - mags.get(equipped, 0)
	for id in Weapons.ammo_in(inventory, equipped):
		if need <= 0:
			break
		var take: int = min(need, inventory[id])
		inventory[id] -= take
		need -= take
		mags[equipped] = mags.get(equipped, 0) + take
		if inventory[id] <= 0:
			inventory.erase(id)
			pickup_order.erase(id)
	_refresh_inventory()


func _update_ammo_hud() -> void:
	var row: Dictionary = Assets.items_by_id.get(equipped, {})
	if row.get("kind", -1) != Assets.Kind.GUN:
		hud.set_ammo("")
		return
	var text := "%d / %d" % [mags.get(equipped, 0), Weapons.ammo_count(inventory, equipped)]
	if _reload_left > 0.0:
		text = "换弹中…"
	hud.set_ammo(text)


func _jump() -> void:
	if player.position.y <= 0.01 and stamina > 8.0:
		_vy = C.JUMP_SPEED
		stamina -= 8.0


func _update_zombies(delta: float, day: int, night: bool, horde: bool) -> void:
	_flow_t -= delta
	if _flow_t <= 0.0:
		_flow_t = 0.5
		world.update_flow(player.position)
	var alive := 0
	for z in zombie_root.get_children():
		if z.dead:
			continue
		alive += 1
		var dmg: float = z.try_attack()
		if dmg > 0.0:
			hp -= dmg
			hud.hurt()
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
		_spawn_zombie(day, night, horde)


func _spawn_zombie(day: int, night: bool, horde: bool, near := Vector3.INF) -> void:
	var z := Zombie.new()
	var model: String = Assets.zombie_models[rng.randi_range(0, Assets.zombie_models.size() - 1)]
	var spd := C.ZOMBIE_HORDE_SPEED if horde else (C.ZOMBIE_NIGHT_SPEED if night else C.ZOMBIE_WALK_SPEED)
	if not z.setup(model, C.ZOMBIE_BASE_HP + C.ZOMBIE_HP_PER_DAY * (day - 1), spd, player):
		z.free()
		return
	z.world = world
	if near != Vector3.INF:
		z.position = world.free_point(near, 4.0, 10.0)
	else:
		z.position = world.free_point(player.position, 18.0, 32.0) if not horde else world.free_point(player.position, 14.0, 24.0)
	z.died.connect(_on_zombie_died)
	z.screamed.connect(_on_scream)
	zombie_root.add_child(z)


func _on_zombie_died(z: Zombie) -> void:
	kills += 1
	Fx.blood_pool(self, z.global_position)
	if rng.randf() < C.ZOMBIE_DROP_CHANCE:
		_spawn_loot(z.global_position + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)))


## 尖叫者叫一声，附近再冒出几只僵尸
func _on_scream(z: Zombie) -> void:
	hud.toast("尖叫者在叫，附近的僵尸被引过来了！")
	var day := int(game_hours / 24.0) + 1
	for i in 3:
		if zombie_root.get_child_count() < C.ZOMBIE_MAX:
			_spawn_zombie(day, true, false, z.global_position)


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


func _update_loot(delta: float) -> void:
	var count := 0
	for l in loot_root.get_children():
		if l.is_queued_for_deletion():
			continue
		count += 1
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
		if player.position.distance_to(_search_from) > 0.8:
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


func _finish_search(c: Dictionary) -> void:
	_search = {}
	hud.set_progress(-1.0)
	c.searched = true
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
	var n := Weapons.pickup_count(id, rng) if Weapons.is_ammo(id) else 1
	inventory[id] = inventory.get(id, 0) + n
	if not pickup_order.has(id):
		pickup_order.append(id)
	var row: Dictionary = Assets.items_by_id[id]
	hud.toast("捡到：%s" % Assets.display_name(id) + (" ×%d" % n if n > 1 else ""))
	# 捡到更好的武器自动换上
	if row.kind in [Assets.Kind.MELEE, Assets.Kind.GUN]:
		var cur: Dictionary = Assets.items_by_id.get(equipped, {})
		if cur.is_empty() or row.power > cur.get("power", 0.0):
			_equip(id)
	_refresh_inventory()


func _use_item(id: String) -> void:
	if not inventory.has(id):
		return
	var row: Dictionary = Assets.items_by_id[id]
	match row.kind:
		Assets.Kind.MELEE, Assets.Kind.GUN:
			_equip("" if equipped == id else id)
		Assets.Kind.FOOD:
			food = min(C.MAX_FOOD, food + row.power)
			_consume(id, "吃了%s" % Assets.display_name(id))
		Assets.Kind.DRINK:
			food = min(C.MAX_FOOD, food + row.power * 0.6)
			hp = min(C.MAX_HP, hp + 5.0)
			_consume(id, "喝了%s" % Assets.display_name(id))
		Assets.Kind.MEDICAL:
			hp = min(C.MAX_HP, hp + row.power)
			_consume(id, "用了%s" % Assets.display_name(id))
		_:
			hud.toast("%s：材料，留着吧" % Assets.display_name(id))
	_refresh_inventory()


func _consume(id: String, msg: String) -> void:
	inventory[id] -= 1
	if inventory[id] <= 0:
		inventory.erase(id)
		pickup_order.erase(id)
	hud.toast(msg)


func _equip(id: String) -> void:
	equipped = id
	_reload_left = 0.0
	if id != "" and Assets.items_by_id[id].kind == Assets.Kind.GUN and not mags.has(id):
		# 捡到的枪里还剩点子弹
		mags[id] = int(ceil(Weapons.stats(id).mag * rng.randf_range(0.3, 1.0)))
	arms.hold(id)
	if id != "":
		hud.toast("装备：%s" % Assets.display_name(id))


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


# —— 生存、昼夜、音乐 ——

func _update_survival(delta: float) -> void:
	food = max(0.0, food - C.FOOD_DRAIN * delta)
	if food <= 0.0:
		hp -= C.STARVE_DAMAGE * delta
	elif food > 60.0:
		hp = min(C.MAX_HP, hp + delta * 0.4)


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
	for z in zombie_root.get_children():
		if not z.dead:
			nearest = min(nearest, z.distance_to_target())
	var want := "Exp"
	if horde and not Assets.music["Bld"].is_empty():
		want = "Bld"
	elif nearest < C.COMBAT_DISTANCE:
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
