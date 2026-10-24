extends Node
## 4c 验收：工作站独立队列、篝火燃料和锅具、使用面板、存读档。

const MAIN = preload("res://scenes/main.tscn")
const C = preload("res://scripts/config.gd")

var failures: Array[String] = []
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
		push_error("test_workstations 超时")
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
	for id in ["tWood", "tWater", "tPot", "resourceWood"]:
		Data.items[id] = {"stack": 100}
	Data._tables["recipes"] = {
		"tFrame": _recipe("tFrame", "workbench", 2.0, [["tWood", 4]], {"cat": "build"}),
		"tBoiled": _recipe("tBoiled", "campfire", 2.0, [["tWater", 1]], {"cat": "food", "tool": "tPot"}),
	}
	var main = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.start(false)
	await get_tree().process_frame
	var inv: InventorySystem = main.inventory
	var cr: Crafting = main.crafting

	var bench := Vector3i(floori(main.player_sys.player.position.x) + 2, 0,
		floori(main.player_sys.player.position.z))
	main.world.add_voxel(bench, "workbench")
	inv.add("tWood", 20)
	check(cr.craft("tFrame", 1, bench), "工作台开始合成")
	check_eq(cr.queue.size(), 0, "背包队列不受影响")
	check_eq(cr.queue_for(bench).size(), 1, "工作台有自己的队列")

	# 离开后继续，队列和进度读档保留
	main.save_game.save()
	main.save_game.continue_game()
	check_eq(cr.queue_for(bench).size(), 1, "工作台队列读档还在")
	main.player_sys.player.position += Vector3(10, 0, 0)
	cr._process(cr.time_of("tFrame") + 0.1)
	check_eq(cr.queue_for(bench).size(), 0, "离开工作台也继续合成")
	check_eq(inv.count("tFrame"), 1, "工作台成品进背包")
	main.player_sys.player.position -= Vector3(10, 0, 0)

	# 篝火：先放木头燃料，再把锅放进工具格
	var fire := Vector3i(floori(main.player_sys.player.position.x) + 1, 0,
		floori(main.player_sys.player.position.z))
	main.world.add_voxel(fire, "campfire")
	inv.add("tWater", 1)
	inv.add("tPot", 1)
	inv.add("resourceWood", 2)
	check(cr.station_state(fire).get("area", "") == "campfire", "识别篝火")
	var pots := inv.count("tPot")
	check(cr.set_tool(fire, "tPot"), "把锅放进篝火")
	check(cr.why_not("tBoiled", 1, fire).contains("燃料"), "没木头不能点篝火")
	check(cr.add_fuel(fire, 1), "加木头燃料")
	check_eq(cr.station_state(fire).fuel, 1, "燃料数量")
	check_eq(inv.count("tPot"), pots - 1, "锅从背包移到工作站")
	check_eq(cr.why_not("tBoiled", 1, fire), "", "有火有锅能煮水")
	check(cr.craft("tBoiled", 1, fire), "篝火开始煮水")
	cr._process(cr.time_of("tBoiled") + 0.1)
	check_eq(inv.count("tBoiled"), 1, "煮出开水")
	check_eq(cr.station_state(fire).fuel, 0, "煮完消耗燃料")

	# 使用面板只显示篝火，并显示燃料/工具
	inv.add("tWater", 1)
	check(cr.add_fuel(fire, 1), "面板打开前补燃料")
	main.hud.craft_panel.open("campfire", fire)
	check(main.hud.craft_panel.visible, "打开篝火面板")
	check_eq(main.hud.craft_panel._station, fire, "面板记住篝火位置")
	check(main.hud.craft_panel._title.text.contains("篝火"), "标题是篝火")
	check(main.hud.craft_panel._fuel_btn.visible, "显示燃料按钮")
	check(main.hud.craft_panel._tool_btn.text.contains("tPot"), "显示锅具按钮")
	var boiled_btn: Button = null
	for b in main.hud.craft_panel._grid.get_children():
		if b.get_meta("recipe", "") == "tBoiled":
			boiled_btn = b
	check(boiled_btn != null and boiled_btn.modulate == Color.WHITE, "工作站配方图标不应变灰")
	main.hud.craft_panel.visible = false

	# 拆掉工作站：队列材料、燃料、锅都要退回
	inv.add("tWater", 1)
	inv.add("resourceWood", 2)
	check(cr.add_fuel(fire, 1), "拆站前补燃料")
	check(cr.craft("tBoiled", 1, fire), "拆站前排队")
	var water_before := inv.count("tWater")
	var wood_before := inv.count("resourceWood")
	var pot_before := inv.count("tPot")
	var fuel_left := int(cr.station_state(fire).get("fuel", 0))
	main.world.remove_voxel(fire)
	cr._process(0.01)
	check_eq(inv.count("tWater"), water_before + 1, "拆站退还材料")
	check_eq(inv.count("resourceWood"), wood_before + fuel_left, "拆站退还燃料")
	check_eq(inv.count("tPot"), pot_before + 1, "拆站退还锅具")

	main.world.remove_voxel(bench)
	await get_tree().process_frame
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
		print("PASS test_workstations")
		get_tree().quit(0)
		return
	for m in failures:
		push_error("test_workstations: " + m)
	print("FAIL test_workstations（%d 项）" % failures.size())
	get_tree().quit(1)
