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
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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
	if pools.size() > 40:
		pools[0].queue_free()


## 子弹打在墙上、车上：火花和灰
static func impact(parent: Node, pos: Vector3, normal: Vector3) -> void:
	_burst(parent, pos, "sparksSheet_A_2x2", true, 6, 0.25, normal, 50.0, Vector2(2.0, 5.0),
		Vector2(0.04, 0.09), 6.0, Color(1.0, 0.8, 0.5, 1.0))
	_burst(parent, pos, "p_smoke2", false, 2, 0.7, normal, 20.0, Vector2(0.2, 0.5),
		Vector2(0.25, 0.4), -0.2, Color(0.6, 0.58, 0.55, 0.5))


## 枪口火光：挂在 parent（武器挂点）下的 local 位置，闪一下就没
static func muzzle(parent: Node3D, local: Vector3) -> void:
	var s := Sprite3D.new()
	if ResourceLoader.exists(DIR + "muzzleflash_point.png"):
		s.texture = load(DIR + "muzzleflash_point.png")
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.no_depth_test = true
	s.pixel_size = 0.0007 * randf_range(0.8, 1.2)
	s.rotation.z = randf() * TAU
	s.modulate = Color(1.0, 0.85, 0.6)
	s.render_priority = 10
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.no_depth_test = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = s.texture
	mat.albedo_color = Color(1.0, 0.85, 0.6)
	s.material_override = mat
	s.position = local
	parent.add_child(s)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.4)
	light.light_energy = 2.5
	light.omni_range = 6.0
	light.position = local
	parent.add_child(light)
	parent.get_tree().create_timer(0.05).timeout.connect(s.queue_free)
	parent.get_tree().create_timer(0.06).timeout.connect(light.queue_free)
