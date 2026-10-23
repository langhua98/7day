extends Node
## 读取本地 assets/ 目录：物品表、图标、模型、音乐。
## 物品列表只来自 assets/index/icon_to_model.json，不写死任何物品。

const ROOT := "res://assets"
const INDEX_PATH := "res://assets/index/icon_to_model.json"

enum Kind { MELEE, GUN, FOOD, DRINK, MEDICAL, RESOURCE, OTHER, BLOCK }

## 每项: {id, zh, en, model, icon, kind, power}
var items: Array[Dictionary] = []
var items_by_id := {}
## 能在地上捡到的物品 id，按类别分组
var loot_pool := {}
var zombie_models: PackedStringArray = []
## Exp 探索 / Cbt 战斗 / Sus 紧张 / Bld 血月
var music := {"Exp": PackedStringArray(), "Cbt": PackedStringArray(), "Sus": PackedStringArray(), "Bld": PackedStringArray()}
var errors: PackedStringArray = []

var _models := {}       # 归一化名 -> res 路径（.glb 优先，其次 .obj）
var _item_models := {}  # 归一化名 -> {mesh, texture}（来自 items.zip，带真贴图，优先使用）
var _model_png := {}    # obj 同名贴图
var _icon_files := {}   # 小写名 -> 真实名
var _cache := {}
var _icon_cache := {}
var _key_re := RegEx.create_from_string("(prefab|_?lod\\d+|mesh|[^a-z0-9])")


func _ready() -> void:
	scan()


func scan() -> void:
	items.clear()
	items_by_id.clear()
	loot_pool.clear()
	errors.clear()
	_models.clear()
	_item_models.clear()
	_model_png.clear()
	_icon_files.clear()
	zombie_models.clear()

	for n in _list("%s/icons" % ROOT, ["png"]):
		_icon_files[n.get_basename().to_lower()] = n.get_basename()
	for n in _list("%s/models" % ROOT, ["png"]):
		_model_png[n.get_basename()] = true
	# glb 自带贴图和骨骼，优先使用；没有 glb 再用 obj + 同名 png
	for ext in ["obj", "glb"]:
		for n in _list("%s/models" % ROOT, [ext]):
			_models[model_key(n.get_basename())] = "%s/models/%s" % [ROOT, n]
	var item_index := "%s/index/item_models.json" % ROOT
	if FileAccess.file_exists(item_index):
		var data = JSON.parse_string(FileAccess.get_file_as_string(item_index))
		if data is Dictionary:
			for k in data:
				var e: Dictionary = data[k]
				if ResourceLoader.exists("%s/%s" % [ROOT, e.get("mesh", "")]):
					_item_models[model_key(k)] = e
	var zseen := {}
	for n in _list("%s/models" % ROOT, ["glb", "obj"]):
		var base := n.get_basename()
		if base.to_lower().contains("zombie") and not zseen.has(base):
			zseen[base] = true
			zombie_models.append(base)

	for key in music.keys():
		music[key] = PackedStringArray()
	for f in _list("%s/music" % ROOT, ["wav", "ogg", "mp3"]):
		var low := f.to_lower()
		for key in music.keys():
			if low.contains(key.to_lower()):
				music[key].append("%s/music/%s" % [ROOT, f])
				break

	_load_index()
	_add_blocks()

	if zombie_models.is_empty():
		errors.append("assets/models/ 里没有文件名含 zombie 的模型")
	for key in ["Exp", "Cbt", "Sus"]:
		if music[key].is_empty():
			errors.append("assets/music/ 里没有 %s 音乐" % key)


## 列出目录里某些扩展名的文件。导出到 iPhone 后原文件会变成 .import/.remap，这里统一还原成原名。
func _list(dir: String, exts: Array) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		var name := f.trim_suffix(".remap").trim_suffix(".import")
		if exts.has(name.get_extension().to_lower()) and not out.has(name):
			out.append(name)
	out.sort()
	return out


## 物品表里的模型名是 prefab 名（如 chainsawPrefab），导出的文件名是网格名（如 Chainsaw_LOD0），
## 两边都去掉 Prefab / _LOD0 / Mesh 和符号后再比对。
func model_key(name: String) -> String:
	return _key_re.sub(name.to_lower(), "", true)


