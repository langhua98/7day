class_name Zombie
extends Node3D
## 僵尸：用导出的带骨骼 glb，走路动作由代码驱动骨骼（导出的包里没有动画）。
## 动作参数都平滑过渡；每只僵尸随机弓背、歪头、瘸腿、手的姿势，看起来不像一个模子。

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
# 骨骼空间里的「前」和「右」，从脚尖方向推出来（不同僵尸的导出朝向不一样）
var _fwd := Vector3.BACK
var _side := Vector3.RIGHT
# 动作：平滑过的参数、每只僵尸自己的走路样子（随机）
var _moving := 0.0
var _hit_dir := Vector3.ZERO
var _sm := {}
var _time := 0.0
var _seed := 0.0
var _hunch := 0.15
var _head_tilt := 0.0
var _lean_side := 0.0
var _limp := 0.0
var _limp_leg := "Right"
var _arm_style := [0, 0]   # 0 往前伸，1 垂着甩
var _arm_h := [0.0, 0.0]
var _lead := 1.0           # 抬哪只手先砍：1 右手，-1 左手


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
	_seed = _rng.randf() * TAU
	_hunch = _rng.randf_range(0.08, 0.32)
	_head_tilt = _rng.randf_range(-0.3, 0.3)
	_lean_side = _rng.randf_range(-0.08, 0.08)
	if _rng.randf() < 0.3:
		_limp = _rng.randf_range(0.3, 0.8)
		_limp_leg = "Left" if _rng.randf() < 0.5 else "Right"
	var style := _rng.randi_range(0, 2)   # 两手前伸 / 两手垂着 / 一伸一垂
	_arm_style = [0, 0] if style == 0 else ([1, 1] if style == 1 else ([0, 1] if _rng.randf() < 0.5 else [1, 0]))
	_arm_h = [_rng.randf_range(-0.25, 0.15), _rng.randf_range(-0.25, 0.15)]
	_voice = "zf_" if type in ["nurse", "arlene", "screamer"] or type.contains("female") else "zm_"
	_roam_t = _rng.randf_range(2.0, 9.0)
	var found := _model.find_children("*", "Skeleton3D", true, false)
	if found.size() > 0:
		_skel = found[0]
		for b in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
				"LeftHandMiddle1", "RightShoulder", "RightArm", "RightForeArm", "RightHand", "RightHandMiddle1",
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
		if _death_t < 0.3:
			_animate(delta)
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
			_lead = 1.0 if _rng.randf() < 0.6 else -1.0
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
		_animate(delta)
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
	_moving = 0.0
	if dist > 0.05:
		var face := to / dist if dist < 3.0 else _dir
		rotation.y = lerp_angle(rotation.y, atan2(face.x, face.z), min(1.0, delta * 6.0))
		if dist > GameConfig.ZOMBIE_REACH * 0.8 and _windup < 0.0 and _scream_t <= 0.0:
			position += _dir * speed * delta
			if world:
				position = world.push_out(position, 0.35)
			_phase += delta * (2.0 + speed * 2.2)
			_moving = speed
	_animate(delta)


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
	_hit_dir = push.normalized() if push.length() > 0.01 else Vector3.ZERO
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

