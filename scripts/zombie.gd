class_name Zombie
extends Node3D
## 僵尸：用导出的带骨骼 glb，走路动作由代码驱动骨骼（导出的包里没有动画）。

signal died(zombie: Zombie)
## 尖叫者看见玩家时叫一声，会把附近的僵尸引过来
signal screamed(zombie: Zombie)

var hp := 60.0
var max_hp := 60.0
var speed := 1.0
var damage := GameConfig.ZOMBIE_DAMAGE
var type := ""
var type_name := "僵尸"
var can_scream := false
var target: Node3D
## 市中心（用来绕开楼和车）
var world: World
var dead := false

var _model: Node3D
var _skel: Skeleton3D
var _phase := 0.0
var _attack_cd := 0.0
var _lunge := 0.0
var _hit_flash := 0.0
var _death_t := 0.0
var _stagger := 0.0
var _windup := -1.0
var _pending_damage := 0.0
var _path_t := 0.0
var _dir := Vector3.ZERO
var _fall_dir := -1.0
var _screamed := false
var _scream_t := 0.0
var _bones := {}
var _rng := RandomNumberGenerator.new()
var _meshes: Array[MeshInstance3D] = []
var _height := GameConfig.ZOMBIE_HEIGHT
var _voice := "zm_"      # 男声 zm_ / 女声 zf_
var _roam_t := 0.0
var _alerted := false
var _anim_t := 0.0
var _anim_interval := 1.0 / 30.0
# 骨骼空间里的「前」和「右」，从脚尖方向推出来（不同僵尸的导出朝向不一样）
var _fwd := Vector3.BACK
var _side := Vector3.RIGHT


