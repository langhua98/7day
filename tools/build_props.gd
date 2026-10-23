extends SceneTree
## 楼里的家具、灯、柜子、门：每个预制体的 glb（assets/poipropsrc/，fetch_assets.py 取的）合成一个网格，
## 存成 assets/poiprops/<名字>.res，游戏里按方块位置用 MultiMesh 摆。
## 用法（导入素材之后）：godot --headless --path . -s tools/build_props.gd
##
## glb 保留了预制体的子节点层级。合并时：
##   - 几级 LOD 只留一级（LOD0 面数多时用 LOD1，手机上楼里东西多）
##   - 损坏状态只留完好的（DMG0）
##   - 门只留门板（门框是墙的一部分，门板要会转）
## 坐标：glb 是 glTF 右手系，正好就是楼网格的本地坐标（游戏的 x 翻过来），原点在方块中心。

const INDEX := "res://assets/poi/props.json"
const OUT := "res://assets/poiprops"
const LOD0_MAX_TRIS := 1200
const LOD_RE := "(?i)lod_?(\\d)"

var _lod := RegEx.new()
var _dmg := RegEx.new()


func _init() -> void:
	_lod.compile(LOD_RE)
	_dmg.compile("(?i)dmg_?([1-9])")
	if not FileAccess.file_exists(INDEX):
		print("没有 props.json，跳过")
		quit()
		return
	var idx = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	DirAccess.make_dir_recursive_absolute(OUT)
	var made := 0
	var failed := []
	for key in idx.models:
		var info: Dictionary = idx.models[key]
		var path: String = "res://assets/" + str(info.mesh)
		var src: String = "res://assets/" + str(info.src)
		if ResourceLoader.exists(path) and FileAccess.get_modified_time(path) >= FileAccess.get_modified_time(src):
			made += 1
			continue
		var mesh := _merge(src, bool(info.get("door", false)))
		if mesh == null:
			failed.append(key)
			continue
		if ResourceSaver.save(mesh, path) == OK:
			made += 1
		else:
			failed.append(key)
	print("楼里的模型: 合成 %d 个，失败 %d 个 %s" % [made, failed.size(), str(failed.slice(0, 10))])
	quit()


func _merge(src: String, door: bool) -> ArrayMesh:
	var ps = load(src)
	if not (ps is PackedScene):
		return null
	var root_node: Node = ps.instantiate()
	var parts := []   # [MeshInstance3D, LOD 级别（-1 没标）, 变换]
	_collect(root_node, Transform3D.IDENTITY, -1, door, parts, false)
	if parts.is_empty():
		root_node.free()
		return null
	# 选一级 LOD
	var tris := {}
	for p in parts:
		var m: Mesh = p[0].mesh
		var n := 0
		for s in m.get_surface_count():
			var ia = m.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
			n += (ia.size() if ia != null else m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()) / 3
		tris[p[1]] = tris.get(p[1], 0) + n
	var levels := tris.keys().filter(func(l): return l >= 0)
	levels.sort()
	var pick := -1
	if not levels.is_empty():
		pick = levels[0]
		if pick == 0 and levels.has(1) and tris[0] > LOD0_MAX_TRIS:
			pick = 1
	# 同一个材质的面合成一个面组
	var groups := {}   # 材质 -> SurfaceTool
	var order := []
	for p in parts:
		if p[1] >= 0 and p[1] != pick:
			continue
		var mi: MeshInstance3D = p[0]
		var m: Mesh = mi.mesh
		for s in m.get_surface_count():
			if m.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var mat: Material = mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.material_override if mi.material_override else m.surface_get_material(s)
			if not groups.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[mat] = st
				order.append(mat)
			(groups[mat] as SurfaceTool).append_from(m, s, p[2])
	root_node.free()
	if order.is_empty():
		return null
	# 自动生成几级简化网格（远一点的块用面数少的）；没有法线贴图，不要切线
	var im := ImporterMesh.new()
	for mat in order:
		var st: SurfaceTool = groups[mat]
		st.index()
		var arr := st.commit_to_arrays()
		arr[Mesh.ARRAY_TANGENT] = null
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, mat)
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


func _collect(n: Node, xf: Transform3D, lod: int, door: bool, parts: Array, skip: bool) -> void:
	var nm := String(n.name)
	if n is Node3D:
		xf = xf * (n as Node3D).transform
		if not (n as Node3D).visible:
			return
	var low := nm.to_lower()
	if _dmg.search(nm) or "collider" in low or "collision" in low or "shadow" in low:
		return
	if door and "frame" in low:
		return
	var m := _lod.search(nm)
	if m:
		lod = int(m.get_string(1))
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		parts.append([n, lod, xf])
	for c in n.get_children():
		_collect(c, xf, lod, door, parts, skip)
