class_name Blocks
## 建造方块和工作站：背包里拿一种方块在手上，点「攻击」就在准星指的地方摆一块 1 米的方块；
## 空手或拿近战武器打方块能把它拆掉。摆好的方块能挡僵尸，也能踩上去往高处搭。
## 贴图用游戏的方块图集（assets/poi/blocks.json，tools/build_poi.gd 生成），没有就用纯色。

const POI_SHADER := preload("res://scripts/poi.gdshader")
const DIR := "res://assets/poi"

## [方块名（和游戏 blocks.xml 里一样）, 中文名, 英文名, 耐久, 没贴图时的颜色]
const TYPES := [
	["frameShapes", "木框", "Wood Frame", 40.0, Color(0.66, 0.5, 0.32)],
	["woodShapes", "木块", "Wood Block", 100.0, Color(0.52, 0.36, 0.21)],
	["cobblestoneShapes", "圆石块", "Cobblestone Block", 200.0, Color(0.5, 0.49, 0.46)],
	["flagstoneShapes", "石板块", "Flagstone Block", 160.0, Color(0.6, 0.56, 0.5)],
	["concreteShapes", "混凝土块", "Concrete Block", 320.0, Color(0.68, 0.68, 0.66)],
	["steelShapes", "钢块", "Steel Block", 600.0, Color(0.42, 0.45, 0.5)],
	# 玩家储物箱（官方 cntWoodWritableCrate）：云盘 lootcontainers 里还没有它的模型，先用木色方块
	# 睡袋：不占格子、不挡路，摆下就是重生点（scripts/respawn.gd 管），模型在 respawnpoints.zip
	["bedroll", "睡袋", "Bedroll", 50.0, Color(0.32, 0.4, 0.3)],
	["cntWoodWritableCrate", "可写木箱（储物箱）", "Writable Storage Box", 120.0, Color(0.62, 0.44, 0.24)],
	# 工作站：摆下后 3 米内才能用对应配方（scripts/crafting.gd 的 station_check）
	["campfire", "篝火", "Campfire", 40.0, Color(0.55, 0.28, 0.12)],
	["workbench", "工作台", "Workbench", 180.0, Color(0.58, 0.4, 0.22)],
	["forge", "锻造炉", "Forge", 260.0, Color(0.38, 0.35, 0.33)],
	["chemistryStation", "化学台", "Chemistry Station", 220.0, Color(0.3, 0.45, 0.42)],
	["cementMixer", "水泥搅拌机", "Cement Mixer", 240.0, Color(0.5, 0.48, 0.4)],
]

## 工作站方块名 → 配方 area
const STATION_AREAS := {
	"campfire": "campfire", "workbench": "workbench", "forge": "forge",
	"chemistryStation": "chemistryStation", "cementMixer": "cementMixer",
}
## 云盘 crafting.zip 的主网格（OBJ）和贴图；没有就退回方块
const STATION_MODELS := {
	"campfire": "campfire", "workbench": "workbench", "forge": "forge",
	"chemistryStation": "chemistryStation", "cementMixer": "cementMixer",
}

const SHAPES := ["cube", "half", "ramp", "stairs", "pole", "plate"]
const SHAPE_NAMES := {
	"cube": "整块", "half": "半块", "ramp": "斜坡", "stairs": "楼梯", "pole": "柱子", "plate": "板",
}
## 只有这些建筑材料有六种形状；工作站/睡袋/箱子没有
const BUILD_BASES := ["frameShapes", "woodShapes", "cobblestoneShapes", "flagstoneShapes",
	"concreteShapes", "steelShapes"]

static var _mat: ShaderMaterial
static var _layers := {}     # 方块名 -> [图集层号, 占几格]
static var _layers_loaded := false
static var _meshes := {}
static var _station_materials := {}
static var _icons := {}
static var _shape_tris := {}
static var _shape_loaded := false


static func _load_shape_tris() -> void:
	if _shape_loaded:
		return
	_shape_loaded = true
	var path := "res://assets/data/block_shapes.json"
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		return
	for k in json.data:
		if json.data[k] is Array:
			_shape_tris[str(k)] = json.data[k]


static func shape_triangles(shape: String) -> int:
	_load_shape_tris()
	return (_shape_tris.get(shape, []) as Array).size()


