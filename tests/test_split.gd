extends Node
## 0a 验收：main 拆成系统后，开局、受伤、存档、读档仍然正常。
## 没有素材也能跑；测试前会备份并还原玩家存档。

const MAIN = preload("res://scenes/main.tscn")
const C = preload("res://scripts/config.gd")

var failures: Array[String] = []
var _elapsed := 0.0
var _save_existed := false
var _save_data := PackedByteArray()
var _bak_existed := false
var _bak_data := PackedByteArray()
var _main: Node


func _ready() -> void:
	if FileAccess.file_exists("user://save.json"):
		_save_existed = true
		_save_data = FileAccess.get_file_as_bytes("user://save.json")
	if FileAccess.file_exists("user://save.bak"):
		_bak_existed = true
		_bak_data = FileAccess.get_file_as_bytes("user://save.bak")
	_run.call_deferred()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > 120.0:
		push_error("test_split 超时")
		_restore_save()
		get_tree().quit(1)


func _run() -> void:
	check(get_node_or_null("/root/GameState") != null, "GameState 自动加载应存在")
	var main = MAIN.instantiate()
	_main = main
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	check(main.get("player_sys") != null, "player_sys 应存在")
	check(main.get("inventory") != null, "inventory 应存在")
	check(main.get("combat") != null, "combat 应存在")
	check(main.get("spawner") != null, "spawner 应存在")
	check(main.get("looting") != null, "looting 应存在")
	check(main.get("save_game") != null, "save_game 应存在")
	if failures.size() > 0:
		_finish()
		return

	main.start(false)
	await get_tree().process_frame
	check(main.running, "开局后 running 应为 true")
	check_close(main.player_sys.hp, C.MAX_HP, 0.01, "开局应满血")
	# 手动跑 3 秒，覆盖玩家、战斗、刷怪、搜刮、天空、音乐和自动存档的每帧路径
	main.set_process(false)
	for i in 180:
		main._process(1.0 / 60.0)
	main.set_process(true)
	check(main.running, "3 秒后不应结束")
	main.player_sys.take_damage(10.0, "test")
	check_close(main.player_sys.hp, C.MAX_HP - 10.0, 0.01, "受伤应扣血")

	# 手感：后坐力应回弹，开镜应收窄 FOV，命中标记应出现
	main.player_sys.add_recoil(0.2)
	for i in 30:
		main.player_sys.update(1.0 / 60.0)
	check(main.player_sys._recoil < 0.2, "后坐力应随时间回弹")
	main.player_sys.aiming = true
	for i in 60:
		main.player_sys.update(1.0 / 60.0)
	check(main.player_sys.camera.fov < C.BASE_FOV, "开镜 FOV 应收窄")
	main.player_sys.aiming = false
	main.hud.hitmarker(true)
	main.hud.crosshair_kick()
	check(main.hud._hitmarker.modulate.a > 0.0, "命中标记应显示")

	# 存档写入版本号、时间、血月次数，并能读回玩家状态
	main.player_sys.hp = 77.0
	main.time_sys.set_time(7 * 24.0 + 3.9)
	main.time_sys.blood_moons_survived = 2
	main.horde.start()
	var horde_left: int = main.horde.remaining
	main.save_game.save()
	var d: Dictionary = main.save_game.read_save()
	check_eq(d.get("version", -1), 2, "存档应有 version=2")
	check_close(float(d.get("hp", 0.0)), 77.0, 0.01, "存档 hp 应正确")
	check_eq(int(d.get("blood_moons_survived", -1)), 2, "存档应保存血月次数")
	main.player_sys.hp = 1.0
	main.save_game.continue_game()
	check_close(main.player_sys.hp, 77.0, 0.01, "读档应恢复 hp")
	check(main.running, "读档后应继续运行")
	check_eq(main.time_sys.day, 8, "读档应恢复第 8 天")
	check_eq(main.time_sys.blood_moons_survived, 2, "读档应恢复血月次数")
	check(main.time_sys.blood_moon, "第 8 天 03:54 读档应处于血月")
	check(main.horde.started, "读档后血月应接着刷")
	check_eq(main.horde.remaining, horde_left, "读档应恢复剩余血月僵尸数")

	# 旧版存档没有 version 和新字段，也要能读
	var old := {
		"seed": 1, "hours": 30.0, "hp": 42.0, "food": 50.0, "water": 60.0,
		"stamina": 80.0, "kills": 3, "inventory": {}, "order": [], "equipped": "",
		"mags": {}, "pos": [0.0, 0.0], "yaw": 0.0, "searched": [], "blocks": [],
	}
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(old))
		f.close()
	main.save_game.continue_game()
	check_close(main.player_sys.hp, 42.0, 0.01, "旧存档应能读")
	check_eq(main.spawner.kills, 3, "旧存档击杀数")
	main.running = false

	# 有素材时检查：开局背包里有枪弹，并且枪已经拿在手上
	var has_gun := false
	for row in Assets.items:
		if row.kind == Assets.Kind.GUN:
			has_gun = true
			break
	if has_gun:
		main.start(true)
		var eq: String = main.inventory.equipped
		check(eq != "", "开局应装备枪")
		check_eq(Assets.items_by_id.get(eq, {}).get("kind", -1), Assets.Kind.GUN, "开局装备应为枪")
		var has_ammo := false
		for id in main.inventory.inventory:
			if Weapons.is_ammo(id) and int(main.inventory.inventory[id]) > 0:
				has_ammo = true
				break
		check(has_ammo, "开局背包里应有子弹")
		check(not main.inventory.mags_type.is_empty(), "开局枪应有弹种")
		check(main.inventory.inventory.size() >= 500, "测试模式背包应包含完整道具表")
		main.running = false
	_finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s：期望 %s，实际 %s" % [message, expected, actual])


func check_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s：期望 %.4f，实际 %.4f" % [message, expected, actual])


func _restore_save() -> void:
	if _save_existed:
		var f := FileAccess.open("user://save.json", FileAccess.WRITE)
		if f:
			f.store_buffer(_save_data)
			f.close()
	elif FileAccess.file_exists("user://save.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
	if _bak_existed:
		var b := FileAccess.open("user://save.bak", FileAccess.WRITE)
		b.store_buffer(_bak_data)
		b.close()
	elif FileAccess.file_exists("user://save.bak"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.bak"))


func _finish() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs:
		gs.player = null
	_restore_save()
	if failures.is_empty():
		print("PASS test_split")
		get_tree().quit(0)
		return
	for f in failures:
		push_error("test_split: " + f)
	print("FAIL test_split（%d 项）" % failures.size())
	get_tree().quit(1)
