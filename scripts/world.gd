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
## 挡路的车和杂物：{c: 中心 Vector2(x,z), h: 半长宽, rot: 朝向, r: 外接圆半径, y: 高度}
var obstacles: Array[Dictionary] = []
## 能翻找的：{node, pos, name, loot, searched, r, kind}
var containers: Array[Dictionary] = []
## 放了哪些楼：[{name, pos}]
var buildings: Array[Dictionary] = []
var models := {}
var textures := {}
var decals: PackedStringArray = []
var pois := {}
var ready_ok := false

var _mesh_info := {}    # 模型名 -> {mesh, xf, size}
var _mat_cache := {}
var _marks: SurfaceTool
var _poi_mat: ShaderMaterial
var _cells := PackedByteArray()   # 楼的占地图，(MAP*2)² 格，1 = 挡路
var _grid := {}         # 粗网格加速查询：格子 -> 障碍物下标
const GRID := 8.0
## 寻路：1 米一格，1 = 走不过去（楼、车、高的杂物）
var _nav := PackedByteArray()
## 以玩家为中心的一块区域里，每格走到玩家要几步（-1 = 走不到或没算）
var _flow := PackedInt32Array()
var _flow_min := Vector2i.ZERO
var _flow_size := 0
var _queue := PackedInt32Array()


func _ready() -> void:
	_cells.resize(MAP * 2 * MAP * 2)
	if FileAccess.file_exists(POI_INDEX):
		var p = JSON.parse_string(FileAccess.get_file_as_string(POI_INDEX))
		if p is Dictionary:
			pois = p
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
	_build_nav()


## 把一个圆（玩家、僵尸）推出楼和障碍物。feet：脚离地多高，比脚低的杂物不挡（跳上去、跳过去）
func push_out(p: Vector3, radius: float, feet := 0.0) -> Vector3:
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
	for i in _nearby(q):
		var o: Dictionary = obstacles[i]
		var d: Vector2 = q - o.c
		if d.length() > o.r + radius or o.y <= feet + 0.05:
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
			if _cell(gx, gz):
				return true
	for i in _nearby(q):
		var o: Dictionary = obstacles[i]
		var local: Vector2 = (q - o.c).rotated(o.rot)
		if absf(local.x) < o.h.x + radius and absf(local.y) < o.h.y + radius:
			return true
	return false


## 这里能站多高：矮杂物（路障、垃圾桶）的顶上。feet 是现在脚的高度，高过脚的东西爬不上去
func ground_at(p: Vector3, radius: float, feet: float) -> float:
	var q := Vector2(p.x, p.z)
	var top := 0.0
	for i in _nearby(q):
		var o: Dictionary = obstacles[i]
		if o.y > GameConfig.STEP_MAX or o.y > feet + 0.05 or o.y <= top:
			continue
		var local: Vector2 = (q - o.c).rotated(o.rot)
		if absf(local.x) < o.h.x + radius * 0.5 and absf(local.y) < o.h.y + radius * 0.5:
			top = o.y
	return top


## 两点之间有没有被楼挡住（子弹、视线用）
func line_blocked(a: Vector3, b: Vector3) -> bool:
	return block_t(a, b) < 1.0


## 从 a 到 b 第一次撞到楼的位置（0~1），没撞到返回 1。楼的占地图只有平面，按楼高 60 米算
func block_t(a: Vector3, b: Vector3) -> float:
	var steps := int(a.distance_to(b) / 0.4)
	for s in range(1, steps):
		var t := float(s) / steps
		var p := a.lerp(b, t)
		if p.y < 60.0 and _cell(floori(p.x), floori(p.z)):
			return t
	return 1.0


## 地上的血迹贴花（没有就返回空字符串）
func blood_decal() -> String:
	var list := []
	for d in decals:
		if d.to_lower().contains("blood"):
			list.append(d)
	return "%s/%s" % [ROOT, list.pick_random()] if not list.is_empty() else ""


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


## 有没有方块贴图（以后上传了 blocktextureatlases 就换上）
func set_block_atlas(atlas: Texture2DArray) -> void:
	if _poi_mat and atlas:
		_poi_mat.set_shader_parameter("atlas", atlas)
		_poi_mat.set_shader_parameter("use_atlas", true)


func _cell(gx: int, gz: int) -> bool:
	var x := gx + MAP
	var z := gz + MAP
	if x < 0 or z < 0 or x >= MAP * 2 or z >= MAP * 2:
		return false
	return _cells[z * MAP * 2 + x] == 1


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
	if solid and kind in ["loot", "car", "prop"] and size.x * size.z > 0.08:
		_add_obstacle(Vector2(pos.x, pos.z), Vector2(size.x, size.z) * 0.5 * 0.9, rot, size.y)
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
		_poi_mat = ShaderMaterial.new()
		_poi_mat.shader = POI_SHADER
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

func _add_obstacle(c: Vector2, h: Vector2, rot: float, height: float) -> void:
	obstacles.append({"c": c, "h": h, "rot": rot, "r": h.length(), "tall": height > 2.5, "y": height})


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


# —— 寻路：僵尸绕着楼和车走 ——
# 整张图 1 米一格。每隔一会儿从玩家所在的格子往外做一次广度优先搜索（只算玩家周围一块），
# 每个僵尸看自己脚下这格周围哪格离玩家更近，就往那格走。

