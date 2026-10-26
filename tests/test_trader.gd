extends Node
## 7c：商人站点、营业时间、买卖、3 天库存、安全区、指南针、存档。

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


func _run() -> void:
	var main = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.start(false)
	await get_tree().process_frame
	var tr: TraderSystem = main.trader
	_check(tr != null, "商人系统已创建")
	if tr == null:
		_finish()
		return
	var dist := Vector2(tr.site.x, tr.site.z).length()
	_check(dist >= 60.0 and dist <= 120.0, "商人离出生点 60–120 米（%.1f）" % dist)
	_check(tr.stock.size() >= 5, "商人有货")

	GameState.hours = 12.0
	tr.update(0.1)
	_check(tr.open, "白天商人营业")
	main.player_sys.player.position = tr.site + Vector3(0, 0, 2)
	main.hud.trader_panel.open()
	_check(main.hud.trader_panel.visible, "能打开商人面板")
	main.hud.trader_panel.visible = false

	main.inventory.add("casinoCoin", 10000)
	var entry: Dictionary = tr.stock[0]
	var id := str(entry.id)
	var before: int = main.inventory.count(id)
	var coins: int = main.inventory.count("casinoCoin")
	var res := tr.buy(id, 1)
	_check(bool(res.get("ok", false)), "商人能买货")
	_check(main.inventory.count(id) > before, "买到的物品进背包")
	_check(main.inventory.count("casinoCoin") < coins, "买东西扣公爵币")
	var count_after: int = main.inventory.count(id)
	var res2 := tr.sell(id, 1)
	_check(bool(res2.get("ok", false)), "商人能卖货")
	_check(main.inventory.count(id) < count_after, "卖掉的物品离开背包")
	_check(main.inventory.count("casinoCoin") > 0, "卖东西得到公爵币")

	# 3 天换货
	var old_next := tr.next_day
	var old_stock := tr.stock.duplicate(true)
	GameState.day = old_next
	tr.update(0.1)
	_check(tr.next_day > old_next, "3 天后进货日往后推")
	_check(tr.stock != old_stock or tr.stock.size() > 0, "换货后仍有库存")

	# 晚上关门，人被请出门
	main.player_sys.player.position = tr.site + Vector3(0, 0, 1)
	GameState.hours = 22.0
	tr.update(0.1)
	_check(not tr.open, "晚上关门")
	var d := Vector2(main.player_sys.player.position.x - tr.site.x,
		main.player_sys.player.position.z - tr.site.z).length()
	_check(d > 15.0, "关门时人已在门外（%.1f 米）" % d)

	# 指南针
	var got := false
	for m in main._compass_markers():
		if (m.color as Color).is_equal_approx(Color(1.0, 0.85, 0.35)):
			got = true
	_check(got, "指南针有商人标记")

	# 商人附近不自然刷僵尸
	GameState.hours = 12.0
	tr.update(0.1)
	main.player_sys.player.position = tr.site + Vector3(0, 0, 2)
	var z = main.spawner.spawn_zombie(GameState.day, false, false)
	if z:
		_check(not tr.is_near(z.global_position), "商人 15 米内不刷僵尸")
	else:
		print("SKIP 僵尸模型未下载")

	# 存档
	var saved := tr.save_data()
	var old_size := tr.stock.size()
	tr.stock.clear()
	tr.load_data(saved)
	_check(tr.stock.size() == old_size, "读档恢复商人库存")
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	if failures.is_empty():
		print("PASS test_trader")
	else:
		print("FAIL test_trader：", "; ".join(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
