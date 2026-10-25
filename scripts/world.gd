class_name World
extends Node3D
## 市中心：十字街道、人行道、七日杀原版的市中心建筑（POI）、街上的车和杂物、能翻找的容器。
## 楼来自 assets/poi/（tools/build_poi.gd 从游戏的远景网格转出来），
## 车和杂物来自 assets/index/world_models.json（tools/fetch_assets.py 从云盘取）。
## 碰撞：楼用 1 米一格的占地图，车和杂物用矩形。玩家和僵尸撞到就被推开、沿墙滑动。

const ROOT := "res://assets"
const INDEX := "res://assets/index/world_models.json"
const POI_INDEX := "res://assets/poi/index.json"
## 楼里的容器方块（tools/build_poi_full.py 输出）：{楼名: {ground, list: [{block, loot, x, y, z, rot}]}}
const POI_CONTAINERS := "res://assets/poi/containers.json"
## 楼里家具、灯、柜子、门的模型（tools/fetch_assets.py 的 fetch_poi_props 输出）：
## {models: {预制体: {mesh, door}}, rot: [方块转向 → Basis 的 9 个数，按列]}。网格由 tools/build_props.gd
## 从预制体的 glb 合成，原点在方块中心，材质（底色贴图）在网格里
const POI_PROPS := "res://assets/poi/props.json"
const POI_SHADER := preload("res://scripts/poi.gdshader")
const TERRAIN_INDEX := "res://assets/terrain/terrain.json"
## 多远以内显示完整的楼（再远用简化的远景网格，省手机性能）
const FULL_DETAIL_RANGE := 80.0
## 走到楼边这个距离以内才画完整版；远处只画远景网格（楼里一屏几十万面，站远了不值得）
const FULL_VISIBLE_RANGE := 40.0
## 远景网格在这个距离外换成更粗的 _lod1，再远换 _lod2（三角面各减半）
const FAR_LOD_DIST := 60.0
const FAR_LOD2_DIST := 120.0
## 完整版至少要有远景网格这么多比例的顶点才用（否则当成没转好）
const FULL_MIN_SHARE := 0.25
## 完整版的楼走近才加载、走远就释放（67 栋全放内存手机吃不消）。距离从楼的外接圆边上算
const FULL_LOAD_RANGE := FULL_DETAIL_RANGE + 30.0
const FULL_FREE_RANGE := FULL_DETAIL_RANGE + 70.0
## 楼里的家具按大小分层：小件 30 米、中件 60 米、大件 85 米（按 16×8×16 米一块分组）
const PROP_SMALL_RANGE := 22.0
const PROP_MED_RANGE := 28.0
const PROP_BIG_RANGE := 34.0
const PROP_CHUNK := 16.0
const PROP_CHUNK_H := 8.0

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
## 可采集的街边物件：合批的藏 MultiMesh 实例，车藏独立节点；血量到 0 后 5 天重生
var props: Array[Dictionary] = []
## 合批节点："模型|格x|格z" -> {mmi, center}
var _batch_nodes := {}
## 远景网格的第二级 LOD 节点（画质切换时改可见距离）
var _poi_lods: Array[Dictionary] = []
## 放了哪些楼：[{name, pos}]
var buildings: Array[Dictionary] = []
var models := {}
var textures := {}
var decals: PackedStringArray = []
var pois := {}
var poi_containers := {}
var poi_props := {}
var _prop_rot: Array[Basis] = []
var _prop_cache := {}   # 预制体 -> {mesh, mat}，没有模型的是 {}
## 地面贴图（游戏的地形贴图数组）：名字 -> {albedo, normal, orm, tile}
var terrain := {}
var ready_ok := false

var _mesh_info := {}    # 模型名 -> {mesh, xf, size}
var _mat_cache := {}
var _marks: SurfaceTool
var _poi_mat: ShaderMaterial
var _cells := PackedByteArray()   # 楼的占地图，(MAP*2)² 格，1 = 挡路
## 能走进去的楼（有 .col 碰撞格子的完整重建楼）。这些楼不盖 _cells，玩家按方块碰撞走
var interiors: Array[PoiInterior] = []
var _iwall := PackedByteArray()   # 能进的楼在街面那层哪些格子是墙（僵尸寻路、刷怪用），1 = 挡路
var _door_nodes := {}             # 楼序号 -> {wood: MultiMeshInstance3D, metal: …, slots: [[材质, 下标]]}
var _grid := {}         # 粗网格加速查询：格子 -> 障碍物下标
const GRID := 8.0
## 合批：不能交互的重复道具按「模型 + 街区格」攒起来，最后每组一个 MultiMesh
const BATCH_CELL := 38.0
var _batching := false
var _batch := {}        # "模型|格x|格z" -> {name, cell, xfs: [Transform3D]}
## 自己摆的方块按 32 米一块、每种方块一个 MultiMesh
const VOXEL_CHUNK := 16
var _vox_chunks := {}   # Vector3i -> {mi, cells: {格子: true}}
var _vox_dirty := {}
var _vox_flush_queued := false
var _station_nodes := {}  # 工作站格子 -> MeshInstance3D（用模型，不进区块网格）

## 画质档位（0 省电 / 1 均衡 / 2 高清）
var quality := 1
## 按距离调整可见距离和投影的实例
var _prop_lod: Array[Dictionary] = []
var _poi_lod: Array[Dictionary] = []
## 有完整版的楼：{name, pos, far, parts, props, path, state, radius}。state 0 没加载 1 加载中 2 显示中 3 加载失败
var _full_pois: Array[Dictionary] = []
var _decal_lod: Array[Dictionary] = []
## 地面/人行道/马路按贴图合批，减少 draw call
var _flat_groups := {}
var _flat_mats := {}


func _ready() -> void:
	_cells.resize(MAP * 2 * MAP * 2)
	_iwall.resize(MAP * 2 * MAP * 2)
	if FileAccess.file_exists(POI_INDEX):
		var p = JSON.parse_string(FileAccess.get_file_as_string(POI_INDEX))
		if p is Dictionary:
			pois = p
	if FileAccess.file_exists(POI_CONTAINERS):
		var pc = JSON.parse_string(FileAccess.get_file_as_string(POI_CONTAINERS))
		if pc is Dictionary:
			poi_containers = pc
	if FileAccess.file_exists(POI_PROPS):
		var pp = JSON.parse_string(FileAccess.get_file_as_string(POI_PROPS))
		if pp is Dictionary:
			poi_props = pp.get("models", {})
			for r in pp.get("rot", []):
				_prop_rot.append(Basis(Vector3(r[0], r[1], r[2]), Vector3(r[3], r[4], r[5]), Vector3(r[6], r[7], r[8])))
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
	# 用 /root 查单例：-s 脚本模式没有自动加载时也能编译运行
	var gs := _game_state()
	if gs and not gs.day_started.is_connected(_on_day_started):
		gs.day_started.connect(_on_day_started)
	rng.seed = seed_value
	_flat_groups.clear()
	_batch.clear()
	_batching = true
	_build_ground()
	_build_blocks()
	_build_streets()
	_build_border()
	_scatter_decals()
	_flush_flats()
	_batching = false
	_flush_batches()
	_rebuild_grid()


## 切换画质：只改可见距离，已经建好的模型不重建
func apply_quality(level: int, preset: Dictionary) -> void:
	quality = clampi(level, 0, GameConfig.QUALITY_PRESETS.size() - 1)
	for e in _prop_lod:
		if not is_instance_valid(e.node):
			continue
		var mi: GeometryInstance3D = e.node
		mi.visibility_range_end = _range_for_kind(e.kind, preset) + e.get("pad", 0.0)
		mi.visibility_range_end_margin = 5.0
	for e in _poi_lod:
		if e.get("shadow_only", false):
			continue
		var mi: MeshInstance3D = e.node
		mi.visibility_range_end = FAR_LOD_DIST if mi.has_meta("lod_split") else preset.poi_range
	for e in _full_pois:
		if e.has("far") and is_instance_valid(e.far):
			e.far.visibility_range_end = FAR_LOD_DIST if e.far.has_meta("lod_split") else preset.poi_range
	for e in _poi_lods:
		if is_instance_valid(e.node):
			e.node.visibility_range_end = FAR_LOD2_DIST if int(e.level) == 1 else preset.poi_range
	for e in _decal_lod:
		var mi: GeometryInstance3D = e.node
		mi.visibility_range_end = preset.decal_range + e.get("pad", 0.0)