static func is_block(id: String) -> bool:
	return not info(id).is_empty()


static func _is_base(id: String) -> bool:
	for t in TYPES:
		if t[0] == id:
			return true
	return false


static func variant_id(base: String, shape: String) -> String:
	return base if shape == "cube" else base + "_" + shape


static func base_of(id: String) -> String:
	for s in SHAPES:
		if s == "cube":
			continue
		var suffix: String = "_" + str(s)
		if id.ends_with(suffix):
			var base: String = id.substr(0, id.length() - suffix.length())
			if BUILD_BASES.has(base):
				return base
	return id


static func shape_of(id: String) -> String:
	for s in SHAPES:
		var suffix: String = "_" + str(s)
		if s != "cube" and id.ends_with(suffix) and BUILD_BASES.has(base_of(id)):
			return str(s)
	return "cube"


static func is_variant(id: String) -> bool:
	return shape_of(id) != "cube"


static func variant_ids() -> Array[String]:
	var out: Array[String] = []
	for base in BUILD_BASES:
		for s in SHAPES:
			if s != "cube":
				out.append(variant_id(str(base), str(s)))
	return out


static func _base_info(base_id: String) -> Dictionary:
	for t in TYPES:
		if t[0] == base_id:
			return {"id": t[0], "zh": t[1], "en": t[2], "hp": t[3], "color": t[4]}
	return {}


static func shape_name(shape: String) -> String:
	return SHAPE_NAMES.get(shape, SHAPE_NAMES["cube"])


static func next_shape(shape: String) -> String:
	var i := SHAPES.find(shape)
	return SHAPES[(i + 1) % SHAPES.size()]


static func is_valid_shape(shape: String) -> bool:
	return SHAPES.has(shape)


## 世界坐标 → 方块本地 0..1 坐标（反向旋转，斜坡/楼梯用）
static func local_point(p: Vector3, cell: Vector3i, rot: int) -> Vector3:
	var q := Vector3(p.x - cell.x - 0.5, 0.0, p.z - cell.z - 0.5)
	q = q.rotated(Vector3.UP, -float(rot) * PI * 0.5)
	return Vector3(q.x + 0.5, 0.0, q.z + 0.5)


## 这种形状在本地 x 处的顶面高度（0..1）
static func top_height(shape: String, rot: int, local: Vector3) -> float:
	var lx := clampf(local.x, 0.0, 1.0)
	match shape:
		"half":
			return 0.5
		"plate":
			return 0.1
		"ramp":
			return lx
		"stairs":
			return clampf(ceilf(lx * 4.0) / 4.0, 0.25, 1.0)
		_:
			return 1.0


static func info(id: String) -> Dictionary:
	var base := base_of(id)
	var row := _base_info(base)
	if row.is_empty():
		return {}
	var shape := shape_of(id)
	if shape == "cube":
		return row
	var out := row.duplicate()
	out["id"] = id
	out["base"] = base
	out["shape"] = shape
	out["zh"] = str(row.zh) + " · " + shape_name(shape)
	return out


## 这个方块是不是工作站；是就返回配方用的 area，不是返回空串
static func station_area(id: String) -> String:
	return STATION_AREAS.get(base_of(id), "")


## 楼和方块共用一个材质（同一份图集，手机上省显存）
static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = POI_SHADER
		var albedo := "%s/atlas_albedo.res" % DIR
		var normal := "%s/atlas_normal.res" % DIR
		if ResourceLoader.exists(albedo):
			var tex: Texture2DArray = load(albedo).to_texture()
			var ntex: Texture2DArray = load(normal).to_texture() if ResourceLoader.exists(normal) else null
			if tex:
				_mat.set_shader_parameter("atlas", tex)
				if ntex:
					_mat.set_shader_parameter("atlas_normal", ntex)
				_mat.set_shader_parameter("use_atlas", true)
	return _mat


static func _layer(id: String) -> Array:
	if not _layers_loaded:
		_layers_loaded = true
		var path := "%s/blocks.json" % DIR
		if FileAccess.file_exists(path):
			var d = JSON.parse_string(FileAccess.get_file_as_string(path))
			if d is Dictionary:
				_layers = d
	return _layers.get(id, [])


