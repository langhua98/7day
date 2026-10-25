extends Node
## 载具验收：摆车、上下车、油门/刹车/倒车、转向、极速、上限、存档。
## 没有素材也能跑：找不到模型时载具用方块顶替外观。

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
	get_tree().create_timer(120.0).timeout.connect(func():
		push_error("test_vehicle 超时")
		get_tree().quit(1))


func _run() -> void:
	_test_physics()
	await _test_manager()
	_finish()


## 物理：单独造一个空世界，不加载整座城
func _test_physics() -> void:
	var w := World.new()
	var v := Vehicle.new()
	v.setup(w, "vehicleBicyclePlaceable", Vector3.ZERO, 0.0)
	check(v.node != null, "载具节点应该建出来（没模型也要有方块顶替）")
	for i in 20:
		v.update(0.1, 0.0, 1.0)
	check(v.speed > 0.0, "踩油门应该加速")
	check(v.pos.z < -0.1, "车应该往 -Z 前开")
	for i in 60:
		v.update(0.1, 0.0, 1.0)
	check_close(v.speed, float(C.VEHICLES["vehicleBicyclePlaceable"].speed), 0.05, "不超过极速")
	var rot0 := v.rot
	for i in 10:
		v.update(0.1, 1.0, 1.0)
	check(v.rot < rot0, "向右打方向 yaw 变小")
	for i in 80:
		v.update(0.1, 0.0, -1.0)
	check(v.speed < 0.0, "停下后继续往下是倒车")
	check(v.speed >= -float(C.VEHICLES["vehicleBicyclePlaceable"].speed) * C.VEHICLE_REVERSE_MULT - 0.01,
		"倒车不超过倒车极速")
	for i in 80:
		v.update(0.1, 0.0, 0.0)
	check_close(v.speed, 0.0, 0.05, "松油门会慢慢停下")
	var st := v.save_state()
	check(st.has("id") and st.has("pos") and st.has("rot"), "存档字段")


func _test_manager() -> void:
	var main = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.start(false)
	await get_tree().process_frame
	var ms: Vehicles = main.vehicles
	var spot: Vector3 = main.world.free_point(Vector3.ZERO, 12.0, 30.0)
	var v: Vehicle = ms.place("vehicleBicyclePlaceable", spot, 0.0)
	check(v != null, "能在空地上摆一辆车")
	check_eq(ms.count(), 1, "载具数量")
	main.player_sys.player.position = main.world.push_out(
		Vector3(spot.x + v.radius + 0.9, spot.y, spot.z), 0.35)
	check(ms.nearest(main.player_sys.player.position) == v, "走近能找到这辆车")
	check(ms.try_mount(), "能上车")
	check(ms.driving and main.hud.driving, "驾驶状态打开")
	check(main.player_sys.driving, "玩家进入驾驶状态")
	check(main.player_sys.player.position.distance_to(v.pos) < 0.01, "玩家跟着车")
	ms.update(0.1)
	check(main.hud._speed_label.text.ends_with("km/h"), "速度表有读数")
	ms.exit_vehicle()
	check(not ms.driving and not main.hud.driving, "下车后退出驾驶状态")
	check(not main.player_sys.driving, "玩家退出驾驶状态")
	check(main.player_sys.player.position.distance_to(v.pos) > v.radius, "人下车站到了车外")

	# 上限
	var guard := 0
	while ms.count() < C.VEHICLE_LIMIT and guard < 20:
		guard += 1
		var p: Vector3 = main.world.free_point(Vector3.ZERO, 10.0, 60.0)
		ms.place("vehicleBicyclePlaceable", p, 0.0)
	check_eq(ms.count(), C.VEHICLE_LIMIT, "摆到上限")
	var extra: Vector3 = main.world.free_point(Vector3.ZERO, 10.0, 60.0)
	check(ms.place("vehicleBicyclePlaceable", extra, 0.0) == null, "超过上限摆不出来")

	# 存档往返
	var saved := ms.save_data()
	check_eq((saved.get("vehicles", []) as Array).size(), C.VEHICLE_LIMIT, "存档里的载具数")
	ms.load_data(saved)
	check_eq(ms.count(), C.VEHICLE_LIMIT, "读档后载具数")
	check(not ms.driving, "读档后不在驾驶状态")


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
		print("PASS test_vehicle")
		get_tree().quit(0)
		return
	for m in failures:
		push_error("test_vehicle: " + m)
	print("FAIL test_vehicle（%d 项）" % failures.size())
	get_tree().quit(1)
