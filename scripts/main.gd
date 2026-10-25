extends Node3D
## 游戏组装：创建世界和各个系统，连接信号；具体逻辑在 scripts/ 下的系统里。

const C = preload("res://scripts/config.gd")

var world: World
var hud: Hud
var music: MusicDirector
var atmosphere: Atmosphere
var player_sys: PlayerSystem
var inventory: InventorySystem
var combat: CombatSystem
var spawner: SpawnerSystem
var horde: Horde
var looting: LootingSystem
var respawn: RespawnSystem
var crafting: Crafting
var save_game: SaveGame
var time_sys: TimeOfDay
var graphics: GraphicsSystem
var rng := RandomNumberGenerator.new()

var running := false
var world_seed := 0


func _ready() -> void:
	rng.randomize()
	# 城市布局跟着存档走：继续上次时还是同一座城
	var save := SaveGame.read_save()
	world_seed = int(save.get("seed", rng.randi() % 1000000))

	atmosphere = Atmosphere.new()
	atmosphere.build(self, world_seed)

	world = World.new()
	add_child(world)
	world.build(world_seed)

	time_sys = TimeOfDay.new()

	hud = Hud.new()
	add_child(hud)

	music = MusicDirector.new()
	add_child(music)
	atmosphere.music = music
	atmosphere.hud = hud

	player_sys = PlayerSystem.new()
	player_sys.setup(self, world, hud, rng)
	player_sys.build()

	inventory = InventorySystem.new()
	inventory.setup(self, hud, player_sys.arms, player_sys, rng)
	add_child(inventory)

	looting = LootingSystem.new()
	looting.setup(self, world, player_sys, inventory, hud, rng)
	looting.build()

	respawn = RespawnSystem.new()
	respawn.setup(self, world, player_sys, inventory, looting, hud)
	respawn.build()
	GameState.player_respawned.connect(_on_respawned)

	spawner = SpawnerSystem.new()
	spawner.setup(self, world, player_sys, hud, looting, rng)
	spawner.build()

	horde = Horde.new()
	horde.setup(self, spawner, world, player_sys, time_sys, rng)

	combat = CombatSystem.new()
	combat.setup(self, get_tree(), player_sys, inventory, world, hud, player_sys.arms, spawner.zombie_root, rng)
	add_child(combat)
	combat.build()
	inventory.combat = combat
	player_sys.inventory = inventory

	graphics = GraphicsSystem.new()
	graphics.setup(self, world, atmosphere, player_sys, hud, spawner.zombie_root)

	crafting = Crafting.new()
	crafting.name = "Crafting"
	add_child(crafting)
	crafting.setup(inventory, looting, player_sys, hud)
	hud.craft_panel.bind(crafting)

	save_game = SaveGame.new()
	save_game.setup(self, world, player_sys, inventory, combat, spawner, horde, atmosphere, hud, time_sys)

	hud.start_pressed.connect(start)
	hud.restart_pressed.connect(start)
	hud.item_used.connect(inventory.use_item)
	hud.item_dropped.connect(looting.drop_slot)
	hud.bag_compact_pressed.connect(inventory.compact)
	hud.action_pressed.connect(looting.action)
	hud.reload_pressed.connect(combat.reload)
	hud.rotate_pressed.connect(combat.rotate_block)
	hud.jump_pressed.connect(player_sys.jump)
	hud.crouch_pressed.connect(player_sys.toggle_crouch)
	hud.continue_pressed.connect(save_game.continue_game)
	hud.quit_to_title.connect(func():
		save_game.save()
		running = false
		GameState.running = false
		combat.running = false
		looting.running = false
		graphics.on_stop()
		crafting.running = false
		music.stop_all()
		Sfx.stop_loops()
		hud.show_start(true))
	hud.back_to_title.connect(func():
		running = false
		GameState.running = false
		combat.running = false
		looting.running = false
		crafting.running = false
		music.stop_all()
		Sfx.stop_loops()
		hud.show_start(save_game.read_save().has("hours")))
	hud.settings_changed.connect(_apply_settings)
	_apply_settings(hud.settings)
	hud.show_start(save.has("hours"))

	time_sys.reset()
	var info := "素材：物品 %d 个（武器、食物、药品等 %d 个可拾取），僵尸 %d 种，音乐 %d 段" % [
		Assets.items.size(), _count_loot(), Assets.zombie_models.size(),
		Assets.music.values().reduce(func(a, l): return a + l.size(), 0)]
	if not Assets.errors.is_empty():
		info += "\n注意：" + "；".join(Assets.errors)
	hud.set_start_info(info)
	atmosphere.update_sky(time_sys.hours)


func _apply_settings(st: Dictionary) -> void:
	Sfx.set_volume("Sfx", st.volume)
	Sfx.set_volume("Music", st.music)
	atmosphere.set_brightness(st.brightness)
	graphics.apply_settings(st)


# —— 存档：切到后台、关窗口时自动存 ——

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		if running and save_game:
			save_game.save()


