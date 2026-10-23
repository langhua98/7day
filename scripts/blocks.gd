class_name Blocks
## 建造方块：背包里拿一种方块在手上，点「攻击」就在准星指的地方摆一块 1 米的方块；
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
	["cntWoodWritableCrate", "可写木箱（储物箱）", "Writable Storage Box", 120.0, Color(0.62, 0.44, 0.24)],
]

static var _mat: ShaderMaterial
static var _layers := {}     # 方块名 -> [图集层号, 占几格]
static var _layers_loaded := false
static var _meshes := {}
static var _icons := {}


static func is_block(id: String) -> bool:
	return not info(id).is_empty()


static func info(id: String) -> Dictionary:
	for t in TYPES:
		if t[0] == id:
			return {"id": t[0], "zh": t[1], "en": t[2], "hp": t[3], "color": t[4]}
	return {}


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


## 1 米的方块，原点在一个角上（0..1），每个顶点带图集层号（UV2）和底色（COLOR）
static func mesh(id: String) -> Mesh:
	if _meshes.has(id):
		return _meshes[id]
	var at := _layer(id)
	var uv2 := Vector2(float(at[0]), float(at[1])) if at.size() >= 2 else Vector2(-1, 1)
	var col: Color = info(id).get("color", Color.GRAY)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 每个面：法线 + 四个角（从外面看逆时针）
	var faces := [
		[Vector3.UP, [Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)]],
		[Vector3.DOWN, [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]],
		[Vector3.RIGHT, [Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)]],
		[Vector3.LEFT, [Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)]],
		[Vector3.BACK, [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)]],
		[Vector3.FORWARD, [Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)]],
	]
	var shade := {Vector3.UP: 1.0, Vector3.DOWN: 0.7}
	for f in faces:
		var n: Vector3 = f[0]
		var c: Array = f[1]
		var s: float = shade.get(n, 0.85)
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n)
			st.set_color(Color(col.r * s, col.g * s, col.b * s))
			st.set_uv(Vector2(c[k].x + c[k].z, c[k].y))
			st.set_uv2(uv2)
			st.add_vertex(c[k])
	var m := st.commit()
	_meshes[id] = m
	return m


## 一块方块的节点（原点在角上，摆在格子坐标上正好占满这一格）
static func make_node(id: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(id)
	mi.material_override = material()
	return mi


## 背包图标：图集贴图缩成的小图，没有就画个色块
static func icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var tex: Texture2D = null
	var path := "%s/block_%s.png" % [DIR, id]
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
