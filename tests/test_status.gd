extends Node
## 3a 验收：状态效果框架、饥渴按游戏小时、读档保留、旧存档迁移。不需要素材。

const C = preload("res://scripts/config.gd")

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var st = get_node_or_null("/root/Status")
	check(st != null, "Status 自动加载应存在")
	if st == null:
		_finish()
		return
	var hud := Hud.new()
	add_child(hud)
	await get_tree().process_frame
	var p := PlayerSystem.new()
	var rng := RandomNumberGenerator.new()
	var holder := Node3D.new()
	add_child(holder)
	p.setup(holder, null, hud, rng)
	st.clear()

	# 不吃不喝：约 40 游戏小时开始掉血（水 100 / 2.5）
	var first_loss := -1.0
	var h := 0.0
	while h < 48.0:
		var hp_before := p.hp
		p.update_survival(1.0, 0.1)
		h += 0.1
		if first_loss < 0.0 and p.hp < hp_before - 0.0001:
			first_loss = h
	check(first_loss > 38.0 and first_loss < 42.0, "约 40 游戏小时开始掉血，实际 %.1f" % first_loss)
	check(st.has("dehydrated"), "水为 0 应有脱水")
	check(st.has("thirsty"), "水低于 25 应有口渴")
	check(st.has("hungry"), "饱食低于 25 应有饥饿")
	check_close(st.offset("stamina_max"), -25.0, 0.01, "口渴体力上限 −25")
	check_close(st.modifier("stamina_regen"), 0.5, 0.01, "饥饿体力恢复 ×0.5")
	# 吃喝后停止掉血
	p.add_water(80.0)
	p.add_food(80.0)
	var hp_now := p.hp
	for i in 10:
		p.update_survival(1.0, 0.1)
	check(not st.has("dehydrated") and not st.has("thirsty"), "喝水后脱水口渴应解除")
	check(p.hp >= hp_now - 0.0001, "吃喝后不再掉血")

	# 改一天长度，按游戏小时节奏不变
	var foods := []
	for spd in [24.0 * 60.0, 60.0]:
		st.clear()
		p.food = 100.0
		p.water = 100.0
		var t := TimeOfDay.new()
		t.seconds_per_day = spd
		t.reset()
		var real: float = spd / 24.0 * 10.0  # 10 游戏小时
		var step: float = real / 200.0
		for i in 200:
			var h0 := t.hours
			t.update(step)
			p.update_survival(step, t.hours - h0)
		foods.append(p.food)
	check_close(foods[0], 100.0 - 16.0, 0.05, "10 游戏小时掉 16 饱食")
	check_close(foods[0], foods[1], 0.05, "不同一天长度下饱食相同")

	# 咖啡因叠饥饿
	st.clear()
	st.add("caffeine", 1.5)
	check_close(st.modifier("stamina_regen"), 2.2, 0.01, "咖啡因 ×2.2")
	# 到期自动移除
	st.add("bleeding")
	check_close(st.remaining("bleeding"), 0.67, 0.001, "流血默认 0.67 游戏小时")
	var dmg: Dictionary = st.tick(10.0, 0.5)
	check_close(float(dmg.hp), -7.0, 0.01, "流血每秒 −0.7")
	st.tick(10.0, 0.5)
	check(not st.has("bleeding"), "流血到期应止住")
	check(st.has("caffeine"), "咖啡因 1.5 小时还没到")

	# 存档、读档保留
	st.clear()
	st.add("bleeding", 0.5)
	st.add("dysentery", 1.0)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(st.save_data()))
	st.clear()
	st.load_data(saved)
	check_close(st.remaining("bleeding"), 0.5, 0.001, "读档流血剩余")
	check_close(st.remaining("dysentery"), 1.0, 0.001, "读档腹泻剩余")
	check_close(st.modifier("water_drain"), 3.5, 0.01, "腹泻水分 ×3.5")
	# 旧存档：bleed/sick/buff 真实秒 → 游戏小时
	st.load_data({"bleed": 30.0, "sick": 60.0, "buff": 0.0}, 60.0)
	check_close(st.remaining("bleeding"), 0.5, 0.001, "旧档流血换算")
	check_close(st.remaining("dysentery"), 1.0, 0.001, "旧档腹泻换算")
	check(not st.has("caffeine"), "旧档没有咖啡因")

	# 物品效果 → 状态
	check(p.stop_bleed(), "绷带应止血")
	check(not st.has("bleeding"), "止血后没有流血")
	p.add_buff(1.5)
	check(st.has("caffeine"), "咖啡加咖啡因")

	# HUD
	hud.set_effects(st.active())
	check_eq(Hud.status_time_text(1.5), "1:30", "剩余时间格式")
	check_eq(Hud.status_time_text(INF), "", "一直有的不显示时间")
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
		print("PASS test_status")
		get_tree().quit(0)
		return
	for f in failures:
		push_error("test_status: " + f)
	print("FAIL test_status（%d 项）" % failures.size())
	get_tree().quit(1)
