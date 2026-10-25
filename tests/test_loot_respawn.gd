extends Node
## 2a 验收（不依赖素材）：容器 5 天重生、保险箱判定、旧标签映射、搜索时长。

const MAIN = preload("res://scenes/main.tscn")
const C = preload("res://scripts/config.gd")

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(90.0).timeout.connect(func():
		push_error("test_loot_respawn 超时")
		get_tree().quit(1))


func _run() -> void:
	var main = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.start(false)
	await get_tree().process_frame

	# 翻空的容器 5 天后重生
	var c := {"name": "测试箱", "pos": Vector3(8, 0, 8), "loot": "garbage", "searched": true,
		"items": [{}, {}], "loot_day": 1, "r": 0.5, "kind": "loot"}
	main.world.containers.append(c)
	main.looting._on_day_started(1 + C.LOOT_RESPAWN_DAYS)
	check(not c.searched and not c.has("items") and not c.has("loot_day"), "翻空的容器 5 天后应重生")

	# 还有东西的容器不重生
	var d := {"name": "测试箱2", "pos": Vector3(9, 0, 9), "loot": "garbage", "searched": true,
		"items": [{}, {"id": "resourceWood", "count": 1}], "loot_day": 2, "r": 0.5, "kind": "loot"}
	main.world.containers.append(d)
	main.looting._on_day_started(2 + C.LOOT_RESPAWN_DAYS)
	check(d.searched, "还有东西的容器不该重生")

	# 保险箱判定
	check(main.looting.is_safe({"block": "cntGunSafe", "container": "gunSafe"}), "枪柜应判定为保险箱")
	check(main.looting.is_safe({"container": "smallSafes"}), "小保险箱应判定为保险箱")
	check(not main.looting.is_safe({"container": "garbage"}), "垃圾桶不是保险箱")
	check(main.looting.is_safe({"name": "保险箱"}), "中文名保险箱也算")

	# 旧标签 → 官方容器名；楼里优先用 container 字段
	check_eq(main.looting._loot_name({"loot": "trash"}), "garbage", "旧 trash 标签")
	check_eq(main.looting._loot_name({"loot": "cars"}), "cars", "新官方名保持不变")
	check_eq(main.looting._loot_name({"container": "gunSafe", "loot": "any"}), "gunSafe", "楼里用 container")

	# 搜索时长
	check_close(main.looting._search_need({"kind": "car"}), C.SEARCH_TIME_CAR, 0.001, "车 3 秒")
	check_close(main.looting._search_need({"block": "cntGunSafe"}), C.SEARCH_TIME_SAFE, 0.001, "保险箱 6 秒")
	check_close(main.looting._search_need({"kind": "loot"}), C.SEARCH_TIME, 0.001, "小容器 1.5 秒")

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


func _finish() -> void:
	GameState.player = null
	if failures.is_empty():
		print("PASS test_loot_respawn")
		get_tree().quit(0)
		return
	for m in failures:
		push_error("test_loot_respawn: " + m)
	print("FAIL test_loot_respawn（%d 项）" % failures.size())
	get_tree().quit(1)
