extends Node
## 第 5 步 5a：方块形状、旋转、存档、区块合批和 HUD 按钮。

const MAIN = preload("res://scenes/main.tscn")

var failures: Array[String] = []


func _ready() -> void:
	_test_shapes()
	_test_save()
	_test_chunks()
	await _test_hud()
	if failures.is_empty():
		print("PASS test_voxels")
		get_tree().quit(0)
		return
	for m in failures:
		push_error("test_voxels: " + m)
	print("FAIL test_voxels（%d 项）" % failures.size())
	get_tree().quit(1)


func _test_shapes() -> void:
	var w := World.new()
	w.add_voxel(Vector3i(0, 0, 0), "woodShapes", -1.0, "cube", 0)
	check_close(w.floor_under(Vector3(0.5, 1.0, 0.5), 0.1), 1.0, "整块顶面 1 米")
	w.add_voxel(Vector3i(2, 0, 0), "woodShapes", -1.0, "half", 0)
	check_close(w.floor_under(Vector3(2.5, 0.5, 0.5), 0.1), 0.5, "半块顶面 0.5 米")
	var pushed := w.push_out(Vector3(2.5, 0, 0.5), 0.35)
	check(pushed.distance_to(Vector3(2.5, 0, 0.5)) < 0.01, "半块不应该把人推开")
	w.add_voxel(Vector3i(4, 0, 0), "woodShapes", -1.0, "ramp", 0)
	check_close(w.floor_under(Vector3(4.1, 0.0, 0.5), 0.1), 0.1, "斜坡低端 0.1 米")
	check_close(w.floor_under(Vector3(4.9, 0.9, 0.5), 0.1), 0.9, "斜坡高端 0.9 米")
	w.add_voxel(Vector3i(6, 0, 0), "woodShapes", -1.0, "stairs", 0)
	check_close(w.floor_under(Vector3(6.1, 0.25, 0.5), 0.1), 0.25, "楼梯第一级")
	check_close(w.floor_under(Vector3(6.6, 0.75, 0.5), 0.1), 0.75, "楼梯第三级")
	w.add_voxel(Vector3i(8, 0, 0), "woodShapes", -1.0, "plate", 0)
	check_close(w.floor_under(Vector3(8.5, 0.1, 0.5), 0.1), 0.1, "板顶面 0.1 米")

	# 同一个世界点，旋转 90° 后斜坡方向应改变
	var p := Vector3(4.1, 0, 4.5)
	var l0 := Blocks.local_point(p, Vector3i(4, 0, 4), 0)
	var l1 := Blocks.local_point(p, Vector3i(4, 0, 4), 1)
	check(absf(Blocks.top_height("ramp", 0, l0) - Blocks.top_height("ramp", 1, l1)) > 0.1,
		"旋转应改变斜坡方向")
	w.free()


func _test_save() -> void:
	var w := World.new()
	w.add_voxel(Vector3i(0, 0, 0), "woodShapes", -1.0, "half", 2)
	var saved := w.voxel_save()
	check_eq(saved[0].size(), 7, "存档应保存形状和朝向")
	var w2 := World.new()
	w2.voxel_load(saved)
	var v: Dictionary = w2.voxels[Vector3i(0, 0, 0)]
	check_eq(str(v.get("shape", "")), "half", "读档恢复形状")
	check_eq(int(v.get("rot", -1)), 2, "读档恢复朝向")
	# 旧存档只有 5 个字段：按整块、朝向 0 读
	w2.voxel_load([[0, 0, 0, "woodShapes", 100.0]])
	v = w2.voxels[Vector3i(0, 0, 0)]
	check_eq(str(v.get("shape", "")), "cube", "旧档按整块读")
	check_eq(int(v.get("rot", -1)), 0, "旧档朝向 0")
	w.free()
	w2.free()


func _test_chunks() -> void:
	var w := World.new()
	for x in 8:
		for z in 8:
			for y in 2:
				w.add_voxel(Vector3i(x, y, z), "woodShapes")
	w._flush_voxels()
	check(w.voxel_draw_groups() <= 2, "8×8×2 方块应合成很少的区块（%d）" % w.voxel_draw_groups())
	w.free()

	var big := World.new()
	for x in 20:
		for z in 20:
			for y in 5:
				big.add_voxel(Vector3i(x, y, z), "woodShapes")
	big._flush_voxels()
	check(big.voxel_draw_groups() <= 8, "2000 块应合成很少的区块（%d）" % big.voxel_draw_groups())
	big.free()

	var full := World.new()
	for i in GameConfig.BLOCK_LIMIT:
		full.voxels[Vector3i(i, 0, 0)] = {}
	check(not full.add_voxel(Vector3i(0, 1, 0), "woodShapes"), "到方块上限不能再摆")
	check(not full.can_place(Vector3i(0, 1, 0)), "can_place 也挡住上限")
	full.free()


func _test_hud() -> void:
	var main = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.start(false)
	await get_tree().process_frame
	Assets.ensure_item("frameShapes", "木框")
	Assets.items_by_id["frameShapes"].kind = Assets.Kind.BLOCK
	main.inventory.add("frameShapes", 10)
	main.inventory.equip("frameShapes")
	await get_tree().process_frame
	check(main.hud._shape_btn.visible, "拿方块时显示形状按钮")
	check(main.hud._rotate_btn.visible, "拿方块时显示旋转按钮")
	main.hud.shape_pressed.emit()
	check(main.combat.block_shape != "cube", "点形状按钮应切换形状")
	main.hud.rotate_pressed.emit()
	check_eq(main.combat.block_rot, 1, "点旋转按钮应转 90°")
	check(main.hud._shape_btn.text.contains(Blocks.shape_name(main.combat.block_shape)), "按钮显示形状名")
	main.free()


func check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)


func check_eq(actual, expected, msg: String) -> void:
	if actual != expected:
		failures.append("%s：期望 %s，实际 %s" % [msg, expected, actual])


func check_close(actual: float, expected: float, msg: String, tol := 0.001) -> void:
	if absf(actual - expected) > tol:
		failures.append("%s：期望 %.4f，实际 %.4f" % [msg, expected, actual])