func _build_nav() -> void:
	var n := MAP * 2
	_nav = _cells.duplicate()
	# 车和杂物：格子中心落在障碍物里（往外放宽一点）就算挡路
	for o in obstacles:
		if o.y < 0.5:
			continue   # 很矮的垃圾、贴花之类不挡僵尸
		var r: float = o.r + 0.3
		for gz in range(floori(o.c.y - r), floori(o.c.y + r) + 1):
			for gx in range(floori(o.c.x - r), floori(o.c.x + r) + 1):
				var local: Vector2 = (Vector2(gx + 0.5, gz + 0.5) - o.c).rotated(o.rot)
				if absf(local.x) < o.h.x + 0.2 and absf(local.y) < o.h.y + 0.2:
					var x := gx + MAP
					var z := gz + MAP
					if x >= 0 and z >= 0 and x < n and z < n:
						_nav[z * n + x] = 1
	_flow_size = GameConfig.NAV_RADIUS * 2 + 1
	_flow.resize(_flow_size * _flow_size)
	_flow.fill(-1)
	_queue.resize(_flow_size * _flow_size)


func _nav_free(gx: int, gz: int) -> bool:
	if absf(gx + 0.5) > EDGE or absf(gz + 0.5) > EDGE:
		return false
	var x := gx + MAP
	var z := gz + MAP
	if x < 0 or z < 0 or x >= MAP * 2 or z >= MAP * 2:
		return false
	return _nav[z * MAP * 2 + x] == 0


## 从 target 往外算每格到 target 的步数
func update_flow(target: Vector3) -> void:
	if _flow_size == 0:
		return
	var s := _flow_size
	var tx := floori(target.x)
	var tz := floori(target.z)
	_flow_min = Vector2i(tx - GameConfig.NAV_RADIUS, tz - GameConfig.NAV_RADIUS)
	_flow.fill(-1)
	var n := MAP * 2
	var head := 0
	var tail := 0
	var start := GameConfig.NAV_RADIUS * s + GameConfig.NAV_RADIUS
	_flow[start] = 0
	_queue[tail] = start
	tail += 1
	var nav := _nav
	var flow := _flow
	var q := _queue
	var ox := _flow_min.x + MAP
	var oz := _flow_min.y + MAP
	while head < tail:
		var cur := q[head]
		head += 1
		var cx := cur % s
		var cz := cur / s
		var d := flow[cur] + 1
		for k in 4:
			var nx := cx + (1 if k == 0 else (-1 if k == 1 else 0))
			var nz := cz + (1 if k == 2 else (-1 if k == 3 else 0))
			if nx < 0 or nz < 0 or nx >= s or nz >= s:
				continue
			var ni := nz * s + nx
			if flow[ni] != -1:
				continue
			var wx := nx + ox
			var wz := nz + oz
			if wx < 0 or wz < 0 or wx >= n or wz >= n or nav[wz * n + wx] != 0:
				continue
			flow[ni] = d
			q[tail] = ni
			tail += 1
	_flow = flow


func _flow_at(gx: int, gz: int) -> int:
	var x := gx - _flow_min.x
	var z := gz - _flow_min.y
	if x < 0 or z < 0 or x >= _flow_size or z >= _flow_size:
		return -1
	return _flow[z * _flow_size + x]


## 僵尸该往哪走才能绕过楼走到玩家身边。返回 ZERO 表示不知道（太远或被围住了），直接朝玩家走
func flow_dir(p: Vector3) -> Vector3:
	if _flow_size == 0:
		return Vector3.ZERO
	var gx := floori(p.x)
	var gz := floori(p.z)
	var here := _flow_at(gx, gz)
	if here == -1:
		# 被推到挡路的格子里了：找周围最近能走的格子
		var best := Vector2i(999999, 0)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var f := _flow_at(gx + dx, gz + dz)
				if f >= 0 and f < best.x:
					best = Vector2i(f, dz * 3 + dx)
		if best.x == 999999:
			return Vector3.ZERO
		here = best.x + 1
	var best_d := float(here)
	var best_dir := Vector3.ZERO
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var f := _flow_at(gx + dx, gz + dz)
			if f < 0:
				continue
			# 斜着走不能切墙角
			if dx != 0 and dz != 0 and (_flow_at(gx + dx, gz) < 0 or _flow_at(gx, gz + dz) < 0):
				continue
			var score := f + (0.4 if dx != 0 and dz != 0 else 0.0)
			if score < best_d:
				best_d = score
				best_dir = Vector3(gx + dx + 0.5 - p.x, 0, gz + dz + 0.5 - p.z)
	if best_dir == Vector3.ZERO:
		return Vector3.ZERO
	return best_dir.normalized()


## 地面上两点之间直线能不能走过去（中间没有楼、车）
func walkable_line(a: Vector3, b: Vector3) -> bool:
	var steps := int(Vector2(a.x - b.x, a.z - b.z).length() / 0.7) + 1
	for s in range(1, steps):
		var p := a.lerp(b, float(s) / steps)
		if not _nav_free(floori(p.x), floori(p.z)):
			return false
	return true
