class_name PoiInterior
extends RefCounted
## 一栋能走进去的楼：按方块算的碰撞格子（tools/build_poi_full.py 写的 assets/poi/<楼>.col）和门。
## 玩家走楼里时，地板、墙、楼梯、梯子、门都从这里查；僵尸只在街面那一层走（world.gd 的 _iwall）。
##
## 坐标：「格子坐标」就是方块数据的下标（游戏原来的 Unity 坐标，一格 1 米）。
## 楼的网格节点放在 origin、绕 Y 转 rot，网格本地坐标 = (-(cx + ox), cy + dy, cz + oz)（x 翻转，和网格一样）。

const EMPTY := 0
const FULL := 8
const TOP_HALF := 9
const RAMP := 10      # 10..13：往 +x、-x、+z、-z 升高
const LADDER := 14
const DOOR := 15
## 不用跳就能走上去的高度（米）：半块台阶、楼梯一级
const STEP_UP := 0.55
## 身体多高（头顶碰撞）
const BODY_H := 1.7
## 门板厚度
const DOOR_T := 0.08

var name := ""
var origin := Vector3.ZERO
var rot := 0.0
var size := Vector3i.ZERO
var offset := Vector3i.ZERO   # (ox, dy, oz)
var cells := PackedByteArray()
## 世界坐标里楼占的范围（xz）
var rect := Rect2()
## 门：{x0, y0, z0, x1, y1, z1, axis, metal, hatch, open, swing}
var doors: Array[Dictionary] = []

var _cs := 1.0
var _sn := 0.0
var _door_of := {}    # 格子下标 -> 门序号


## 读 .col 文件。失败返回 null
static func load_col(path: String, poi_name: String, at: Vector3, turn: float, door_list: Array) -> PoiInterior:
	if not FileAccess.file_exists(path):
		return null
	var d := FileAccess.get_file_as_bytes(path)
	if d.size() < 16 or d.slice(0, 4).get_string_from_ascii() != "poic":
		return null
	var sz := Vector3i(d.decode_u16(4), d.decode_u16(6), d.decode_u16(8))
	var off := Vector3i(d.decode_s16(10), d.decode_s16(12), d.decode_s16(14))
	var n := sz.x * sz.y * sz.z
	var raw := d.slice(16).decompress(n, FileAccess.COMPRESSION_GZIP)
	if raw.size() != n:
		push_warning("%s 的碰撞格子读不了" % poi_name)
		return null
	var it := PoiInterior.new()
	it.setup(poi_name, raw, sz, off, at, turn, door_list)
	return it


func setup(poi_name: String, data: PackedByteArray, sz: Vector3i, off: Vector3i, at: Vector3, turn: float,
		door_list: Array) -> void:
	name = poi_name
	cells = data
	size = sz
	offset = off
	origin = at
	rot = turn
	_cs = cos(turn)
	_sn = sin(turn)
	var lo := Vector2(INF, INF)
	var hi := -lo
	for corner in [Vector3(0, 0, 0), Vector3(sz.x, 0, 0), Vector3(0, 0, sz.z), Vector3(sz.x, 0, sz.z)]:
		var w := to_world(corner)
		lo = lo.min(Vector2(w.x, w.z))
		hi = hi.max(Vector2(w.x, w.z))
	rect = Rect2(lo, hi - lo)
	doors.clear()
	_door_of.clear()
	for e in door_list:
		if not (e is Dictionary):
			continue
		var dr := {"x0": int(e.get("x0", 0)), "y0": int(e.get("y0", 0)), "z0": int(e.get("z0", 0)),
			"x1": int(e.get("x1", 0)), "y1": int(e.get("y1", 0)), "z1": int(e.get("z1", 0)),
			"axis": str(e.get("axis", "x")), "metal": bool(e.get("metal", false)),
			"hatch": bool(e.get("hatch", false)), "block": str(e.get("block", "")), "open": false}
		var k := doors.size()
		for y in range(dr.y0, dr.y1 + 1):
			for z in range(dr.z0, dr.z1 + 1):
				for x in range(dr.x0, dr.x1 + 1):
					if _in(x, y, z):
						_door_of[_idx(x, y, z)] = k
		# 开门往哪边转：往门外/门里空着的那边
		var into := Vector3i(0, 0, 1) if dr.axis == "x" else Vector3i(1, 0, 0)
		dr["swing"] = 1 if code_at(dr.x0 + into.x, dr.y0, dr.z0 + into.z) == EMPTY else -1
		doors.append(dr)


# —— 坐标换算 ——

## 世界坐标 → 格子坐标（小数）
func to_cell(p: Vector3) -> Vector3:
	var q := p - origin
	var lx := q.x * _cs - q.z * _sn
	var lz := q.x * _sn + q.z * _cs
	return Vector3(-lx - offset.x, q.y - offset.y, lz - offset.z)