func has_model(name: String) -> bool:
	return name != "" and (_item_models.has(model_key(name)) or _models.has(model_key(name)))


## 物品模型原样（保留原点，七日杀物品的原点就是握把位置），带真贴图。没有就返回 null。
func make_item_mesh(name: String, tint := Color(0.55, 0.53, 0.5)) -> Node3D:
	var e: Dictionary = _item_models.get(model_key(name), {})
	if e.is_empty():
		return null
	var mesh = _cached_load("%s/%s" % [ROOT, e.mesh])
	if not (mesh is Mesh):
		return null
	var key := "%s#itemmat" % e.get("texture", str(tint))
	if not _cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.75
		if e.has("texture"):
			mat.albedo_texture = _cached_load("%s/%s" % [ROOT, e.texture])
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		else:
			mat.albedo_color = tint
		_cache[key] = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _cache[key]
	return mi


func _load_index() -> void:
	if not FileAccess.file_exists(INDEX_PATH):
		errors.append("找不到 assets/index/icon_to_model.json")
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(INDEX_PATH)) != OK:
		errors.append("icon_to_model.json 第 %d 行解析失败：%s" % [json.get_error_line(), json.get_error_message()])
		return
	for row in normalize_index(json.data):
		if not has_model(row.model):
			row.model = ""
		row.icon = _icon_files.get(row.id.to_lower(), "")
		if row.model == "" and row.icon == "":
			continue  # 没有任何素材的物品不进游戏
		_classify(row)
		items.append(row)
		items_by_id[row.id] = row
		if row.kind != Kind.OTHER:
			if not loot_pool.has(row.kind):
				loot_pool[row.kind] = []
			loot_pool[row.kind].append(row.id)
	if loot_pool.is_empty():
		errors.append("icon_to_model.json 里没有能匹配到图标或模型的武器、食物、药品")


## 建造方块（scripts/blocks.gd）也当物品放进物品表；物品表里有同名图标就用游戏的图标
func _add_blocks() -> void:
	for t in Blocks.TYPES:
		var id: String = t[0]
		var row: Dictionary = items_by_id.get(id, {})
		if row.is_empty():
			row = {"id": id, "zh": t[1], "en": t[2], "model": "", "icon": _icon_files.get(id.to_lower(), "")}
			items.append(row)
			items_by_id[id] = row
		else:
			for k in loot_pool:
				loot_pool[k].erase(id)
		if row.zh == "":
			row.zh = t[1]
		row.model = ""
		row.kind = Kind.BLOCK
		row.power = 0.0


## 把各种可能的写法统一成 {id, zh, en, model}。主要格式是 [物品名, 中文名, 英文名, 模型名]。
static func normalize_index(data) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var seen := {}
	var source: Array = []
	if data is Array:
		for r in data:
			source.append([null, r])
	elif data is Dictionary:
		var inner = null
		for k in ["items", "data", "rows"]:
			if data.has(k) and data[k] is Array:
				inner = data[k]
				break
		if inner != null:
			for r in inner:
				source.append([null, r])
		else:
			for k in data.keys():
				source.append([str(k), data[k]])
	for pair in source:
		var row := _row(pair[0], pair[1])
		if row.is_empty() or row.id == "" or seen.has(row.id):
			continue
		seen[row.id] = true
		rows.append(row)
	return rows


static func _clean(v) -> String:
	return "" if v == null else str(v).strip_edges()


static func _clean_model(v) -> String:
	var s := _clean(v)
	var low := s.to_lower()
	if low.ends_with(".obj") or low.ends_with(".glb"):
		s = s.get_basename()
	if s == "-" or low == "null" or low == "none":
		return ""
	return s