## 性能面板的一行：最近一栋完整版的楼、离多远、完整网格有几块在可见距离内。
## 走近楼时三角面数应该跳一大截；没跳说明完整网格没画出来。
func full_debug(player_pos: Vector3) -> String:
	var best := {}
	var bd := INF
	var p := Vector2(player_pos.x, player_pos.z)
	for e in _full_pois:
		var d := p.distance_to(e.pos)
		if d < bd:
			bd = d
			best = e
	if best.is_empty():
		return "没有完整版的楼"
	if best.state != 2:
		return "%s %dm 完整版%s" % [best.name, int(bd), ["没加载", "加载中", "", "加载失败"][best.state]]
	var on := 0
	var tris := 0
	for fi in best.parts:
		var mi: MeshInstance3D = fi
		var c: Vector3 = mi.global_transform * mi.get_aabb().get_center()
		if player_pos.distance_to(c) < mi.visibility_range_end:
			on += 1
			for i in mi.mesh.get_surface_count():
				tris += mi.mesh.surface_get_array_index_len(i) / 3
	return "%s %dm 完整 %d/%d块 %dk面" % [best.name, int(bd), on, best.parts.size(), tris / 1000]


## 按玩家位置加载/释放完整版的楼和楼里的家具（后台线程读文件，读完下一次再摆上）
func update_detail(player_pos: Vector3) -> void:
	var p := Vector2(player_pos.x, player_pos.z)
	for e in _full_pois:
		var d := maxf(0.0, p.distance_to(e.pos) - float(e.radius))
		match int(e.state):
			0:
				if d < FULL_LOAD_RANGE:
					e["pending"] = _full_request(e)
					e.state = 1
			1:
				var done := true
				for path in e.pending:
					var st := ResourceLoader.load_threaded_get_status(path)
					if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
						done = false
				if not done:
					continue
				var full = ResourceLoader.load_threaded_get(e.path) \
					if ResourceLoader.load_threaded_get_status(e.path) == ResourceLoader.THREAD_LOAD_LOADED else null
				if full == null or not ("meshes" in full):
					push_warning("%s 的完整版读不出来" % e.name)
					e.state = 3
					continue
				for path in e.pending:
					if path != e.path and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
						ResourceLoader.load_threaded_get(path)   # 进缓存，_prop_model 里 load 直接拿到
				_show_full(e, full)
				e.state = 2
			2:
				if d > FULL_FREE_RANGE:
					_hide_full(e)
					e.state = 0


## 发出后台读取：完整网格 + 这栋楼用到、还没读过的家具模型
func _full_request(e: Dictionary) -> Array:
	var paths := [e.path]
	ResourceLoader.load_threaded_request(e.path)
	var entry = poi_containers.get(e.name)
	if entry is Dictionary:
		for key in entry.get("props", {}).get("models", []):
			var info: Dictionary = poi_props.get(key, {})
			if info.has("mesh") and not _prop_cache.has(key):
				var mp := "%s/%s" % [ROOT, info.mesh]
				if not paths.has(mp) and ResourceLoader.exists(mp):
					ResourceLoader.load_threaded_request(mp)
					paths.append(mp)
	return paths


func _show_full(e: Dictionary, full: Resource) -> void:
	var mi: MeshInstance3D = e.far
	for m in full.meshes:
		var fi := MeshInstance3D.new()
		fi.mesh = m
		# 只有方块面的网格整个用 POI 着色器，和远景网格一样用 material_override
		var all_blocks: bool = m.get_surface_count() > 0
		for i in m.get_surface_count():
			if not m.surface_get_name(i).begins_with("blocks"):
				all_blocks = false
		if all_blocks:
			fi.material_override = _poi_material()
		else:
			for i in m.get_surface_count():
				if m.surface_get_name(i).begins_with("blocks"):
					fi.set_surface_override_material(i, _poi_material())
		fi.position = mi.position
		fi.rotation.y = e.rot
		fi.visibility_range_end = FULL_VISIBLE_RANGE
		fi.visibility_range_end_margin = 5.0
		# 影子用简化网格投（便宜得多），完整网格只负责看
		fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fi.set_meta("poi_full_part", true)
		add_child(fi)
		e.parts.append(fi)
	e.props = _build_full_props(e)
	mi.visibility_range_begin = FULL_VISIBLE_RANGE + 2.0
	mi.visibility_range_begin_margin = 5.0
	if e.get("far_lod1"):
		e.far_lod1.visibility_range_begin = FULL_VISIBLE_RANGE + 2.0


func _hide_full(e: Dictionary) -> void:
	for fi in e.parts:
		(fi as Node).queue_free()
	e.parts.clear()
	if e.props != null:
		(e.props as Node).queue_free()
		e.props = null
	var mi: MeshInstance3D = e.far
	mi.visibility_range_begin = 0.0
	mi.visibility_range_begin_margin = 0.0
	if e.get("far_lod1"):
		e.far_lod1.visibility_range_begin = FAR_LOD_DIST


## 实体模型（家具、灯、柜子、门）：{mesh}，没有模型返回 {}
func _prop_model(key: String) -> Dictionary:
	if _prop_cache.has(key):
		return _prop_cache[key]
	var out := {}
	var info: Dictionary = poi_props.get(key, {})
	if info.has("mesh") and ResourceLoader.exists("%s/%s" % [ROOT, info.mesh]):
		var mesh = load("%s/%s" % [ROOT, info.mesh])
		if mesh is Mesh:
			out = {"mesh": mesh}
	_prop_cache[key] = out
	return out


func _prop_basis(r: int) -> Basis:
	return _prop_rot[r] if r >= 0 and r < _prop_rot.size() else Basis.IDENTITY


## 楼里的家具：同一块（16×8×16 米）里同一种模型合成一个 MultiMesh。挂在和楼网格同变换的节点下
func _build_full_props(e: Dictionary) -> Node3D:
	var entry = poi_containers.get(e.name)
	if not (entry is Dictionary):
		return null
	var pr: Dictionary = entry.get("props", {})
	var names: Array = pr.get("models", [])
	var groups := {}
	for item in pr.get("items", []):
		var mi_: int = int(item[0])
		if mi_ < 0 or mi_ >= names.size() or _prop_model(names[mi_]).is_empty():
			continue
		# 方块数据是游戏的左手坐标，楼网格翻了 x，这里也翻；y 是方块底面，模型原点在方块中心
		var pos := Vector3(-float(item[1]), float(item[2]) + 0.5, float(item[3]))
		# 同一栋楼里同一种家具合成一个 MultiMesh（按模型合并，减少绘制次数）
		var gk := "%d" % mi_
		if not groups.has(gk):
			groups[gk] = {"key": names[mi_], "xfs": [], "sum": Vector3.ZERO}
		groups[gk].xfs.append(Transform3D(_prop_basis(int(item[4])), pos))
		groups[gk].sum += pos
	if groups.is_empty():
		return null
	var far: MeshInstance3D = e.far
	var holder := Node3D.new()
	holder.name = "Props_" + str(e.name)
	holder.position = far.position
	holder.rotation.y = e.rot
	for g in groups.values():
		var pm := _prop_model(g.key)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pm.mesh
		mm.instance_count = g.xfs.size()
		# 节点放在这组家具的中心，visibility_range 按中心算距离
		var center: Vector3 = g.sum / maxf(1.0, float(g.xfs.size()))
		for k in g.xfs.size():
			var xf: Transform3D = g.xfs[k]
			xf.origin -= center
			mm.set_instance_transform(k, xf)
		var aabb: AABB = pm.mesh.get_aabb()
		var size := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		var view := PROP_SMALL_RANGE if size < 0.7 else (PROP_MED_RANGE if size < 1.6 else PROP_BIG_RANGE)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = center
		mmi.visibility_range_end = view
		mmi.visibility_range_end_margin = 5.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mmi)
	add_child(holder)
	return holder