func _animate(delta: float) -> void:
	if _skel == null:
		# 没骨骼的模型就整体晃一晃
		_model.rotation.z = sin(_phase) * 0.06
		_model.position.y = abs(sin(_phase)) * 0.04
		_model.rotation.x = -0.4 * clamp(_stagger / GameConfig.ZOMBIE_STAGGER, 0.0, 1.0)
		return
	if dead:
		# 倒地时手脚摊开
		_aim("LeftArm", "LeftForeArm", Vector3(0.8, 0.2, 0.3))
		_aim("RightArm", "RightForeArm", Vector3(-0.8, 0.2, 0.3))
		return
	_skel.reset_bone_poses()
	_time += delta
	if _moving <= 0.0:
		_phase += delta * 1.2   # 站着也轻轻晃
	# 走/跑的幅度慢慢变，停下、起步不会一下子切换
	var walk := _smooth_f("walk", 1.0 if _moving > 0.0 else 0.0, 5.0, delta)
	var run := _smooth_f("run", clamp((_moving - 1.6) / 1.4, 0.0, 1.0), 4.0, delta)
	var p := _phase
	var s := sin(p)
	var c := cos(p)
	var wind := 0.0
	if _windup >= 0.0:
		wind = clamp(1.0 - _windup / GameConfig.ZOMBIE_WINDUP, 0.0, 1.0)
	var stag: float = clamp(_stagger / GameConfig.ZOMBIE_STAGGER, 0.0, 1.0)
	var screaming := _scream_t > 0.0
	var strike := _lunge
	var hit_react := stag
	# 被打的方向在僵尸的左边还是右边（扭身子往那边躲）
	var hit_side: float = signf(_hit_dir.dot(global_basis.x)) if _hit_dir != Vector3.ZERO else 1.0

	# —— 身体：弓着背，跑起来更低；抬手时后仰，砍下来时往前扑；挨打往后仰并扭开 ——
	var lean: float = _hunch + run * 0.3 - wind * 0.25 + strike * 0.45 - hit_react * 0.35 - stag * 0.35
	if screaming:
		lean = -0.3
	lean = _smooth_f("lean", lean, 7.0 if strike <= 0.0 else 18.0, delta)
	var twist: float = _smooth_f("twist", -s * (0.14 + run * 0.1) * walk + wind * 0.35 * _lead - strike * 0.4 * _lead
			+ hit_react * 0.3 * hit_side, 9.0, delta)
	var roll: float = sin(p * 0.5 + _seed) * 0.05 + hit_react * 0.15 * hit_side + _lean_side
	if _bones.has("Hips"):
		var hips: int = _bones["Hips"]
		var rest := _skel.get_bone_rest(hips)
		var limp_dip: float = _limp * max(0.0, -s) * 0.05
		var bob: float = -abs(c) * (0.035 + run * 0.03) * walk - run * 0.07 - limp_dip
		var sway := _side * s * 0.03 * walk
		_skel.set_bone_pose_position(hips, rest.origin + Vector3(0, bob, 0) + sway + _fwd * strike * 0.08)
		var hq := Quaternion(Vector3.UP, s * 0.12 * walk) * Quaternion(_fwd, (s * 0.06 + _limp * 0.05) * walk)
		_skel.set_bone_pose_rotation(hips, hq * rest.basis.get_rotation_quaternion())
	# 背分在几节脊椎上弯，看起来是一整条弧线而不是一根棍子
	for b in ["Spine", "Spine1", "Spine2"]:
		_turn(b, _side, lean * 0.4)
	_turn("Spine1", _fwd, roll)
	_turn("Spine2", Vector3.UP, twist)
	# 头：抬起来看前面，晃来晃去，有的歪着
	var nod: float = -lean * 0.7 + abs(c) * 0.06 * walk - hit_react * 0.4 - stag * 0.3
	if screaming:
		nod -= 0.5
	var loll: float = _head_tilt + sin(_time * 0.9 + _seed) * 0.12 * (1.0 - run * 0.6)
	_turn("Neck", _side, nod * 0.4)
	_turn("Head", _side, nod * 0.6)
	_turn("Head", _fwd, _smooth_f("loll", loll, 3.0, delta))

	# —— 腿：大腿前后摆；往前迈的那条腿膝盖弯起来，脚落地时伸直；有的僵尸一条腿瘸 ——
	var amp: float = (0.38 + run * 0.32) * walk
	for side in ["Left", "Right"]:
		var lp: float = p if side == "Left" else p + PI
		var a: float = sin(lp) * amp
		var lame: float = _limp if side == _limp_leg else 0.0
		a *= 1.0 - lame * 0.6
		var lift: float = pow(max(0.0, sin(lp + 1.7)), 1.5) * (0.5 + run * 0.7) * walk * (1.0 - lame * 0.7)
		var knee: float = 0.1 + lift + run * 0.15
		var out: float = 0.06 if side == "Left" else -0.06
		_aim(side + "UpLeg", side + "Leg", Vector3(out, -cos(a), sin(a)))
		_aim(side + "Leg", side + "Foot", Vector3(out * 0.5, -cos(a - knee), sin(a - knee)))

	# —— 胳膊：每只僵尸姿势不一样（两手前伸 / 垂着甩 / 一只伸一只耷拉）；跑起来前后摆 ——
	for side in ["Left", "Right"]:
		var sgn := 1.0 if side == "Left" else -1.0
		var lp: float = p + PI if side == "Left" else p   # 和同侧的腿反着摆
		var wob := Vector3(sin(_time * 1.3 + _seed * sgn), sin(_time * 1.7 + _seed * 2.0 * sgn), 0) * 0.08
		var style: int = _arm_style[0 if side == "Left" else 1]
		var up: Vector3
		var fore: Vector3
		if style == 0:
			# 往前伸着够人
			up = Vector3(0.18 * sgn, -0.2 + _arm_h[0 if side == "Left" else 1], 1.0) + Vector3(0, sin(lp) * 0.08, 0)
			fore = up + Vector3(-0.1 * sgn, 0.25, 0.2)
		else:
			# 垂着，跟着步子甩
			up = Vector3(0.18 * sgn, -1.0, 0.12 + sin(lp) * 0.45 * walk)
			fore = up + Vector3(-0.05 * sgn, 0.35, 0.55)
		# 跑：手肘弯起来前后摆
		var pump := Vector3(0.15 * sgn, -0.75, sin(lp) * 0.9)
		up = up.lerp(pump, run * 0.8)
		fore = fore.lerp(pump + Vector3(0, 0.9, 0.7), run * 0.8)
		up += wob
		var lead: bool = (side == "Right") == (_lead > 0.0)
		if wind > 0.0:
			# 抬手：领头的那只举得更高更靠后
			var hi := Vector3(0.3 * sgn, 1.0, 0.15 if lead else 0.5)
			up = up.lerp(hi, wind)
			fore = fore.lerp(hi + Vector3(-0.1 * sgn, 0.3, 0.6), wind)
		elif screaming:
			up = Vector3(0.9 * sgn, 0.15, 0.35) + wob * 2.0
			fore = Vector3(0.6 * sgn, 0.5, 0.5)
		elif stag > 0.0:
			up = up.lerp(Vector3(0.7 * sgn, 0.3 + sin(_time * 18.0 + sgn) * 0.3, 0.3), stag)
			fore = up + Vector3(0, 0.4, 0.2)
		if strike > 0.0:
			# 砍下来：往前下方挥过去
			var low := Vector3((-0.25 if lead else 0.2) * sgn, -0.35, 1.0)
			up = up.lerp(low, strike)
			fore = fore.lerp(low + Vector3(-0.2 * sgn, -0.4, 0.2), strike)
		var k := 6.0 if strike <= 0.0 and wind <= 0.0 else 16.0
		up = _smooth_v(side + "up", up, k, delta)
		fore = _smooth_v(side + "fore", fore, k, delta)
		_turn(side + "Shoulder", _side, -0.15 * max(0.0, up.normalized().y + 0.2))
		_aim(side + "Arm", side + "ForeArm", up)
		_aim(side + "ForeArm", side + "Hand", fore)
		# 手腕耷拉着
		_aim(side + "Hand", side + "HandMiddle1", fore.normalized() + Vector3(0, -0.6, 0))


func _smooth_f(key: String, target_value: float, rate: float, delta: float) -> float:
	var v: float = _sm.get(key, target_value)
	v = lerp(v, target_value, 1.0 - exp(-rate * delta))
	_sm[key] = v
	return v


func _smooth_v(key: String, target_value: Vector3, rate: float, delta: float) -> Vector3:
	var v: Vector3 = _sm.get(key, target_value)
	v = v.lerp(target_value, 1.0 - exp(-rate * delta))
	_sm[key] = v
	return v


## 把一根骨头绕 axis（骨骼空间，用 _side 表示前后弯）转 angle
func _turn(bone_name: String, axis: Vector3, angle: float) -> void:
	if not _bones.has(bone_name) or absf(angle) < 0.001:
		return
	var bone: int = _bones[bone_name]
	var parent := _skel.get_bone_parent(bone)
	var parent_g := _skel.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var g := parent_g * _skel.get_bone_rest(bone)
	var new_basis := Basis(axis.normalized(), angle) * g.basis
	_skel.set_bone_pose_rotation(bone, (parent_g.basis.inverse() * new_basis).get_rotation_quaternion())


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
