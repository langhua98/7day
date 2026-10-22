class_name FpArms
extends Node3D
## 第一人称手臂：用导出的 FP_ARM 模型（T 字姿势的两条小臂），
## 运行时按左右拆开，摆成从屏幕下方伸出来的样子，右手拿武器。

var _right_pivot := Node3D.new()
var _left_pivot := Node3D.new()
var _hand := Node3D.new()        # 右手掌心位置，武器挂在这里
var _weapon: Node3D
var _swing := 0.0                 # 0..1 挥动进度
var _swing_speed := 3.0
var _bob := 0.0
var _arm_len := 0.5
var has_arms := false

## 手臂摆放（相机空间：x 右、y 上、-z 前）。模型是整条胳膊（肩到指尖约 0.78 米），
## 所以把肩膀那头放在镜头后下方，只露出小臂和手。拿到真机上不顺眼可以改这里。
const RIGHT_SHOULDER := Vector3(0.32, -0.34, 0.30)
const RIGHT_DIR := Vector3(-0.14, 0.32, -1.0)
const LEFT_SHOULDER := Vector3(-0.36, -0.40, 0.30)
const LEFT_DIR := Vector3(0.18, 0.30, -1.0)
## 绕手臂自身转多少（弧度），用来让手掌朝内
const RIGHT_ROLL := -1.4
const LEFT_ROLL := 0.5


func _ready() -> void:
	add_child(_right_pivot)
	add_child(_left_pivot)
	_build()


func _build() -> void:
	var src := Assets.make_model(GameConfig.FP_ARMS_MODEL, 0.0)
	if src == null:
		push_warning("没找到第一人称手臂模型 %s，只显示武器" % GameConfig.FP_ARMS_MODEL)
		_right_pivot.position = RIGHT_SHOULDER
		_right_pivot.basis = _aim_basis(RIGHT_DIR, RIGHT_ROLL)
		_hand.position = Vector3(0.35, 0, 0)
		_right_pivot.add_child(_hand)
		return
	var mis := src.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		src.free()
		return
	var mi: MeshInstance3D = mis[0]
	Assets.fix_materials(src, GameConfig.FP_ARMS_MODEL, Color(0.72, 0.58, 0.48), GameConfig.FP_ARMS_TEXTURES)
	var mat: Material = mi.get_surface_override_material(0)
	if mat == null:
		mat = mi.get_active_material(0)
	if mat is StandardMaterial3D:
		mat = mat.duplicate()
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.disable_receive_shadows = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	var right := _split(mi.mesh, true)
	var left := _split(mi.mesh, false)
	src.free()
	if right.is_empty() or left.is_empty():
		return
	has_arms = true
	_arm_len = right.length
	_attach(_right_pivot, right.mesh, mat, RIGHT_SHOULDER, RIGHT_DIR, RIGHT_ROLL)
	_attach(_left_pivot, left.mesh, mat, LEFT_SHOULDER, LEFT_DIR, LEFT_ROLL)
	_hand.position = Vector3(_arm_len * 0.84, 0, 0)
	_right_pivot.add_child(_hand)


func _attach(pivot: Node3D, mesh: Mesh, mat: Material, elbow: Vector3, dir: Vector3, roll: float) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(m)
	pivot.position = elbow
	pivot.basis = _aim_basis(dir, roll)
	pivot.set_meta("base", pivot.transform)


## 把模型里 x>0（右臂）或 x<0（左臂）的三角形拆出来，并让手臂沿局部 +X 从原点（手肘）伸出去
func _split(mesh: Mesh, right_side: bool) -> Dictionary:
	if mesh == null or mesh.get_surface_count() == 0:
		return {}
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals = arrays[Mesh.ARRAY_NORMAL]
	var uvs = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if idx.is_empty():
		idx = PackedInt32Array(range(verts.size()))
	var sign := 1.0 if right_side else -1.0
	var inner := INF
	var outer := -INF
	for v in verts:
		var x := v.x * sign
		if x > 0.0:
			inner = min(inner, x)
			outer = max(outer, x)
	if outer <= inner:
		return {}
	# 以肩膀那头的截面中心为原点
	var center := Vector2.ZERO
	var cn := 0.0
	for v in verts:
		if v.x * sign > 0.0 and v.x * sign < inner + 0.08:
			center += Vector2(v.y, v.z * sign)
			cn += 1.0
	if cn > 0.0:
		center /= cn
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, idx.size() - 2, 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		if (a.x + b.x + c.x) * sign <= 0.0:
			continue
		for k in 3:
			var i := idx[t + k]
			if uvs is PackedVector2Array and uvs.size() > i:
				st.set_uv(uvs[i])
			var v := verts[i]
			# 左臂绕 Y 轴转 180°，这样两条手臂都是沿 +X 伸出去
			st.add_vertex(Vector3(v.x * sign - inner, v.y - center.x, v.z * sign - center.y))
	st.generate_normals()
	return {"mesh": st.commit(), "length": outer - inner}