## 按玩家位置开关近处楼和道具的投影。远处不投影，手机阴影贴图只画身边。
func update_shadows(player_pos: Vector3, level: int) -> void:
	var preset: Dictionary = GameConfig.QUALITY_PRESETS[clampi(level, 0, GameConfig.QUALITY_PRESETS.size() - 1)]
	var p := Vector2(player_pos.x, player_pos.z)
	var poi_d: float = preset.poi_shadow_distance
	for e in _poi_lod:
		if not is_instance_valid(e.node):
			continue
		var mi: MeshInstance3D = e.node
		var on: bool = poi_d > 0.0 and p.distance_to(e.pos) <= poi_d
		var cast_on: GeometryInstance3D.ShadowCastingSetting = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if e.get("shadow_only", false) \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.cast_shadow = cast_on if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var prop_d: float = preset.prop_shadow_distance
	for e in _prop_lod:
		if not is_instance_valid(e.node):
			continue
		var mi: GeometryInstance3D = e.node
		var on: bool = prop_d > 0.0 and (e.kind in ["car", "prop", "loot"])
		if on:
			var q := Vector2(mi.global_position.x, mi.global_position.z)
			on = p.distance_to(q) <= prop_d + e.get("pad", 0.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _range_for_kind(kind: String, preset: Dictionary) -> float:
	match kind:
		"car":
			return preset.car_range
		"small":
			return preset.small_range
		"deco":
			return preset.deco_range
		_:
			return preset.prop_range


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
	# 能进的楼：按方块碰撞（地板、墙、楼梯、门）
	for it in interiors:
		if it.contains(Vector3(q.x, 0, q.y), radius + 1.0):
			var r := it.push_out(Vector3(q.x, p.y, q.y), radius)
			q = Vector2(r.x, r.z)
	# 自己摆的方块：只算和身体高度（脚底到头顶）重叠的那几层
	if not voxels.is_empty():
		for gz in range(floori(q.y - radius), floori(q.y + radius) + 1):
			for gx in range(floori(q.x - radius), floori(q.x + radius) + 1):
				if not _solid_column(gx, gz, p):
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
		if o.get("dead", false):
			continue
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
		if o.get("dead", false):
			continue
		var local: Vector2 = (q - o.c).rotated(o.rot)
		if absf(local.x) < o.h.x + radius and absf(local.y) < o.h.y + radius:
			return true
	return false


## 两点之间有没有被楼挡住（子弹、视线用）
func line_blocked(a: Vector3, b: Vector3) -> bool:
	var steps := int(a.distance_to(b) / 0.5)
	for s in range(1, steps):
		var p := a.lerp(b, float(s) / steps)
		if _point_blocked(p):
			return true
	return false


## 视线、子弹走到这一点被挡没有：能进的楼里按方块（分楼层），其他楼按占地图
func _point_blocked(p: Vector3) -> bool:
	for it in interiors:
		if it.contains(p):
			return it.solid_point(p) or (not _low.is_empty() and _low.has(Vector2i(floori(p.x), floori(p.z))) and p.y < 2.0)
	var gx := floori(p.x)
	var gz := floori(p.z)
	return _cell(gx, gz) or _iwall_at(gx, gz) or \
		(not _low.is_empty() and _low.has(Vector2i(gx, gz)) and p.y < 2.0)


## 子弹飞到这一点打中墙、楼板没有（地面、楼、自己摆的方块）
func solid_at(p: Vector3) -> bool:
	if p.y < 0.0:
		return true
	for it in interiors:
		if it.contains(p):
			return it.solid_point(p) or voxels.has(cell_of(p))
	return (p.y < 30.0 and _cell(floori(p.x), floori(p.z))) or voxels.has(cell_of(p))


## 离玩家最近、够得着的容器（楼里的容器还要在同一层）
func nearest_container(p: Vector3, reach := 1.4) -> Dictionary:
	var best := {}
	var best_d := INF
	for c in containers:
		if c.get("dead", false):
			continue
		if c.get("indoor", false) and absf(p.y - c.pos.y) > 2.0:
			continue
		var d: float = Vector2(p.x - c.pos.x, p.z - c.pos.z).length() - c.r
		if d < reach and d < best_d and not line_blocked(p + Vector3.UP * 1.2, c.pos + Vector3.UP * 0.8):
			best_d = d
			best = c
	return best


func inside_interior(p: Vector3, radius := 0.0) -> bool:
	for it in interiors:
		if it.contains(p, radius):
			return true
	return false


## 随机找一个空地（不在楼里、车里）
func free_point(center: Vector3, min_r: float, max_r: float) -> Vector3:
	for i in 40:
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf_range(min_r * min_r, max_r * max_r))
		var p := center + Vector3(cos(ang) * r, 0, sin(ang) * r)
		p.y = 0.0
		if not blocked(p, 0.6) and not inside_interior(p, 0.6):
			return p
	var fallback := push_out(center + Vector3(min_r, 0, 0), 0.6)
	fallback.y = 0.0
	return fallback


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
const FLOW_SIZE := FLOW_R * 2 + 1
var _flow := PackedInt32Array()
var _flow_center := Vector2i(1 << 20, 0)
## 正在后台分几帧算的新距离场（算完才换掉 _flow，僵尸这期间用旧的）
## 以前一次算完要 20 多毫秒，每 0.5 秒卡一帧，跑动时画面一顿一顿的
var _fj_active := false
var _fj_center := Vector2i.ZERO
var _fj_dist := PackedInt32Array()
var _fj_wall := PackedByteArray()   # 窗口里每格挡不挡路（开算时一行一行填）
var _fj_queue := PackedInt32Array()
var _fj_row := 0                    # 墙填到第几行
var _fj_head := 0
var _fj_tail := 0
var _fj_next := Vector2i.ZERO       # 算的过程中又要了新中心，算完接着算
var _fj_has_next := false


## 立刻把距离场整个算完（测试、开局用）
func update_flow(target: Vector3) -> void:
	request_flow(target)
	while _fj_active:
		flow_step(1 << 30)


## 要一个以 target 为中心的新距离场；真正的计算在 flow_step 里分几帧做完
func request_flow(target: Vector3) -> void:
	var c := Vector2i(floori(target.x), floori(target.z))
	if _fj_active:
		_fj_next = c
		_fj_has_next = true
		return
	_start_flow(c)


func _start_flow(c: Vector2i) -> void:
	var n := FLOW_SIZE * FLOW_SIZE
	if _fj_dist.size() != n:
		_fj_dist.resize(n)
		_fj_wall.resize(n)
		_fj_queue.resize(n)
	_fj_dist.fill(-1)
	_fj_center = c
	_fj_row = 0
	_fj_head = 0
	_fj_tail = 0
	_fj_active = true


## 每帧调：最多花 budget_usec 微秒往下算（BFS，8 方向，不能斜着穿墙角）
func flow_step(budget_usec: int) -> void:
	if not _fj_active:
		return
	var t0 := Time.get_ticks_usec()
	var size := FLOW_SIZE
	var ox := _fj_center.x - FLOW_R
	var oz := _fj_center.y - FLOW_R
	# 第一步：把窗口里的墙填进字节表，后面 BFS 只查表
	# 直接读 _cells / _iwall 两张表（不走 _wall()，GDScript 每格调函数太慢）
	var cells := _cells
	var iwall := _iwall
	var has_low := not _low.is_empty()
	var map2 := MAP * 2
	var wall_out := _fj_wall
	while _fj_row < size:
		var base := _fj_row * size
		var wz := oz + _fj_row
		var mz := wz + MAP
		var row_in := mz >= 0 and mz < map2
		var rbase := mz * map2 + MAP
		for x in size:
			var gx := ox + x
			var w := 0
			var mx := gx + MAP
			if row_in and mx >= 0 and mx < map2:
				if (not cells.is_empty() and cells[rbase + gx] == 1) \
						or (not iwall.is_empty() and iwall[rbase + gx] == 1):
					w = 1
			if w == 0 and has_low and _low.has(Vector2i(gx, wz)):
				w = 1
			wall_out[base + x] = w
		_fj_row += 1
		if _fj_row == size:
			var start := FLOW_R * size + FLOW_R
			_fj_dist[start] = 0
			_fj_queue[0] = start
			_fj_tail = 1
		if Time.get_ticks_usec() - t0 > budget_usec:
			return
	# 第二步：BFS。每 256 格看一次表
	var dist := _fj_dist
	var wall := _fj_wall
	var queue := _fj_queue
	var head := _fj_head
	var tail := _fj_tail
	var count := 0
	while head < tail:
		var i := queue[head]
		head += 1
		var x := i % size
		var z := i / size
		var d1 := dist[i] + 1
		var w_l := x == 0 or wall[i - 1] == 1
		var w_r := x == size - 1 or wall[i + 1] == 1
		var w_u := z == 0 or wall[i - size] == 1
		var w_d := z == size - 1 or wall[i + size] == 1
		# 上下左右、再斜着（斜着要两边都不是墙）。没写成函数：每格 8 次函数调用比 BFS 本身还贵
		# 没走过的格子：是墙标 -2，不是墙记距离并排进队列
		var ni := 0
		if x > 0:
			ni = i - 1
			if dist[ni] == -1:
				if w_l: dist[ni] = -2
				else: dist[ni] = d1; queue[tail] = ni; tail += 1
		if x < size - 1:
			ni = i + 1
			if dist[ni] == -1:
				if w_r: dist[ni] = -2
				else: dist[ni] = d1; queue[tail] = ni; tail += 1
		if z > 0:
			ni = i - size
			if dist[ni] == -1:
				if w_u: dist[ni] = -2
				else: dist[ni] = d1; queue[tail] = ni; tail += 1
		if z < size - 1:
			ni = i + size
			if dist[ni] == -1:
				if w_d: dist[ni] = -2
				else: dist[ni] = d1; queue[tail] = ni; tail += 1
		if not w_r and not w_d:
			ni = i + size + 1
			if dist[ni] == -1:
				if wall[ni] == 1: dist[ni] = -2
				else: dist[ni] = d1; queue[tail] = ni; tail += 1
		if not w_r and not w_u:
			ni = i - size + 1
			if dist[ni] == -1:
				if wall[ni] == 1: dist[ni] = -2
				else: dist[ni] = d1; queue[tail] = ni; tail += 1
		if not w_l and not w_d:
			ni = i + size - 1
			if dist[ni] == -1:
				if wall[ni] == 1: dist[ni] = -2
				else: dist[ni] = d1; queue[tail] = ni; tail += 1
		if not w_l and not w_u:
			ni = i - size - 1
			if dist[ni] == -1:
				if wall[ni] == 1: dist[ni] = -2
				else: dist[ni] = d1; queue[tail] = ni; tail += 1
		count += 1
		if count & 255 == 0 and Time.get_ticks_usec() - t0 > budget_usec:
			_fj_head = head
			_fj_tail = tail
			return
	# 算完：换上新的，有排队的中心就接着算
	_fj_head = head
	_fj_tail = tail
	var tmp := _flow
	_flow = _fj_dist
	_fj_dist = tmp
	_flow_center = _fj_center
	_fj_active = false
	if _fj_has_next:
		_fj_has_next = false
		_start_flow(_fj_next)


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
	if _cells.is_empty():
		return false
	var x := gx + MAP
	var z := gz + MAP
	if x < 0 or z < 0 or x >= MAP * 2 or z >= MAP * 2:
		return false
	return _cells[z * MAP * 2 + x] == 1


