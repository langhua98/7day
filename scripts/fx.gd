class_name Fx
## 特效：喷血、地上的血迹、枪口火光、子弹打在墙上的火花。贴图来自 assets/effects/（游戏自带的特效贴图）。

const DIR := "res://assets/effects/"
static var _mats := {}


static func _mat(tex: String, additive := false) -> StandardMaterial3D:
	var key := tex + str(additive)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	else:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if ResourceLoader.exists(DIR + tex + ".png"):
		m.albedo_texture = load(DIR + tex + ".png")
	_mats[key] = m
	return m


static func _burst(parent: Node, pos: Vector3, tex: String, additive: bool, amount: int, life: float,
		dir: Vector3, spread: float, speed: Vector2, size: Vector2, gravity: float, color: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = life
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _mat(tex, additive)
	p.mesh = quad
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.gravity = Vector3(0, -gravity, 0)
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.color = color
	var fade := Gradient.new()
	fade.set_color(0, color)
	fade.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = fade
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


## 打中僵尸：血雾 + 血滴
static func blood(parent: Node, pos: Vector3, dir: Vector3, big := false) -> void:
	_burst(parent, pos, "blood_mist02", false, 3 if not big else 5, 0.45, dir, 25.0, Vector2(0.3, 1.2),
		Vector2(0.35, 0.7) * (1.5 if big else 1.0), 0.5, Color(0.55, 0.02, 0.02, 0.9))
	_burst(parent, pos, "p_blood", false, 10 if not big else 18, 0.6, dir, 40.0, Vector2(1.5, 3.5),
		Vector2(0.05, 0.12), 9.0, Color(0.45, 0.0, 0.0, 1.0))


## 地上一摊血（最多留 40 摊，多了把最早的删掉）
static func blood_pool(parent: Node, pos: Vector3) -> void:
	if not ResourceLoader.exists(DIR + "blood_splat_1.png"):
		return
	var key := "pool"
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(DIR + "blood_splat_1.png")
		m.albedo_color = Color(0.5, 0.05, 0.05)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.35
		m.roughness = 0.3
		_mats[key] = m
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	var s := randf_range(1.0, 1.8)
	pm.size = Vector2(s, s)
	mi.mesh = pm
	mi.material_override = _mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = Vector3(pos.x, 0.04, pos.z)
	mi.rotation.y = randf() * TAU
	mi.add_to_group("blood_pool")
	var pools := parent.get_tree().get_nodes_in_group("blood_pool")
	if pools.size() > GameConfig.BLOOD_POOL_MAX:
		pools[0].queue_free()


## 子弹打在墙上、车上：火花和灰
static func impact(parent: Node, pos: Vector3, normal: Vector3) -> void:
	_burst(parent, pos, "sparksSheet_A_2x2", true, 6, 0.25, normal, 50.0, Vector2(2.0, 5.0),
		Vector2(0.04, 0.09), 6.0, Color(1.0, 0.8, 0.5, 1.0))
	_burst(parent, pos, "p_smoke2", false, 2, 0.7, normal, 20.0, Vector2(0.2, 0.5),
		Vector2(0.25, 0.4), -0.2, Color(0.6, 0.58, 0.55, 0.5))


## 枪口火光：挂在 parent（第一人称手臂）下的 local 位置，持续约 4 帧。
## 由几部分组成：火舌（贴图 muzzleflash_point 上下两张随机取一张，正对镜头）、
## 枪口一团橙色光、中间白热的芯；再加一盏一闪的点光源把周围照亮。
## parent 有 muzzle_direction() 时火舌沿枪管方向，没有就朝镜头前方。
static func muzzle(parent: Node3D, local: Vector3, size := 1.0) -> void:
	var dir := Vector3.FORWARD
	if parent.has_method("muzzle_direction"):
		dir = parent.muzzle_direction()
	size *= randf_range(0.85, 1.15)
	var root := Node3D.new()
	root.position = local
	parent.add_child(root)
	# 火舌：一条沿枪管往前喷（看过去是斜着往准星方向的一道），再加三条在屏幕平面里散开成星形，根部都在枪口
	var to_cam := (-local).normalized()   # 镜头在 parent 原点
	var u := dir - to_cam * dir.dot(to_cam)
	if u.length() < 0.01:
		u = Vector3.UP - to_cam * to_cam.y
	u = u.normalized()
	var v := to_cam.cross(u)
	var tongues: Array[MeshInstance3D] = []
	var spin := randf() * TAU
	for i in 4:
		var length := (0.30 if i == 0 else randf_range(0.10, 0.15)) * size
		var along := u if i == 0 else (u * cos(spin + i * TAU / 3.0) + v * sin(spin + i * TAU / 3.0))
		var t := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(length, length * (0.45 if i == 0 else 0.55))
		q.center_offset = Vector3(length * 0.45, 0, 0)
		t.mesh = q
		t.material_override = _flash_mat("tongue%d" % (randi() % 2), Color(1.0, 0.8, 0.55))
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.basis = Basis(along, to_cam.cross(along), to_cam)
		root.add_child(t)
		tongues.append(t)
	# 正面的光团和白芯
	var glow := _flash_quad(0.22 * size, Color(1.0, 0.55, 0.2))
	var core := _flash_quad(0.08 * size, Color(1.0, 0.95, 0.8))
	root.add_child(glow)
	root.add_child(core)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.38)
	light.light_energy = 4.0
	light.omni_range = 8.0
	light.distance_fade_enabled = true
	light.distance_fade_begin = 30.0
	light.distance_fade_length = 5.0
	root.add_child(light)
	var tw := root.create_tween()
	tw.set_parallel(true)
	for t in tongues:
		tw.tween_property(t, "scale", Vector3(1.2, 0.4, 1.0), 0.07).set_delay(0.02)
	tw.tween_property(glow, "scale", Vector3.ONE * 0.4, 0.07).set_delay(0.02)
	tw.tween_property(core, "scale", Vector3.ONE * 0.3, 0.06).set_delay(0.02)
	tw.tween_property(light, "light_energy", 0.0, 0.08)
	parent.get_tree().create_timer(0.09).timeout.connect(root.queue_free)


## 叠加发光的材质。kind: tongue0 / tongue1 是火舌贴图的上半张 / 下半张，glow 是程序生成的圆形光斑
static func _flash_mat(kind: String, color: Color) -> StandardMaterial3D:
	var key := "flash_%s_%s" % [kind, color]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 10
	m.albedo_color = color
	if kind.begins_with("tongue") and ResourceLoader.exists(DIR + "muzzleflash_point.png"):
		m.albedo_texture = load(DIR + "muzzleflash_point.png")
		m.uv1_scale = Vector3(1, 0.5, 1)
		m.uv1_offset = Vector3(0, 0.5 if kind == "tongue1" else 0.0, 0)
	else:
		var g := GradientTexture2D.new()
		g.width = 64
		g.height = 64
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(0.5, 0.0)
		var grad := Gradient.new()
		grad.set_color(0, Color.WHITE)
		grad.set_color(1, Color.BLACK)
		grad.add_point(0.35, Color(0.7, 0.7, 0.7))
		g.gradient = grad
		m.albedo_texture = g
	if kind == "glow":
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mats[key] = m
	return m


static func _flash_quad(size: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	mi.material_override = _flash_mat("glow", color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