## 格子坐标 → 世界坐标
func to_world(c: Vector3) -> Vector3:
	var lx := -(c.x + offset.x)
	var lz := c.z + offset.z
	return origin + Vector3(lx * _cs + lz * _sn, c.y + offset.y, -lx * _sn + lz * _cs)


## 格子坐标 → 楼节点的本地坐标（门板、箱子挂在楼节点下面）
func to_local(c: Vector3) -> Vector3:
	return Vector3(-(c.x + offset.x), c.y + offset.y, c.z + offset.z)


func contains(p: Vector3, margin := 0.0) -> bool:
	return rect.grow(margin).has_point(Vector2(p.x, p.z))


func _in(x: int, y: int, z: int) -> bool:
	return x >= 0 and y >= 0 and z >= 0 and x < size.x and y < size.y and z < size.z


func _idx(x: int, y: int, z: int) -> int:
	return x + y * size.x + z * size.x * size.y


## 这格现在是什么（门按开关算成空或整格）
func code_at(x: int, y: int, z: int) -> int:
	if not _in(x, y, z):
		return EMPTY
	var k := cells[_idx(x, y, z)]
	if k == DOOR:
		var di: int = _door_of.get(_idx(x, y, z), -1)
		return EMPTY if di >= 0 and doors[di].open else FULL
	return k


## 一格里 (u, w) 这根竖线上实心的那段 [底, 顶]（0..1）；空的返回 (1, 0)
static func span(code: int, u: float, w: float) -> Vector2:
	if code >= 1 and code <= FULL:
		return Vector2(0.0, code / 8.0)
	match code:
		TOP_HALF:
			return Vector2(0.5, 1.0)
		RAMP:
			return Vector2(0.0, maxf(u, 0.05))
		RAMP + 1:
			return Vector2(0.0, maxf(1.0 - u, 0.05))
		RAMP + 2:
			return Vector2(0.0, maxf(w, 0.05))
		RAMP + 3:
			return Vector2(0.0, maxf(1.0 - w, 0.05))
	return Vector2(1.0, 0.0)


static func is_ramp(code: int) -> bool:
	return code >= RAMP and code < RAMP + 4


## 这一列格子挡不挡站在 feet 高度的身体（能直接迈上去的矮台阶、楼梯不挡）
func _blocks_body(gx: int, gz: int, feet: float) -> bool:
	for y in range(floori(feet), floori(feet + BODY_H) + 1):
		var k := code_at(gx, y, gz)
		if k == EMPTY or k == LADDER or is_ramp(k):
			continue
		var s := span(k, 0.5, 0.5)
		if y + s.y > feet + STEP_UP and y + s.x < feet + BODY_H:
			return true
	return false


# —— 给 world.gd 用的查询 ——

## 把圆（玩家、僵尸）推出墙。和 world.push_out 的方块一样当 1×1 的格子推
func push_out(p: Vector3, radius: float) -> Vector3:
	var c := to_cell(p)
	var q := Vector2(c.x, c.z)
	for gz in range(floori(q.y - radius), floori(q.y + radius) + 1):
		for gx in range(floori(q.x - radius), floori(q.x + radius) + 1):
			if not _blocks_body(gx, gz, c.y):
				continue
			var cc := Vector2(gx + 0.5, gz + 0.5)
			var d := q - cc
			var h := 0.5 + radius
			if absf(d.x) < h and absf(d.y) < h:
				if h - absf(d.x) < h - absf(d.y):
					d.x = signf(d.x if d.x != 0.0 else 1.0) * h
				else:
					d.y = signf(d.y if d.y != 0.0 else 1.0) * h
				q = cc + d
	var out := to_world(Vector3(q.x, c.y, q.y))
	out.y = p.y
	return out


## 站在 p 时脚下最高的落脚面（世界 y）；只算不高于脚底 + STEP_UP 的，没有返回 -INF
func floor_at(p: Vector3, radius: float) -> float:
	var c := to_cell(p)
	var limit := c.y + STEP_UP
	var best := -INF
	var y_top := mini(floori(limit), size.y - 1)
	for gz in range(floori(c.z - radius), floori(c.z + radius) + 1):
		for gx in range(floori(c.x - radius), floori(c.x + radius) + 1):
			if gx < 0 or gz < 0 or gx >= size.x or gz >= size.z:
				continue
			var u := clampf(c.x - gx, 0.0, 1.0)
			var w := clampf(c.z - gz, 0.0, 1.0)
			for y in range(y_top, -1, -1):
				if float(y + 1) <= best:
					break
				var s := span(code_at(gx, y, gz), u, w)
				if s.y <= s.x:
					continue
				if y + s.y <= limit + 0.001:
					best = maxf(best, y + s.y)
					break
	if best == -INF:
		return -INF
	return origin.y + best + offset.y


