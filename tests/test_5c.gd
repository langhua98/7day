extends Node
## 5c：可摆的门/闸门/梯子/尖刺/领地石，开关、碰撞、伤害、存档。

const MAIN = preload("res://scenes/main.tscn")
const C = preload("res://scripts/config.gd")

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


func _free_cell(w: World, near := Vector3.ZERO) -> Vector3i:
	for i in 20:
		var base := w.free_point(near, 4.0, 30.0)
		var c := Vector3i(floori(base.x), 0, floori(base.z))
		if w.can_place(c):
			return c
	return Vector3i(1 << 20, 0, 0)


func _run() -> void:
	for id in ["oldWoodDoor", "woodHatch", "ladderWood", "trapSpikesWoodDmg0", "trapSpikesIronDmg0", "keystoneBlock"]:
		_check(Data.items.has(id), "物品表应有 %s" % id)
	_check(not Data.get_table("recipes").get("oldWoodDoor", {}).is_empty(), "官方木门配方应在")
	_check(not Data.get_table("recipes").get("keystoneBlock", {}).is_empty(), "官方土地征用块配方应在")

	var main = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.start(false)
	await get_tree().process_frame
	var w: World = main.world

	# 门：关着挡视线/挡僵尸，打开能过，开关存读档
	var dc := _free_cell(w)
	if dc.x < 1 << 19:
		w.add_voxel(dc, "oldWoodDoor")
		_check(w.is_tall_cell(dc), "关着的木门是障碍")
		_check(w.low_blocked(dc.x, dc.z), "关着的木门挡视线")
		_check(w._special_nodes.has(dc), "木门有模型节点")
		var opened := w.toggle_voxel_door(dc)
		_check(opened and bool(w.voxels[dc].get("open", false)), "开门状态生效")
		_check(not w.is_tall_cell(dc) and not w.low_blocked(dc.x, dc.z), "开门后能过")
		var dsave := w.voxel_save()
		var w2 := World.new()
		w2.voxel_load(dsave)
		_check(bool(w2.voxels[dc].get("open", false)), "读档保留门开着")
		_check(w2._special_nodes.has(dc), "读档重建门模型")
		w2.free()
	else:
		print("SKIP 门测试（没有空地）")

	# 闸门：能开关
	var hc := _free_cell(w)
	if hc.x < 1 << 19:
		w.add_voxel(hc, "woodHatch")
		_check(not w.is_tall_cell(hc), "闸门不高")
		w.toggle_voxel_door(hc)
		_check(bool(w.voxels[hc].get("open", false)), "闸门能打开")
	else:
		print("SKIP 闸门测试（没有空地）")

	# 梯子：能爬，且不挡路
	var lc := _free_cell(w)
	if lc.x < 1 << 19:
		w.add_voxel(lc, "ladderWood")
		_check(w.ladder_at(Vector3(lc) + Vector3(0.5, 0.5, 0.5)), "站在梯子边能爬")
		_check(not w.low_blocked(lc.x, lc.z), "梯子不挡视线")
		_check(w.low_top(lc.x, lc.z) == 0.0, "梯子不算台阶")
	else:
		print("SKIP 梯子测试（没有空地）")

	# 尖刺：玩家/僵尸掉血、减速、陷阱磨损
	var sc := _free_cell(w)
	if sc.x < 1 << 19:
		w.add_voxel(sc, "trapSpikesWoodDmg0")
		_check(w._trap_cells.has(sc), "尖刺登记为陷阱")
		main.player_sys.player.position = Vector3(sc) + Vector3(0.5, 0.1, 0.5)
		main.player_sys.hp = 100.0
		var trap_hp := float(w.voxels[sc].hp)
		var z = main.spawner.spawn_zombie_at("zombieJoe", "normal", 1, false, false,
			Vector3(sc) + Vector3(0.6, 0.0, 0.5))
		main._update_traps(0.1)
		_check(main.player_sys.hp < 100.0, "玩家踩尖刺掉血")
		_check(main.player_sys.slow_t > 0.0, "玩家踩尖刺减速")
		if z:
			_check(z.hp < z.max_hp, "僵尸踩尖刺掉血")
			_check(z.slow_t > 0.0, "僵尸踩尖刺减速")
		_check(float(w.voxels[sc].hp) < trap_hp, "尖刺会磨损")
	else:
		print("SKIP 尖刺测试（没有空地）")

	# 领地石：只能一个，指南针有标记
	var cc := _free_cell(w)
	var cc2 := _free_cell(w, Vector3(20, 0, 0))
	if cc.x < 1 << 19:
		_check(w.add_voxel(cc, "keystoneBlock") and w.has_claim() and w.claim_cell() == cc, "领地石生效")
		if cc2.x < 1 << 19 and cc2 != cc:
			_check(not w.add_voxel(cc2, "keystoneBlock"), "第二个领地石放不下")
		var markers: Array = main._compass_markers()
		var got := false
		for m in markers:
			if (m.color as Color).is_equal_approx(Color(0.4, 1.0, 0.65)):
				got = true
		_check(got, "指南针有领地石标记")
		var csave := w.voxel_save()
		var w3 := World.new()
		w3.voxel_load(csave)
		_check(w3.has_claim() and w3.claim_cell() == cc, "读档恢复领地石")
		w3.free()
	else:
		print("SKIP 领地石测试（没有空地）")

	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	if failures.is_empty():
		print("PASS test_5c")
	else:
		print("FAIL test_5c：", "; ".join(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
