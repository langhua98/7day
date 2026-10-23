extends Node
## 3c 验收：睡袋只有一个、死后在睡袋醒来、尸体背包能拿回全部东西、两次死亡两个背包、
## 濒死创伤、存活天数 −2、读档都在。没有素材也能跑。

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
		push_error("test_respawn 超时")
		get_tree().quit(1))


func _run() -> void:
	Data.items["testAmmo"] = {"stack": 300}
	Assets.ensure_item("testAmmo", "测试子弹")
	Assets.ensure_item("testKnife", "测试刀")
	var main = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.start(true)
	await get_tree().process_frame
	var inv: InventorySystem = main.inventory
	var rs: RespawnSystem = main.respawn
	var lt: LootingSystem = main.looting
	var p: PlayerSystem = main.player_sys

	check(Assets.items_by_id.has(C.BEDROLL_ID), "睡袋应在物品表里")
	check(inv.has(C.BEDROLL_ID), "测试模式背包里有睡袋")
	check(not rs.has_bedroll(), "开局没有睡袋")

	# 睡袋同时只能有一个
	GameState.bedroll_placed.emit(Vector3(10.5, 0, 10.5), 0.0)
	GameState.bedroll_placed.emit(Vector3(20.5, 0, -6.5), 1.0)
	check(rs.has_bedroll(), "摆下睡袋")
	check_close(rs.respawn_point().distance_to(Vector3(20.5, 0, -6.5)), 0.0, 0.01, "新睡袋替换旧的")
	var bedroll_nodes := main.get_children().filter(func(n): return n is Node3D and n.get_child_count() > 0 \
		and n.get_child(n.get_child_count() - 1) is Label3D and n.get_child(n.get_child_count() - 1).text == "睡袋" \
		and not n.is_queued_for_deletion())
	check_eq(bedroll_nodes.size(), 1, "场景里只有一个睡袋")

	# 身上东西
	inv.reset()
	inv.add("testAmmo", 450)
	inv.add({"id": "testKnife", "count": 1, "quality": 4})
	inv.equip("testKnife")
	var before_total := inv.count("testAmmo")
	GameState.day = 5
	main.time_sys.set_time(4 * 24.0 + 10.0)
	var stage_before := GameState.gamestage()
	var alive_before := GameState.days_alive()

	# 第一次死：在 (3, 0, 4)
	p.player.position = Vector3(3, 0, 4)
	p.hp = 0.0
	main._die()
	check(rs.dying, "死后在黑屏中")
	check(not main.running, "黑屏时游戏停住")
	check_eq(inv.used_slots(), 0, "死后背包清空")
	check_eq(inv.equipped, "", "手上的也放进尸体背包")
	check_eq(lt.corpse_bags.size(), 1, "一个尸体背包")
	check_eq(GameState.days_alive(), alive_before - C.DAYS_ALIVE_LOST_ON_DEATH, "存活天数 −2")
	check(GameState.gamestage() < stage_before, "游戏阶段跟着降")
	await get_tree().create_timer(C.DEATH_BLACKOUT + 0.3).timeout
	check(not rs.dying, "2 秒后醒来")
	check(main.running, "醒来后游戏继续")
	check(Vector2(p.player.position.x, p.player.position.z).distance_to(Vector2(20.5, -6.5)) < 1.0, "在睡袋醒来")
	check_close(p.hp, C.MAX_HP * 0.5, 0.01, "血 50%")
	check_close(p.food, C.MAX_FOOD * 0.5, 0.5, "饱食 50%")
	check_close(p.water, C.MAX_WATER * 0.5, 0.5, "水 50%")
	check(Status.has("near_death_trauma"), "濒死创伤")
	check_close(Status.remaining("near_death_trauma"), 24.0, 0.01, "濒死创伤 1 游戏天")
	check_close(p.stamina_max(), 80.0, 0.01, "体力上限 −20")

	# 第二次死：在 (-5, 0, 2)，身上带一点东西
	inv.add("testAmmo", 7)
	p.player.position = Vector3(-5, 0, 2)
	p.hp = 0.0
	main._die()
	rs.respawn_now()
	check_eq(lt.corpse_bags.size(), 2, "再死一次有两个尸体背包")

	# 读档：睡袋、两个背包、濒死创伤、存活天数都在
	main.save_game.save()
	var lost := GameState.days_alive_lost
	main.save_game.continue_game()
	await get_tree().process_frame
	check(rs.has_bedroll(), "读档后睡袋还在")
	check_close(rs.respawn_point().distance_to(Vector3(20.5, 0, -6.5)), 0.0, 0.01, "读档后睡袋位置不变")
	check_eq(lt.corpse_bags.size(), 2, "读档后两个尸体背包都在")
	check(Status.has("near_death_trauma"), "读档后濒死创伤还在")
	check_eq(GameState.days_alive_lost, lost, "读档后存活天数扣减保留")

	# 回到第一个背包：全部拿回
	inv.reset()
	var bag: Dictionary = {}
	for b in lt.corpse_bags:
		if b.pos.distance_to(Vector3(3, 0, 4)) < 0.5:
			bag = b
	check(not bag.is_empty(), "第一个背包在死亡位置")
	p.player.position = Vector3(3, 0, 4.5)
	check(is_same(lt.nearest_crate(), bag), "走到背包旁能打开")
	lt.open_panel(bag)
	main.hud.container_panel.take_all()
	check_eq(inv.count("testAmmo"), before_total, "子弹全部拿回")
	check(inv.has("testKnife"), "刀拿回")
	check_eq(int(inv.qualities.get("testKnife", 0)), 4, "品质保留")
	main.hud.container_panel.close_panel()
	await get_tree().process_frame
	check_eq(lt.corpse_bags.size(), 1, "拿空的背包消失")
	_finish()


func check(cond: bool, message: String) -> void:
	if not cond:
		failures.append(message)


func check_close(actual: float, expected: float, tol: float, message: String) -> void:
	if absf(actual - expected) > tol:
		failures.append("%s：期望 %.3f，实际 %.3f" % [message, expected, actual])


func check_eq(actual, expected, message: String) -> void:
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
		print("PASS test_respawn")
		get_tree().quit(0)
		return
	for m in failures:
		push_error("test_respawn: " + m)
	print("FAIL test_respawn（%d 项）" % failures.size())
	get_tree().quit(1)
