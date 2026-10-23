extends "res://tests/test_base.gd"
## 僵尸寻路距离场：分几帧算的结果要和一次算完一样，每帧不超预算太多，墙要绕着走。


func _initialize() -> void:
	var w := World.new()
	w._cells.resize(World.MAP * 2 * World.MAP * 2)
	w._iwall.resize(World.MAP * 2 * World.MAP * 2)
	# 一堵南北向的墙 x=5，z 从 -20 到 20，只在 z=10 留个口
	for z in range(-20, 21):
		if z != 10:
			w._cells[(z + World.MAP) * World.MAP * 2 + 5 + World.MAP] = 1
	var target := Vector3(0.5, 0, 0.5)
	w.update_flow(target)
	var full := w._flow.duplicate()
	var size := World.FLOW_SIZE
	var at := func(x: int, z: int) -> int: return full[(z + World.FLOW_R) * size + x + World.FLOW_R]
	check_eq(at.call(0, 0), 0, "中心距离 0")
	check_eq(at.call(3, 0), 3, "直走 3 格")
	check_eq(at.call(3, 3), 3, "斜走 3 格")
	check_eq(at.call(5, 0), -2, "墙标成 -2")
	# 墙另一边 (6, 0) 要从 z=10 的口绕过去：至少 10 + 10 步
	check(at.call(6, 0) >= 20, "墙后的格子要绕路，实际 %d" % at.call(6, 0))
	check(w.flow_dir(Vector3(-3.5, 0, 0.5)).x > 0.5, "西边的僵尸往东走")

	# 分片：预算很小也要算出一样的结果，且要分好多帧
	w._flow = PackedInt32Array()
	w.request_flow(target)
	var steps := 0
	while w._fj_active and steps < 100000:
		w.flow_step(200)
		steps += 1
	check(steps > 3, "小预算应分多帧算完，实际 %d 帧" % steps)
	check(w._flow == full, "分片结果和一次算完一致")

	# 算的过程中又要新中心：算完旧的接着算新的
	w.request_flow(Vector3(-10.5, 0, 2.5))
	w.flow_step(200)
	w.request_flow(Vector3(-20.5, 0, 2.5))
	while w._fj_active:
		w.flow_step(1 << 30)
	check_eq(w._flow_center, Vector2i(-21, 2), "排队的新中心最后生效")
	w.free()
	finish("test_flow")