static func _row(key, r) -> Dictionary:
	if r is Array:
		var a: Array = r.duplicate()
		if key != null and a.size() == 3:
			a.push_front(key)
		while a.size() < 4:
			a.append("")
		return {"id": _clean(a[0]), "zh": _clean(a[1]), "en": _clean(a[2]), "model": _clean_model(a[3])}
	if r is Dictionary:
		var pick := func(keys: Array):
			for k in keys:
				if r.has(k):
					return r[k]
			return null
		var id = pick.call(["item", "id", "name", "icon", "物品名"])
		return {
			"id": _clean(id if id != null else key),
			"zh": _clean(pick.call(["zh", "cn", "chinese", "name_zh", "中文名"])),
			"en": _clean(pick.call(["en", "english", "name_en", "英文名"])),
			"model": _clean_model(pick.call(["model", "mesh", "模型名"])),
		}
	if r is String and key != null:
		return {"id": _clean(key), "zh": "", "en": "", "model": _clean_model(r)}
	return {}


# —— 物品分类：按七日杀物品名的前缀判断（melee/gun/food/drink/medical/resource），不针对具体物品 ——

const MELEE_POWER := {
	"chainsaw": 46.0, "sledge": 48.0, "machete": 34.0, "sword": 32.0, "fireaxe": 32.0, "axe": 26.0,
	"spear": 24.0, "pick": 24.0, "bat": 22.0, "baton": 24.0, "club": 20.0,
	"knife": 16.0, "pipe": 16.0, "shovel": 16.0, "hammer": 15.0, "wrench": 14.0, "knuckle": 13.0,
}
const SKIP_WORDS := ["admin", "test", "master", "dev", "poi", "schematic", "quest"]


func _classify(row: Dictionary) -> void:
	var id: String = row.id.to_lower()
	row.kind = Kind.OTHER
	row.power = 0.0
	for w in SKIP_WORDS:
		if id.contains(w):
			return
	if id.ends_with("parts"):
		row.kind = Kind.RESOURCE   # 枪的零件
	elif id.begins_with("gunbot"):
		return                      # 机器人炮台，不是拿在手上的枪
	elif id.begins_with("gun"):
		row.kind = Kind.GUN
		row.power = GameConfig.GUN_DAMAGE
	elif id.begins_with("melee"):
		row.kind = Kind.MELEE
		row.power = 18.0
		var best := 0
		for word in MELEE_POWER:
			if id.contains(word) and word.length() > best:
				best = word.length()
				row.power = MELEE_POWER[word]
	elif id.begins_with("medical"):
		row.kind = Kind.MEDICAL
		row.power = 35.0
	elif id.begins_with("drinkingfountain") or id == "drinkJarEmpty":
		row.kind = Kind.RESOURCE
	elif id.begins_with("drink"):
		row.kind = Kind.DRINK
		row.power = 25.0
	elif id.begins_with("food"):
		row.kind = Kind.FOOD
		row.power = 35.0
	elif id.begins_with("resource") or id.begins_with("ammo"):
		row.kind = Kind.RESOURCE


## 测试模式补全道具：没有图标/模型的官方物品也建一行，背包里至少能看到名字
func ensure_item(id: String, zh: String, en := "") -> Dictionary:
	if items_by_id.has(id):
		return items_by_id[id]
	var row := {"id": id, "zh": zh, "en": en, "model": "", "icon": _icon_files.get(id.to_lower(), ""),
		"kind": Kind.OTHER, "power": 0.0}
	_classify(row)
	items_by_id[id] = row
	return row


func display_name(id: String) -> String:
	var row: Dictionary = items_by_id.get(id, {})
	if row.is_empty():
		return id
	if row.zh != "":
		return row.zh
	return row.en if row.en != "" else row.id


## 不同容器掉的东西不一样：垃圾桶多是材料，购物车多是吃的，警车里有枪
const LOOT_WEIGHTS := {
	"any": {Kind.MELEE: 18, Kind.GUN: 8, Kind.FOOD: 22, Kind.DRINK: 16, Kind.MEDICAL: 14, Kind.RESOURCE: 22},
	"trash": {Kind.MELEE: 6, Kind.FOOD: 20, Kind.DRINK: 12, Kind.MEDICAL: 4, Kind.RESOURCE: 58},
	"food": {Kind.FOOD: 70, Kind.DRINK: 25, Kind.RESOURCE: 5},
	"drink": {Kind.DRINK: 80, Kind.FOOD: 20},
	"medical": {Kind.MEDICAL: 70, Kind.FOOD: 10, Kind.DRINK: 10, Kind.RESOURCE: 10},
	"weapon": {Kind.MELEE: 35, Kind.GUN: 30, Kind.RESOURCE: 35},
	"tool": {Kind.MELEE: 45, Kind.RESOURCE: 55},
}