## 楼，或者贴地两格里有自己摆的方块（僵尸过不去、绕着走）
func _wall(gx: int, gz: int) -> bool:
	return _cell(gx, gz) or _iwall_at(gx, gz) or (not _low.is_empty() and _low.has(Vector2i(gx, gz)))


func _iwall_at(gx: int, gz: int) -> bool:
	if _iwall.is_empty():
		return false
	var x := gx + MAP
	var z := gz + MAP
	if x < 0 or z < 0 or x >= MAP * 2 or z >= MAP * 2:
		return false
	return _iwall[z * MAP * 2 + x] == 1


## 重算能进的楼在街面那层某一格挡不挡路（格子里取 4 个点，站在地面 y=0）
func _update_iwall(it: PoiInterior, gx: int, gz: int) -> void:
	var x := gx + MAP
	var z := gz + MAP
	if x < 0 or z < 0 or x >= MAP * 2 or z >= MAP * 2:
		return
	var hit := false
	for o in [Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.25, 0.75), Vector2(0.75, 0.75)]:
		if it.blocks_at(Vector3(gx + o.x, 0.0, gz + o.y)):
			hit = true
			break
	_iwall[z * MAP * 2 + x] = 1 if hit else 0


# —— 自己摆的方块（1 米一格，格子坐标 = 世界坐标向下取整） ——

## 格子 -> {id, hp, node}
var voxels := {}
var stations := {}     # area -> [格子]，靠近工作站的判定用
var station_cells := {}  # 格子 -> area，合成系统查工作站用
var _low := {}      # Vector2i(x, z) -> 这一列 y=0、1 两格里有几块（挡僵尸用）
var _voxel_root: Node3D
const VOXEL_TOP := 40


static func cell_of(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x), floori(p.y), floori(p.z))


func has_voxel(c: Vector3i) -> bool:
	return voxels.has(c)


## 这一列在 [脚底, 头顶] 这段高度里有没有迈不上去的方块
func _solid_column(gx: int, gz: int, p: Vector3) -> bool:
	for y in range(maxi(0, floori(p.y + 0.05)), floori(p.y + 1.7) + 1):
		var cell := Vector3i(gx, y, gz)
		var v: Dictionary = voxels.get(cell, {})
		if v.is_empty():
			continue
		var local := Blocks.local_point(p, cell, int(v.get("rot", 0)))
		var th := float(y) + Blocks.top_height(str(v.get("shape", "cube")), int(v.get("rot", 0)), local)
		if th > p.y + 0.55:
			return true
	return false


## 这格能不能摆：空的、不在楼里、在地图里、不太高
func can_place(c: Vector3i) -> bool:
	if voxels.has(c) or c.y < 0 or c.y >= VOXEL_TOP:
		return false
	if voxels.size() >= GameConfig.BLOCK_LIMIT:
		return false
	if absi(c.x) >= int(EDGE) or absi(c.z) >= int(EDGE):
		return false
	var mid := Vector3(c) + Vector3.ONE * 0.5
	for it in interiors:
		if it.contains(mid) and (it.solid_point(mid) or it.ladder_at(Vector3(c))):
			return false
	return not _cell(c.x, c.z)


func add_voxel(c: Vector3i, id: String, hp := -1.0, shape := "cube", rot := 0) -> bool:
	if voxels.has(c) or voxels.size() >= GameConfig.BLOCK_LIMIT:
		return false
	if not Blocks.is_valid_shape(shape):
		shape = "cube"
	rot = posmod(rot, 4)
	voxels[c] = {"id": id, "hp": hp if hp > 0.0 else float(Blocks.info(id).get("hp", 100.0)),
		"shape": shape, "rot": rot}
	var area := Blocks.station_area(id)
	if area != "":
		if not stations.has(area):
			stations[area] = []
		stations[area].append(c)
		station_cells[c] = area
		_ensure_voxel_root()
		var node := Blocks.make_node(id)
		node.position = Vector3(c) + Blocks.mesh_offset(id)
		_voxel_root.add_child(node)
		_station_nodes[c] = node
	else:
		_vox_mark(c, true)
	if c.y <= 1:
		var k := Vector2i(c.x, c.z)
		_low[k] = _low.get(k, 0) + 1
	return true


func _ensure_voxel_root() -> void:
	if _voxel_root == null:
		_voxel_root = Node3D.new()
		_voxel_root.name = "Voxels"
		add_child(_voxel_root)


## 方块按 16×16×16 分区块，每个区块合成一个网格，下一帧统一重建
func _vox_key(c: Vector3i) -> Vector3i:
	return Vector3i(floori(float(c.x) / VOXEL_CHUNK), floori(float(c.y) / VOXEL_CHUNK),
		floori(float(c.z) / VOXEL_CHUNK))


func _vox_mark(c: Vector3i, on: bool) -> void:
	var key := _vox_key(c)
	if not _vox_chunks.has(key):
		if not on:
			return
		_vox_chunks[key] = {"mi": null, "cells": {}}
	var ch: Dictionary = _vox_chunks[key]
	if on:
		ch.cells[c] = true
	else:
		ch.cells.erase(c)
	_vox_dirty[key] = true
	# 相邻区块的共享面也要重算
	for d in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.DOWN, Vector3i.UP, Vector3i.FORWARD, Vector3i.BACK]:
		var nk := _vox_key(c + d)
		if nk != key:
			_vox_dirty[nk] = true
	if not _vox_flush_queued:
		_vox_flush_queued = true
		_flush_voxels.call_deferred()


func _is_full_voxel(c: Vector3i) -> bool:
	var v: Dictionary = voxels.get(c, {})
	return not v.is_empty() and str(v.get("shape", "cube")) == "cube" \
		and Blocks.station_area(str(v.get("id", ""))) == ""