func _count_loot() -> int:
	var n := 0
	for k in Assets.loot_pool:
		n += Assets.loot_pool[k].size()
	return n


# —— 开局 / 结束 ——

func start(fresh := true) -> void:
	hud.close_game_panels()
	spawner.reset()
	horde.reset()
	looting.reset()
	respawn.reset()
	time_sys.reset()
	player_sys.reset()
	inventory.reset()
	crafting.reset()
	combat.reset()
	atmosphere.reset()
	GameState.running = true
	graphics.on_start()

	for c in world.containers:
		c.searched = false
		c.erase("items")
	world.clear_voxels()
	world.door_load([])
	for i in C.LOOT_COUNT / 2:
		looting.spawn_loot(world.free_point(Vector3.ZERO, 4.0, 60.0))
	if fresh:
		if C.TEST_ALL_ITEMS:
			inventory.give_all_items()
		else:
			inventory.give_starter_kit()
		respawn.on_start(true)
	# 开局在面前放一件近战武器，马上就能看到手里的模型
	var weapons: Array = Assets.loot_pool.get(Assets.Kind.MELEE, [])
	if not weapons.is_empty() and not C.TEST_ALL_ITEMS:
		var with_model := weapons.filter(func(id): return Assets.items_by_id[id].model != "")
		var pick: String = (with_model if not with_model.is_empty() else weapons).pick_random()
		looting.spawn_loot(Vector3(0, 0, -3.0), pick)
	running = true
	combat.running = true
	looting.running = true
	crafting.running = true
	hud.set_banner("")
	inventory.refresh()
	save_game.reset_timer()
	if fresh and C.TEST_ALL_ITEMS:
		hud.toast("测试模式：全部物品和建造方块都在背包里，子弹用不完")
	elif fresh:
		hud.toast("第 1 天。找武器、找吃的，天黑前做好准备。")
		save_game.save()


func _compass_markers() -> Array:
	var out := []
	if respawn.has_bedroll():
		out.append(_compass_marker(respawn.respawn_point(), Color(0.45, 0.75, 1.0)))
	for b in looting.corpse_bags:
		out.append(_compass_marker(b.pos, Color(1.0, 0.4, 0.3)))
	return out


func _compass_marker(pos: Vector3, color: Color) -> Dictionary:
	var d := pos - player_sys.player.position
	return {"bearing": rad_to_deg(atan2(d.x, -d.z)), "color": color}


## 死了：PERMADEATH 下结算删档；否则停住游戏，黑屏后在睡袋醒来（respawn.gd）
func _die() -> void:
	if C.PERMADEATH:
		_end()
		return
	running = false
	combat.running = false
	looting.running = false
	crafting.running = false
	hud.close_game_panels()
	respawn.die()
	save_game.save()


func _on_respawned(_pos: Vector3) -> void:
	if not GameState.running:
		return
	running = true
	combat.running = true
	looting.running = true
	crafting.running = true
	save_game.save()


func _end() -> void:
	running = false
	GameState.running = false
	combat.running = false
	looting.running = false
	graphics.on_stop()
	crafting.running = false
	save_game.delete_save()
	music.stop_all()
	Sfx.stop_loops()
	Sfx.play("death")
	music.request("Sus", 99.0)
	hud.show_end("你死在了第 %d 天\n活过 %d 次血月，击杀 %d 只僵尸" % [
		time_sys.day, time_sys.blood_moons_survived, spawner.kills])


# —— 每帧 ——

func _process(delta: float) -> void:
	if not running:
		atmosphere.update_sky(time_sys.hours)
		return
	var hours_before := time_sys.hours
	time_sys.update(delta)
	var day := time_sys.day
	var hour := fmod(time_sys.hours, 24.0)
	var night := time_sys.night
	var blood_moon := time_sys.blood_moon

	player_sys.aiming = hud.aim_held \
		and Assets.items_by_id.get(inventory.equipped, {}).get("kind", -1) == Assets.Kind.GUN
	player_sys.update(delta)
	combat.update(delta)
	spawner.update(delta, day, night, blood_moon)
	horde.update(delta, blood_moon, day)
	looting.update_loot(delta)
	looting.update_action(delta)
	respawn.update(delta)
	player_sys.update_survival(delta, time_sys.hours - hours_before)
	if graphics.sky_due(delta):
		atmosphere.update_sky(time_sys.hours)
	atmosphere.update_music(delta, night, blood_moon, spawner.zombie_root)
	atmosphere.update_banner(day, hour, night, blood_moon)
	save_game.update(delta)
	graphics.update(delta)

	var near := 0
	for z in spawner.zombie_root.get_children():
		if not z.dead and z.distance_to_target() < C.TENSION_DISTANCE:
			near += 1
	hud.set_status(day, hour, player_sys.hp, player_sys.food, spawner.kills, near, night,
		day % C.BLOOD_MOON_EVERY == 0 or blood_moon, blood_moon, GameState.next_blood_moon_day())
	hud.set_compass(player_sys.yaw, _compass_markers())
	if player_sys.hp <= 0.0:
		_die()
