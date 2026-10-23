class_name World
extends Node3D
## 市中心：十字街道、人行道、七日杀原版的市中心建筑（POI）、街上的车和杂物、能翻找的容器。
## 楼来自 assets/poi/（tools/build_poi.gd 从游戏的远景网格转出来），
## 车和杂物来自 assets/index/world_models.json（tools/fetch_assets.py 从云盘取）。
## 碰撞：楼用 1 米一格的占地图，车和杂物用矩形。玩家和僵尸撞到就被推开、沿墙滑动。

const ROOT := "res://assets"
const INDEX := "res://assets/index/world_models.json"
const POI_INDEX := "res://assets/poi/index.json"
const POI_SHADER := preload("res://scripts/poi.gdshader")
const TERRAIN_INDEX := "res://assets/terrain/terrain.json"

## 街道中线（x、z 两个方向一样）。原点是市中心的十字路口
const ROADS := [-152.0, -76.0, 0.0, 76.0, 152.0]
const ROAD_W := 10.0
const WALK_W := 3.0
## 能走到的边界（最外圈的路上摆了路障）
const EDGE := 150.0
## 占地图范围（米）
const MAP := 160

## 每个街区放哪些楼（游戏里 Zoning 是 downtown 的建筑）
const BIG := ["skyscraper_01", "skyscraper_04", "hotel_ostrich", "courthouse_med_01", "downtown_building_03",
	"church_01", "theater_stage_01", "remnant_church_01"]
const MID := ["downtown_building_01", "downtown_building_02", "downtown_building_04", "downtown_strip_01",
	"downtown_strip_03", "downtown_strip_04", "parking_garage_01", "parking_garage_03", "parking_garage_04",
	"fire_station_01", "bar_01", "diner_01", "diner_02", "fastfood_01", "fastfood_03", "body_shop_01",
	"downtown_business_06", "downtown_business_07", "industrial_business_08", "countrytown_business_03"]
const SMALL := ["downtown_filler_01", "downtown_filler_02", "downtown_filler_12", "downtown_filler_13",
	"downtown_filler_14", "downtown_filler_15", "downtown_filler_21", "downtown_filler_22", "downtown_filler_23",
	"downtown_filler_25", "downtown_filler_26", "downtown_filler_27", "downtown_filler_29", "downtown_filler_30",
	"downtown_filler_31", "post_office_01", "remnant_downtown_filler_07", "remnant_downtown_filler_08",
	"remnant_downtown_filler_09", "remnant_downtown_filler_11", "remnant_downtown_filler_12",
	"remnant_downtown_filler_14", "remnant_downtown_filler_15", "remnant_downtown_filler_17",
	"rubble_downtown_filler_02", "downtown_filler_park_02", "downtown_filler_plaza_02"]
## 市中心四个街区固定放最高的楼
const CENTER := ["skyscraper_01", "hotel_ostrich", "skyscraper_04", "courthouse_med_01"]

var rng := RandomNumberGenerator.new()
## 挡路的车和杂物：{c: 中心 Vector2(x,z), h: 半长宽, rot: 朝向, r: 外接圆半径}
var obstacles: Array[Dictionary] = []
## 能翻找的：{node, pos, name, loot, searched, r, kind}
var containers: Array[Dictionary] = []
## 放了哪些楼：[{name, pos}]
var buildings: Array[Dictionary] = []
var models := {}
var textures := {}
var decals: PackedStringArray = []
var pois := {}
## 地面贴图（游戏的地形贴图数组）：名字 -> {albedo, normal, orm, tile}
var terrain := {}
var ready_ok := false

var _mesh_info := {}    # 模型名 -> {mesh, xf, size}
var _mat_cache := {}
var _marks: SurfaceTool
var _poi_mat: ShaderMaterial
var _cells := PackedByteArray()   # 楼的占地图，(MAP*2)² 格，1 = 挡路
var _grid := {}         # 粗网格加速查询：格子 -> 障碍物下标
const GRID := 8.0


func _ready() -> void:
	_cells.resize(MAP * 2 * MAP * 2)
	if FileAccess.file_exists(POI_INDEX):
		var p = JSON.parse_string(FileAccess.get_file_as_string(POI_INDEX))
		if p is Dictionary:
			pois = p
	if FileAccess.file_exists(TERRAIN_INDEX):
		var t = JSON.parse_string(FileAccess.get_file_as_string(TERRAIN_INDEX))
		if t is Dictionary:
			terrain = t
	if not FileAccess.file_exists(INDEX):
		push_warning("没有 world_models.json，街上没有车和杂物")
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	if not (data is Dictionary):
		return
	models = data.get("models", {})
	textures = data.get("textures", {})
	decals = PackedStringArray(data.get("decals", []))
	ready_ok = true


# —— 对外接口 ——

func build(seed_value: int) -> void:
	rng.seed = seed_value
	_build_ground()
	_build_blocks()
	_build_streets()
	_build_border()
	_scatter_decals()
	_rebuild_grid()