func _aim_basis(dir: Vector3, roll: float) -> Basis:
	var x := dir.normalized()
	var up := Vector3.UP
	var y := (up - x * up.dot(x)).normalized()
	var z := x.cross(y)
	return Basis(x, y, z) * Basis(Vector3.RIGHT, roll)


## 换手上的东西：有模型用模型，没模型用图标
func hold(item_id: String) -> void:
	if _weapon:
		_weapon.queue_free()
		_weapon = null
	if item_id == "":
		return
	var holder := Node3D.new()
	var row: Dictionary = Assets.items_by_id.get(item_id, {})
	var vis: Node3D = null
	if row.get("model", "") != "":
		vis = Assets.make_model(row.model, GameConfig.HELD_SIZE, false, Assets.icon_tint(item_id))
	if vis:
		# 把模型最长的方向转到「从手里向前上方伸出去」
		var aabb := _visual_aabb(vis)
		var axis := Vector3.UP
		if aabb.size.x >= aabb.size.y and aabb.size.x >= aabb.size.z:
			axis = Vector3.RIGHT
		elif aabb.size.z >= aabb.size.y:
			axis = Vector3.BACK
		var spin := Node3D.new()
		spin.add_child(vis)
		vis.position -= Vector3(0, aabb.size.y * 0.15, 0)
		spin.basis = Basis(Quaternion(axis, Vector3.UP))
		holder.add_child(spin)
	else:
		var tex := Assets.icon(item_id)
		if tex == null:
			return
		var sp := Sprite3D.new()
		sp.texture = tex
		sp.pixel_size = 0.32 / max(tex.get_width(), 1)
		sp.shaded = false
		sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sp.position = Vector3(0, 0.08, 0)
		holder.add_child(sp)
	# 握持：武器竖在掌心，略向前倾
	holder.basis = Basis(Vector3.FORWARD, 0.0)
	_hand.add_child(holder)
	holder.global_basis = global_basis * Basis(Vector3.RIGHT, -0.9) * Basis(Vector3.FORWARD, 0.2)
	_weapon = holder
	for m in holder.find_children("*", "GeometryInstance3D", true, false):
		(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _visual_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p and p != n:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b := xf * mi.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func swing(speed := 3.0) -> void:
	if _swing <= 0.0:
		_swing = 1.0
		_swing_speed = speed


func is_swinging() -> bool:
	return _swing > 0.0


func _process(delta: float) -> void:
	_bob += delta
	var walk: float = get_meta("walking", 0.0)
	var bob := Vector3(sin(_bob * 9.0) * 0.012, abs(cos(_bob * 9.0)) * -0.015, 0) * walk
	var idle := Vector3(0, sin(_bob * 1.6) * 0.004, 0)
	var t := 0.0
	if _swing > 0.0:
		_swing = max(0.0, _swing - delta * _swing_speed)
		t = sin((1.0 - _swing) * PI)
	for pivot in [_right_pivot, _left_pivot]:
		if not pivot.has_meta("base"):
			continue
		var base: Transform3D = pivot.get_meta("base")
		pivot.transform = Transform3D(base.basis, base.origin + bob + idle)
	if _right_pivot.has_meta("base"):
		var base: Transform3D = _right_pivot.get_meta("base")
		# 向前下方劈砍
		var chop := Basis(Vector3.RIGHT, -1.1 * t) * Basis(Vector3.UP, 0.5 * t)
		_right_pivot.transform = Transform3D(chop * base.basis, base.origin + bob + idle + Vector3(-0.05, 0.05, -0.18) * t)
	elif _swing > 0.0:
		_right_pivot.rotation.x = -1.1 * t
