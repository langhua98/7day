extends Node
## 4a 验收：配方读 JSON、材料打折、材料不够不能做、队列 4 项、工作站判定、读档后队列还在、合成面板。没有素材也能跑。

const MAIN = preload("res://scenes/main.tscn")
const C = preload("res://scripts/config.gd")

var failures: Array[String] = []
var crafted := []
var _save_existed := false
var _save_data := PackedByteArray()


func _ready() -> void:
	if FileAccess.file_exists("user://save.json"):
		_save_existed = true
		_save_data = FileAccess.get_file_as_bytes("user://save.json")
	_run.call_deferred()
	get_tree().create_timer(90.0).timeout.connect(func():
		push_error("test_craft 超时")
		get_tree().quit(1))


func _recipe(id: String, area: String, time: float, ings: Array, extra := {}) -> Dictionary:
	var list := []
	for p in ings:
		list.append({"id": p[0], "count": p[1], "zh": p[0]})
	var r := {"id": id, "count": 1, "area": area, "time": time, "tool": "", "tags": [], "learnable": false,
		"cat": "tool", "zh": id, "block": false, "ingredients": list}
	r.merge(extra, true)
	return r


func _run() -> void:
	# 假配方：石斧（背包）、篝火（方块成品）、木框（工作台）、要学的书配方、要锅的开水
	for id in ["tRock", "tFiber", "tWood", "tWater", "tPot"]:
		Data.items[id] = {"stack": 100}
	Data._tables["recipes"] = {
		"tAxe": _recipe("tAxe", "", 4.0, [["tRock", 2], ["tFiber", 2], ["tWood", 2]]),
		"tCampfire": _recipe("tCampfire", "", 2.0, [["tRock", 5]], {"cat": "build", "zh": "测试篝火"}),
		"tFrame": _recipe("tFrame", "workbench", 2.0, [["tWood", 4]], {"cat": "build"}),
		"tSecret": _recipe("tSecret", "", 2.0, [["tWood", 1]], {"learnable": true}),
		"tBoiled": _recipe("tBoiled", "campfire", 2.0, [["tWater", 1]], {"cat": "food", "tool": "tPot"}),
	}
	var main = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.start(false)
	await get_tree().process_frame
	var inv: InventorySystem = main.inventory
	var cr: Crafting = main.crafting
	GameState.item_crafted.connect(func(id, n): crafted.append([id, n]))

	check(Assets.items_by_id.has("tCampfire"), "方块成品登记成物品")
	check_eq(Crafting.cost(2), 1, "材料 ×0.5")
	check_eq(Crafting.cost(25), 13, "材料向上取整")
	check_eq(Crafting.cost(1), 1, "材料至少 1")
	check_eq(cr.time_of("tAxe"), 4.0 * C.CRAFT_TIME_MULT, "时间 ×0.5")
	check(cr.list("tool").has("tSecret") == C.RECIPES_ALL_UNLOCKED, "learnable 配方按开关显示")

	# 材料不够不能做
	inv.add("tRock", 3)
	inv.add("tFiber", 1)
	inv.add("tWood", 5)
	check(cr.can_craft("tAxe", 1), "材料够能做石斧")
	check(not cr.can_craft("tAxe", 2), "两把纤维不够")
	check_eq(cr.why_not("tAxe", 2), "材料不够", "原因")
	check_eq(cr.max_count("tAxe"), 1, "最多做 1 把")
	check(cr.craft("tAxe", 1), "开始做石斧")
	check_eq(inv.count("tRock"), 2, "扣小石头")
	check_eq(inv.count("tFiber"), 0, "扣纤维")
	check(not cr.craft("tAxe", 1), "材料不够时 craft 返回 false")

	# 工作站：测试模式当作在旁边；4c 接上 station_check 后按真实距离
	check(Crafting.near_station(""), "背包随时可做")
	check_eq(Crafting.near_station("workbench"), C.TEST_STATIONS_NEAR, "没有 4c 时按测试开关")
	Crafting.station_check = func(_a): return false
	check(cr.why_not("tFrame").contains("工作台"), "离工作台远不能做")
	Crafting.station_check = Callable()
	# 工具
	inv.add("tWater", 1)
	check(cr.why_not("tBoiled").begins_with("需要"), "没锅不能煮")
	inv.add("tPot", 1)
	check_eq(cr.why_not("tBoiled"), "", "有锅能煮")

	# 队列 4 项
	inv.add("tRock", 50)
	inv.add("tWood", 20)
	check(cr.craft("tCampfire", 1), "队列第 2 项")
	check(cr.craft("tFrame", 2), "队列第 3 项")
	check(cr.craft("tCampfire", 2), "队列第 4 项")
	check_eq(cr.queue.size(), 4, "队列 4 项")
	check(cr.why_not("tCampfire").begins_with("队列满了"), "第 5 项不能加")
	check(not cr.craft("tCampfire", 1), "队列满了 craft 返回 false")

	# 合成面板：打开有格子，不够的按钮不可点
	main.hud.craft_panel.open()
	await get_tree().process_frame
	check(main.hud.craft_panel.visible, "面板打开")
	check(main.hud.craft_panel._grid.get_child_count() > 0, "面板有配方格子")
	check(main.hud.craft_panel._craft_btn.disabled, "队列满了合成按钮不可点")
	main.hud.craft_panel.visible = false

	# 时间推进：做完第一项石斧
	cr._process(cr.time_of("tAxe") + 0.01)
	check_eq(inv.count("tAxe"), 1, "石斧进背包")
	check_eq(crafted.size(), 1, "发 item_crafted")
	check_eq(cr.queue.size(), 3, "做完出队")
	cr._process(0.3)
	var t_before: float = cr.queue[0].t

	# 取消退材料：第 3 项 tFrame ×2 退 4 木头
	var wood := inv.count("tWood")
	cr.cancel(1)
	check_eq(inv.count("tWood"), wood + 4, "取消退还材料")
	check_eq(cr.queue.size(), 2, "取消后 2 项")

	# 存档、读档后队列还在，进度还在
	main.save_game.save()
	main.save_game.continue_game()
	check_eq(main.crafting.queue.size(), 2, "读档后队列 2 项")
	if main.crafting.queue.size() == 2:
		check_eq(main.crafting.queue[0].key, "tCampfire", "读档后第一项")
		check(absf(float(main.crafting.queue[0].t) - t_before) < 0.001, "读档后进度保留")
	await get_tree().process_frame
	check_eq(main.inventory.count("tAxe"), 1, "读档后石斧还在")
	# 旧存档没有队列字段
	main.crafting.load_data({})
	check_eq(main.crafting.queue.size(), 0, "旧档没有队列")

	main.running = false
	_finish()


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
		print("PASS test_craft")
		get_tree().quit(0)
		return
	for m in failures:
		push_error("test_craft: " + m)
	print("FAIL test_craft（%d 项）" % failures.size())
	get_tree().quit(1)