## 把一个圆（玩家、僵尸）推出楼和障碍物
func push_out(p: Vector3, radius: float) -> Vector3:
	var q := Vector2(p.x, p.z)
	# 楼：查周围的格子，每个挡路的格子当成 1×1 的方块
	for gz in range(floori(q.y - radius), floori(q.y + radius) + 1):
		for gx in range(floori(q.x - radius), floori(q.x + radius) + 1):
			if _cell(gx, gz):
				var c := Vector2(gx + 0.5, gz + 0.5)
				var d := q - c
				var h := 0.5 + radius
				if absf(d.x) < h and absf(d.y) < h:
					if h - absf(d.x) < h - absf(d.y):
						d.x = signf(d.x if d.x != 0.0 else 1.0) * h
					else:
						d.y = signf(d.y if d.y != 0.0 else 1.0) * h
					q = c + d
	# 自己摆的方块：只算和身体高度（脚底到头顶）重叠的那几层
	if not voxels.is_empty():
		for gz in range(floori(q.y - radius), floori(q.y + radius) + 1):
			for gx in range(floori(q.x - radius), floori(q.x + radius) + 1):
				if not _solid_column(gx, gz, p.y):
					continue
				var c := Vector2(gx + 0.5, gz + 0.5)
				var d := q - c
				var h := 0.5 + radius
				if absf(d.x) < h and absf(d.y) < h:
					if h - absf(d.x) < h - absf(d.y):
						d.x = signf(d.x if d.x != 0.0 else 1.0) * h
					else:
						d.y = signf(d.y if d.y != 0.0 else 1.0) * h
					q = c + d
	for i in _nearby(q):
		var o: Dictionary = obstacles[i]
		var d: Vector2 = q - o.c
		if d.length() > o.r + radius:
			continue
		var local := d.rotated(o.rot)
		var h: Vector2 = o.h + Vector2(radius, radius)
		if absf(local.x) < h.x and absf(local.y) < h.y:
			if h.x - absf(local.x) < h.y - absf(local.y):
				local.x = signf(local.x if local.x != 0.0 else 1.0) * h.x
			else:
				local.y = signf(local.y if local.y != 0.0 else 1.0) * h.y
			q = o.c + local.rotated(-o.rot)
	q.x = clampf(q.x, -EDGE, EDGE)
	q.y = clampf(q.y, -EDGE, EDGE)
	return Vector3(q.x, p.y, q.y)


## 这个点在不在楼、车里面
func blocked(p: Vector3, radius := 0.3) -> bool:
	var q := Vector2(p.x, p.z)
	if absf(q.x) > EDGE or absf(q.y) > EDGE:
		return true
	for gz in range(floori(q.y - radius), floori(q.y + radius) + 1):
		for gx in range(floori(q.x - radius), floori(q.x + radius) + 1):
			if _wall(gx, gz):
				return true
	for i in _nearby(q):
		var o: Dictionary = obstacles[i]
		var local: Vector2 = (q - o.c).rotated(o.rot)
		if absf(local.x) < o.h.x + radius and absf(local.y) < o.h.y + radius:
			return true
	return false


## 两点之间有没有被楼挡住（子弹、视线用）
func line_blocked(a: Vector3, b: Vector3) -> bool:
	var steps := int(a.distance_to(b) / 0.5)
	for s in range(1, steps):
		var p := a.lerp(b, float(s) / steps)
		if _wall(floori(p.x), floori(p.z)):
			return true
	return false


## 离玩家最近、够得着的容器
func nearest_container(p: Vector3, reach := 1.4) -> Dictionary:
	var best := {}
	var best_d := INF
	for c in containers:
		var d: float = Vector2(p.x - c.pos.x, p.z - c.pos.z).length() - c.r
		if d < reach and d < best_d:
			best_d = d
			best = c
	return best


## 随机找一个空地（不在楼里、车里）
func free_point(center: Vector3, min_r: float, max_r: float) -> Vector3:
	for i in 40:
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf_range(min_r * min_r, max_r * max_r))
		var p := center + Vector3(cos(ang) * r, 0, sin(ang) * r)
		if not blocked(p, 0.6):
			return p
	return push_out(center + Vector3(min_r, 0, 0), 0.6)


## 换上方块贴图图集（tools/build_poi.gd 打包的 assets/poi/atlas_*.res），没有就用纯色
func set_block_atlas(atlas: Texture2DArray, normal: Texture2DArray = null) -> void:
	var mat := _poi_material()
	if atlas:
		mat.set_shader_parameter("atlas", atlas)
		if normal:
			mat.set_shader_parameter("atlas_normal", normal)
		mat.set_shader_parameter("use_atlas", true)


# —— 僵尸寻路：以玩家为中心的距离场，僵尸沿着距离变小的方向走就能绕开楼 ——

const FLOW_R := 48
var _flow := PackedInt32Array()
var _flow_center := Vector2i(1 << 20, 0)