## 工作站模型；云盘素材没接上时返回 null
static func _station_mesh(id: String) -> Mesh:
	var path := "res://assets/stationmodels/%s.obj" % id
	if ResourceLoader.exists(path):
		var m = load(path)
		if m is Mesh:
			return m
	return null


## 工作站模型的贴图材质；没有贴图就用木色
static func _station_material(id: String) -> Material:
	if _station_materials.has(id):
		return _station_materials[id]
	var m := StandardMaterial3D.new()
	var path := "res://assets/stationmodels/%s.png" % id
	if ResourceLoader.exists(path):
		m.albedo_texture = load(path)
	else:
		m.albedo_color = info(id).get("color", Color(0.55, 0.4, 0.25))
	m.roughness = 0.95
	_station_materials[id] = m
	return m


## 模型原点在方块中心，摆到格子上要偏半格
static func mesh_offset(id: String) -> Vector3:
	return Vector3(0.5, 0.0, 0.5) if _station_mesh(id) != null else Vector3.ZERO


## 方块的材质：工作站有模型时用模型贴图，否则用方块图集
static func material_for(id: String) -> Material:
	if STATION_MODELS.has(id) and _station_mesh(id) != null:
		return _station_material(id)
	return material()


static func _quad(n: Vector3, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> Dictionary:
	return {"n": n, "p": [a, b, c, d]}


static func _tri(n: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Dictionary:
	return {"n": n, "p": [a, b, c]}


static func _box_faces(lo: Vector3, hi: Vector3, skip_bottom := false) -> Array:
	var x0 := lo.x
	var y0 := lo.y
	var z0 := lo.z
	var x1 := hi.x
	var y1 := hi.y
	var z1 := hi.z
	var out := [
		_quad(Vector3.UP, Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0)),
		_quad(Vector3.RIGHT, Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x1, y0, z1)),
		_quad(Vector3.LEFT, Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0)),
		_quad(Vector3.BACK, Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1)),
		_quad(Vector3.FORWARD, Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y0, z0)),
	]
	if not skip_bottom:
		out.append(_quad(Vector3.DOWN, Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1)))
	return out


static func _faces(shape: String) -> Array:
	match shape:
		"half":
			return _box_faces(Vector3.ZERO, Vector3(1, 0.5, 1))
		"plate":
			return _box_faces(Vector3.ZERO, Vector3(1, 0.1, 1))
		"pole":
			return _box_faces(Vector3(0.4, 0, 0.4), Vector3(0.6, 1, 0.6))
		"ramp":
			return [
				_quad(Vector3.UP + Vector3.LEFT, Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)),
				_quad(Vector3.RIGHT, Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)),
				_tri(Vector3.FORWARD, Vector3(0, 0, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)),
				_tri(Vector3.BACK, Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1)),
				_quad(Vector3.DOWN, Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)),
			]
		"stairs":
			var out := []
			for i in 4:
				var x0 := float(i) * 0.25
				var x1 := float(i + 1) * 0.25
				var y1 := x1
				out.append(_quad(Vector3.UP, Vector3(x0, y1, 0), Vector3(x0, y1, 1), Vector3(x1, y1, 1), Vector3(x1, y1, 0)))
				out.append(_quad(Vector3.FORWARD, Vector3(x0, 0, 0), Vector3(x0, y1, 0), Vector3(x1, y1, 0), Vector3(x1, 0, 0)))
				out.append(_quad(Vector3.BACK, Vector3(x0, 0, 1), Vector3(x1, 0, 1), Vector3(x1, y1, 1), Vector3(x0, y1, 1)))
				if i < 3:
					var prev := float(i) * 0.25
					out.append(_quad(Vector3.RIGHT, Vector3(x1, prev, 0), Vector3(x1, y1, 0), Vector3(x1, y1, 1), Vector3(x1, prev, 1)))
			out.append(_quad(Vector3.RIGHT, Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)))
			out.append(_quad(Vector3.LEFT, Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 0.25, 1), Vector3(0, 0.25, 0)))
			return out
		_:
			return _box_faces(Vector3.ZERO, Vector3.ONE)


static func _rot_point(p: Vector3, rot: int) -> Vector3:
	var c := Vector3(0.5, 0, 0.5)
	return c + Basis(Vector3.UP, float(rot) * PI * 0.5) * (p - c)


