extends Node
## 4a 验收：配方读 JSON、材料打折、材料不够不能做、队列 4 项、工作站判定、读档后队列还在、合成面板。没有素材也能跑。

const MAIN = preload("res://scenes/main.tscn")
const C = preload("res://scripts/config.gd")

var failures: Array[String] = []
var crafted := []
var _save_existed := false
var _save_data := PackedByteArray()
var _bak_existed := false
var _bak_data := PackedByteArray()


func _ready() -> void:
	if FileAccess.file_exists("user://save.json"):
		_save_existed = true
		_save_data = FileAccess.get_file_as_bytes("user://save.json")
	if FileAccess.file_exists("user://save.bak"):
		_bak_existed = true
		_bak_data = FileAccess.get_file_as_bytes("user://save.bak")
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
	for id in ["tRock", "tFiber", "tWood", "tWater", "tPot", "resourceWood"]:
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

	# 工作站：真实摆放后按 3 米距离判定
	check(Crafting.near_station(""), "背包随时可做")
	check(not Crafting.near_station("workbench"), "没摆工作台时不能做工作台配方")
	var real_station_check: Callable = Crafting.station_check
	Crafting.station_check = func(_a): return false
	check(cr.why_not("tFrame").contains("工作台"), "离工作台远不能做")
	Crafting.station_check = real_station_check
	# 工具（篝火配方要先站在篝火旁）
	var camp_cell := Vector3i(floori(main.player_sys.player.position.x) - 2, 0,
		floori(main.player_sys.player.position.z))
	main.world.add_voxel(camp_cell, "campfire")
	inv.add("tWater", 1)
	inv.add(C.CAMPFIRE_FUEL, 1)
	check(cr.add_fuel(camp_cell, 1), "篝火加燃料")
	check(cr.why_not("tBoiled", 1, camp_cell).begins_with("需要"), "没锅不能煮")
	inv.add("tPot", 1)
	check(cr.set_tool(camp_cell, "tPot"), "锅放进篝火")
	check_eq(cr.why_not("tBoiled", 1, camp_cell), "", "有锅能煮")
	main.world.remove_voxel(camp_cell)

	# 4c 工作站：可摆放，3 米内才能用，靠近后按使用打开对应面板
	for id in ["campfire", "workbench", "forge", "chemistryStation", "cementMixer"]:
		check(Blocks.is_block(id), "工作站是方块：%s" % id)
	check_eq(Assets.items_by_id.get("workbench", {}).get("kind", -1), Assets.Kind.BLOCK, "工作台物品可摆放")
	check(Crafting.current == cr, "主场景接上合成系统")
	var cell := Vector3i(floori(main.player_sys.player.position.x) + 2, 0,
		floori(main.player_sys.player.position.z))
	main.world.add_voxel(cell, "workbench")
	check(Crafting.near_station("workbench"), "工作台 3 米内能合成")
	check_eq(cr.why_not("tFrame", 1, cell), "", "工作台旁木框可合成")
	main.looting.update_action(0.0)
	check(main.hud._action_text.contains("工作台"), "靠近工作台显示使用按钮")
	main.looting.action()
	check(main.hud.craft_panel.visible, "使用后打开合成面板")
	check_eq(main.hud.craft_panel._area, "workbench", "只显示工作台配方")
	check(main.hud.craft_panel._title.text.contains("工作台"), "面板标题是工作台")
	main.hud.craft_panel.visible = false
	main.player_sys.player.position += Vector3(10, 0, 0)
	check(not Crafting.near_station("workbench"), "离工作台 10 米不能合成")
	check(cr.why_not("tFrame", 1, cell).contains("工作台"), "远离时提示要工作台")
	main.player_sys.player.position -= Vector3(10, 0, 0)

	# 队列 4 项
	inv.add("tRock", 50)
	inv.add("tWood", 20)
	check(cr.craft("tCampfire", 1), "队列第 2 项")
	check(cr.craft("tFrame", 2, cell), "工作台队列")
	check(cr.craft("tCampfire", 2), "队列第 3 项")
	check(cr.craft("tCampfire", 1), "队列第 4 项")
	check_eq(cr.queue.size(), 4, "背包队列 4 项")
	check_eq(cr.queue_for(cell).size(), 1, "工作台队列 1 项")
	check(cr.why_not("tCampfire").begins_with("队列满了"), "第 5 项不能加")
	check(not cr.craft("tCampfire", 1), "队列满了 craft 返回 false")

	# 合成面板：打开有格子，不够的按钮不可点
	main.hud.craft_panel.open()
	await get_tree().process_frame
	check(main.hud.craft_panel.visible, "面板打开")
	check(main.hud.craft_panel._grid.get_child_count() > 0, "面板有配方格子")
	check(main.hud.craft_panel._craft_btn.disabled, "队列满了合成按钮不可点")
	main.hud.craft_panel.visible = false

	# 取消工作台队列，退还 tFrame ×2 的 4 木头
	var wood := inv.count("tWood")
	cr.cancel(0, cell)
	check_eq(inv.count("tWood"), wood + 4, "取消退还材料")
	check_eq(cr.queue_for(cell).size(), 0, "工作台取消后空")
	check_eq(cr.queue.size(), 4, "背包取消后仍 4 项")

	# 时间推进：做完第一项石斧
	cr._process(cr.time_of("tAxe") + 0.01)
	check_eq(inv.count("tAxe"), 1, "石斧进背包")
	check_eq(crafted.size(), 1, "发 item_crafted")
	check_eq(cr.queue.size(), 3, "做完出队")
	cr._process(0.3)
	var t_before: float = cr.queue[0].t

	# 存档、读档后队列还在，进度还在
	main.save_game.save()
	main.save_game.continue_game()
	check(Crafting.near_station("workbench"), "读档后工作站还在")
	check_eq(main.crafting.queue.size(), 3, "读档后队列 3 项")
	if main.crafting.queue.size() == 3:
		check_eq(main.crafting.queue[0].key, "tCampfire", "读档后第一项")
		check(absf(float(main.crafting.queue[0].t) - t_before) < 0.001, "读档后进度保留")
	await get_tree().process_frame
	check_eq(main.inventory.count("tAxe"), 1, "读档后石斧还在")
	# 旧存档没有队列字段
	main.crafting.load_data({})
	check_eq(main.crafting.queue.size(), 0, "旧档没有队列")

	# 拆掉工作台就不能再用它的配方
	main.world.remove_voxel(cell)
	check(not Crafting.near_station("workbench"), "拆掉工作台后不能合成")
	await get_tree().process_frame
	Crafting.station_check = Callable()

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
	if _bak_existed:
		var b := FileAccess.open("user://save.bak", FileAccess.WRITE)
		b.store_buffer(_bak_data)
		b.close()
	elif FileAccess.file_exists("user://save.bak"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.bak"))
	if failures.is_empty():
		print("PASS test_craft")
		get_tree().quit(0)
		return
	for m in failures:
		push_error("test_craft: " + m)
	print("FAIL test_craft（%d 项）" % failures.size())
	get_tree().quit(1)