## 每隔一会儿以 target 为中心重算一次（BFS，8 方向，不能斜着穿墙角）
func update_flow(target: Vector3) -> void:
	var size := FLOW_R * 2 + 1
	if _flow.size() != size * size:
		_flow.resize(size * size)
	_flow.fill(-1)
	_flow_center = Vector2i(floori(target.x), floori(target.z))
	var queue := PackedInt32Array()
	queue.resize(size * size)
	var head := 0
	var tail := 0
	var start := FLOW_R * size + FLOW_R
	_flow[start] = 0
	queue[tail] = start
	tail += 1
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	while head < tail:
		var i := queue[head]
		head += 1
		var x := i % size
		var z := i / size
		var d := _flow[i]
		for k in 8:
			var dv: Vector2i = dirs[k]
			var nx := x + dv.x
			var nz := z + dv.y
			if nx < 0 or nz < 0 or nx >= size or nz >= size:
				continue
			var ni := nz * size + nx
			if _flow[ni] != -1:
				continue
			var wx := _flow_center.x - FLOW_R + nx
			var wz := _flow_center.y - FLOW_R + nz
			if _wall(wx, wz):
				_flow[ni] = -2
				continue
			if k >= 4 and (_wall(_flow_center.x - FLOW_R + x + dv.x, _flow_center.y - FLOW_R + z) or _wall(_flow_center.x - FLOW_R + x, _flow_center.y - FLOW_R + z + dv.y)):
				continue
			_flow[ni] = d + 1
			queue[tail] = ni
			tail += 1


## 从 p 出发往目标走的方向（不在距离场里返回 ZERO，调用方直接朝目标走）
func flow_dir(p: Vector3) -> Vector3:
	var size := FLOW_R * 2 + 1
	var x := floori(p.x) - _flow_center.x + FLOW_R
	var z := floori(p.z) - _flow_center.y + FLOW_R
	if x < 1 or z < 1 or x >= size - 1 or z >= size - 1:
		return Vector3.ZERO
	var here := _flow[z * size + x]
	var best := here if here >= 0 else 1 << 30
	var best_v := Vector2i.ZERO
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var v := _flow[(z + dz) * size + x + dx]
			if v >= 0 and v < best:
				best = v
				best_v = Vector2i(dx, dz)
	if best_v == Vector2i.ZERO:
		return Vector3.ZERO
	# 朝相邻格子的中心走，避免贴着墙角卡住
	var c := Vector3(floori(p.x) + best_v.x + 0.5, p.y, floori(p.z) + best_v.y + 0.5)
	var d := c - p
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else Vector3.ZERO


func _cell(gx: int, gz: int) -> bool:
	var x := gx + MAP
	var z := gz + MAP
	if x < 0 or z < 0 or x >= MAP * 2 or z >= MAP * 2:
		return false
	return _cells[z * MAP * 2 + x] == 1


## 楼，或者贴地两格里有自己摆的方块（僵尸过不去、绕着走）
func _wall(gx: int, gz: int) -> bool:
	return _cell(gx, gz) or (not _low.is_empty() and _low.has(Vector2i(gx, gz)))


# —— 自己摆的方块（1 米一格，格子坐标 = 世界坐标向下取整） ——

## 格子 -> {id, hp, node}
var voxels := {}
var _low := {}      # Vector2i(x, z) -> 这一列 y=0、1 两格里有几块（挡僵尸用）
var _voxel_root: Node3D
const VOXEL_TOP := 40


static func cell_of(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x), floori(p.y), floori(p.z))


func has_voxel(c: Vector3i) -> bool:
	return voxels.has(c)


## 这一列在 [脚底, 头顶] 这段高度里有没有方块
func _solid_column(gx: int, gz: int, feet: float) -> bool:
	for y in range(maxi(0, floori(feet + 0.05)), floori(feet + 1.7) + 1):
		if voxels.has(Vector3i(gx, y, gz)):
			return true
	return false


## 这格能不能摆：空的、不在楼里、在地图里、不太高
func can_place(c: Vector3i) -> bool:
	if voxels.has(c) or c.y < 0 or c.y >= VOXEL_TOP:
		return false
	if absi(c.x) >= int(EDGE) or absi(c.z) >= int(EDGE):
		return false
	return not _cell(c.x, c.z)


func add_voxel(c: Vector3i, id: String, hp := -1.0) -> void:
	if voxels.has(c):
		return
	if _voxel_root == null:
		_voxel_root = Node3D.new()
		_voxel_root.name = "Voxels"
		add_child(_voxel_root)
	var node := Blocks.make_node(id)
	node.position = Vector3(c)
	_voxel_root.add_child(node)
	voxels[c] = {"id": id, "hp": hp if hp > 0.0 else float(Blocks.info(id).get("hp", 100.0)), "node": node}
	if c.y <= 1:
		var k := Vector2i(c.x, c.z)
		_low[k] = _low.get(k, 0) + 1


func remove_voxel(c: Vector3i) -> String:
	var v: Dictionary = voxels.get(c, {})
	if v.is_empty():
		return ""
	(v.node as Node).queue_free()
	voxels.erase(c)
	if c.y <= 1:
		var k := Vector2i(c.x, c.z)
		_low[k] = _low.get(k, 1) - 1
		if _low[k] <= 0:
			_low.erase(k)
	return v.id


