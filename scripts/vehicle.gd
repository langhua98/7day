class_name Vehicle
extends RefCounted
## 可驾驶载具：外观和简单驾驶物理。位置和朝向每帧由 vehicles.gd 同步给玩家。

const C = preload("res://scripts/config.gd")
const DIR := "res://assets/vehicles/"
## 4x4 是分件导出的，按车辆坐标拼起来（X 左右、Y 高度、Z 前后）
const PARTS_4X4 := ["4x4_body.obj", "4x4_under.obj", "4x4_hood.obj", "4x4_door_l.obj",
	"4x4_door_r.obj", "4x4_tailgate.obj", "4x4_headlight.obj", "4x4_wheel_steer.obj"]

var id := ""
var def := {}
var pos := Vector3.ZERO
var rot := 0.0
var speed := 0.0
var radius := 1.2
var node: Node3D
var world: World


func setup(world_ref: World, item_id: String, at: Vector3, yaw: float) -> void:
	world = world_ref
	id = item_id
	def = C.VEHICLES.get(id, {}).duplicate()
	radius = float(def.get("radius", 1.2))
	pos = at
	rot = yaw
	node = _make_visual()
	if node:
		node.position = pos
		node.rotation.y = rot


## 每帧：steer 左负右正，throttle 上正下负（下=刹车/倒车）
func update(delta: float, steer: float, throttle: float) -> void:
	var top := float(def.get("speed", 12.0))
	var acc := float(def.get("accel", 6.0))
	if throttle > 0.05:
		speed = minf(top, speed + acc * throttle * delta)
	elif throttle < -0.05:
		if speed > 0.0:
			speed = maxf(0.0, speed + throttle * C.VEHICLE_BRAKE * delta)
		else:
			speed = maxf(-top * C.VEHICLE_REVERSE_MULT, speed + acc * throttle * delta)
	else:
		speed = move_toward(speed, 0.0, C.VEHICLE_FRICTION * delta)
	# 速度越快转向越顺；倒车时打方向反过来
	if absf(speed) > 0.05:
		var scale := clampf(absf(speed) / C.VEHICLE_TURN_SPEED_REF, 0.3, 1.0)
		rot -= steer * C.VEHICLE_TURN_RATE * scale * delta * (1.0 if speed >= 0.0 else -1.0)
	var fwd := Vector3(-sin(rot), 0.0, -cos(rot))
	var want := pos + fwd * speed * delta
	var got := want
	if world:
		got = world.push_out(want, radius)
		got.y = world.floor_under(got, radius)
	var moved := Vector2(got.x - pos.x, got.z - pos.z).length()
	var intended := absf(speed) * delta
	if intended > 0.05 and moved < intended * 0.4:
		# 撞到楼、方块或障碍物：停住
		speed = 0.0
	pos = got
	if node:
		node.position = pos
		node.rotation.y = rot


func speed_kmh() -> float:
	return absf(speed) * 3.6


func save_state() -> Dictionary:
	return {"id": id, "pos": [pos.x, pos.y, pos.z], "rot": rot}


# —— 外观 ——

func _make_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "VehicleNode"
	var body: Node3D = null
	var model := str(def.get("model", ""))
	if model == "4x4":
		body = _build_4x4()
	elif model != "":
		body = _load_model(model)
	if body == null:
		body = _fallback_body()
	# 底部中心对齐原点，再按 yaw 把车头转到 -Z
	var aabb := _bounds(body, Transform3D.IDENTITY)
	if aabb.size != Vector3.ZERO:
		var c := aabb.get_center()
		body.position -= Vector3(c.x, aabb.position.y, c.z)
	var pivot := Node3D.new()
	pivot.rotation.y = float(def.get("yaw", 0.0))
	pivot.add_child(body)
	root.add_child(pivot)
	return root


func _load_model(file: String) -> Node3D:
	var path := DIR + file
	if not ResourceLoader.exists(path):
		return null
	var res = load(path)
	if res is PackedScene:
		var inst = res.instantiate()
		if inst is Node3D:
			_fix_materials(inst, path.get_basename() + ".png", _tint())
			return inst
		return null
	if res is Mesh:
		return _mesh_body(res, path.get_basename() + ".png")
	return null


## glb 里的贴图可能只是 2×2 占位，有同名 png 就换上；都没有就用定义的底色
func _fix_materials(root: Node, tex_path: String, tint: Color) -> void:
	var tex: Texture2D = null
	if ResourceLoader.exists(tex_path):
		tex = load(tex_path)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if not (mat is StandardMaterial3D):
				continue
			var sm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			if tex:
				sm.albedo_texture = tex
				sm.albedo_color = Color.WHITE
			elif sm.albedo_texture == null or sm.albedo_texture.get_width() <= 8:
				sm.albedo_texture = null
				sm.albedo_color = tint
			m.set_surface_override_material(i, sm)


func _mesh_body(mesh: Mesh, tex_path: String) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _flat_material(tex_path)
	var holder := Node3D.new()
	holder.add_child(mi)
	return holder


func _flat_material(tex_path: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.8
	if ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	else:
		mat.albedo_color = _tint()
	return mat


## 模型没带贴图时的底色（config 里每种车可以配 tint）
func _tint() -> Color:
	return def.get("tint", Color(0.5, 0.52, 0.55))


## 4x4 用 vehicles.zip 里的分件拼：车身、底盘、引擎盖、车门、尾门、车灯、方向盘 + 4 个轮子
func _build_4x4() -> Node3D:
	var holder := Node3D.new()
	var mat := _flat_material(DIR + "4x4.png")
	var missing := 0
	for f: String in PARTS_4X4:
		var path := DIR + f
		if not ResourceLoader.exists(path):
			missing += 1
			continue
		var mesh = load(path)
		if not (mesh is Mesh):
			missing += 1
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		holder.add_child(mi)
	var wheel_path := DIR + "4x4_wheel.obj"
	if ResourceLoader.exists(wheel_path) and load(wheel_path) is Mesh:
		var wm = load(wheel_path)
		for p: Vector3 in [Vector3(-0.85, 0.64, 1.7), Vector3(0.85, 0.64, 1.7),
				Vector3(-0.85, 0.64, -1.7), Vector3(0.85, 0.64, -1.7)]:
			var wi := MeshInstance3D.new()
			wi.mesh = wm
			wi.position = p
			wi.material_override = mat
			holder.add_child(wi)
	else:
		missing += 1
	return null if missing > 2 else holder


func _fallback_body() -> Node3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(radius * 1.8, 1.1, radius * 2.8)
	mi.mesh = box
	mi.position.y = 0.55
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.47, 0.5)
	mi.material_override = mat
	var holder := Node3D.new()
	holder.add_child(mi)
	return holder


## 不带骨骼的模型算包围盒：沿节点树累乘变换
static func _bounds(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out = here * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for ch in n.get_children():
		var b := _bounds(ch, here)
		if b.size == Vector3.ZERO:
			continue
		out = b if first else out.merge(b)
		first = false
	return out