func setup(model_name: String, hp_value: float, speed_value: float, player: Node3D) -> bool:
	_model = Assets.make_model(model_name, 0.0)
	if _model == null:
		return false
	# 没有骨骼的 obj 按高度缩放；带骨骼的 glb 本身就是米制
	var h: float = _model.get_meta("height", GameConfig.ZOMBIE_HEIGHT)
	if h < 1.2 or h > 3.5:
		_model.free()
		_model = Assets.make_model(model_name, GameConfig.ZOMBIE_HEIGHT, true)
		h = GameConfig.ZOMBIE_HEIGHT
	_height = h
	add_child(_model)
	_model.rotation.y = GameConfig.ZOMBIE_FACING_OFFSET
	type = model_name.trim_prefix("zombie_")
	var t: Dictionary = GameConfig.ZOMBIE_TYPES.get(type, {})
	type_name = t.get("name", "僵尸")
	can_scream = t.get("screams", false)
	hp = hp_value * t.get("hp", 1.0)
	max_hp = hp
	speed = speed_value * t.get("speed", 1.0) * _rng.randf_range(0.85, 1.15)
	damage = GameConfig.ZOMBIE_DAMAGE * t.get("damage", 1.0)
	_fall_dir = -1.0 if _rng.randf() < 0.6 else 1.0
	target = player
	_phase = _rng.randf() * TAU
	_voice = "zf_" if type in ["nurse", "arlene", "screamer"] or type.contains("female") else "zm_"
	_roam_t = _rng.randf_range(2.0, 9.0)
	var found := _model.find_children("*", "Skeleton3D", true, false)
	if found.size() > 0:
		_skel = found[0]
		for b in ["Hips", "Spine1", "Head", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand",
				"LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]:
			var i := _skel.find_bone(b)
			if i >= 0:
				_bones[b] = i
	for m in _model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(m)
		# 僵尸不投影：阴影里再算一遍骨骼很贵，近处也看不出少了它
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_detect_facing()
	return true


## 用脚 → 脚尖的方向判断模型正面，让所有僵尸都脸朝前走路
func _detect_facing() -> void:
	if _skel == null:
		return
	var fwd := Vector3.ZERO
	for side in ["Left", "Right"]:
		var foot := _skel.find_bone(side + "Foot")
		var toe := _skel.find_bone(side + "ToeBase")
		if foot >= 0 and toe >= 0:
			fwd += _skel.get_bone_global_rest(toe).origin - _skel.get_bone_global_rest(foot).origin
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return
	_fwd = fwd.normalized()
	_side = Vector3.UP.cross(_fwd)
	# 骨骼节点在模型里的变换，把骨骼空间的「前」换算到模型空间
	var xf := Transform3D.IDENTITY
	var n: Node = _skel
	while n and n != self:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var model_fwd := xf.basis * _fwd
	_model.rotation.y -= atan2(model_fwd.x, model_fwd.z)


func _process(delta: float) -> void:
	# 骨骼动画按距离降频：近处 30Hz，中距离 15Hz，远处 10Hz
	var dist_now := distance_to_target()
	_anim_interval = 1.0 / 30.0 if dist_now < 30.0 else (1.0 / 15.0 if dist_now < 60.0 else 1.0 / 10.0)
	_anim_t -= delta
	var do_anim := _anim_t <= 0.0
	if do_anim:
		_anim_t = _anim_interval
	if dead:
		_death_t += delta
		if do_anim and _death_t < 0.3:
			_animate()
		# 倒地：向后或向前倒，倒下后停一会儿沉到地下
		rotation.x = lerp(rotation.x, _fall_dir * PI / 2.0, min(1.0, delta * 5.0))
		position.y = lerp(position.y, 0.15, min(1.0, delta * 5.0)) if _death_t < 2.5 else position.y
		if _death_t > 2.5:
			position.y -= delta * 0.5
		if _death_t > 4.0:
			queue_free()
		return
	_attack_cd = max(0.0, _attack_cd - delta)
	_lunge = max(0.0, _lunge - delta * 3.0)
	if _hit_flash > 0.0:
		_hit_flash -= delta
		if _hit_flash <= 0.0:
			_set_tint(Color.WHITE)
	if target == null:
		return
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	# 出手：抬手 → 砸下来，砸下来那一刻还在够得着的距离才算打中
	if _windup >= 0.0:
		_windup -= delta
		if _windup < 0.0:
			_lunge = 1.0
			_attack_cd = GameConfig.ZOMBIE_ATTACK_COOLDOWN
			if dist <= GameConfig.ZOMBIE_REACH * 1.25:
				_pending_damage = damage
	if can_scream and not _screamed and dist < 22.0:
		_screamed = true
		_scream_t = 1.2
		screamed.emit(self)
		Sfx.play("scream", global_position + Vector3.UP * 1.6, 6.0)
	if _scream_t > 0.0:
		_scream_t -= delta
	# 叫声：第一次靠近时吼一声，平时隔一阵哼一声
	if not _alerted and dist < 16.0:
		_alerted = true
		Sfx.play(_voice + "alert", global_position + Vector3.UP * 1.6)
	_roam_t -= delta
	if _roam_t <= 0.0:
		_roam_t = _rng.randf_range(5.0, 12.0)
		if dist < 40.0:
			Sfx.play(_voice + "roam", global_position + Vector3.UP * 1.6, -3.0)
	if _stagger > 0.0:
		_stagger -= delta
		if do_anim:
			_animate()
		return
	# 寻路：直接看得见就直走，被楼挡住就沿距离场绕
	_path_t -= delta
	if _path_t <= 0.0 or _dir == Vector3.ZERO:
		_path_t = 0.3
		_dir = to / dist if dist > 0.05 else Vector3.ZERO
		if world and dist > 2.0 and world.line_blocked(global_position + Vector3.UP, target.global_position + Vector3.UP):
			var f := world.flow_dir(global_position)
			if f != Vector3.ZERO:
				_dir = f
	if dist > 0.05:
		var face := to / dist if dist < 3.0 else _dir
		rotation.y = lerp_angle(rotation.y, atan2(face.x, face.z), min(1.0, delta * 6.0))
		if dist > GameConfig.ZOMBIE_REACH * 0.8 and _windup < 0.0 and _scream_t <= 0.0:
			position += _dir * speed * delta
			if world:
				position = world.push_out(position, 0.35)
			_phase += delta * (2.0 + speed * 2.2)
	if do_anim:
		_animate()


func distance_to_target() -> float:
	if target == null:
		return INF
	var d := target.global_position - global_position
	d.y = 0.0
	return d.length()


## 返回这一帧造成的伤害（0 表示没打中）。够得着就开始抬手，过一会儿才真正打中
func try_attack() -> float:
	if dead:
		return 0.0
	if _pending_damage > 0.0:
		var d := _pending_damage
		_pending_damage = 0.0
		return d
	if _attack_cd <= 0.0 and _windup < 0.0 and _stagger <= 0.0 and distance_to_target() <= GameConfig.ZOMBIE_REACH:
		_windup = GameConfig.ZOMBIE_WINDUP
		Sfx.play(_voice + "attack", global_position + Vector3.UP * 1.6)
	return 0.0


## 被打中的位置（世界坐标）：用来判断爆头、喷血
func head_height() -> float:
	return global_position.y + _height * 0.86


func height() -> float:
	return _height


func take_hit(amount: float, from: Vector3, headshot := false) -> void:
	if dead:
		return
	hp -= amount
	_hit_flash = 0.15
	if hp > 0.0 and _rng.randf() < 0.5:
		Sfx.play(_voice + "pain", global_position + Vector3.UP * 1.6)
	_set_tint(Color(1.0, 0.45, 0.45))
	# 受击硬直：打断出手
	_stagger = GameConfig.ZOMBIE_HEADSHOT_STAGGER if headshot else GameConfig.ZOMBIE_STAGGER
	_windup = -1.0
	var push := global_position - from
	push.y = 0.0
	if push.length() > 0.01:
		position += push.normalized() * 0.35
		if world:
			position = world.push_out(position, 0.35)
	if hp <= 0.0:
		dead = true
		Sfx.play(_voice + "death", global_position + Vector3.UP * 1.4)
		_set_tint(Color.WHITE)
		# 打的方向决定往哪边倒
		var back := (global_position - from)
		back.y = 0.0
		if back.length() > 0.01:
			rotation.y = atan2(-back.x, -back.z) if _fall_dir < 0.0 else atan2(back.x, back.z)
		died.emit(self)


func _set_tint(c: Color) -> void:
	for m in _meshes:
		if c == Color.WHITE:
			m.material_overlay = null
		else:
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(c.r, c.g * 0.2, c.b * 0.2, 0.35)
			m.material_overlay = mat


# —— 程序化走路：导出的包里没有动画，用代码摆骨骼 ——

func _animate() -> void:
	if _skel == null:
		# 没骨骼的模型就整体晃一晃
		_model.rotation.z = sin(_phase) * 0.06
		_model.position.y = abs(sin(_phase)) * 0.04
		return
	var s := sin(_phase)
	var swing := 0.45 * s
	var reach := 0.15 + _lunge * 0.5
	if dead:
		# 倒地时手脚摊开
		_aim("LeftArm", "LeftForeArm", Vector3(0.8, 0.2, 0.3))
		_aim("RightArm", "RightForeArm", Vector3(-0.8, 0.2, 0.3))
		return
	var raise := 0.0
	if _windup >= 0.0:
		# 抬手准备砸
		raise = 1.0 - _windup / GameConfig.ZOMBIE_WINDUP
	elif _scream_t > 0.0:
		raise = 0.6
	# 腿：大腿前后摆，小腿跟着弯
	_aim("LeftUpLeg", "LeftLeg", Vector3(0, -cos(swing), sin(swing)))
	_aim("RightUpLeg", "RightLeg", Vector3(0, -cos(-swing), sin(-swing)))
	_aim("LeftLeg", "LeftFoot", Vector3(0, -1.0, sin(swing) * 0.3 - max(0.0, -s) * 0.6))
	_aim("RightLeg", "RightFoot", Vector3(0, -1.0, -sin(swing) * 0.3 - max(0.0, s) * 0.6))
	# 胳膊：经典僵尸姿势，向前伸
	_aim("LeftArm", "LeftForeArm", Vector3(0.12 + raise * 0.15, -0.25 + reach * 0.3 + s * 0.05 + raise * 1.6 - _lunge * 0.6, 1.0))
	_aim("RightArm", "RightForeArm", Vector3(-0.12 - raise * 0.15, -0.25 + reach * 0.3 - s * 0.05 + raise * 1.6 - _lunge * 0.6, 1.0))
	_aim("LeftForeArm", "LeftHand", Vector3(0.05, -0.15 + reach * 0.4, 1.0))
	_aim("RightForeArm", "RightHand", Vector3(-0.05, -0.15 + reach * 0.4, 1.0))
	if _bones.has("Hips"):
		var hips: int = _bones["Hips"]
		var rest := _skel.get_bone_rest(hips)
		_skel.set_bone_pose_position(hips, rest.origin + Vector3(0, -abs(s) * 0.04, 0))
		# 受击时上身往后仰
		var lean := Quaternion(_side, -_stagger * 1.2 + raise * 0.15 - _lunge * 0.2)
		_skel.set_bone_pose_rotation(hips, lean * Quaternion(_fwd, s * 0.05) * rest.basis.get_rotation_quaternion())


## 旋转 bone，使它指向 child 的方向变成 dir（x 右、y 上、z 前，按这只僵尸的朝向换算）
func _aim(bone_name: String, child_name: String, local_dir: Vector3) -> void:
	var dir := _side * local_dir.x + Vector3.UP * local_dir.y + _fwd * local_dir.z
	if not _bones.has(bone_name) or not _bones.has(child_name):
		return
	var bone: int = _bones[bone_name]
	var parent := _skel.get_bone_parent(bone)
	var parent_g := _skel.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var rest_local := _skel.get_bone_rest(bone)
	var g := parent_g * rest_local
	# 中间可能隔着 ArmRoll 这类扭转骨，所以用两者的全局静止姿势求相对位置
	var child_off := (_skel.get_bone_global_rest(bone).affine_inverse() * _skel.get_bone_global_rest(_bones[child_name])).origin
	if child_off.length() < 0.0001:
		return
	var cur := (g.basis * child_off).normalized()
	var want := dir.normalized()
	if cur.dot(want) > 0.99999:
		return
	var q := Quaternion(cur, want)
	var new_basis := Basis(q) * g.basis
	var local := parent_g.basis.inverse() * new_basis
	_skel.set_bone_pose_rotation(bone, local.get_rotation_quaternion())