## 打方块，耐久打完就拆掉，返回拆下来的方块名（没拆掉返回空）
func damage_voxel(c: Vector3i, dmg: float) -> String:
	var v: Dictionary = voxels.get(c, {})
	if v.is_empty():
		return ""
	v.hp -= dmg
	if v.hp <= 0.0:
		return remove_voxel(c)
	return ""


## 方块还剩几成耐久（0..1）
func voxel_health(c: Vector3i) -> float:
	var v: Dictionary = voxels.get(c, {})
	if v.is_empty():
		return 0.0
	return v.hp / float(Blocks.info(v.id).get("hp", 100.0))


func clear_voxels() -> void:
	for c in voxels.keys():
		remove_voxel(c)
	voxels.clear()
	_low.clear()


## 存档用：[[x, y, z, 方块名, 耐久], …]
func voxel_save() -> Array:
	var out := []
	for c in voxels:
		out.append([c.x, c.y, c.z, voxels[c].id, voxels[c].hp])
	return out


func voxel_load(list: Array) -> void:
	clear_voxels()
	for e in list:
		if e is Array and e.size() >= 4 and Blocks.is_block(str(e[3])):
			add_voxel(Vector3i(int(e[0]), int(e[1]), int(e[2])), str(e[3]), float(e[4]) if e.size() > 4 else -1.0)


## 站在 p 时脚下最高的方块顶（没有就是地面 0）。只算比脚底高不了多少的方块，免得被吸到头顶上
func floor_under(p: Vector3, radius: float) -> float:
	if voxels.is_empty():
		return 0.0
	var best := 0.0
	var top := floori(p.y + 0.3)
	for gz in range(floori(p.z - radius), floori(p.z + radius) + 1):
		for gx in range(floori(p.x - radius), floori(p.x + radius) + 1):
			for y in range(mini(top - 1, VOXEL_TOP), -1, -1):
				if float(y + 1) <= best:
					break
				if voxels.has(Vector3i(gx, y, gz)):
					best = float(y + 1)
					break
	return best


## 头顶（p.y + height）碰到方块没有
func ceiling_hit(p: Vector3, radius: float, height: float) -> bool:
	if voxels.is_empty():
		return false
	var y := floori(p.y + height)
	for gz in range(floori(p.z - radius), floori(p.z + radius) + 1):
		for gx in range(floori(p.x - radius), floori(p.x + radius) + 1):
			if voxels.has(Vector3i(gx, y, gz)):
				return true
	return false


## 沿射线一格一格走（DDA），找到第一个碰到的东西：
## {hit: 打中的方块格子（没打中方块是 null）, place: 打中前那一格（能摆新方块的地方）, t: 距离}
## 打到地面或楼也算，这时 hit 是 null。什么都没碰到返回空字典。
func ray_voxel(from: Vector3, dir: Vector3, reach: float) -> Dictionary:
	dir = dir.normalized()
	var c := cell_of(from)
	var prev := c
	var step := Vector3i(int(signf(dir.x)), int(signf(dir.y)), int(signf(dir.z)))
	var t_max := Vector3.ZERO
	var t_delta := Vector3.ZERO
	for a in 3:
		if absf(dir[a]) < 1e-6:
			t_max[a] = INF
			t_delta[a] = INF
		else:
			var edge := float(c[a] + (1 if dir[a] > 0.0 else 0))
			t_max[a] = (edge - from[a]) / dir[a]
			t_delta[a] = absf(1.0 / dir[a])
	var t := 0.0
	while t <= reach:
		if c != cell_of(from):
			if voxels.has(c):
				return {"hit": c, "place": prev, "t": t}
			if c.y < 0 or (c.y < 30 and _cell(c.x, c.z)):
				return {"hit": null, "place": prev, "t": t}
		prev = c
		var a := 0
		if t_max.y < t_max[a]:
			a = 1
		if t_max.z < t_max[a]:
			a = 2
		t = t_max[a]
		t_max[a] += t_delta[a]
		c[a] += step[a]
	return {}


func has(name: String) -> bool:
	return models.has(name)


## 摆一个模型：底部贴地、中心在 pos、绕 Y 转 rot。返回节点（找不到模型返回 null）
func place(name: String, pos: Vector3, rot := 0.0, solid := true) -> Node3D:
	var info := _info(name)
	if info.is_empty():
		return null
	var e: Dictionary = models[name]
	var mi := MeshInstance3D.new()
	mi.mesh = info.mesh
	mi.transform = info.xf
	mi.material_override = _material(e.get("texture", ""))
	var holder := Node3D.new()
	holder.name = name
	holder.position = pos
	holder.rotation.y = rot
	holder.add_child(mi)
	add_child(holder)
	var size: Vector3 = info.size
	var kind: String = e.get("kind", "prop")
	# 远了就不画：小件 40 米、道具 70 米、车 110 米（手机上省大量三角面）
	mi.visibility_range_end = {"small": 40.0, "deco": 40.0, "car": 110.0}.get(kind, 70.0)
	mi.visibility_range_end_margin = 5.0
	if solid and kind in ["loot", "car", "prop"] and size.x * size.z > 0.08:
		_add_obstacle(Vector2(pos.x, pos.z), Vector2(size.x, size.z) * 0.5 * 0.9, rot, size.y > 2.5)
	if kind in ["loot", "car"]:
		containers.append({"node": holder, "pos": pos, "name": e.get("name", name), "loot": e.get("loot", "any"),
			"searched": false, "r": max(size.x, size.z) * 0.5, "kind": kind})
	return holder


