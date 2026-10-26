extends Node
## 7d：5 个委托、三类任务、交任务、奖励三选一、放弃、存档。

const MAIN = preload("res://scenes/main.tscn")

var failures: Array[String] = []
var _done := false


func _ready() -> void:
	_run.call_deferred()
	var t := Timer.new()
	t.wait_time = 150.0
	t.one_shot = true
	t.timeout.connect(func():
		if not _done:
			_check(false, "超时")
			_finish())
	add_child(t)
	t.start()


func _check(cond: bool, what: String) -> void:
	if cond:
		print("PASS ", what)
	else:
		failures.append(what)
		print("FAIL ", what)


func _run() -> void:
	var main = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.start(false)
	await get_tree().process_frame
	var q: QuestSystem = main.quests
	_check(q != null and q.offers.size() == 5, "商人给 5 个委托")
	_check(not q.data.is_empty(), "任务奖励表已加载")
	var tr: TraderSystem = main.trader
	GameState.hours = 12.0
	tr.update(0.1)
	main.player_sys.player.position = tr.site + Vector3(0, 0, 2)

	# 取货：接 → 去箱子 → 拿 → 回商人 → 选择奖励
	var fetch_poi := ""
	var fetch_target := Vector3.ZERO
	for e in main.world.poi_instances():
		if q.sleepers.data.has(str(e.get("name", ""))):
			fetch_poi = str(e.get("name", ""))
			fetch_target = q._poi_target(e)
			break
	if fetch_poi == "":
		fetch_target = tr.site + Vector3(8, 0, 0)
	var def: Dictionary = q.data["tier1"]["fetch"]
	var choices := q._reward_choices(1)
	q.offers = [{"kind": "fetch", "tier": 1, "poi": fetch_poi, "target": fetch_target,
		"name": def.name, "desc": "", "xp": int(def.xp), "coins": int(def.coins),
		"choices": choices, "state": "offer", "progress": 0}]
	_check(q.accept(0), "能接取货任务")
	_check(not q.active.is_empty() and str(q.active.kind) == "fetch", "取货任务生效")
	main.player_sys.player.position = fetch_target
	_check(q.interact(fetch_target), "能拿补给箱")
	_check(str(q.active.state) == "return", "取货进入交任务状态")
	main.player_sys.player.position = tr.site + Vector3(0, 0, 2)
	_check(q.turn_in(), "能在商人处交任务")
	_check(str(q.active.state) == "reward", "交任务后选奖励")
	var coins0: int = main.inventory.count("casinoCoin")
	var got := str(q.active.choices[0])
	q.choose_reward(got)
	_check(q.active.is_empty() and q.completed == 1, "选奖励后任务完成")
	_check(main.inventory.has(got), "奖励物品进背包")
	_check(main.inventory.count("casinoCoin") > coins0, "任务给公爵币")

	# 清剿：接 → 把楼标记清空 → 回商人
	var clear_poi := ""
	var clear_target := Vector3.ZERO
	for e in main.world.poi_instances():
		if q.sleepers.data.has(str(e.get("name", ""))):
			clear_poi = str(e.get("name", ""))
			clear_target = q._poi_target(e)
			break
	if clear_poi != "":
		var cdef: Dictionary = q.data["tier1"]["clear"]
		q.offers = [{"kind": "clear", "tier": 1, "poi": clear_poi, "target": clear_target,
			"name": cdef.name, "desc": "", "xp": int(cdef.xp), "coins": int(cdef.coins),
			"choices": q._reward_choices(1), "state": "offer", "progress": 0}]
		_check(q.accept(0), "能接清剿任务")
		for v in q.sleepers.volumes:
			if str(v.poi) == clear_poi:
				q.sleepers.cleared_areas[str(v.key)] = GameState.day
				v.cleared = true
		q.update(0.1)
		_check(str(q.active.get("state", "")) == "return", "清完楼任务进入交任务")
		main.player_sys.player.position = tr.site
		q.turn_in()
		q.choose_reward(str(q.active.choices[0]))
		_check(q.completed == 2, "清剿任务完成")
	else:
		print("SKIP 清剿（没有睡眠区）")

	# 挖宝：接 → 走到点 → 挖 5 下 → 回商人
	var bdef: Dictionary = q.data["tier1"]["buried"]
	var btarget := tr.site + Vector3(6, 0, 0)
	q.offers = [{"kind": "buried", "tier": 1, "poi": "", "target": btarget,
		"name": bdef.name, "desc": "", "xp": int(bdef.xp), "coins": int(bdef.coins),
		"choices": q._reward_choices(1), "state": "offer", "progress": 0}]
	_check(q.accept(0), "能接挖宝任务")
	main.player_sys.player.position = btarget
	for i in 5:
		q.interact(btarget)
	_check(str(q.active.get("state", "")) == "return", "挖 5 下后进入交任务")
	main.player_sys.player.position = tr.site
	q.turn_in()
	q.choose_reward(str(q.active.choices[0]))
	_check(q.completed == 3, "挖宝任务完成")

	# 放弃
	q.offers = [{"kind": "buried", "tier": 1, "poi": "", "target": btarget,
		"name": bdef.name, "desc": "", "xp": 1, "coins": 1, "choices": [], "state": "offer", "progress": 0}]
	q.accept(0)
	q.abandon()
	_check(q.active.is_empty(), "能放弃任务")

	# 面板和存读档
	main.hud.quest_panel.open()
	_check(main.hud.quest_panel.visible, "任务面板能打开")
	main.hud.quest_panel.visible = false
	var saved := q.save_data()
	q.reset()
	q.load_data(saved)
	_check(q.completed == 3, "读档恢复已完成数")
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	if failures.is_empty():
		print("PASS test_quests")
	else:
		print("FAIL test_quests：", "; ".join(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
