extends SceneTree
## 能进的楼：楼梯走上二楼、墙挡人、门开关、梯子、子弹和视线隔楼板、存档记门
## （godot --headless --path . -s tests/test_poi_interior.gd）

const X := 8
const Y := 6
const Z := 8
var fails: Array[String] = []


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)


func _init() -> void:
	var cells := PackedByteArray()
	cells.resize(X * Y * Z)
	var put := func(x: int, y: int, z: int, k: int) -> void:
		cells[x + y * X + z * X * Y] = k
	for z in Z:
		for x in X:
			if x == 0 or z == 0 or x == X - 1 or z == Z - 1:
				for y in 3:
					put.call(x, y, z, PoiInterior.FULL)        # 一楼外墙
			put.call(x, 2, z, PoiInterior.FULL)                # 二楼楼板（顶面 3 米）
	put.call(4, 0, 0, PoiInterior.DOOR)                        # 一楼大门 1×2
	put.call(4, 1, 0, PoiInterior.DOOR)
	# 楼梯：沿 +x 三格，每格升 1 米，最后接上二楼楼板
	put.call(2, 0, 5, PoiInterior.RAMP)
	put.call(3, 1, 5, PoiInterior.RAMP)
	put.call(4, 2, 5, PoiInterior.RAMP)
	for x in [1, 2, 3]:
		put.call(x, 2, 5, PoiInterior.EMPTY)                   # 楼梯井
	put.call(3, 1, 4, PoiInterior.EMPTY)
	put.call(6, 0, 6, PoiInterior.LADDER)                      # 梯子井
	put.call(6, 1, 6, PoiInterior.LADDER)
	put.call(6, 2, 6, PoiInterior.LADDER)
	put.call(1, 0, 2, 4)                                       # 半块台阶
	var path := "user://test_interior.col"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer("poic".to_ascii_buffer())
	for v in [X, Y, Z]:
		f.store_16(v)
	for v in [-4, 0, -4]:
		f.store_16(v & 0xFFFF)
	f.store_buffer(cells.compress(FileAccess.COMPRESSION_GZIP))
	f.close()
	var doors := [{"block": "doorWood", "x0": 4, "y0": 0, "z0": 0, "x1": 4, "y1": 1, "z1": 0, "axis": "x", "metal": false}]
	var it := PoiInterior.load_col(path, "t", Vector3(10.0, 0.0, 20.0), PI / 2, doors)
	check(it != null, "读 .col")
	if it == null:
		_done()
		return
	check(it.size == Vector3i(X, Y, Z) and it.offset == Vector3i(-4, 0, -4), "尺寸、偏移")
	# 格子坐标和世界坐标来回换
	var probe := Vector3(2.3, 1.7, 5.6)
	check(it.to_cell(it.to_world(probe)).distance_to(probe) < 0.001, "坐标来回换")
	var w := World.new()
	w._cells.resize(World.MAP * 2 * World.MAP * 2)
	w._iwall.resize(World.MAP * 2 * World.MAP * 2)
	w.add_interior(it, {"doors": doors, "list": [{"block": "cntFridge", "drawn": false, "x": 1.5, "y": 1, "z": 1.5, "sx": 1, "sy": 2, "sz": 1}]})
	var at := func(c: Vector3) -> Vector3: return it.to_world(c)

	# 街面占地图：墙挡、屋里空、门关着挡、开了不挡
	var wall: Vector3 = at.call(Vector3(0.5, 0, 3.5))
	var room: Vector3 = at.call(Vector3(5.5, 0, 3.5))
	var door_cell: Vector3 = at.call(Vector3(4.5, 0, 0.5))
	check(w.blocked(wall, 0.0), "外墙挡路")
	check(not w.blocked(room, 0.0), "屋里能走")
	check(w.blocked(door_cell, 0.0), "门关着挡路")

	# 玩家走进墙会被推出来
	var pushed := w.push_out(at.call(Vector3(0.9, 0, 3.5)), 0.35)
	check(it.to_cell(pushed).x >= 1.34, "推出墙 %s" % it.to_cell(pushed))
	# 关着的门推人，开了能穿过
	var through: Vector3 = at.call(Vector3(4.5, 0, 0.5))
	check(it.to_cell(w.push_out(through, 0.35)).distance_to(Vector3(4.5, 0, 0.5)) > 0.3, "关着的门挡人")
	var d := w.nearest_door(at.call(Vector3(4.5, 0, 1.6)), at.call(Vector3(4.5, 0, 0.5)) - at.call(Vector3(4.5, 0, 1.6)))
	check(not d.is_empty() and d.door == 0 and not d.open, "面前找到门")
	check(w.nearest_door(at.call(Vector3(4.5, 0, 1.6)), at.call(Vector3(4.5, 0, 3.0)) - at.call(Vector3(4.5, 0, 1.6))).is_empty(), "背对着门不算")
	check(w.toggle_door(0, 0), "开门")
	check(it.to_cell(w.push_out(through, 0.35)).distance_to(Vector3(4.5, 0, 0.5)) < 0.01, "门开了能穿过")
	check(not w.blocked(door_cell, 0.0), "门开了僵尸能过")
	check(w.door_save() == [["t", 0]], "存档记开着的门")
	check(w.door_blocked_by(0, 0, through, 0.35), "站在门洞里")
	w.door_load([])
	check(not it.doors[0].open and w.blocked(door_cell, 0.0), "读档关门")
	w.door_load([["t", 0]])
	check(it.doors[0].open, "读档开门")

	# 半块台阶直接迈上去
	check(absf(w.floor_under(at.call(Vector3(1.5, 0, 2.5)), 0.3) - 0.5) < 0.01, "半块台阶 0.5 米")
	# 一楼站地面，不会被吸到二楼
	check(absf(w.floor_under(at.call(Vector3(5.5, 0, 3.5)), 0.3)) < 0.01, "一楼地面")
	check(absf(w.floor_under(at.call(Vector3(5.5, 3.2, 3.5)), 0.3) - 3.0) < 0.01, "二楼楼板 3 米")
	check(absf(w.floor_under(at.call(Vector3(2.5, 0.3, 5.5)), 0.0) - 0.5) < 0.01, "楼梯一半高度")

	# 沿楼梯一路走上二楼（和 player.gd 一样：先贴地，再横着走、推出墙）
	var p: Vector3 = at.call(Vector3(1.4, 0, 5.5))
	var step: Vector3 = (at.call(Vector3(2.4, 0, 5.5)) - at.call(Vector3(1.4, 0, 5.5))) * 0.05
	var vy := 0.0
	for i in 140:
		vy -= 12.0 / 60.0
		p.y += vy / 60.0
		var fy := w.floor_under(p, 0.3)
		if p.y <= fy + 0.01:
			p.y = fy
			vy = 0.0
		p = w.push_out(p + step, 0.35)
	var end := it.to_cell(p)
	check(absf(p.y - 3.0) < 0.05 and end.x > 5.5, "走楼梯上二楼 %s" % end)

	# 头顶碰楼板
	check(not w.ceiling_hit(at.call(Vector3(5.5, 0, 3.5)), 0.3, 1.8), "一楼站着不碰头")
	check(w.ceiling_hit(at.call(Vector3(5.5, 0.4, 3.5)), 0.3, 1.8), "一楼跳起来碰楼板")

	# 梯子
	check(w.ladder_at(at.call(Vector3(6.5, 0, 6.5))) and w.ladder_at(at.call(Vector3(6.5, 2.2, 6.5))), "梯子格")
	check(not w.ladder_at(at.call(Vector3(5.5, 0, 3.5))), "不是梯子")

	# 子弹、视线：楼板挡，屋里不挡
	check(w.solid_at(at.call(Vector3(5.5, 2.5, 3.5))), "子弹打中楼板")
	check(not w.solid_at(at.call(Vector3(5.5, 1.2, 3.5))), "屋里空气")
	check(w.line_blocked(at.call(Vector3(5.5, 1.5, 3.5)), at.call(Vector3(5.5, 4.5, 3.5))), "隔楼板看不见")
	check(not w.line_blocked(at.call(Vector3(5.5, 1.5, 3.5)), at.call(Vector3(2.5, 1.5, 2.5))), "同一层看得见")
	check(w.line_blocked(at.call(Vector3(5.5, 1.5, 3.5)), at.call(Vector3(5.5, 1.5, -3.0))), "隔外墙看不见")

	# 楼里不能往墙里、楼板里摆方块，空着的地方能摆
	var slab := World.cell_of(at.call(Vector3(5.5, 2.5, 3.5)))
	check(not w.can_place(slab), "楼板里不能摆")
	check(w.can_place(World.cell_of(at.call(Vector3(5.5, 0.5, 3.5)))), "屋里空地能摆")
	w.free()
	_done()


func _done() -> void:
	for m in fails:
		print("FAIL: ", m)
	print("test_poi_interior ", "OK" if fails.is_empty() else "FAIL")
	quit(0 if fails.is_empty() else 1)
