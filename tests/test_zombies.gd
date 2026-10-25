extends Node
## 6c 验收：官方僵尸数值、野性/辐射变体、眼睛发光、辐射回血、警察吐酸、拆弹自爆、蜘蛛跳。
## 没有 zombies.json 时跳过；模型没下载的条目跳过对应的场景检查。

const MAIN = preload("res://scenes/main.tscn")
const C = preload("res://scripts/config.gd")

var failures: Array[String] = []
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 7
	_run.call_deferred()
	get_tree().create_timer(150.0).timeout.connect(func():
		push_error("test_zombies 超时")
		get_tree().quit(1))


func _run() -> void:
	var table: Dictionary = Data.get_table("zombies")
	if table.is_empty():
		print("SKIP test_zombies（沙盒没有 zombies.json）")
		get_tree().quit(0)
		return
	_test_data(table)
	await _test_scene()
	_finish()


func _test_data(table: Dictionary) -> void:
	check(table.has("zombieJoe"), "应有 joe 的官方数据")
	var joe: Dictionary = table.get("zombieJoe", {})
	check(float(joe.get("hp", 0.0)) > 0.0, "joe 血量应来自 JSON")
	check(float(joe.get("speed", 0.0)) > 0.0, "joe 速度应来自 JSON")
	check(float(joe.get("xp", 0.0)) > 0.0, "joe 经验应来自 JSON")
	check(float(joe.get("damage", 0.0)) > 0.0, "joe 攻击应来自 JSON")
	var normal := Zombies.stats("joe", "normal")
	var feral := Zombies.stats("joe", "feral")
	var radiated := Zombies.stats("joe", "radiated")
	check(not normal.is_empty() and not feral.is_empty() and not radiated.is_empty(), "joe 应有普通/野性/辐射三种")
	check_close(float(feral.hp), float(normal.hp) * C.ZOMBIE_FERAL_HP, 0.1, "野性血 ×1.5")
	check(float(feral.speed) > float(normal.speed), "野性更快")
	check_close(float(radiated.hp), float(normal.hp) * C.ZOMBIE_FERAL_HP * C.ZOMBIE_RADIATED_HP, 0.1, "辐射血再 ×2")
	check(bool(radiated.get("radiated", false)) and not bool(normal.get("radiated", false)), "辐射标记")
	# GS1 只有普通，GS60 能出辐射和野性
	for i in 200:
		if Zombies.pick_variant("joe", 1, rng) != "normal":
			failures.append("GS1 不应出变体")
			break
	var saw_rad := false
	var saw_feral := false
	for i in 400:
		var v := Zombies.pick_variant("joe", 60, rng)
		if v == "radiated":
			saw_rad = true
		elif v == "feral":
			saw_feral = true
	check(saw_feral, "GS60 应能出野性")
	check(saw_rad, "GS60 应能出辐射")
	var big := Zombies.stats("bigmama", "normal")
	check(bool(big.get("big", false)), "大妈妈应是大块头")


func _test_scene() -> void:
	if Assets.zombie_models.is_empty():
		print("SKIP test_zombies 场景部分（没有僵尸模型）")
		return
	var main = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.start(false)
	await get_tree().process_frame
	var sp: SpawnerSystem = main.spawner
	# 野性：血更多、眼睛发光
	var zf = sp.spawn_zombie_at("zombieJoe", "feral", 1, false, false, Vector3(10, 0, 10))
	if zf:
		check(zf.feral and not zf.radiated, "野性标记")
		check(zf.hp > float(Zombies.stats("joe", "normal").get("hp", 0.0)) * 1.4, "野性血更多")
		check(zf._eye_node != null, "野性应有发光眼睛")
	# 辐射：绿色 + 每秒回血
	var zr = sp.spawn_zombie_at("zombieJoe", "radiated", 1, false, false, Vector3(12, 0, 12))
	if zr:
		check(zr.radiated, "辐射标记")
		check(zr._eye_node != null, "辐射应有发光眼睛")
		zr.hp = zr.max_hp * 0.5
		zr._process(1.0)
		check(zr.hp > zr.max_hp * 0.5, "辐射僵尸每秒回血")
	# 警察
	var zc = sp.spawn_zombie_at("zombieFatCop", "normal", 1, false, false, Vector3(14, 0, 14))
	if zc:
		check_eq(zc.special, "cop", "警察会吐酸")
	# 拆弹：从背后打会自爆
	var zd = sp.spawn_zombie_at("zombieDemolition", "normal", 1, false, false, Vector3(16, 0, 16))
	if zd:
		zd.rotation.y = 0.0
		var behind: Vector3 = zd.global_position - zd.global_basis.z * 2.0
		zd.take_hit(1.0, behind)
		check(zd._exploded and zd.dead, "拆弹僵尸背后被打会爆炸")
	# 蜘蛛：会跳
	var zs = sp.spawn_zombie_at("zombieSpider", "normal", 1, false, false, Vector3(20, 0, 20))
	if zs:
		main.player_sys.player.position = Vector3(20, 0, 24)
		zs.brain.chase()
		zs.brain.can_see = true
		zs._process(0.1)
		check(zs._jump_vy > 0.0, "蜘蛛会跳")
	# 大块头：拆弹僵尸应判定为大块头
	var zb = Zombies.stats("demolition", "normal")
	check(bool(zb.get("big", false)), "拆弹僵尸应是大块头")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s：期望 %s，实际 %s" % [message, expected, actual])


func check_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s：期望 %.4f，实际 %.4f" % [message, expected, actual])


func _finish() -> void:
	GameState.player = null
	if failures.is_empty():
		print("PASS test_zombies")
		get_tree().quit(0)
		return
	for m in failures:
		push_error("test_zombies: " + m)
	print("FAIL test_zombies（%d 项）" % failures.size())
	get_tree().quit(1)
