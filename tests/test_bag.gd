extends Node
## 2b 验收：格子背包、叠加上限、旧档转换、容器面板转移、储物箱存档。没有素材也能跑。

const MAIN = preload("res://scenes/main.tscn")
const C = preload("res://scripts/config.gd")

var failures: Array[String] = []
var _save_existed := false
var _save_data := PackedByteArray()


func _ready() -> void:
	if FileAccess.file_exists("user://save.json"):
		_save_existed = true
		_save_data = FileAccess.get_file_as_bytes("user://save.json")
	_run.call_deferred()
	get_tree().create_timer(90.0).timeout.connect(func():
		push_error("test_bag 超时")
		get_tree().quit(1))


func _run() -> void:
	# 假物品：一种能叠 300 的子弹、一种不能叠的刀、一种吃的
	Data.items["testAmmo"] = {"stack": 300}
	Data.items["testFood"] = {"stack": 10}
	Assets.ensure_item("testAmmo", "测试子弹")
	Assets.ensure_item("testKnife", "测试刀")
	Assets.ensure_item("testFood", "测试罐头")
	var main = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.start(false)
	await get_tree().process_frame
	var inv: InventorySystem = main.inventory

	check(inv.slots().size() >= C.BAG_SLOTS, "背包至少 45 格")
	check_eq(inv.add("testAmmo", 450), 0, "450 发子弹应全放下")
	check_eq(inv.count("testAmmo"), 450, "子弹总数")
	check_eq(_slots_of(inv, "testAmmo"), 2, "450 发占 2 格（叠 300）")
	inv.add({"id": "testKnife", "count": 1, "quality": 3})
	inv.add({"id": "testKnife", "count": 1, "quality": 5})
	check_eq(_slots_of(inv, "testKnife"), 2, "刀不叠加")
	check_eq(int(inv.qualities.get("testKnife", 0)), 5, "汇总品质取最高")
	check_eq(inv.remove("testAmmo", 200), 200, "扣 200 发")
	check_eq(inv.count("testAmmo"), 250, "剩 250 发")
	check(inv.has("testAmmo", 250) and not inv.has("testAmmo", 251), "has() 判断")
	check(inv.overload() == 0.0, "测试模式不超重")

	# 测试模式格子不够自动扩
	for i in 60:
		inv.add("testFood", 10)
	check_eq(inv.count("testFood"), 600, "测试模式格子自动扩到装得下")

	# 容器面板：拿、放、全部拿走
	var items: Array = [{"id": "testFood", "count": 3, "quality": 0, "durability": 0.0}, {}, {}]
	var panel: ContainerPanel = main.hud.container_panel
	panel.open("测试柜子", items, inv)
	check(panel.visible, "容器面板应打开")
	panel.take(0)
	check(items[0].is_empty(), "拿走后容器格子变空")
	check_eq(inv.count("testFood"), 603, "拿到背包里")
	var knife_slot := -1
	for i in inv.slots().size():
		if inv.slots()[i].get("id", "") == "testKnife":
			knife_slot = i
			break
	panel.put(knife_slot)
	check_eq(str(items[0].get("id", "")), "testKnife", "背包里的刀放进容器")
	panel.take_all()
	check(items.all(func(s): return s.is_empty()), "全部拿走")
	panel.close_panel()
	check(not panel.visible, "面板关掉")

	# 储物箱：摆一个，放东西，存档读档后还在
	var cell := Vector3i(30, 0, 30)
	main.world.add_voxel(cell, "cntWoodWritableCrate")
	GameState.block_changed.emit(cell)
	check(main.looting.crates.has(cell), "摆下储物箱应登记")
	check_eq(main.looting.crates[cell].items.size(), C.CRATE_SLOTS, "储物箱 32 格")
	main.looting.crates[cell].items[0] = {"id": "testAmmo", "count": 77, "quality": 0, "durability": 0.0}
	if not main.world.containers.is_empty():
		main.world.containers[0]["items"] = [{"id": "testFood", "count": 2, "quality": 0, "durability": 0.0}]
	main.save_game.save()
	main.save_game.continue_game()
	check(main.looting.crates.has(cell), "读档后储物箱还在")
	if main.looting.crates.has(cell):
		check_eq(int(main.looting.crates[cell].items[0].get("count", 0)), 77, "读档后箱子里的东西还在")
	check_eq(inv.count("testAmmo"), 250, "读档后背包子弹数")
	check_eq(_slots_of(inv, "testKnife"), 2, "读档后背包格子还原")
	if not main.world.containers.is_empty():
		check_eq(int(main.world.containers[0].get("items", [{}])[0].get("count", 0)), 2, "容器没拿完的东西要保存")
	# 拆掉箱子，东西掉地上
	main.world.remove_voxel(cell)
	GameState.block_changed.emit(cell)
	check(not main.looting.crates.has(cell), "拆掉箱子后注销")

	# 旧存档「id → 数量」转格子
	var old := {"seed": 1, "hours": 30.0, "hp": 42.0, "inventory": {"testAmmo": 650, "testKnife": 1},
		"order": ["testKnife", "testAmmo"], "qualities": {"testKnife": 4}, "equipped": "", "mags": {}, "blocks": []}
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	main.save_game.continue_game()
	check_eq(inv.count("testAmmo"), 650, "旧档子弹数")
	check_eq(_slots_of(inv, "testAmmo"), 3, "旧档 650 发转成 3 格")
	check_eq(int(inv.qualities.get("testKnife", 0)), 4, "旧档品质给到武器格")
	main.running = false
	_finish()


func _slots_of(inv: InventorySystem, id: String) -> int:
	var n := 0
	for s in inv.slots():
		if s.get("id", "") == id:
			n += 1
	return n


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s：期望 %s，实际 %s" % [message, expected, actual])


func _finish() -> void:
	GameState.player = null
	if _save_existed:
		var f := FileAccess.open("user://save.json", FileAccess.WRITE)
		f.store_buffer(_save_data)
		f.close()
	elif FileAccess.file_exists("user://save.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
	if failures.is_empty():
		print("PASS test_bag")
		get_tree().quit(0)
		return
	for m in failures:
		push_error("test_bag: " + m)
	print("FAIL test_bag（%d 项）" % failures.size())
	get_tree().quit(1)