## 立刻把改过的方块区块重建一遍（摆/拆方块后的那一帧末尾自动调用）
func _flush_voxels() -> void:
	_vox_flush_queued = false
	_ensure_voxel_root()
	for key in _vox_dirty.keys():
		var ch: Dictionary = _vox_chunks.get(key, {})
		if ch.is_empty():
			continue
		if ch.cells.is_empty():
			if ch.mi:
				(ch.mi as Node).queue_free()
			_vox_chunks.erase(key)
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for c in ch.cells:
			var v: Dictionary = voxels.get(c, {})
			if v.is_empty() or Blocks.station_area(str(v.get("id", ""))) != "":
				continue
			Blocks.append_block(st, str(v.id), str(v.get("shape", "cube")), int(v.get("rot", 0)), c,
				Callable(self, "_is_full_voxel"))
		var mesh := st.commit()
		if ch.mi == null:
			var mi := MeshInstance3D.new()
			mi.material_override = Blocks.material()
			_voxel_root.add_child(mi)
			ch.mi = mi
		(ch.mi as MeshInstance3D).mesh = mesh
	_vox_dirty.clear()


## 测试和 bench 用：现在有几个方块绘制组
func voxel_draw_groups() -> int:
	return _vox_chunks.size() + _station_nodes.size()

func remove_voxel(c: Vector3i) -> String:
	var v: Dictionary = voxels.get(c, {})
	if v.is_empty():
		return ""
	var id := str(v.id)
	voxels.erase(c)
	var area := Blocks.station_area(id)
	if area != "" and stations.has(area):
		stations[area].erase(c)
		station_cells.erase(c)
	if _station_nodes.has(c):
		var node: Node = _station_nodes[c]
		_station_nodes.erase(c)
		if is_instance_valid(node):
			node.queue_free()
	else:
		_vox_mark(c, false)
	if c.y <= 1:
		var k := Vector2i(c.x, c.z)
		_low[k] = _low.get(k, 1) - 1
		if _low[k] <= 0:
			_low.erase(k)
	return id


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
	stations.clear()
	station_cells.clear()
	for node in _station_nodes.values():
		if is_instance_valid(node):
			node.queue_free()
	_station_nodes.clear()
	for ch in _vox_chunks.values():
		if ch.get("mi") and is_instance_valid(ch.mi):
			(ch.mi as Node).queue_free()
	_vox_chunks.clear()
	_vox_dirty.clear()


## 存档用：[[x, y, z, 方块名, 耐久, 形状, 朝向], …]
func voxel_save() -> Array:
	var out := []
	for c in voxels:
		var v: Dictionary = voxels[c]
		out.append([c.x, c.y, c.z, v.id, v.hp, v.get("shape", "cube"), int(v.get("rot", 0))])
	return out


func voxel_load(list: Array) -> void:
	clear_voxels()
	for e in list:
		if e is Array and e.size() >= 4 and Blocks.is_block(str(e[3])):
			add_voxel(Vector3i(int(e[0]), int(e[1]), int(e[2])), str(e[3]),
				float(e[4]) if e.size() > 4 else -1.0,
				str(e[5]) if e.size() > 5 else "cube",
				int(e[6]) if e.size() > 6 else 0)


## 这一格是什么工作站；不是返回空串
func station_area_at(cell: Vector3i) -> String:
	return station_cells.get(cell, "")


## p 附近 reach 米内有没有这种工作站
func near_station(p: Vector3, area: String, reach := 3.0) -> bool:
	for c in stations.get(area, []):
		if _near_station_cell(p, c, reach):
			return true
	return false


## 最近的工作站：{area, name, pos, dist}；没有返回 {}
func nearest_station(p: Vector3, reach := 3.0) -> Dictionary:
	var best := {}
	var best_d := reach + 0.001
	for area in stations:
		for c in stations[area]:
			if not _near_station_cell(p, c, reach):
				continue
			var at := Vector3(c) + Vector3(0.5, 0.5, 0.5)
			var d := p.distance_to(at)
			if d < best_d:
				best_d = d
				best = {"area": area, "name": Blocks.info(area).get("zh", area), "pos": at, "dist": d, "cell": c}
	return best


func _near_station_cell(p: Vector3, c: Vector3i, reach: float) -> bool:
	if absf(p.y - float(c.y)) > 2.0:
		return false
	return Vector2(p.x - (float(c.x) + 0.5), p.z - (float(c.z) + 0.5)).length() <= reach


## 站在 p 时脚下最高的方块顶（没有就是地面 0）。只算比脚底高不了多少的方块，免得被吸到头顶上
func floor_under(p: Vector3, radius: float) -> float:
	var best := 0.0
	for it in interiors:
		if it.contains(p, radius):
			best = maxf(best, it.floor_at(p, radius))
	if voxels.is_empty():
		return best
	var top := mini(floori(p.y + 0.3), VOXEL_TOP)
	for gz in range(floori(p.z - radius), floori(p.z + radius) + 1):
		for gx in range(floori(p.x - radius), floori(p.x + radius) + 1):
			for y in range(top, -1, -1):
				var v: Dictionary = voxels.get(Vector3i(gx, y, gz), {})
				if v.is_empty():
					continue
				var local := Blocks.local_point(p, Vector3i(gx, y, gz), int(v.get("rot", 0)))
				var th := float(y) + Blocks.top_height(str(v.get("shape", "cube")), int(v.get("rot", 0)), local)
				if th <= p.y + 0.55 + 0.001:
					best = maxf(best, th)
	return best


## 头顶（p.y + height）碰到方块没有
func ceiling_hit(p: Vector3, radius: float, height: float) -> bool:
	for it in interiors:
		if it.contains(p, radius) and it.ceiling_hit(p, radius, height):
			return true
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
			if c.y < 0 or (c.y < 30 and _cell(c.x, c.z)) or _interior_solid(from + dir * (t + 0.01)):
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
	var kind: String = e.get("kind", "prop")
	var size: Vector3 = info.size
	if _batching and not (kind in ["loot", "car"]):
		# 不能翻的道具不建独立节点，攒进 MultiMesh（几百个路障变成几十次绘制）
		var oi := -1
		if solid and kind == "prop" and size.x * size.z > 0.08:
			oi = _add_obstacle(Vector2(pos.x, pos.z), Vector2(size.x, size.z) * 0.5 * 0.9, rot, size.y > 2.5)
		var cell := Vector2i(floori(pos.x / BATCH_CELL), floori(pos.z / BATCH_CELL))
		var bkey := "%s|%d|%d" % [name, cell.x, cell.y]
		if not _batch.has(bkey):
			_batch[bkey] = {"name": name, "cell": cell, "xfs": [], "props": []}
		_batch[bkey].xfs.append(Transform3D(Basis(Vector3.UP, rot), pos) * info.xf)
		if kind in ["prop", "small", "deco"]:
			var mat := Harvest.material(name)
			var hpmax := Harvest.hp(name)
			props.append({"name": name, "pos": pos, "rot": rot, "kind": kind, "batched": true,
				"bkey": bkey, "index": _batch[bkey].xfs.size() - 1, "obstacle": oi,
				"material": mat, "hp": hpmax, "max_hp": hpmax, "dead": false, "dead_day": 0,
				"local_xf": Transform3D.IDENTITY})
			_batch[bkey].props.append(props.size() - 1)
		return null
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
	# 远了就不画：具体距离由画质档位决定，先按均衡档放
	mi.visibility_range_end = _range_for_kind(kind, GameConfig.QUALITY_PRESETS[1])
	mi.visibility_range_end_margin = 5.0
	# 投影在 start 后按玩家距离开关，标题界面不画阴影
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_prop_lod.append({"node": mi, "kind": kind})
	var obs_i := -1
	if solid and kind in ["loot", "car", "prop"] and size.x * size.z > 0.08:
		obs_i = _add_obstacle(Vector2(pos.x, pos.z), Vector2(size.x, size.z) * 0.5 * 0.9, rot, size.y > 2.5)
	if kind in ["loot", "car"]:
		var ci := containers.size()
		containers.append({"node": holder, "pos": pos, "name": e.get("name", name), "loot": e.get("loot", "any"),
			"searched": false, "r": max(size.x, size.z) * 0.5, "kind": kind})
		if kind == "car":
			var mat2 := Harvest.material(name)
			var hpmax2 := Harvest.hp(name)
			props.append({"name": name, "pos": pos, "rot": rot, "kind": kind, "batched": false,
				"node": holder, "container": ci, "obstacle": obs_i,
				"material": mat2, "hp": hpmax2, "max_hp": hpmax2, "dead": false, "dead_day": 0,
				"local_xf": Transform3D.IDENTITY})
	return holder