func size_of(name: String) -> Vector3:
	var info := _info(name)
	return info.get("size", Vector3.ONE)


func _info(name: String) -> Dictionary:
	if _mesh_info.has(name):
		return _mesh_info[name]
	if not models.has(name):
		return {}
	var mesh = load("%s/%s" % [ROOT, models[name].mesh])
	if not (mesh is Mesh):
		_mesh_info[name] = {}
		return {}
	var a: AABB = mesh.get_aabb()
	# 有的模型单位是百米（导出时缩小了 100 倍）
	var s := 100.0 if max(a.size.x, max(a.size.y, a.size.z)) < 0.08 else 1.0
	# 有的模型 Z 朝上：底部不在 y=0 的就当 Z 朝上，转成 Y 朝上
	var basis := Basis.from_scale(Vector3.ONE * s)
	if absf(a.position.y) > 0.08 * a.size.y:
		basis = Basis(Vector3.RIGHT, -PI / 2) * basis
	var b := Transform3D(basis, Vector3.ZERO) * a
	var center := b.get_center()
	var xf := Transform3D(basis, Vector3(-center.x, -b.position.y, -center.z))
	var info := {"mesh": mesh, "xf": xf, "size": b.size}
	_mesh_info[name] = info
	return info


func _material(tex_path: String) -> Material:
	if _mat_cache.has(tex_path):
		return _mat_cache[tex_path]
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.85
	if tex_path != "":
		mat.albedo_texture = load("%s/%s" % [ROOT, tex_path])
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	else:
		mat.albedo_color = Color(0.5, 0.48, 0.45)
	_mat_cache[tex_path] = mat
	return mat


func _tex(name: String) -> Texture2D:
	if textures.has(name):
		return load("%s/%s" % [ROOT, textures[name]])
	return null


# —— 地面、街道 ——

func _flat(rect: Rect2, y: float, tex_name: String, tile: float, tint := Color.WHITE) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = rect.size
	mi.mesh = pm
	mi.position = Vector3(rect.get_center().x, y, rect.get_center().y)
	var key := "flat:%s:%s:%s" % [tex_name, rect.size, tint]
	if not _mat_cache.has(key) and terrain.has(tex_name):
		# 游戏的地形贴图：颜色 + 法线 + 粗糙度/AO，路面有凹凸感
		var t: Dictionary = terrain[tex_name]
		var m := ORMMaterial3D.new()
		m.albedo_color = tint
		m.albedo_texture = load("%s/%s" % [ROOT, t.albedo])
		m.normal_enabled = true
		m.normal_texture = load("%s/%s" % [ROOT, t.normal])
		m.orm_texture = load("%s/%s" % [ROOT, t.orm])
		m.uv1_scale = Vector3(rect.size.x / tile, rect.size.y / tile, 1)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_mat_cache[key] = m
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.roughness = 0.95
		m.albedo_color = tint
		var t := _tex(tex_name)
		if t:
			m.albedo_texture = t
			m.uv1_scale = Vector3(rect.size.x / tile, rect.size.y / tile, 1)
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_mat_cache[key] = m
	mi.material_override = _mat_cache[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_ground() -> void:
	var size := 420.0
	var tex := "gravel" if textures.has("gravel") else "rubble"
	_flat(Rect2(-size / 2, -size / 2, size, size), 0.0, tex, 6.0, Color(0.8, 0.78, 0.75))


func _intervals() -> Array:
	# 相邻两条路之间的街区范围（含人行道）
	var out := []
	for i in ROADS.size() - 1:
		out.append(Vector2(ROADS[i] + ROAD_W / 2, ROADS[i + 1] - ROAD_W / 2))
	return out


func _build_streets() -> void:
	var span := EDGE * 2 + 40.0
	_marks = SurfaceTool.new()
	_marks.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 横向的路整条铺，纵向的路在路口之间分段，避免重叠闪烁
	for r in ROADS:
		_flat(Rect2(-span / 2, r - ROAD_W / 2, span, ROAD_W), 0.012, "asphalt", 8.0)
	var iv := _intervals()
	for r in ROADS:
		for seg in iv:
			_flat(Rect2(r - ROAD_W / 2, seg.x, ROAD_W, seg.y - seg.x), 0.012, "asphalt", 8.0)
			_lane_marks(Vector2(r, seg.x), Vector2(r, seg.y))
	for r in ROADS:
		for seg in iv:
			_lane_marks(Vector2(seg.x, r), Vector2(seg.y, r))
	var mi := MeshInstance3D.new()
	mi.mesh = _marks.commit()
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.78, 0.68, 0.32)
	mm.roughness = 0.9
	mi.material_override = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# 路上的车：有的停着，有的撞歪了
	var cars := ["sedan_LOD1", "suv_LOD1", "policeCar_LOD1", "burntSedan_LOD0", "miniVan_LOD0",
		"pickUpTruck__LOD0", "frontCrumpledSedan_LOD0", "abandonedSUV_LOD0"]
	for r in ROADS.slice(1, ROADS.size() - 1):
		for seg in iv:
			for axis in 2:
				var n := rng.randi_range(1, 3)
				for k in n:
					var along := rng.randf_range(seg.x + 4, seg.y - 4)
					var lane := (2.6 if rng.randf() < 0.5 else -2.6) + rng.randf_range(-0.6, 0.6)
					var rot := (0.0 if rng.randf() < 0.5 else PI) + rng.randf_range(-0.25, 0.25)
					if rng.randf() < 0.25:
						rot += rng.randf_range(0.6, 1.4)
					var pos := Vector3(r + lane, 0, along) if axis == 0 else Vector3(along, 0, r + lane)
					if axis == 1:
						rot += PI / 2
					if not blocked(pos, 1.5):
						place(cars[rng.randi_range(0, cars.size() - 1)], pos, rot)
	# 公交车横在路口附近
	for i in 2:
		var r: float = ROADS[rng.randi_range(1, ROADS.size() - 2)]
		var p := Vector3(r + rng.randf_range(-2, 2), 0, ROADS[rng.randi_range(1, ROADS.size() - 2)] + rng.randf_range(10, 18))
		if not blocked(p, 3.0):
			place("bus_city_LOD0", p, rng.randf_range(-0.5, 0.5))
	# 路口的路障
	for x in ROADS.slice(1, ROADS.size() - 1):
		for z in ROADS.slice(1, ROADS.size() - 1):
			if rng.randf() < 0.45:
				var side := Vector3(rng.randf_range(-3, 3), 0, ROAD_W / 2 + 1.0)
				var rot := 0.0
				if rng.randf() < 0.5:
					side = Vector3(side.z, 0, side.x)
					rot = PI / 2
				var name := "barrierConcrete_LOD0" if rng.randf() < 0.6 else "barrierPlastic_LOD0"
				for k in 3:
					var off := Vector3(3.1 * (k - 1), 0, 0) if rot == 0.0 else Vector3(0, 0, 3.1 * (k - 1))
					var p := Vector3(x, 0, z) + side + off
					if not blocked(p, 0.5):
						place(name, p, rot + rng.randf_range(-0.1, 0.1))


