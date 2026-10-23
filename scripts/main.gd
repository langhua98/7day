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
var looting: LootingSystem
var save_game: SaveGame
var rng := RandomNumberGenerator.new()

var running := false
var game_hours := C.START_HOUR   # 从第 1 天 0 点起算的小时数
var world_seed := 0
var _last_hour := -1
var _last_day := 0
var _was_night := false


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

	spawner = SpawnerSystem.new()
	spawner.setup(self, world, player_sys, hud, looting, rng)
	spawner.build()

	combat = CombatSystem.new()
	combat.setup(self, get_tree(), player_sys, inventory, world, hud, player_sys.arms, spawner.zombie_root, rng)
	add_child(combat)
	combat.build()
	inventory.combat = combat

	save_game = SaveGame.new()
	save_game.setup(self, world, player_sys, inventory, combat, spawner, atmosphere, hud)

	hud.start_pressed.connect(start)
	hud.restart_pressed.connect(start)
	hud.item_used.connect(inventory.use_item)
	hud.action_pressed.connect(looting.action)
	hud.reload_pressed.connect(combat.reload)
	hud.jump_pressed.connect(player_sys.jump)
	hud.continue_pressed.connect(save_game.continue_game)
	hud.quit_to_title.connect(func():
		save_game.save()
		running = false
		GameState.running = false
		combat.running = false
		looting.running = false
		Sfx.stop_loops()
		hud.show_start(true))
	hud.settings_changed.connect(_apply_settings)
	_apply_settings(hud.settings)
	hud.show_start(save.has("hours"))

	GameState.reset()
	GameState.hours = game_hours
	GameState.day = 1
	GameState.gamestage = 1
	var info := "素材：物品 %d 个（武器、食物、药品等 %d 个可拾取），僵尸 %d 种，音乐 %d 段" % [
		Assets.items.size(), _count_loot(), Assets.zombie_models.size(),
		Assets.music.values().reduce(func(a, l): return a + l.size(), 0)]
	if not Assets.errors.is_empty():
		info += "\n注意：" + "；".join(Assets.errors)
	hud.set_start_info(info)
	atmosphere.update_sky(game_hours)


func _apply_settings(st: Dictionary) -> void:
	Sfx.set_volume("Sfx", st.volume)
	Sfx.set_volume("Music", st.music)
	atmosphere.set_brightness(st.brightness)


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
	spawner.reset()
	looting.reset()
	game_hours = C.START_HOUR
	player_sys.reset()
	inventory.reset()
	combat.reset()
	atmosphere.reset()
	GameState.reset()
	GameState.hours = game_hours
	GameState.day = 1
	GameState.gamestage = 1
	GameState.running = true
	_last_hour = int(C.START_HOUR)
	_last_day = 1
	_was_night = false

	for c in world.containers:
		c.searched = false
	world.clear_voxels()
	for i in C.LOOT_COUNT / 2:
		looting.spawn_loot(world.free_point(Vector3.ZERO, 4.0, 60.0))
	if C.TEST_ALL_ITEMS and fresh:
		inventory.give_all_items()
	# 开局在面前放一件近战武器，马上就能看到手里的模型
	var weapons: Array = Assets.loot_pool.get(Assets.Kind.MELEE, [])
	if not weapons.is_empty() and not C.TEST_ALL_ITEMS:
		var with_model := weapons.filter(func(id): return Assets.items_by_id[id].model != "")
		var pick: String = (with_model if not with_model.is_empty() else weapons).pick_random()
		looting.spawn_loot(Vector3(0, 0, -3.0), pick)
	running = true
	combat.running = true
	looting.running = true
	hud.set_banner("")
	inventory.refresh()
	save_game.reset_timer()
	if fresh and C.TEST_ALL_ITEMS:
		hud.toast("测试模式：全部物品和建造方块都在背包里，子弹用不完")
	elif fresh:
		hud.toast("第 1 天。找武器、找吃的，天黑前做好准备。")
		save_game.save()


func _end(win: bool) -> void:
	running = false
	GameState.running = false
	combat.running = false
	looting.running = false
	save_game.delete_save()
	Sfx.stop_loops()
	if not win:
		Sfx.play("death")
	music.request("Exp" if win else "Sus", 99.0)
	var day := int(game_hours / 24.0) + 1
	if win:
		hud.show_end("你活过了第七天的血月！\n击杀 %d 只僵尸" % spawner.kills)
	else:
		hud.show_end("你死在了第 %d 天\n击杀 %d 只僵尸" % [day, spawner.kills])


# —— 每帧 ——

func _process(delta: float) -> void:
	if not running:
		atmosphere.update_sky(game_hours)
		return
	game_hours += delta * 24.0 / C.DAY_SECONDS
	var day := int(game_hours / 24.0) + 1
	var hour := fmod(game_hours, 24.0)
	var night := hour >= C.NIGHT_START or hour < C.NIGHT_END
	var horde := (day == C.HORDE_DAY and hour >= C.NIGHT_START) or (day == C.HORDE_DAY + 1 and hour < C.NIGHT_END)
	GameState.hours = game_hours
	GameState.day = day
	GameState.gamestage = day
	var hour_int := int(hour)
	if hour_int != _last_hour:
		_last_hour = hour_int
		GameState.hour_changed.emit(day, hour)
	if day != _last_day:
		_last_day = day
		GameState.day_started.emit(day)
	if night and not _was_night:
		GameState.night_started.emit()
	elif not night and _was_night:
		GameState.dawn.emit()
	_was_night = night

	if day > C.HORDE_DAY and hour >= C.NIGHT_END:
		_end(true)
		return

	player_sys.update(delta)
	looting.update(delta)
	combat.update(delta)
	spawner.update(delta, day, night, horde)
	looting.update_loot(delta)
	looting.update_action(delta)
	player_sys.update_survival(delta)
	atmosphere.update_sky(game_hours)
	atmosphere.update_music(delta, night, horde, spawner.zombie_root)
	atmosphere.update_banner(day, hour, night, horde)
	save_game.update(delta)

	var near := 0
	for z in spawner.zombie_root.get_children():
		if not z.dead and z.distance_to_target() < C.TENSION_DISTANCE:
			near += 1
	hud.set_status(day, hour, player_sys.hp, player_sys.food, spawner.kills, near, night)
	if player_sys.hp <= 0.0:
		_end(false)
