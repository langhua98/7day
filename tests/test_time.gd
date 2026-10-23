extends Node
## 1a 验收：24 分钟一天、无尽、血月每 7 天、18/21 点预警、04:00 结束。
## 测试直接调 TimeOfDay，不需要素材。

const C = preload("res://scripts/config.gd")

var failures: Array[String] = []


func _ready() -> void:
	check(GameState != null, "GameState 应存在")

	# 24 分钟一天；测试里用 1 秒一天方便推进
	var t := TimeOfDay.new()
	t.seconds_per_day = 1.0
	t.reset()
	check_eq(t.day, 1, "开局第 1 天")
	check_close(t.hours, C.START_HOUR, 0.01, "开局小时")

	var warnings: Array[int] = []
	GameState.blood_moon_warning.connect(func(h: int): warnings.append(h))
	var started := [0]
	var ended := [0]
	GameState.blood_moon_started.connect(func(): started[0] += 1)
	GameState.blood_moon_ended.connect(func(_n: int): ended[0] += 1)

	# 第 7 天 17:54 起，18 点预警
	t.set_time(6 * 24.0 + 17.9)
	t.update(0.01)
	check(warnings.has(18), "第 7 天 18:00 应有预警")
	# 推进到 22 点：21 点预警 + 血月开始
	t.update(0.2)
	check(warnings.has(21), "第 7 天 21:00 应有预警")
	check(t.blood_moon, "第 7 天 22:00 后应进入血月")
	check(GameState.is_blood_moon(), "GameState.is_blood_moon")
	check_eq(started[0], 1, "血月开始信号只发一次")
	check_eq(GameState.next_blood_moon_day(), 14, "血月中下次是第 14 天")

	# 第 8 天 03:54，04:00 血月结束
	var t2 := TimeOfDay.new()
	t2.seconds_per_day = 1.0
	t2.reset()
	t2.set_time(7 * 24.0 + 3.9)
	t2.update(0.01)
	check(not t2.blood_moon, "第 8 天 04:00 后血月应结束")
	check_eq(t2.blood_moons_survived, 1, "活过一次血月")
	check_eq(ended[0], 1, "血月结束信号")
	check(not GameState.is_blood_moon(), "GameState 血月状态应清掉")

	# 下次血月天数
	var t3 := TimeOfDay.new()
	t3.seconds_per_day = 1.0
	t3.reset()
	t3.set_time(0 * 24.0 + 8.0)
	check_eq(GameState.next_blood_moon_day(), 7, "第 1 天时下次是第 7 天")
	t3.set_time(7 * 24.0 + 5.0)
	check_eq(GameState.next_blood_moon_day(), 14, "第 8 天时下次是第 14 天")

	# 无尽：10 秒（10 天）不会触发胜利/结束；时间继续走
	var t4 := TimeOfDay.new()
	t4.seconds_per_day = 1.0
	t4.reset()
	t4.update(10.0)
	check(t4.day >= 11, "时间应继续到第 11 天以后")
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
	if failures.is_empty():
		print("PASS test_time")
		get_tree().quit(0)
		return
	for f in failures:
		push_error("test_time: " + f)
	print("FAIL test_time（%d 项）" % failures.size())
	get_tree().quit(1)