## 把攒下的道具按组建成 MultiMeshInstance3D。节点放在组的中心，visibility_range 按中心算距离
func _flush_batches() -> void:
	for bkey in _batch:
		var b: Dictionary = _batch[bkey]
		var info := _info(b.name)
		var e: Dictionary = models[b.name]
		var kind: String = e.get("kind", "prop")
		var center := Vector3((b.cell.x + 0.5) * BATCH_CELL, 0.0, (b.cell.y + 0.5) * BATCH_CELL)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = info.mesh
		mm.instance_count = b.xfs.size()
		var bprops: Array = b.get("props", [])
		for k in b.xfs.size():
			var xf: Transform3D = b.xfs[k]
			xf.origin -= center
			mm.set_instance_transform(k, xf)
			if k < bprops.size():
				props[int(bprops[k])]["local_xf"] = xf
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Batch_" + b.name
		mmi.multimesh = mm
		mmi.position = center
		mmi.material_override = _material(e.get("texture", ""))
		# 组有半格大，可见距离放宽半格，保证近处的一个都不少
		mmi.visibility_range_end = _range_for_kind(kind, GameConfig.QUALITY_PRESETS[1]) + BATCH_CELL * 0.5
		mmi.visibility_range_end_margin = 5.0
		# 投影由 update_shadows 按玩家距离开关
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_batch_nodes[bkey] = {"mmi": mmi, "center": center}
		_prop_lod.append({"node": mmi, "kind": kind, "pad": BATCH_CELL * 0.5})
	_batch.clear()

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

## 地面、人行道、马路都先攒着，最后按贴图合成一个大网格。
## 以前每块地一个 PlaneMesh，光地面就上百个 draw call。
func _flat(rect: Rect2, y: float, tex_name: String, tile: float, tint := Color.WHITE) -> void:
	var key := "%s|%s" % [tex_name, tint]
	if not _flat_groups.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_flat_groups[key] = {"st": st, "tex": tex_name, "tint": tint, "verts": 0}
	var g: Dictionary = _flat_groups[key]
	var st: SurfaceTool = g.st
	var base: int = g.verts
	var x0 := rect.position.x
	var z0 := rect.position.y
	var x1 := rect.end.x
	var z1 := rect.end.y
	# 从上往下看是顺时针（Godot 正面绕向），法线朝上
	var points := [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]
	var uvs := [Vector2(x0 / tile, z0 / tile), Vector2(x1 / tile, z0 / tile),
		Vector2(x1 / tile, z1 / tile), Vector2(x0 / tile, z1 / tile)]
	for i in 4:
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[i])
		st.add_vertex(points[i])
	g.verts += 4
	for i in [0, 1, 2, 0, 2, 3]:
		st.add_index(base + i)


func _flush_flats() -> void:
	for key in _flat_groups:
		var g: Dictionary = _flat_groups[key]
		var st: SurfaceTool = g.st
		st.generate_tangents()
		var mesh: ArrayMesh = st.commit()
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _flat_material(g.tex, g.tint)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_flat_groups.clear()


func _flat_material(tex_name: String, tint: Color) -> Material:
	var key := "%s|%s" % [tex_name, tint]
	if _flat_mats.has(key):
		return _flat_mats[key]
	var m: Material
	if terrain.has(tex_name):
		# 游戏的地形贴图：颜色 + 法线 + 粗糙度/AO，路面有凹凸感
		var t: Dictionary = terrain[tex_name]
		var om := ORMMaterial3D.new()
		om.albedo_color = tint
		om.albedo_texture = load("%s/%s" % [ROOT, t.albedo])
		om.normal_enabled = true
		om.normal_texture = load("%s/%s" % [ROOT, t.normal])
		om.orm_texture = load("%s/%s" % [ROOT, t.orm])
		om.uv1_scale = Vector3.ONE
		om.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m = om
	else:
		var sm := StandardMaterial3D.new()
		sm.roughness = 0.95
		sm.albedo_color = tint
		var t := _tex(tex_name)
		if t:
			sm.albedo_texture = t
			sm.uv1_scale = Vector3.ONE
			sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m = sm
	_flat_mats[key] = m
	return m


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
	mi.visibility_range_end = GameConfig.QUALITY_PRESETS[1].poi_range
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("poi_far", true)
	add_child(mi)
	# 远处（FAR_LOD_DIST 以外）用更粗的远景 LOD
	var lod1_path := "%s/poi/%s_lod1.res" % [ROOT, name]
	var lod1: MeshInstance3D = null
	var lod2_node: MeshInstance3D = null
	if ResourceLoader.exists(lod1_path):
		var coarse = load(lod1_path)
		if coarse is Mesh:
			lod1 = MeshInstance3D.new()
			lod1.mesh = coarse
			lod1.material_override = _poi_material()
			lod1.visibility_range_begin = FAR_LOD_DIST
			lod1.visibility_range_begin_margin = 5.0
			lod1.visibility_range_end = GameConfig.QUALITY_PRESETS[1].poi_range
			lod1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lod1.set_meta("poi_far", true)
			add_child(lod1)
			lod1.position = mi.position
			lod1.rotation.y = rot
			mi.set_meta("lod_split", true)
			mi.visibility_range_end = FAR_LOD_DIST
			lod1.visibility_range_end = FAR_LOD2_DIST
			_poi_lods.append({"node": lod1, "level": 1})
			var lod2_path := "%s/poi/%s_lod2.res" % [ROOT, name]
			if ResourceLoader.exists(lod2_path):
				var coarse2 = load(lod2_path)
				if coarse2 is Mesh:
					var lod2 := MeshInstance3D.new()
					lod2.mesh = coarse2
					lod2.material_override = _poi_material()
					lod2.visibility_range_begin = FAR_LOD2_DIST
					lod2.visibility_range_begin_margin = 5.0
					lod2.visibility_range_end = GameConfig.QUALITY_PRESETS[1].poi_range
					lod2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					lod2.set_meta("poi_far", true)
					add_child(lod2)
					lod2.position = mi.position
					lod2.rotation.y = rot
					lod2_node = lod2
					_poi_lods.append({"node": lod2, "level": 2})
	# 有完整方块数据生成的楼时，近处换成它（有窗户、楼梯、屋檐），远处还用简化的远景网格
	var full_path := "%s/poi/%s_full.res" % [ROOT, name]
	# 完整版顶点太少说明方块数据没转好（缺形状模型、方块表不对），用它楼会在近处消失，宁可还用远景网格
	var use_full := ResourceLoader.exists(full_path) and float(info.get("full_verts", 0)) >= float(info.get("verts", 1)) * FULL_MIN_SHARE
	if not use_full and ResourceLoader.exists(full_path):
		push_warning("%s 的完整版只有 %d 顶点（远景 %d），不用" % [name, int(info.get("full_verts", 0)), int(info.get("verts", 0))])
	if use_full:
		_full_pois.append({"name": name, "pos": c, "far": mi, "far_lod1": lod1, "parts": [], "props": null,
			"path": full_path, "state": 0, "rot": rot,
			"radius": 0.5 * Vector2(float(info.grid_w), float(info.grid_h)).length()})
		var shadow := MeshInstance3D.new()
		# 影子用最粗的 LOD 投，远处看不出差别
		shadow.mesh = lod2_node.mesh if lod2_node else (lod1.mesh if lod1 else mesh)
		shadow.material_override = _poi_material()
		shadow.position = mi.position
		shadow.rotation.y = rot
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		shadow.visibility_range_end = FULL_DETAIL_RANGE + 10.0
		add_child(shadow)
		# 近处阴影交给只投影的简化网格；远景网格始终不投影
		_poi_lod.append({"node": shadow, "pos": c, "shadow_only": true})
	else:
		_poi_lod.append({"node": mi, "pos": c})
	buildings.append({"name": name, "pos": Vector3(c.x, 0, c.y)})
	_poi_containers(name, c, rot, mi.position.y)
	# 有按方块的碰撞格子：楼能走进去，不盖实心占地
	if use_full and _add_interior(name, Vector3(c.x, mi.position.y, c.y), rot):
		return
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


## 把这栋楼方块数据里的容器方块加进 containers。方块本身已经画在完整网格里，这里只登记位置。
## loot 是官方 LootList 名（交给 Loot.roll）；旧的分类掷骰没有对应时按 any。
func _poi_containers(name: String, c: Vector2, rot: float, base_y: float) -> void:
	var entry = poi_containers.get(name)
	if not (entry is Dictionary):
		return
	var cs := cos(rot)
	var sn := sin(rot)
	for e in entry.get("list", []):
		# 方块数据是游戏的左手坐标，网格翻了 x，这里也翻
		var lx := -float(e.get("x", 0.0))
		var lz := float(e.get("z", 0.0))
		var pos := Vector3(c.x + lx * cs + lz * sn, base_y + float(e.get("y", 0.0)), c.y - lx * sn + lz * cs)
		var official: String = str(e.get("loot", ""))
		containers.append({"node": null, "pos": pos, "name": _container_zh(official),
			"loot": "any", "container": official, "block": str(e.get("block", "")),
			"searched": false, "r": 0.5, "kind": "block", "indoor": true, "poi": name})


