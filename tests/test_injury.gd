extends Node
## 3b 验收：摔落、扭伤、骨折、感染、对应药品、读档保留。不需要素材。

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
	rng.seed = 7
	var holder := Node3D.new()
	add_child(holder)
	p.setup(holder, null, hud, rng)
	st.clear()

	# 摔落：3 米以内不掉血
	p.hp = 100.0
	p.land(1.1)
	p.land(3.0)
	check_close(p.hp, 100.0, 0.001, "3 米以内不掉血")
	check(not st.has("sprain") and not st.has("fracture"), "3 米以内不受伤")
	# 3–4 米：掉血，约一半扭伤
	var sprains := 0
	for i in 200:
		st.clear()
		p.hp = 100.0
		p.land(3.5)
		if st.has("sprain"):
			sprains += 1
		check(not st.has("fracture"), "3.5 米不骨折")
	check_close(p.hp, 100.0 - 0.5 * C.FALL_DAMAGE_PER_M, 0.01, "3.5 米掉 7.5 血")
	check(sprains > 70 and sprains < 130, "3–4 米约 50%% 扭伤，实际 %d/200" % sprains)
	# 扭伤：移速 −25%，夹板后 6 小时好
	st.clear()
	p.sprain_leg()
	check_close(st.modifier("move_speed"), 0.75, 0.001, "扭伤移速 ×0.75")
	check_close(st.remaining("sprain"), 24.0, 0.001, "扭伤 1 游戏天")
	check(p.apply_splint() != "", "夹板能固定扭伤")
	check(not st.has("sprain") and st.has("sprain_splinted"), "扭伤变成已固定")
	check_close(st.remaining("sprain_splinted"), 6.0, 0.001, "已固定 6 游戏小时")
	for i in 70:
		st.tick(1.0, 0.1)
	check(not st.has("sprain_splinted"), "已固定 6 小时后好")
	check_close(st.modifier("move_speed"), 1.0, 0.001, "好了以后移速恢复")

	# 从 5 米高的方块跳下（起跳再高约 1.1 米）必骨折
	for i in 20:
		st.clear()
		p.hp = 100.0
		p.land(6.1)
		check(st.has("fracture"), "5 米方块跳下必骨折")
	check_close(p.hp, 100.0 - 3.1 * C.FALL_DAMAGE_PER_M, 0.01, "6.1 米掉 46.5 血")
	check_close(st.modifier("move_speed"), 0.5, 0.001, "骨折移速 ×0.5")
	check(st.blocked("no_sprint") and st.blocked("no_jump"), "骨折不能冲刺和跳")
	check(st.remaining("fracture") == INF, "骨折不会自己好")
	# 夹板 → 打夹板 3 天
	check(p.apply_splint() != "", "夹板能固定骨折")
	check(not st.has("fracture") and st.has("fracture_splinted"), "骨折变成打夹板")
	check(not st.blocked("no_jump"), "打夹板能跳")
	check_close(st.remaining("fracture_splinted"), 72.0, 0.001, "打夹板 3 游戏天")
	for i in 71:
		st.tick(1.0, 1.0)
	check(st.has("fracture_splinted"), "71 小时还没好")
	st.tick(1.0, 1.0)
	check(not p.has_fracture(), "3 游戏天后痊愈")
	# 石膏 → 1 天
	p.break_leg()
	check(p.apply_cast() != "", "石膏能治骨折")
	check(st.has("fracture_cast") and not st.has("fracture"), "骨折变成打石膏")
	check_close(st.remaining("fracture_cast"), 24.0, 0.001, "石膏 1 游戏天")
	st.clear()
	check_eq(p.apply_splint(), "", "没受伤用夹板没效果")

	# 大块头僵尸打中约 10% 骨折，普通僵尸不会
	var breaks := 0
	for i in 400:
		st.clear()
		p.hp = 100.0
		p.zombie_hit(1.0, "lumberjack")
		if st.has("fracture"):
			breaks += 1
	check(breaks > 20 and breaks < 70, "大块头打中约 10%% 骨折，实际 %d/400" % breaks)
	for i in 200:
		st.clear()
		p.hp = 100.0
		p.zombie_hit(1.0, "nurse")
		check(not st.has("fracture"), "护士僵尸不打断腿")

	# 感染：每次被打中 10%，约 20 次内会感染
	var infected_runs := 0
	var total_hits := 0
	for run in 100:
		st.clear()
		var hits := 0
		while not st.has("infection") and hits < 200:
			p.hp = 100.0
			p.zombie_hit(1.0, "joe")
			hits += 1
		total_hits += hits
		if hits <= 20:
			infected_runs += 1
	check(infected_runs > 75, "20 次以内感染的比例约 88%%，实际 %d%%" % infected_runs)
	check(total_hits > 600 and total_hits < 1400, "平均约 10 次感染，实际 %.1f" % (total_hits / 100.0))
	check_eq(p.infection(), C.INFECTION_START, "感染从 1% 开始")
	# 每游戏小时 +1%
	p.food = 100.0
	p.water = 100.0
	for i in 10:
		p.update_survival(1.0, 1.0)
	check_eq(p.infection(), 11, "10 游戏小时后感染 11%")
	# 药品
	var herbal := Survival.effect("drugHerbalAntibiotics", Assets.Kind.MEDICAL)
	var anti := Survival.effect("drugAntibiotics", Assets.Kind.MEDICAL)
	var honey := Survival.effect("foodHoney", Assets.Kind.FOOD)
	check_eq(int(herbal.get("infection", 0)), -25, "草药抗生素 −25%")
	check_eq(int(honey.get("infection", 0)), -5, "蜂蜜 −5%")
	check(Survival.effect("medicalSplint", Assets.Kind.MEDICAL).get("splint", false), "夹板物品")
	check(Survival.effect("medicalPlasterCast", Assets.Kind.MEDICAL).get("cast", false), "石膏物品")
	st.set_stacks("infection", 40)
	p.treat_infection(int(honey.infection))
	check_eq(p.infection(), 35, "蜂蜜后 35%")
	p.treat_infection(int(herbal.infection))
	check_eq(p.infection(), 10, "草药抗生素后 10%")
	check(p.treat_infection(int(anti.infection)) != "", "抗生素有效")
	check(not st.has("infection"), "抗生素治好感染")
	# 到 100% 死亡
	st.set_stacks("infection", 99)
	p.hp = 100.0
	p.update_survival(1.0, 1.0)
	check(p.hp <= 0.0, "感染到 100% 死亡")

	# 读档保留
	st.clear()
	p.break_leg()
	p.apply_splint()
	st.set_stacks("infection", 37)
	st.tick(1.0, 2.0)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(st.save_data()))
	st.clear()
	st.load_data(saved)
	check_close(st.remaining("fracture_splinted"), 70.0, 0.001, "读档打夹板剩余")
	check_eq(st.stacks("infection"), 37, "读档感染度")

	# HUD 显示百分比
	hud.set_effects(st.active())
	var shown := false
	for e in st.active():
		if e.id == "infection" and e.unit == "%":
			shown = true
	check(shown, "感染在状态条按百分比显示")
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
		print("PASS test_injury")
		get_tree().quit(0)
		return
	for f in failures:
		push_error("test_injury: " + f)
	print("FAIL test_injury（%d 项）" % failures.size())
	get_tree().quit(1)