static func _rot_normal(n: Vector3, rot: int) -> Vector3:
	return (Basis(Vector3.UP, float(rot) * PI * 0.5) * n).normalized()


static func append_block(st: SurfaceTool, id: String, shape: String, rot: int, cell: Vector3i,
		is_full: Callable) -> void:
	var at := _layer(id)
	var uv2 := Vector2(float(at[0]), float(at[1])) if at.size() >= 2 else Vector2(-1, 1)
	var col: Color = info(id).get("color", Color.GRAY)
	_load_shape_tris()
	var tris: Array = _shape_tris.get(shape, [])
	if not tris.is_empty():
		for tri in tris:
			if not (tri is Array) or tri.size() < 3:
				continue
			var a := Vector3(float(tri[0][0]), float(tri[0][1]), float(tri[0][2]))
			var b := Vector3(float(tri[1][0]), float(tri[1][1]), float(tri[1][2]))
			var c := Vector3(float(tri[2][0]), float(tri[2][1]), float(tri[2][2]))
			# load_glb 转换坐标后绕序反了，法线取反才是朝外
			var n := (c - a).cross(b - a)
			if n.length_squared() < 1e-12:
				continue
			n = n.normalized()
			var rn := _rot_normal(n, rot)
			if shape == "cube" and is_full.call(cell + Vector3i(roundi(rn.x), roundi(rn.y), roundi(rn.z))):
				continue
			var shade := 1.0 if rn.y > 0.5 else (0.7 if rn.y < -0.5 else 0.85)
			for p in [a, b, c]:
				st.set_normal(rn)
				st.set_color(Color(col.r * shade, col.g * shade, col.b * shade))
				st.set_uv(Vector2(p.x + p.z, p.y))
				st.set_uv2(uv2)
				st.add_vertex(_rot_point(p, rot) + Vector3(cell))
		return
	for f in _faces(shape):
		var n: Vector3 = _rot_normal(f["n"], rot)
		if shape == "cube" and is_full.call(cell + Vector3i(roundi(n.x), roundi(n.y), roundi(n.z))):
			continue
		var pts: Array = f["p"]
		var shade := 1.0 if n.y > 0.5 else (0.7 if n.y < -0.5 else 0.85)
		var order := [0, 2, 1, 0, 3, 2] if pts.size() == 4 else [0, 2, 1]
		for k in order:
			var p: Vector3 = _rot_point(pts[k], rot) + Vector3(cell)
			st.set_normal(n)
			st.set_color(Color(col.r * shade, col.g * shade, col.b * shade))
			st.set_uv(Vector2(p.x + p.z, p.y))
			st.set_uv2(uv2)
			st.add_vertex(p)


## 1 米的方块，原点在一个角上（0..1），每个顶点带图集层号（UV2）和底色（COLOR）
static func mesh(id: String, shape := "cube", rot := 0) -> Mesh:
	var key := "%s|%s|%d" % [id, shape, rot]
	if _meshes.has(key):
		return _meshes[key]
	if STATION_MODELS.has(base_of(id)):
		var sm := _station_mesh(id)
		if sm != null:
			_meshes[key] = sm
			return sm
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	append_block(st, id, shape, rot, Vector3i.ZERO, func(_c: Vector3i) -> bool: return false)
	var m := st.commit()
	_meshes[key] = m
	return m


## 一块方块的节点（原点在角上，摆在格子坐标上正好占满这一格）
static func make_node(id: String, shape := "cube", rot := 0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(id, shape, rot)
	mi.material_override = material_for(id)
	return mi


## 背包图标：图集贴图缩成的小图，没有就画个色块
static func icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var tex: Texture2D = null
	var path := "%s/block_%s.png" % [DIR, base_of(id)]
	if ResourceLoader.exists(path):
		tex = load(path)
	if tex == null:
		var col: Color = info(id).get("color", Color.GRAY)
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(col)
		var dark := col.darkened(0.35)
		for i in 64:
			for w in 4:
				img.set_pixel(i, w, dark)
				img.set_pixel(i, 63 - w, dark)
				img.set_pixel(w, i, dark)
				img.set_pixel(63 - w, i, dark)
		tex = ImageTexture.create_from_image(img)
	_icons[id] = tex
	return tex
