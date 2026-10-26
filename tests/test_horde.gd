extends Node
## 1b 验收：官方血月阶段表、游戏阶段和同时上限。

func _ready() -> void:
	var failures: Array[String] = []
	var t := TimeOfDay.new()
	t.seconds_per_day = 1.0
	t.reset()
	t.set_time(6 * 24.0 + 22.0)  # 第 7 天 22:00
	Progression.level = 7  # 7a：游戏阶段改用真实等级
	if GameState.gamestage() != 16:
		failures.append("第 7 天 GS 应为 16，实际 %d" % GameState.gamestage())
	var h := Horde.new()
	h.time_sys = t
	h.rng = RandomNumberGenerator.new()
	h.start()
	var p: Dictionary = h.plan()
	if int(p.get("stage", 0)) <= 0:
		failures.append("应从 gamestages.json 选到血月阶段")
	if int(p.get("total", 0)) <= 0:
		failures.append("血月总数应大于 0")
	if int(p.get("max_alive", 0)) != 10:
		failures.append("第 1 次血月同时上限应为 10，实际 %s" % p.get("max_alive"))
	t.blood_moons_survived = 1
	h.start()
	if int(h.plan().get("max_alive", 0)) != 12:
		failures.append("第 2 次血月同时上限应更高")
	h.end()
	if h.started:
		failures.append("end() 后血月应停止")
	if not Data.get_table("gamestages").has("BloodMoonHorde"):
		failures.append("gamestages.json 应有 BloodMoonHorde")
	if not Data.get_table("entitygroups").has("feralHordeStageGS1"):
		failures.append("entitygroups.json 应有 feralHordeStageGS1")
	if failures.is_empty():
		print("PASS test_horde")
		get_tree().quit(0)
	else:
		for f in failures:
			push_error("test_horde: " + f)
		print("FAIL test_horde（%d 项）" % failures.size())
		get_tree().quit(1)