## 能进的楼：读碰撞格子，盖街面那层的占地图，摆门板和没模型的容器箱子。没有 .col 返回 false
func _add_interior(name: String, at: Vector3, rot: float) -> bool:
	var entry = poi_containers.get(name)
	if not (entry is Dictionary) or not entry.get("col", false):
		return false
	var it := PoiInterior.load_col("%s/poi/%s.col" % [ROOT, name], name, at, rot, entry.get("doors", []))
	if it == null:
		return false
	add_interior(it, entry)
	return true


## 登记一栋能进的楼（测试也直接调这个）
func add_interior(it: PoiInterior, entry: Dictionary) -> void:
	interiors.append(it)
	var r := it.rect
	for gz in range(floori(r.position.y), ceili(r.end.y) + 1):
		for gx in range(floori(r.position.x), ceili(r.end.x) + 1):
			_update_iwall(it, gx, gz)
	_build_interior_props(interiors.size() - 1, entry)


## 门板（木门、铁门各一个 MultiMesh）和没有模型的容器（画成箱子）。挂在和楼网格一样变换的节点下
func _build_interior_props(ii: int, entry: Dictionary) -> void:
	var it: PoiInterior = interiors[ii]
	var holder := Node3D.new()
	holder.name = "Interior_" + it.name
	holder.position = it.origin
	holder.rotation.y = it.rot
	add_child(holder)
	var slots := []
	var lists := {"wood": [], "metal": []}
	var door_fit := {}   # 门模型 -> 把模型缩放成以原点为中心的单位立方体（宽沿 x）
	for i in it.doors.size():
		var kind := "metal" if it.doors[i].metal else "wood"
		var dm: Dictionary = {}
		var key := str(_door_model_of(entry, i))
		if key != "":
			dm = _prop_model(key)
		if not dm.is_empty():
			kind = "m:" + key
			if not door_fit.has(kind):
				door_fit[kind] = _unit_fit(dm.mesh.get_aabb())
		if not lists.has(kind):
			lists[kind] = []
		slots.append([kind, lists[kind].size()])
		lists[kind].append(i)
	var nodes := {"slots": slots, "fit": door_fit}
	for kind in lists:
		if lists[kind].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var mmi := MultiMeshInstance3D.new()
		var fit := Transform3D.IDENTITY
		if kind.begins_with("m:"):
			var dm := _prop_model(kind.substr(2))
			mm.mesh = dm.mesh
			fit = door_fit[kind]
		else:
			mm.mesh = BoxMesh.new()
			mmi.material_override = _prop_material(kind)
		mm.instance_count = lists[kind].size()
		for k in lists[kind].size():
			mm.set_instance_transform(k, it.door_transform(lists[kind][k]) * fit)
		mmi.multimesh = mm
		mmi.visibility_range_end = FULL_DETAIL_RANGE
		holder.add_child(mmi)
		nodes[kind] = mmi
	_door_nodes[ii] = nodes
	# 没模型的容器：画成一个箱子，免得看不见
	var boxes: Array[Transform3D] = []
	for e in entry.get("list", []):
		if e.get("drawn", true):
			continue
		if e.get("model") is String and not poi_props.get(e.model, {}).is_empty():
			continue   # 有实体模型，在 _build_full_props 里画
		var sz := Vector3(float(e.get("sx", 1)), float(e.get("sy", 1)), float(e.get("sz", 1))) * 0.9
		var c := Vector3(-float(e.get("x", 0.0)), float(e.get("y", 0.0)) + sz.y * 0.5, float(e.get("z", 0.0)))
		boxes.append(Transform3D(Basis.from_scale(sz), c))
	if not boxes.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = BoxMesh.new()
		mm.instance_count = boxes.size()
		for k in boxes.size():
			mm.set_instance_transform(k, boxes[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _prop_material("crate")
		mmi.visibility_range_end = FULL_DETAIL_RANGE
		holder.add_child(mmi)


## 第 i 扇门的模型名（containers.json 里 doors[i].model），没有返回 ""
func _door_model_of(entry: Dictionary, i: int) -> String:
	var dl: Array = entry.get("doors", [])
	if i < dl.size() and dl[i] is Dictionary and dl[i].get("model") is String:
		return dl[i].model
	return ""


## 把 aabb 缩放、平移成以原点为中心的单位立方体；模型宽的一边沿 z 时先转 90 度让宽沿 x（门板宽沿 x）
func _unit_fit(a: AABB) -> Transform3D:
	var b := Basis.IDENTITY
	var sz := a.size
	if sz.z > sz.x:
		b = Basis(Vector3.UP, PI / 2)
		sz = Vector3(sz.z, sz.y, sz.x)
	sz = sz.max(Vector3.ONE * 0.001)
	var rotated := Transform3D(b, Vector3.ZERO) * a
	var scale := Basis.from_scale(Vector3.ONE / sz)
	return Transform3D(scale, -(scale * rotated.get_center())) * Transform3D(b, Vector3.ZERO)


func _prop_material(kind: String) -> Material:
	var key := "interior_" + kind
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		match kind:
			"metal":
				m.albedo_color = Color(0.44, 0.46, 0.48)
				m.metallic = 0.6
				m.roughness = 0.45
			"crate":
				m.albedo_color = Color(0.46, 0.4, 0.32)
				m.roughness = 0.9
			_:
				m.albedo_color = Color(0.42, 0.29, 0.18)
				m.roughness = 0.8
		_mat_cache[key] = m
	return _mat_cache[key]


func _interior_solid(p: Vector3) -> bool:
	for it in interiors:
		if it.contains(p) and it.solid_point(p):
			return true
	return false


## 身体在梯子格里（玩家爬梯子）
func ladder_at(p: Vector3) -> bool:
	for it in interiors:
		if it.contains(p) and it.ladder_at(p):
			return true
	return false


## 离 p 最近、大致在面前的门：{interior, door, pos, open}，没有返回空
func nearest_door(p: Vector3, facing: Vector3, reach := 1.8) -> Dictionary:
	var best := {}
	var best_d := INF
	for ii in interiors.size():
		var it := interiors[ii]
		if not it.contains(p, reach + 1.0):
			continue
		var i := it.nearest_door(p, facing, reach)
		if i < 0:
			continue
		var c := it.door_center(i)
		var d := Vector2(c.x - p.x, c.z - p.z).length()
		if d < best_d:
			best_d = d
			best = {"interior": ii, "door": i, "pos": c, "open": it.doors[i].open}
	return best


## 开关门：更新碰撞、门板和街面占地图（僵尸寻路）
func set_door(ii: int, i: int, open: bool) -> void:
	if ii < 0 or ii >= interiors.size():
		return
	var it := interiors[ii]
	if i < 0 or i >= it.doors.size():
		return
	it.set_door(i, open)
	for k in it.door_world_cells(i):
		_update_iwall(it, k.x, k.y)
	var nodes: Dictionary = _door_nodes.get(ii, {})
	var slot: Array = nodes.get("slots", [])[i] if i < nodes.get("slots", []).size() else []
	if slot.size() == 2 and nodes.has(slot[0]):
		var fit: Transform3D = nodes.get("fit", {}).get(slot[0], Transform3D.IDENTITY)
		(nodes[slot[0]] as MultiMeshInstance3D).multimesh.set_instance_transform(slot[1], it.door_transform(i) * fit)


func toggle_door(ii: int, i: int) -> bool:
	if ii < 0 or ii >= interiors.size() or i < 0 or i >= interiors[ii].doors.size():
		return false
	var open: bool = not interiors[ii].doors[i].open
	set_door(ii, i, open)
	return open


## 门会不会夹住人：关门时门洞里站着人就不关
func door_blocked_by(ii: int, i: int, p: Vector3, radius: float) -> bool:
	var it := interiors[ii]
	var d: Dictionary = it.doors[i]
	var c := it.to_cell(p)
	return c.x > d.x0 - radius and c.x < d.x1 + 1 + radius and c.z > d.z0 - radius and c.z < d.z1 + 1 + radius \
		and c.y > d.y0 - 1.6 and c.y < d.y1 + 1


## 存档：开着的门 [[楼名, 门序号], …]
func door_save() -> Array:
	var out := []
	for it in interiors:
		for i in it.doors.size():
			if it.doors[i].open:
				out.append([it.name, i])
	return out


func door_load(list: Array) -> void:
	for ii in interiors.size():
		for i in interiors[ii].doors.size():
			if interiors[ii].doors[i].open:
				set_door(ii, i, false)
	for e in list:
		if not (e is Array) or e.size() < 2:
			continue
		for ii in interiors.size():
			if interiors[ii].name == str(e[0]):
				set_door(ii, int(e[1]), true)


## 容器的中文叫法（按官方 LootList 名里的关键词猜，猜不到就叫「柜子」）
func _container_zh(loot: String) -> String:
	var l := loot.to_lower()
	for k in [["fridge", "冰箱"], ["cupboard", "橱柜"], ["cabinet", "柜子"], ["desk", "书桌"], ["safe", "保险箱"],
			["garbage", "垃圾桶"], ["trash", "垃圾桶"], ["cardboard", "纸箱"], ["box", "箱子"], ["crate", "木箱"],
			["shelf", "货架"], ["dresser", "梳妆台"], ["locker", "储物柜"], ["toilet", "马桶"], ["oven", "烤箱"],
			["bookcase", "书柜"], ["book", "书柜"], ["medicine", "药柜"], ["gun", "枪柜"], ["backpack", "背包"],
			["mailbox", "邮箱"], ["sink", "水槽"], ["file", "文件柜"], ["vending", "售货机"], ["register", "收银机"]]:
		if l.contains(k[0]):
			return k[1]
	return "柜子"


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
		# 贴花是贴地的，用 alpha 裁剪代替半透明，省掉排序和大量 overdraw
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.35
		m.roughness = 1.0
		mats.append(m)
	# 地面污渍地面污渍按「贴图 + 街区格」合成 MultiMesh，不再一块一个节点
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var groups := {}
	for i in GameConfig.DECAL_COUNT:
		var p := Vector3(rng.randf_range(-EDGE, EDGE), 0.03 + (i % 5) * 0.001, rng.randf_range(-EDGE, EDGE))
		var s := rng.randf_range(0.8, 2.6)
		var rot := rng.randf() * TAU
		var m := rng.randi_range(0, mats.size() - 1)
		var cell := Vector2i(floori(p.x / BATCH_CELL), floori(p.z / BATCH_CELL))
		var key := Vector3i(m, cell.x, cell.y)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, 1.0, s)), p))
	for key in groups:
		var xfs: Array = groups[key]
		var center := Vector3((key.y + 0.5) * BATCH_CELL, 0.0, (key.z + 0.5) * BATCH_CELL)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = quad
		mm.instance_count = xfs.size()
		for k in xfs.size():
			var xf: Transform3D = xfs[k]
			xf.origin -= center
			mm.set_instance_transform(k, xf)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = center
		mmi.material_override = mats[key.x]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = GameConfig.QUALITY_PRESETS[1].decal_range + BATCH_CELL * 0.5
		add_child(mmi)
		_decal_lod.append({"node": mmi, "pad": BATCH_CELL * 0.5})