## 头顶（p.y + height）碰到东西没有
func ceiling_hit(p: Vector3, radius: float, height: float) -> bool:
	var c := to_cell(p)
	var top := c.y + height
	var y := floori(top)
	for gz in range(floori(c.z - radius), floori(c.z + radius) + 1):
		for gx in range(floori(c.x - radius), floori(c.x + radius) + 1):
			var k := code_at(gx, y, gz)
			if k == EMPTY or k == LADDER or is_ramp(k):
				continue
			var s := span(k, 0.5, 0.5)
			if top > y + s.x and top < y + s.y:
				return true
	return false


## 这个点在不在实心里（子弹、视线、摆方块）
func solid_point(p: Vector3) -> bool:
	var c := to_cell(p)
	var x := floori(c.x)
	var y := floori(c.y)
	var z := floori(c.z)
	var k := code_at(x, y, z)
	if k == EMPTY or k == LADDER:
		return false
	var s := span(k, c.x - x, c.z - z)
	return c.y - y >= s.x and c.y - y <= s.y


## 站在 p 的身体碰不碰到这一列的墙（街面那层给僵尸用的占地图）
func blocks_at(p: Vector3) -> bool:
	var c := to_cell(p)
	return _blocks_body(floori(c.x), floori(c.z), c.y)


## 身体（脚底或胸口）在梯子格里
func ladder_at(p: Vector3) -> bool:
	var c := to_cell(p)
	var x := floori(c.x)
	var z := floori(c.z)
	return code_at(x, floori(c.y + 0.1), z) == LADDER or code_at(x, floori(c.y + 1.0), z) == LADDER


# —— 门 ——

## 门的中心（世界坐标，门洞中间离地 1 米）
func door_center(i: int) -> Vector3:
	var d: Dictionary = doors[i]
	return to_world(Vector3((d.x0 + d.x1 + 1) * 0.5, d.y0 + minf(1.0, (d.y1 - d.y0 + 1) * 0.5), (d.z0 + d.z1 + 1) * 0.5))


## 离 p 最近、在 reach 以内、大致在面前（facing 是朝向，零向量 = 不管朝向）的门，没有返回 -1
func nearest_door(p: Vector3, facing: Vector3, reach: float) -> int:
	var best := -1
	var best_d := reach
	for i in doors.size():
		var to := door_center(i) - p
		if absf(to.y - 0.6) > 1.6:
			continue
		var flat := Vector2(to.x, to.z)
		var dist := flat.length()
		if dist > best_d:
			continue
		if facing != Vector3.ZERO and dist > 0.6:
			var f := Vector2(facing.x, facing.z).normalized()
			if f.dot(flat / dist) < 0.5:
				continue
		best_d = dist
		best = i
	return best


func set_door(i: int, open: bool) -> void:
	if i >= 0 and i < doors.size():
		doors[i].open = open


## 门板现在的变换（楼节点本地坐标）：单位立方体先缩放成 宽×高×厚（宽沿 x），再绕 y 转到门洞方向。
## 开着时绕门轴那头转 90 度贴着门框立着。门模型也按这个摆（先缩放成单位立方体）
func door_transform(i: int) -> Transform3D:
	var d: Dictionary = doors[i]
	var h: float = d.y1 - d.y0 + 1 - 0.04
	var y: float = d.y0 + 0.02 + h * 0.5
	var c: Vector3
	var w: float
	var yaw := 0.0
	if d.axis == "x":
		w = d.x1 - d.x0 + 1
		var zc: float = d.z0 + 0.5 * (d.z1 - d.z0 + 1)
		if d.open:
			c = Vector3(d.x0 + DOOR_T * 0.5, y, zc + d.swing * w * 0.5)
			yaw = PI / 2
		else:
			c = Vector3(d.x0 + w * 0.5, y, zc)
	else:
		w = d.z1 - d.z0 + 1
		var xc: float = d.x0 + 0.5 * (d.x1 - d.x0 + 1)
		if d.open:
			c = Vector3(xc + d.swing * w * 0.5, y, d.z0 + DOOR_T * 0.5)
		else:
			c = Vector3(xc, y, d.z0 + w * 0.5)
			yaw = PI / 2
	return Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(w, h, DOOR_T)), to_local(c))


## 门所在的世界格子（开关门后重算街面占地图用）
func door_world_cells(i: int) -> Array[Vector2i]:
	var d: Dictionary = doors[i]
	var out: Array[Vector2i] = []
	for z in range(d.z0 - 1, d.z1 + 2):
		for x in range(d.x0 - 1, d.x1 + 2):
			var w := to_world(Vector3(x + 0.5, d.y0, z + 0.5))
			var k := Vector2i(floori(w.x), floori(w.z))
			if not out.has(k):
				out.append(k)
	return out
