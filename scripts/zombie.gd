class_name Zombie
extends Node3D
## 僵尸：用导出的带骨骼 glb，走路动作由代码驱动骨骼（导出的包里没有动画）。

signal died(zombie: Zombie)

var hp := 60.0
var max_hp := 60.0
var speed := 1.0
var target: Node3D
var dead := false

var _model: Node3D
var _skel: Skeleton3D
var _phase := 0.0
var _attack_cd := 0.0
var _lunge := 0.0
var _hit_flash := 0.0
var _death_t := 0.0
var _bones := {}
var _rng := RandomNumberGenerator.new()
var _meshes: Array[MeshInstance3D] = []
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
	add_child(_model)
	_model.rotation.y = GameConfig.ZOMBIE_FACING_OFFSET
	hp = hp_value
	max_hp = hp_value
	speed = speed_value * _rng.randf_range(0.85, 1.15)
	target = player
	_phase = _rng.randf() * TAU
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
	if dead:
		_death_t += delta
		rotation.x = lerp(rotation.x, -PI / 2.0, min(1.0, delta * 4.0))
		if _death_t > 2.5:
			position.y -= delta * 0.6
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
	if dist > 0.05:
		var dir := to / dist
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), min(1.0, delta * 6.0))
		if dist > GameConfig.ZOMBIE_REACH * 0.8:
			position += dir * speed * delta
			_phase += delta * (2.0 + speed * 2.2)
	_animate()


func distance_to_target() -> float:
	if target == null:
		return INF
	var d := target.global_position - global_position
	d.y = 0.0
	return d.length()


## 返回这一帧造成的伤害（0 表示没打）
func try_attack() -> float:
	if dead or _attack_cd > 0.0 or distance_to_target() > GameConfig.ZOMBIE_REACH:
		return 0.0
	_attack_cd = GameConfig.ZOMBIE_ATTACK_COOLDOWN
	_lunge = 1.0
	return GameConfig.ZOMBIE_DAMAGE


func take_hit(amount: float, from: Vector3) -> void:
	if dead:
		return
	hp -= amount
	_hit_flash = 0.15
	_set_tint(Color(1.0, 0.45, 0.45))
	var push := global_position - from
	push.y = 0.0
	if push.length() > 0.01:
		position += push.normalized() * 0.35
	if hp <= 0.0:
		dead = true
		_set_tint(Color.WHITE)
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
	# 腿：大腿前后摆，小腿跟着弯
	_aim("LeftUpLeg", "LeftLeg", Vector3(0, -cos(swing), sin(swing)))
	_aim("RightUpLeg", "RightLeg", Vector3(0, -cos(-swing), sin(-swing)))
	_aim("LeftLeg", "LeftFoot", Vector3(0, -1.0, sin(swing) * 0.3 - max(0.0, -s) * 0.6))
	_aim("RightLeg", "RightFoot", Vector3(0, -1.0, -sin(swing) * 0.3 - max(0.0, s) * 0.6))
	# 胳膊：经典僵尸姿势，向前伸
	_aim("LeftArm", "LeftForeArm", Vector3(0.12, -0.25 + reach * 0.3 + s * 0.05, 1.0))
	_aim("RightArm", "RightForeArm", Vector3(-0.12, -0.25 + reach * 0.3 - s * 0.05, 1.0))
	_aim("LeftForeArm", "LeftHand", Vector3(0.05, -0.15 + reach * 0.4, 1.0))
	_aim("RightForeArm", "RightHand", Vector3(-0.05, -0.15 + reach * 0.4, 1.0))
	if _bones.has("Hips"):
		var hips: int = _bones["Hips"]
		var rest := _skel.get_bone_rest(hips)
		_skel.set_bone_pose_position(hips, rest.origin + Vector3(0, -abs(s) * 0.04, 0))
		_skel.set_bone_pose_rotation(hips, Quaternion(_fwd, s * 0.05) * rest.basis.get_rotation_quaternion())


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
