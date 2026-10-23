extends SceneTree
## 把七日杀建筑的远景网格（assets/poi/*.poimesh，原文件扩展名是 .mesh）转成 Godot 网格（assets/poi/*.res），
## 并写 assets/poi/index.json（尺寸、地面高度等）。
## 用法：godot --headless --path . -s tools/build_poi.gd
## 有 assets/blocks（fetch_assets.py 取的方块贴图）时，顺便打包成图集 assets/poi/atlas_albedo.res、atlas_normal.res，
## 并把每个顶点的贴图编号换成图集层号（UV2.x = 起始层，UV2.y = 大贴图占几格；-1 = 没贴图，用顶点颜色）。
##
## .mesh 格式（游戏自带的远景简化网格，"hsem" 第 7 版）：
##   "hsem" u8 版本 u16 分块数，每块：u8 长度+块名、u32 n + n 个 float xyz、
##   u32 n + n 个 (u16 方块贴图号, u16 256+角, u16, u16)、u32 m + m 个 u16 三角形下标。
##   之后是招牌之类的附加数据，用不到。

const DIR := "res://assets/poi"
const BLOCKS := "res://assets/blocks"
const IMAGE_LAYERS := preload("res://scripts/image_layers.gd")
const CORNERS := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]

var atlas_ids := {}   # 贴图编号 → [起始层, 横向格数, 纵向格数]