func _lane_marks(a: Vector2, b: Vector2) -> void:
	# 黄色虚线，全部拼进一个网格里（几百段分开画太费手机）
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x) * 0.09
	var length := a.distance_to(b)
	var d := 2.0
	while d < length - 2.0:
		var p0 := a + dir * d
		var p1 := a + dir * minf(d + 2.4, length - 1.0)
		var q := [p0 - side, p1 - side, p1 + side, p0 + side]
		for i in [0, 1, 2, 0, 2, 3]:
			_marks.set_normal(Vector3.UP)
			_marks.add_vertex(Vector3(q[i].x, 0.022, q[i].y))
		d += 6.0


# —— 街区：每块放七日杀原版的楼 ——

func _build_blocks() -> void:
	var iv := _intervals()
	var n := iv.size()
	var mid := n / 2
	var big := BIG.filter(func(b): return not (b in CENTER) and pois.has(b))
	var mids := MID.filter(func(b): return pois.has(b))
	var smalls := SMALL.filter(func(b): return pois.has(b))
	_shuffle(big)
	_shuffle(mids)
	_shuffle(smalls)
	var center := CENTER.filter(func(b): return pois.has(b))
	# 外圈街区：大楼、中楼、四栋小楼轮流
	var plan := []
	for i in 12:
		plan.append(["big", "mid", "quad"][i % 3])
	_shuffle(plan)
	var k := 0
	for ix in n:
		for iz in n:
			var rect := Rect2(iv[ix].x, iv[iz].x, iv[ix].y - iv[ix].x, iv[iz].y - iv[iz].x)
			_flat(rect, 0.015, "sidewalk_terrain", 3.0)
			var lot := rect.grow(-WALK_W)
			_flat(lot, 0.02, "concrete", 4.0, Color(0.78, 0.78, 0.76))
			var c := lot.get_center()
			var inner: bool = (ix == mid - 1 or ix == mid) and (iz == mid - 1 or iz == mid)
			if inner and not center.is_empty():
				_poi(center.pop_front(), c)
				_lot_edges(lot, 60.0)
				continue
			var what: String = plan[k % plan.size()]
			k += 1
			if what == "big" and big.is_empty():
				what = "mid"
			if what == "mid" and mids.is_empty():
				what = "quad"
			match what:
				"big":
					_poi(big.pop_front(), c)
					_lot_edges(lot, 60.0)
				"mid":
					# 42 米的楼放在一角，剩下的地方是停车场
					var off := Vector2(9.0 * (1 if rng.randf() < 0.5 else -1), 9.0 * (1 if rng.randf() < 0.5 else -1))
					_poi(mids.pop_front(), c + off)
					_parking(lot, Rect2(c + off - Vector2(21, 21), Vector2(42, 42)))
				_:
					for q in 4:
						if smalls.is_empty():
							smalls = SMALL.filter(func(b): return pois.has(b))
							_shuffle(smalls)
						if smalls.is_empty():
							break
						var qo := Vector2(17.5 if q % 2 == 0 else -17.5, 17.5 if q < 2 else -17.5)
						_poi(smalls.pop_front(), c + qo)
					_alleys(lot)


