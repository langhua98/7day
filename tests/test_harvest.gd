extends Node
## 4b 验收：工具/材质匹配、采集掉落、车拆掉后再出现、工具耐久和修理、背包拆解。
## 需要 assets/data/harvest.json 和 assets/index/world_models.json；沙盒没有就跳过。

const MAIN = preload("res://scenes/main.tscn")
const C = preload("res://scripts/config.gd")

var failures: Array[String] = []
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 99
	_run.call_deferred()
	get_tree().create_timer(150.0).timeout.connect(func():
		push_error("test_harvest 超时")
		get_tree().quit(1))


func _run() -> void:
	if Data.get_table("harvest").is_empty() or Data.get_table("harvest_overrides").is_empty():
		print("SKIP test_harvest（沙盒没有 harvest.json）")
		get_tree().quit(0)
		return
	_test_tools()
	var main = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.start(false)
	await get_tree().process_frame
	if main.world.props.is_empty():
		print("SKIP test_harvest（没有场景模型，街上没有物件）")
		get_tree().quit(0)
		return
	await _test_props(main)
	_test_durability(main)
	await _test_salvage(main)
	_finish()


func _test_tools() -> void:
	check_eq(Harvest.tool_kind("meleeToolSalvageT1Wrench"), "metal", "扳手对金属")
	check_eq(Harvest.tool_kind("meleeToolAxeT1IronFireaxe"), "wood", "斧头对木头")
	check_eq(Harvest.tool_kind("meleeToolPickT1IronPickaxe"), "stone", "镐对石头")
	check_eq(Harvest.tool_kind("meleeWpnClubT1BaseballBat"), "", "球棒不算对口工具")
	check_eq(Harvest.material("sedan_LOD1"), "metal", "轿车是金属")
	check_eq(Harvest.material("trashPileA_1"), "trash", "垃圾堆是垃圾")
	check(Harvest.hp("sedan_LOD1") >= 50.0, "车应该有像样的血量")
	var good := 0
	var bare := 0
	var ids := {}
	for i in 20:
		for d in Harvest.drops("metal", "metal", rng):
			good += int(d.count)
			ids[str(d.id)] = true
		for d in Harvest.drops("metal", "", rng):
			bare += int(d.count)
	check(good > bare * 2, "对口工具产出应明显高于空手（%d vs %d）" % [good, bare])
	check(ids.has("resourceScrapIron"), "拆金属应该出废铁")
	check(ids.has("resourceMechanicalParts"), "拆金属应该出机械零件")


func _test_props(main) -> void:
	var world: World = main.world
	var car_i := -1
	for i in world.props.size():
		if str(world.props[i].kind) == "car" and world.props[i].has("container"):
			car_i = i
			break
	check(car_i >= 0, "场景里应该有车")
	if car_i < 0:
		return
	var pr: Dictionary = world.props[car_i]
	var ci := int(pr.container)
	var c: Dictionary = world.containers[ci]
	var node = pr.node
	check_eq(str(pr.material), "metal", "车是金属材质")
	check(not bool(pr.dead), "车一开始是好的")
	var guard := 0
	while not bool(pr.dead) and guard < 60:
		guard += 1
		world.hit_prop(car_i, 30.0)
	check(bool(pr.dead), "车应该能被拆掉")
	check(bool(c.get("dead", false)), "拆掉后车容器也没了")
	check(not node.visible, "拆掉后车模型应隐藏")
	check(bool(world.obstacles[int(pr.obstacle)].get("dead", false)), "拆掉后不再挡路")
	# 存档 / 重置 / 读档
	var saved: Dictionary = world.harvest_save()
	world.harvest_reset()
	check(not bool(pr.dead) and not bool(c.get("dead", false)), "重置后车回来了")
	check(node.visible, "重置后模型显示")
	world.harvest_load(saved.get("harvest_dead", []))
	check(bool(pr.dead) and bool(c.get("dead", false)), "读档后车还是拆掉的")
	check(not node.visible, "读档后模型仍隐藏")
	# 5 天后重生
	world._on_day_started(int(pr.get("dead_day", 0)) + C.HARVEST_RESPAWN_DAYS + 1)
	check(not bool(pr.dead) and not bool(c.get("dead", false)), "5 天后车应刷新")
	check(node.visible, "刷新后模型显示")
	check(not bool(world.obstacles[int(pr.obstacle)].get("dead", false)), "刷新后重新挡路")


func _test_durability(main) -> void:
	var inv: InventorySystem = main.inventory
	inv.reset()
	var id := "meleeToolSalvageT1Wrench"
	inv.add(id, 1)
	check(inv.max_durability(id) > 0.0, "扳手应有耐久上限")
	check(not inv.is_broken(id), "新扳手不是坏的")
	inv.damage_tool(id, inv.max_durability(id))
	check(inv.is_broken(id), "耐久扣完应坏了")
	inv.repair_tool(id)
	check(not inv.is_broken(id), "修好后恢复")
	check_close(inv.durability_of(id), inv.max_durability(id), 0.01, "修满耐久")


func _test_salvage(main) -> void:
	var inv: InventorySystem = main.inventory
	inv.reset()
	var id := "meleeToolRepairT0StoneAxe"
	inv.add(id, 1)
	var slot := -1
	for i in inv.slots().size():
		if str(inv.slots()[i].get("id", "")) == id:
			slot = i
			break
	check(slot >= 0, "背包里应有石斧")
	var wood_before := inv.count("resourceWood")
	inv.salvage_slot(slot)
	check_eq(inv.count(id), 0, "拆解后物品消失")
	await get_tree().create_timer(C.SALVAGE_TIME + 0.4).timeout
	check(inv.count("resourceWood") > wood_before, "拆解应返还木头")


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
	GameState.player = null
	if failures.is_empty():
		print("PASS test_harvest")
		get_tree().quit(0)
		return
	for m in failures:
		push_error("test_harvest: " + m)
	print("FAIL test_harvest（%d 项）" % failures.size())
	get_tree().quit(1)