func random_loot(rng: RandomNumberGenerator, tag := "any") -> String:
	if loot_pool.is_empty():
		return ""
	var weights: Dictionary = LOOT_WEIGHTS.get(tag, LOOT_WEIGHTS["any"])
	var total := 0
	for k in loot_pool:
		total += weights.get(k, 0)
	if total <= 0:
		return random_loot(rng) if tag != "any" else ""
	var r := rng.randi_range(0, total - 1)
	for k in loot_pool:
		r -= weights.get(k, 0)
		if r < 0:
			var list: Array = loot_pool[k]
			return list[rng.randi_range(0, list.size() - 1)]
	return ""


# —— 资源加载 ——

func icon(id: String) -> Texture2D:
	var row: Dictionary = items_by_id.get(id, {})
	if row.get("kind", -1) == Kind.BLOCK and row.icon == "":
		return Blocks.icon(id)
	if row.is_empty() or row.icon == "":
		return null
	if not _icon_cache.has(id):
		_icon_cache[id] = load("%s/icons/%s.png" % [ROOT, row.icon])
	return _icon_cache[id]


## 生成一个模型实例，底部中心对齐原点。
## size > 0 时按高度（by_height）或最长边缩放到 size 米；size <= 0 保持原始尺寸（七日杀模型本身就是米）。
## tint：模型没带贴图时用的底色（物品用图标的平均色）。
func make_model(name: String, size: float, by_height := false, tint := Color(0.55, 0.53, 0.5)) -> Node3D:
	var path: String = _models.get(model_key(name), "")
	var inst: Node3D = make_item_mesh(name, tint)
	if inst == null and path == "":
		return null
	if inst != null:
		pass
	elif path.ends_with(".glb"):
		var scene = _cached_load(path)
		if scene is PackedScene:
			inst = scene.instantiate()
			fix_materials(inst, path.get_file().get_basename(), tint)
	else:
		inst = _obj_instance(path)
	if inst == null:
		push_warning("模型加载失败: %s" % path)
		return null
	var aabb := _bounds(inst, Transform3D.IDENTITY)
	if aabb.size == Vector3.ZERO:
		aabb = AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	var extent: float = aabb.size.y if by_height else max(aabb.size.x, aabb.size.y, aabb.size.z)
	var s: float = 1.0 if size <= 0.0 else size / max(extent, 0.0001)
	var root := Node3D.new()
	root.name = name
	var c := aabb.get_center()
	inst.scale = Vector3.ONE * s
	inst.position = Vector3(-c.x, -aabb.position.y, -c.z) * s
	root.add_child(inst)
	root.set_meta("height", aabb.size.y * s)
	root.set_meta("extent", max(aabb.size.x, aabb.size.y, aabb.size.z) * s)
	return root


## 有的导出 glb 没把贴图打包进去（只有 2×2 的灰色占位或干脆没有）。
## 这时找同名 png（assets/models/<名字>.png 或 assets/textures/ 里名字对得上的），找不到就用底色。
func fix_materials(root: Node, name: String, tint: Color, extra_textures: Array = []) -> void:
	var key := "%s#fix" % name
	if not _cache.has(key):
		var tex: Texture2D = null
		var candidates: Array = ["%s/models/%s.png" % [ROOT, name]]
		for t in extra_textures:
			candidates.append("%s/textures/%s" % [ROOT, t])
		var tex_key := model_key(name)
		for f in _list("%s/textures" % ROOT, ["png"]):
			if model_key(f.get_basename().trim_suffix("_d")) == tex_key:
				candidates.append("%s/textures/%s" % [ROOT, f])
		for c in candidates:
			if ResourceLoader.exists(c):
				tex = load(c)
				break
		_cache[key] = tex
	var override: Texture2D = _cache[key]
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if not (mat is StandardMaterial3D):
				continue
			var sm := mat as StandardMaterial3D
			var has_real := sm.albedo_texture != null and sm.albedo_texture.get_width() > 8
			var fixed := sm.duplicate() as StandardMaterial3D
			fixed.albedo_color = Color.WHITE  # 导出时底色被压成 0.4，还原
			if not has_real:
				if override:
					fixed.albedo_texture = override
				else:
					fixed.albedo_texture = null
					fixed.albedo_color = tint
			m.set_surface_override_material(i, fixed)


