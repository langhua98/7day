extends Node
## 7a：等级曲线、加点、技能修正、存档、经验来源。

const C = preload("res://scripts/config.gd")
var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()
	_timer(120)


func _timer(sec: float) -> void:
	var t := Timer.new()
	t.wait_time = sec
	t.one_shot = true
	t.timeout.connect(func():
		if not _done:
			_check(false, "超时")
			_finish())
	add_child(t)
	t.start()


var _done := false


func _check(cond: bool, what: String) -> void:
	if cond:
		print("PASS ", what)
	else:
		failures.append(what)
		print("FAIL ", what)


func _run() -> void:
	_check(Progression.data.get("skills", {}).size() >= 18, "应加载官方技能表")
	Progression.reset()
	var start_points := Progression.points
	_check(start_points == (20 if C.TEST_ALL_ITEMS else 0), "测试模式开局送 20 点")
	_check(Progression.level == 1 and Progression.attributes.size() == 5, "1 级、5 项属性")
	_check(Progression.xp_to_next() == 10000.0, "1 级升 2 级要 10000 经验")

	# 杀僵尸 5000 经验 ×2 = 10000，刚好升 2 级
	var z := Zombie.new()
	z.xp = 5000
	add_child(z)
	GameState.zombie_killed.emit(z, "")
	z.queue_free()
	_check(Progression.level == 2, "杀僵尸应升到 2 级")
	_check(Progression.points == start_points + 1, "升 1 级给 1 点")
	_check(Progression.xp_to_next() == 10500.0, "2 级升 3 级要 10500 经验")

	# 合成经验：1 个成品 5 经验 ×2
	var before := Progression.xp
	GameState.item_crafted.emit("woodFrame", 1)
	_check(Progression.xp == before + 10.0, "合成 1 件给 10 经验")

	# 搜刮技能：搜刮时间 −10%，搜刮阶段 +5%
	var p0 := Progression.points
	_check(Progression.buy_perk("perkLuckyLooter"), "能加幸运搜刮")
	_check(Progression.points == p0 - 1 and Progression.perk_level("perkLuckyLooter") == 1, "扣点、技能到 1")
	_check(absf(Progression.loot_time_mult() - 0.9) < 0.01, "Lucky Looter 1 级搜刮时间 ×0.9")
	_check(absf(Progression.loot_stage_mult() - 1.05) < 0.01, "Lucky Looter 1 级搜刮阶段 +5%")

	# 武器伤害：步枪标签带 perkDeadEye，1 级 +10%
	_check(Progression.buy_perk("perkDeadEye"), "能加死神之眼")
	_check(absf(Progression.damage_mult("weapon,ranged,perkDeadEye") - 1.1) < 0.01, "死神之眼 1 级步枪 +10%")
	_check(absf(Progression.damage_mult("weapon,shotgun,perkBoomstick") - 1.0) < 0.01, "没加的霰弹枪不变")

	# 属性：感知升一级
	var cost := Progression.attr_cost("attPerception")
	var pts := Progression.points
	_check(Progression.buy_attr("attPerception"), "能升属性")
	_check(Progression.attr_level("attPerception") == 2 and Progression.points == pts - cost, "属性升级扣点")

	# 背包：PackMule 1 级 +4 格
	_check(Progression.buy_perk("perkPackMule"), "能加背包客")
	_check(Progression.carry_bonus() == 4, "背包客 1 级 +4 格")

	# GameState 用真实等级
	GameState.day = 1
	_check(GameState.gamestage() == int((Progression.level + 1) * 1.2), "游戏阶段按等级算")

	# 存读档
	var saved := Progression.save_data()
	var lvl := Progression.level
	var lucky := Progression.perk_level("perkLuckyLooter")
	Progression.reset()
	_check(Progression.level == 1 and Progression.perk_level("perkLuckyLooter") == 0, "重置回到 1 级")
	Progression.load_data(saved)
	_check(Progression.level == lvl, "读档恢复等级")
	_check(Progression.perk_level("perkLuckyLooter") == lucky, "读档恢复技能点")
	_check(Progression.attr_level("attPerception") == 2, "读档恢复属性")
	_check(Progression.points >= 0, "读档后点数正常")

	# 满级附近不再升级
	Progression.level = Progression.max_level()
	Progression.xp = 0.0
	Progression.add_xp(999999.0, "test")
	_check(Progression.level == Progression.max_level(), "满级后不再升级")

	# 技能面板能打开、切属性、选技能
	Progression.load_data(saved)
	var hud := Hud.new()
	add_child(hud)
	await get_tree().process_frame
	hud.skills_panel.bind(Progression)
	hud.skills_panel.open()
	hud.skills_panel._set_attr("attAgility")
	hud.skills_panel._select_skill("perkGunslinger")
	await get_tree().process_frame
	_check(hud.skills_panel.visible, "技能面板能打开")
	_check(hud.skills_panel._detail_title.text != "", "技能详情有标题")
	_check(hud.skills_panel._detail_body.text.length() > 10, "技能详情有效果说明")
	var pts_before := Progression.points
	var guns_before := Progression.perk_level("perkGunslinger")
	hud.skills_panel._buy_selected()
	_check(Progression.points == pts_before - 1, "面板加点扣点")
	_check(Progression.perk_level("perkGunslinger") == guns_before + 1, "面板加点生效")
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	if failures.is_empty():
		print("PASS test_progression")
	else:
		print("FAIL test_progression：", "; ".join(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