## 放一栋楼：随机转 0/90/180/270 度，并把占地图盖到城市占地图上
func _poi(name: String, c: Vector2) -> void:
	var info: Dictionary = pois.get(name, {})
	var mesh = load("%s/poi/%s.res" % [ROOT, name])
	if info.is_empty() or not (mesh is Mesh):
		return
	var turns := rng.randi_range(0, 3)
	var rot := turns * PI / 2
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _poi_material()
	mi.position = Vector3(c.x, -float(info.ground) + 0.03, c.y)
	mi.rotation.y = rot
	mi.visibility_range_end = 260.0
	add_child(mi)
	buildings.append({"name": name, "pos": Vector3(c.x, 0, c.y)})
	var w: int = info.grid_w
	var h: int = info.grid_h
	var g: String = info.grid
	var o: Array = info.grid_origin
	var cs := cos(rot)
	var sn := sin(rot)
	for z in h:
		for x in w:
			if g.unicode_at(z * w + x) != 49:   # "1"
				continue
			var lx: float = o[0] + x + 0.5
			var lz: float = o[1] + z + 0.5
			# 绕 Y 轴转：x' = x cos + z sin，z' = -x sin + z cos
			var wx := c.x + lx * cs + lz * sn
			var wz := c.y - lx * sn + lz * cs
			var gx := floori(wx) + MAP
			var gz := floori(wz) + MAP
			if gx >= 0 and gz >= 0 and gx < MAP * 2 and gz < MAP * 2:
				_cells[gz * MAP * 2 + gx] = 1


func _poi_material() -> ShaderMaterial:
	if _poi_mat == null:
		_poi_mat = Blocks.material()
	return _poi_mat


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


## 大楼四周的人行道边上：垃圾桶、邮箱、售货机、包
func _lot_edges(lot: Rect2, _size: float) -> void:
	var items := ["bruteStyleTrashCanFull_1", "domedTrashCanFull_1", "fancyGarbageCan_1", "trashBinCommercial_LOD0",
		"mailBox_01_LOD0", "mailBox_03_LOD0", "vendingMachinePlayer_LOD0", "trashPileE_LOD0", "backPack_LOD0",
		"duffle_LOD0", "sportsBag_LOD0", "purse_LOD0", "chairFoldingMetalFoldedFallen_LOD0", "trashGround03_LOD0",
		"Dumpster_LOD0", "trashPileA_1"]
	for k in rng.randi_range(5, 9):
		var side := rng.randi_range(0, 3)
		var t := rng.randf_range(2.0, lot.size.x - 2.0)
		var p := Vector2()
		var rot := 0.0
		match side:
			0:
				p = Vector2(lot.position.x + t, lot.position.y - 1.4)
			1:
				p = Vector2(lot.position.x + t, lot.end.y + 1.4)
				rot = PI
			2:
				p = Vector2(lot.position.x - 1.4, lot.position.y + t)
				rot = PI / 2
			3:
				p = Vector2(lot.end.x + 1.4, lot.position.y + t)
				rot = -PI / 2
		var pos := Vector3(p.x, 0, p.y)
		var name: String = items[rng.randi_range(0, items.size() - 1)]
		if models.has(name) and not blocked(pos, 0.5):
			place(name, pos, rot + rng.randf_range(-0.3, 0.3))


## 四栋小楼中间的十字小巷：大垃圾箱、垃圾堆、木托盘
func _alleys(lot: Rect2) -> void:
	var c := lot.get_center()
	var items := ["Dumpster_LOD0", "trashPileA_1", "trashPileC_1", "trashPileE_LOD0", "palletsWoodStack",
		"boxesCardboardPallet_LOD0", "trashGround02_LOD0", "plasticBin_LOD0", "cardboardRecycledPallet_LOD0",
		"bruteStyleTrashCanFull_1", "tiltTruckFull_1", "shippingCrate_LOD0", "couchUglySmall_LOD0"]
	for k in rng.randi_range(6, 10):
		var along := rng.randf_range(-lot.size.x / 2 + 2, lot.size.x / 2 - 2)
		var across := rng.randf_range(-2.5, 2.5)
		var p := Vector3(c.x + along, 0, c.y + across) if k % 2 == 0 else Vector3(c.x + across, 0, c.y + along)
		var rot := 0.0 if k % 2 == 0 else PI / 2
		if not blocked(p, 0.5):
			place(items[rng.randi_range(0, items.size() - 1)], p, rot + rng.randf_range(-0.3, 0.3))
	_lot_edges(lot, 60.0)