## 系统内存吃紧：放掉远处的完整楼和缓存（下次靠近会重新加载）
func trim_memory(player_pos: Vector3) -> void:
	var p := Vector2(player_pos.x, player_pos.z)
	for e in _full_pois:
		if int(e.state) != 2:
			continue
		var d := maxf(0.0, p.distance_to(e.pos) - float(e.radius))
		if d > 60.0:
			_hide_full(e)
			e.state = 0
	_prop_cache.clear()
	_mesh_info.clear()
	_mat_cache.clear()


# —— 采集（4b）——

func _game_state() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("GameState")
	return null


func _day() -> int:
	var gs := _game_state()
	return int(gs.day) if gs else 0


## 准星前够得着的可采集物件，返回 props 下标（-1 = 没有）
func nearest_prop(p: Vector3, reach: float, aim: Vector3) -> int:
	var best := -1
	var best_d := INF
	var flat := Vector3(aim.x, 0.0, aim.z)
	if flat.length() > 0.01:
		flat = flat.normalized()
	for i in props.size():
		var pr: Dictionary = props[i]
		if pr.get("dead", false):
			continue
		var to: Vector3 = pr.pos - p
		if absf(to.y) > 2.0:
			continue
		to.y = 0.0
		var d := to.length()
		if d > reach or d < 0.001:
			continue
		if flat != Vector3.ZERO and d > 1.0 and flat.dot(to / d) < 0.25:
			continue
		if _point_blocked(Vector3(pr.pos) + Vector3.UP * 0.8):
			continue
		if d < best_d:
			best_d = d
			best = i
	return best


## 打物件：扣血，拆掉时藏起外观、去掉碰撞；返回 {destroyed, material, name, pos}
func hit_prop(idx: int, dmg: float) -> Dictionary:
	if idx < 0 or idx >= props.size():
		return {}
	var pr: Dictionary = props[idx]
	if pr.get("dead", false):
		return {}
	pr.hp = maxf(0.0, float(pr.hp) - dmg)
	var out := {"destroyed": false, "material": str(pr.material), "name": str(pr.name), "pos": Vector3(pr.pos)}
	if float(pr.hp) > 0.0:
		return out
	pr.dead = true
	pr.dead_day = _day()
	out.destroyed = true
	_set_prop_hidden(pr, true)
	if int(pr.get("obstacle", -1)) >= 0 and int(pr.obstacle) < obstacles.size():
		obstacles[int(pr.obstacle)]["dead"] = true
	if pr.has("container") and int(pr.container) < containers.size():
		containers[int(pr.container)]["dead"] = true
	return out


func _set_prop_hidden(pr: Dictionary, hidden: bool) -> void:
	if pr.get("batched", false):
		var b: Dictionary = _batch_nodes.get(str(pr.bkey), {})
		var mmi: MultiMeshInstance3D = b.get("mmi")
		if mmi == null or mmi.multimesh == null:
			return
		var idx := int(pr.index)
		if idx < 0 or idx >= mmi.multimesh.instance_count:
			return
		if hidden:
			mmi.multimesh.set_instance_transform(idx, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0.0, -999.0, 0.0)))
		else:
			mmi.multimesh.set_instance_transform(idx, pr.local_xf)
		return
	var node = pr.get("node")
	if node and is_instance_valid(node):
		node.visible = not hidden


func _restore_prop(pr: Dictionary) -> void:
	pr.dead = false
	pr.dead_day = 0
	pr.hp = float(pr.get("max_hp", pr.get("hp", 1.0)))
	_set_prop_hidden(pr, false)
	if int(pr.get("obstacle", -1)) >= 0 and int(pr.obstacle) < obstacles.size():
		obstacles[int(pr.obstacle)]["dead"] = false
	if pr.has("container") and int(pr.container) < containers.size():
		var c: Dictionary = containers[int(pr.container)]
		c["dead"] = false
		c.searched = false
		c.erase("items")
		c.erase("loot_day")
		c.erase("hp")


## 拆掉 5 个游戏天后原地刷新
func _on_day_started(day: int) -> void:
	for pr in props:
		if not pr.get("dead", false):
			continue
		if day - int(pr.get("dead_day", day)) < GameConfig.HARVEST_RESPAWN_DAYS:
			continue
		_restore_prop(pr)


func harvest_save() -> Dictionary:
	var dead := []
	for i in props.size():
		var pr: Dictionary = props[i]
		if pr.get("dead", false):
			dead.append([i, int(pr.get("dead_day", 0))])
	return {"harvest_dead": dead}


func harvest_load(list) -> void:
	harvest_reset()
	for e in list:
		if not (e is Array) or e.size() < 2:
			continue
		var i := int(e[0])
		if i < 0 or i >= props.size():
			continue
		var pr: Dictionary = props[i]
		pr.dead = true
		pr.dead_day = int(e[1])
		_set_prop_hidden(pr, true)
		if int(pr.get("obstacle", -1)) >= 0 and int(pr.obstacle) < obstacles.size():
			obstacles[int(pr.obstacle)]["dead"] = true
		if pr.has("container") and int(pr.container) < containers.size():
			containers[int(pr.container)]["dead"] = true


## 重开/读档前把所有物件恢复
func harvest_reset() -> void:
	for pr in props:
		_restore_prop(pr)


# —— 车和杂物的碰撞 ——

func _add_obstacle(c: Vector2, h: Vector2, rot: float, tall := false) -> int:
	obstacles.append({"c": c, "h": h, "rot": rot, "r": h.length(), "tall": tall})
	return obstacles.size() - 1


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
