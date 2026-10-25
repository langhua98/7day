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
	if FileAccess.file_exists("res://assets/data/block_shapes.json"):
		for s in ["cube", "half", "ramp", "stairs", "pole", "plate"]:
			check(Blocks.shape_triangles(s) > 0, "官方形状 %s 应加载" % s)
	var w := World.new()
	for x in 8:
		for z in 8:
			for y in 2:
				w.add_voxel(Vector3i(x, y, z), "woodShapes")
	w._flush_voxels()
	check(w.voxel_draw_groups() <= 2, "8×8×2 方块应合成很少的区块（%d）" % w.voxel_draw_groups())
	w.free()

	var cube := World.new()
	for x in 2:
		for z in 2:
			for y in 2:
				cube.add_voxel(Vector3i(x, y, z), "woodShapes")
	cube._flush_voxels()
	var ch: Dictionary = cube._vox_chunks.values()[0]
	var arr: Array = (ch.mi as MeshInstance3D).mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	check_eq(verts.size(), 144, "2×2×2 整块应剔除内部面")
	cube.free()

	var big := World.new()
	for x in 20:
		for z in 20:
			for y in 5:
				big.add_voxel(Vector3i(x, y, z), "woodShapes")
	big._flush_voxels()
	check(big.voxel_draw_groups() <= 8, "2000 块应合成很少的区块（%d）" % big.voxel_draw_groups())
	big.free()

	# 结构稳定：木块悬挑超过 4 格会掉
	var sw := World.new()
	sw.add_voxel(Vector3i(1, 0, 0), "woodShapes")
	for x in range(1, 8):
		sw.add_voxel(Vector3i(x, 1, 0), "woodShapes")
	var dropped := sw.check_support(Vector3i(1, 0, 0))
	check(dropped >= 2, "木块悬挑超过 4 格应掉落（%d）" % dropped)
	check(not sw.voxels.has(Vector3i(7, 1, 0)), "最远端应掉落")
	check(sw.voxels.has(Vector3i(5, 1, 0)), "4 格悬挑应保留")
	sw.free()

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
	check(main.hud._rotate_btn.visible, "拿方块时显示旋转按钮")
	check_eq(main.combat._placement_shape(), "cube", "基础方块按整块摆")
	main.hud.rotate_pressed.emit()
	check_eq(main.combat.block_rot, 1, "点旋转按钮应转 90°")

	# 六种形状作为独立背包物品：选半块后固定按半块摆，仍可旋转
	check_eq(Blocks.base_of("woodShapes_half"), "woodShapes", "半块物品映射到木块")
	check_eq(Blocks.shape_of("woodShapes_half"), "half", "半块物品形状")
	check(Blocks.variant_ids().has("woodShapes_ramp"), "生成斜坡物品")
	main.inventory.add("woodShapes_half", 5)
	main.inventory.equip("woodShapes_half")
	await get_tree().process_frame
	check(main.hud._rotate_btn.visible, "独立形状物品仍可旋转")
	check_eq(main.combat._placement_shape(), "half", "半块物品按半块摆")
	check(Blocks.info("woodShapes_half").zh.contains("半块"), "物品名带形状")

	# 锤子升级木框
	Assets.ensure_item("meleeToolRepairT1ClawHammer", "修理工锤")
	main.inventory.add("meleeToolRepairT1ClawHammer", 1)
	main.inventory.equip("meleeToolRepairT1ClawHammer")
	var up_cell := Vector3i(0, 20, 0)
	main.world.add_voxel(up_cell, "frameShapes")
	for i in 4:
		main.combat._try_tool_action(up_cell)
	check_eq(str(main.world.voxels[up_cell].id), "woodShapes", "锤子升级木框")
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