## 中楼旁边的空地：停着车，有的地方是加油站或幸存者营地
func _parking(lot: Rect2, building: Rect2) -> void:
	var cars := ["sedan_LOD1", "suv_LOD1", "miniVan_LOD0", "pickUpTruck__LOD0", "burntSedan_LOD0", "abandonedSUV_LOD0",
		"frontCrumpledSedan_LOD0", "policeCar_LOD1"]
	var r := rng.randf()
	var tries := 0
	var placed := 0
	var want := rng.randi_range(5, 9)
	while placed < want and tries < 60:
		tries += 1
		var p := Vector3(rng.randf_range(lot.position.x + 2.5, lot.end.x - 2.5), 0, rng.randf_range(lot.position.y + 2.5, lot.end.y - 2.5))
		if building.grow(2.5).has_point(Vector2(p.x, p.z)) or blocked(p, 2.6):
			continue
		place(cars[rng.randi_range(0, cars.size() - 1)], p, (0.0 if rng.randf() < 0.5 else PI / 2) + rng.randf_range(-0.2, 0.2))
		placed += 1
	var extras := ["gasPumpFull_LOD0", "gasPumpFull_LOD0"] if r < 0.3 else (
		["campingTentAngularDamaged_LOD0", "palletBagSandBaseFull_LOD0", "palletBagSandBaseFull_LOD0", "superChest_1",
		"weaponBag_sm_1", "gasGrillFull_1", "corpseHangingLog1_LOD0", "umbrellaTableDown_LOD0", "waterCoolerFull_1"]
		if r < 0.6 else ["shippingCrate_LOD0", "utilityCartFull_1", "janitorCart_1", "handTruck_1", "groceryCartFull_LOD0",
		"tier1LootChest_LOD0", "foodClutterPileMedium_01_LOD0", "brickStack_LOD0", "plywoodStack_LOD0"])
	for name in extras:
		for t in 15:
			var p := Vector3(rng.randf_range(lot.position.x + 1.5, lot.end.x - 1.5), 0, rng.randf_range(lot.position.y + 1.5, lot.end.y - 1.5))
			if building.grow(1.0).has_point(Vector2(p.x, p.z)) or blocked(p, 1.0):
				continue
			place(name, p, rng.randf() * TAU)
			break
	_lot_edges(lot, 60.0)


# —— 边界：最外圈的路上一排水泥路障 ——

func _build_border() -> void:
	for side in 4:
		var t := -EDGE
		while t <= EDGE:
			var p := Vector3(t, 0, EDGE + 0.8)
			var rot := 0.0
			match side:
				1:
					p = Vector3(t, 0, -EDGE - 0.8)
				2:
					p = Vector3(EDGE + 0.8, 0, t)
					rot = PI / 2
				3:
					p = Vector3(-EDGE - 0.8, 0, t)
					rot = PI / 2
			var on_road := false
			for r in ROADS:
				if absf(t - r) < ROAD_W / 2:
					on_road = true
			if on_road and rng.randf() < 0.5:
				place("burntSedan_LOD0", p, rot + PI / 2 + rng.randf_range(-0.2, 0.2), false)
				t += 5.0
				continue
			place("barrierConcrete_LOD0", p, rot + rng.randf_range(-0.05, 0.05), false)
			t += 3.0


func _scatter_decals() -> void:
	if decals.is_empty():
		return
	var mats := []
	for d in decals:
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("%s/%s" % [ROOT, d])
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 1.0
		mats.append(m)
	for i in 220:
		var p := Vector3(rng.randf_range(-EDGE, EDGE), 0.03 + (i % 5) * 0.001, rng.randf_range(-EDGE, EDGE))
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		var s := rng.randf_range(0.8, 2.6)
		pm.size = Vector2(s, s)
		mi.mesh = pm
		mi.position = p
		mi.rotation.y = rng.randf() * TAU
		mi.material_override = mats[rng.randi_range(0, mats.size() - 1)]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 60.0
		add_child(mi)


# —— 车和杂物的碰撞 ——

func _add_obstacle(c: Vector2, h: Vector2, rot: float, tall := false) -> void:
	obstacles.append({"c": c, "h": h, "rot": rot, "r": h.length(), "tall": tall})


func _rebuild_grid() -> void:
	_grid.clear()
	for i in obstacles.size():
		var o: Dictionary = obstacles[i]
		var r: float = o.r + 1.0
		for gx in range(floori((o.c.x - r) / GRID), floori((o.c.x + r) / GRID) + 1):
			for gz in range(floori((o.c.y - r) / GRID), floori((o.c.y + r) / GRID) + 1):
				var k := Vector2i(gx, gz)
				if not _grid.has(k):
					_grid[k] = PackedInt32Array()
				_grid[k].append(i)


func _nearby(q: Vector2) -> PackedInt32Array:
	if _grid.is_empty():
		# 搭建过程中网格还没建，直接全查
		var all := PackedInt32Array()
		for i in obstacles.size():
			all.append(i)
		return all
	return _grid.get(Vector2i(floori(q.x / GRID), floori(q.y / GRID)), PackedInt32Array())