func _init() -> void:
	_build_atlas()
	var index := {}
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".poimesh"):
			continue
		var name := f.get_basename()
		var info := _convert(name)
		if not info.is_empty():
			index[name] = info
			print("%s: %d 顶点" % [name, info.verts])
	var out := FileAccess.open(DIR + "/index.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(index, " "))
	out.close()
	print("建筑网格: %d 栋" % index.size())
	quit()


func _convert(name: String) -> Dictionary:
	var data := FileAccess.get_file_as_bytes("%s/%s.poimesh" % [DIR, name])
	if data.size() < 8 or data.slice(0, 4).get_string_from_ascii() != "hsem":
		push_warning("%s 不是远景网格" % name)
		return {}
	var p := 5
	var chunks := data.decode_u16(p)
	p += 2
	var mesh := ArrayMesh.new()
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var total := 0
	var tex_ids := {}
	var chunk_data := []
	for c in chunks:
		var l := data[p]
		p += 1 + l
		var nv := data.decode_u32(p)
		p += 4
		var floats := data.slice(p, p + nv * 12).to_float32_array()
		p += nv * 12
		var na := data.decode_u32(p)
		p += 4
		var attrs := data.slice(p, p + na * 8).to_int32_array()   # 每顶点两个 int32 = 四个 u16
		p += na * 8
		var ni := data.decode_u32(p)
		p += 4
		var raw_idx := data.slice(p, p + ni * 2)
		p += ni * 2
		if nv == 0 or ni == 0:
			continue
		var verts := PackedVector3Array()
		verts.resize(nv)
		var uvs := PackedVector2Array()
		uvs.resize(nv)
		var uv2 := PackedVector2Array()
		uv2.resize(nv)
		var colors := PackedColorArray()
		colors.resize(nv)
		for i in nv:
			# Unity 是左手坐标系，翻转 x 变成 Godot 的右手坐标系
			var v := Vector3(-floats[i * 3], floats[i * 3 + 1], floats[i * 3 + 2])
			verts[i] = v
			lo = lo.min(v)
			hi = hi.max(v)
			var a: int = attrs[i * 2] if i < na else 0
			var tex := a & 0xffff
			var corner := ((a >> 16) & 0xffff) - 256
			uvs[i] = CORNERS[clampi(corner, 0, 3)]
			var at: Array = atlas_ids.get(str(tex), [])
			uv2[i] = Vector2(at[0], at[1]) if at.size() >= 2 else Vector2(-1, 1)
			colors[i] = _palette(tex)
			tex_ids[tex] = true
		var idx := PackedInt32Array()
		idx.resize(ni)
		for t in ni:
			idx[t] = raw_idx.decode_u16(t * 2)
		chunk_data.append([verts, idx])
		var normals := PackedVector3Array()
		normals.resize(nv)
		for t in range(0, ni - 2, 3):
			var a := verts[idx[t]]
			var n := (verts[idx[t + 1]] - a).cross(verts[idx[t + 2]] - a)
			for k in 3:
				normals[idx[t + k]] += n
		for i in nv:
			# 翻转 x 后三角形绕向反了，叉乘出来的法线朝里，取反让它朝外（否则阴影会出条纹）
			normals[i] = -normals[i].normalized() if normals[i].length() > 0.0 else Vector3.UP
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		total += nv
	if mesh.get_surface_count() == 0:
		return {}
	ResourceSaver.save(mesh, "%s/%s.res" % [DIR, name], ResourceSaver.FLAG_COMPRESS)
	var xml := FileAccess.get_file_as_string("%s/%s.xml" % [DIR, name])
	var fp := _footprint(chunk_data, lo, hi)
	return {
		"ground": lo.y, "grid_origin": [floorf(lo.x), floorf(lo.z)], "grid_w": fp[0], "grid_h": fp[1], "grid": fp[2],
		"verts": total,
		"min": [lo.x, lo.y, lo.z], "max": [hi.x, hi.y, hi.z],
		"size": _prop(xml, "PrefabSize"), "yoffset": _prop(xml, "YOffset"),
		"zoning": _prop(xml, "Zoning"), "tier": _prop(xml, "DifficultyTier"),
		"textures": tex_ids.keys(),
	}


## 挡路的格子（1 米一格）：人身高范围内有墙的格子，加上头顶有楼板/屋顶的格子（楼里面）。
## 返回 [宽, 高, 每行一个 "0/1" 字符串拼起来]
func _footprint(chunk_data: Array, lo: Vector3, hi: Vector3) -> Array:
	var ox := floorf(lo.x)
	var oz := floorf(lo.z)
	var w := int(ceilf(hi.x) - ox) + 1
	var h := int(ceilf(hi.z) - oz) + 1
	var cells := PackedByteArray()
	cells.resize(w * h)
	var y0 := lo.y + 0.4
	var y1 := lo.y + 2.2
	for cd in chunk_data:
		var verts: PackedVector3Array = cd[0]
		var idx: PackedInt32Array = cd[1]
		for t in range(0, idx.size() - 2, 3):
			var a := verts[idx[t]]
			var b := verts[idx[t + 1]]
			var c := verts[idx[t + 2]]
			var mn := a.min(b).min(c)
			var mx := a.max(b).max(c)
			var flat := mx.y - mn.y < 0.05
			if flat:
				# 头顶 3 米以上的楼板、屋顶：下面是楼里面
				if mn.y < lo.y + 3.0:
					continue
			elif mx.y < y0 or mn.y > y1:
				continue
			for x in range(int(floorf(mn.x - ox + (0.01 if flat else -0.01))), int(floorf(mx.x - ox - (0.01 if flat else -0.01))) + 1):
				for z in range(int(floorf(mn.z - oz + (0.01 if flat else -0.01))), int(floorf(mx.z - oz - (0.01 if flat else -0.01))) + 1):
					if x >= 0 and z >= 0 and x < w and z < h:
						cells[z * w + x] = 1
	var rows := ""
	for i in w * h:
		rows += "1" if cells[i] == 1 else "0"
	return [w, h, rows]


## 方块贴图 → 图层组（颜色和法线各一个，游戏里拼成 Texture2DArray），压缩成 ETC2 省手机显存
func _build_atlas() -> void:
	var path := ProjectSettings.globalize_path(BLOCKS)
	var info = JSON.parse_string(FileAccess.get_file_as_string(BLOCKS + "/atlas.json")) if FileAccess.file_exists(BLOCKS + "/atlas.json") else null
	if not (info is Dictionary) or int(info.get("layers", 0)) == 0:
		print("没有方块贴图（assets/blocks），楼用纯色")
		return
	atlas_ids = info.ids
	var n := int(info.layers)
	for kind in [["c", "albedo"], ["n", "normal"]]:
		var images: Array[Image] = []
		for i in n:
			var img := Image.load_from_file("%s/%s_%03d.png" % [path, kind[0], i])
			img.convert(Image.FORMAT_RGB8)
			img.generate_mipmaps(kind[0] == "n")
			if kind[0] == "n":
				img.compress(Image.COMPRESS_ETC2, Image.COMPRESS_SOURCE_NORMAL)
			else:
				img.compress(Image.COMPRESS_ETC2, Image.COMPRESS_SOURCE_SRGB)
			images.append(img)
		var res: Resource = IMAGE_LAYERS.new()
		res.images = images
		ResourceSaver.save(res, "%s/atlas_%s.res" % [DIR, kind[1]], ResourceSaver.FLAG_COMPRESS)
	print("方块图集: %d 种贴图，%d 层" % [atlas_ids.size(), n])
	_build_block_index(info.get("blocks", {}), path)


## 建造方块（scripts/blocks.gd）：方块名 → [图集层号, 占几格]，写到 assets/poi/blocks.json；
## 顺便把贴图缩成小图 block_<方块名>.png，当背包图标
func _build_block_index(blocks: Dictionary, path: String) -> void:
	var out := {}
	for name in blocks:
		var at: Array = atlas_ids.get(str(int(blocks[name])), [])
		if at.is_empty():
			continue
		out[name] = [int(at[0]), int(at[1])]
		var img := Image.load_from_file("%s/c_%03d.png" % [path, int(at[0])])
		if img:
			img.resize(96, 96, Image.INTERPOLATE_LANCZOS)
			img.save_png(ProjectSettings.globalize_path("%s/block_%s.png" % [DIR, name]))
	var f := FileAccess.open(DIR + "/blocks.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	print("建造方块贴图: %d 种" % out.size())


func _prop(xml: String, key: String) -> String:
	var re := RegEx.create_from_string("name=\"%s\" value=\"([^\"]*)\"" % key)
	var m := re.search(xml)
	return m.get_string(1) if m else ""


## 还没有方块贴图时，按贴图号给一个旧城区常见的颜色（灰、米、砖红、深棕）
func _palette(tex: int) -> Color:
	var tones := [Color(0.62, 0.61, 0.58), Color(0.72, 0.68, 0.6), Color(0.55, 0.36, 0.3), Color(0.45, 0.42, 0.4),
		Color(0.36, 0.3, 0.26), Color(0.7, 0.7, 0.7), Color(0.5, 0.52, 0.55), Color(0.62, 0.5, 0.4)]
	var h := (tex * 2654435761) & 0xffffffff
	var c: Color = tones[h % tones.size()]
	var v := 0.9 + float((h >> 8) % 20) / 100.0
	return Color(c.r * v, c.g * v, c.b * v)