## 图标的平均颜色，给没贴图的物品模型上色
func icon_tint(id: String) -> Color:
	var key := "%s#tint" % id
	if _cache.has(key):
		return _cache[key]
	var c := Color(0.55, 0.53, 0.5)
	var tex := icon(id)
	if tex:
		var img := tex.get_image()
		if img:
			if img.is_compressed():
				img.decompress()
			var sum := Vector3.ZERO
			var n := 0.0
			var step: int = max(1, img.get_width() / 24)
			for y in range(0, img.get_height(), step):
				for x in range(0, img.get_width(), step):
					var p := img.get_pixel(x, y)
					if p.a > 0.5:
						sum += Vector3(p.r, p.g, p.b)
						n += 1.0
			if n > 0:
				sum /= n
				c = Color(sum.x, sum.y, sum.z)
	_cache[key] = c
	return c


func _cached_load(path: String):
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


func _obj_instance(path: String) -> Node3D:
	var res = _cached_load(path)
	var mesh: Mesh = null
	if res is Mesh:
		mesh = res
	elif res is PackedScene:
		return res.instantiate()
	if mesh == null:
		return null
	var key := path + "#mat"
	if not _cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.9
		var base := path.get_file().get_basename()
		if _model_png.has(base):
			mat.albedo_texture = load("%s/models/%s.png" % [ROOT, base])
			if GameConfig.ALPHA_CUTOUT:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mat.alpha_scissor_threshold = 0.4
		_cache[key] = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _cache[key]
	return mi


## 不进场景树也能算包围盒：沿着节点树累乘变换。
## 带骨骼的模型网格是绑定姿势下的坐标（有的是 Z 朝上），不可靠，改用骨骼位置算。
func _bounds(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is Skeleton3D and (n as Skeleton3D).get_bone_count() > 0:
		var sk := n as Skeleton3D
		for i in sk.get_bone_count():
			var p := here * sk.get_bone_global_rest(i).origin
			if first:
				out = AABB(p, Vector3.ZERO)
				first = false
			else:
				out = out.expand(p)
		# 头骨在头的底部，往上补一点；四周补一点身体厚度
		out = out.grow(0.08)
		out.position.y += 0.08  # 脚底不补，免得悬空
		out.size.y += 0.04
		return out
	if n is MeshInstance3D and (n as MeshInstance3D).mesh and (n as MeshInstance3D).skin == null:
		out = here * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		var b := _bounds(c, here)
		if b.size == Vector3.ZERO:
			continue
		out = b if first else out.merge(b)
		first = false
	return out


## 物品的 3D 外观：有模型用模型，没有模型用它的图标（立在地上的贴片）
func make_item_visual(id: String, size: float) -> Node3D:
	var row: Dictionary = items_by_id.get(id, {})
	if row.is_empty():
		return null
	if row.model != "":
		# 带真贴图的物品按真实大小（放大一点，地上好找）；样例模型统一缩放
		var real := _item_models.has(model_key(row.model))
		var m := make_model(row.model, 0.0 if real else size, false, icon_tint(id))
		if m and real:
			var ext: float = m.get_meta("extent", size)
			var want: float = clamp(ext * 1.5, size * 0.6, size * 1.6)
			m.scale = Vector3.ONE * want / max(ext, 0.001)
		if m:
			return m
	var tex := icon(id)
	if tex == null:
		return null
	var holder := Node3D.new()
	var sprite := Sprite3D.new()
	sprite.texture = tex
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = false
	sprite.pixel_size = size / max(tex.get_width(), 1)
	sprite.position.y = size * 0.5
	holder.add_child(sprite)
	return holder
