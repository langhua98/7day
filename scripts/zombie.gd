class_name Zombie
extends Node3D
## 僵尸：用导出的带骨骼 glb，动作全部由代码摆骨骼（导出的包里没有动画）。
## 白天在附近闲逛，看到或听到你才追；夜里一直追。会绕着楼和车走（寻路见 world.gd 的 flow_dir）。
## 攻击先抬手再砍（这段时间退开就能躲），挨打会后退、踉跄，死了往后倒。
## 胖警察会远远地吐酸，尖叫者看到你会叫来别的僵尸。

signal died(zombie: Zombie)
## 要放声音：groan 低吼、attack 扑、scream 尖叫、spit 吐、death 倒地
signal noise(zombie: Zombie, sound: String)
signal spit(zombie: Zombie, from: Vector3, to: Vector3)
signal screamed(zombie: Zombie)

enum State { WANDER, CHASE, WINDUP, STAGGER, SPIT, SCREAM, DEAD }

var hp := 60.0
var max_hp := 60.0
var speed := 1.0
var target: Node3D
## 市中心（用来绕开楼和车）
var world: World
var dead := false
var state := State.WANDER
## 夜里、血月、被惊动后一直追
var aggressive := false
var kind := {}
var kind_name := "僵尸"
var height := 1.85
var damage := 9.0
var armor := 0.0
## 这一帧打中玩家的伤害（main 取走）
var pending_damage := 0.0

var _model: Node3D
var _skel: Skeleton3D
var _yaw := 0.0
var _phase := 0.0
var _attack_cd := 0.0
var _state_t := 0.0
var _strike := 0.0
var _hit_react := 0.0
var _hit_dir := Vector3.BACK
var _hit_flash := 0.0
var _death_t := 0.0
var _fall_axis := Vector3.RIGHT
var _push := Vector3.ZERO
var _move_dir := Vector3.ZERO
var _wander_to := Vector3.ZERO
var _wander_wait := 0.0
var _think_wander := 0.0
var _think := 0.0
var _direct := false
var _groan_t := 0.0
var _special_cd := 0.0
var _moving := 0.0
var _bones := {}
var _rng := RandomNumberGenerator.new()
var _meshes: Array[MeshInstance3D] = []
# 骨骼空间里的「前」和「右」，从脚尖方向推出来（不同僵尸的导出朝向不一样）
var _fwd := Vector3.BACK
var _side := Vector3.RIGHT

static var _flash_mat: StandardMaterial3D


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
	height = h
	add_child(_model)
	_model.rotation.y = GameConfig.ZOMBIE_FACING_OFFSET
	_rng.randomize()
	kind = Assets.zombie_type(model_name)
	kind_name = kind.get("name", "僵尸")
	hp = hp_value * kind.get("hp", 1.0)
	max_hp = hp
	damage = kind.get("dmg", GameConfig.ZOMBIE_DAMAGE)
	armor = kind.get("armor", 0.0)
	speed = speed_value * kind.get("speed", 1.0) * _rng.randf_range(0.88, 1.12)
	target = player
	_phase = _rng.randf() * TAU
	_groan_t = _rng.randf_range(2.0, 9.0)
	_special_cd = _rng.randf_range(2.0, 5.0)
	var found := _model.find_children("*", "Skeleton3D", true, false)
	if found.size() > 0:
		_skel = found[0]
		for b in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftArm", "LeftForeArm", "LeftHand",
				"RightArm", "RightForeArm", "RightHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]:
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


func place_at(p: Vector3) -> void:
	position = p
	_yaw = _rng.randf() * TAU
	rotation.y = _yaw
	_wander_to = p


# —— 每帧 ——

func _process(delta: float) -> void:
	if dead:
		_update_death(delta)
		return
	_attack_cd = max(0.0, _attack_cd - delta)
	_special_cd = max(0.0, _special_cd - delta)
	_strike = max(0.0, _strike - delta * 3.5)
	_hit_react = max(0.0, _hit_react - delta * 4.0)
	_state_t += delta
	if _hit_flash > 0.0:
		_hit_flash -= delta
		if _hit_flash <= 0.0:
			_set_flash(false)
	# 被打退：冲量慢慢衰减
	if _push.length_squared() > 0.0001:
		position += _push * delta
		_push = _push.move_toward(Vector3.ZERO, delta * 9.0)
		if world:
			position = world.push_out(position, 0.35)
	if target == null:
		return
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var dir := to / dist if dist > 0.01 else Vector3.FORWARD
	_moving = 0.0
	_groan_t -= delta
	if _groan_t <= 0.0:
		_groan_t = _rng.randf_range(5.0, 12.0) if state == State.WANDER else _rng.randf_range(3.0, 7.0)
		noise.emit(self, "groan")

	match state:
		State.WANDER:
			_think -= delta
			if _think <= 0.0:
				_think = 0.4
				if aggressive or _notices(dist, dir):
					_set_state(State.CHASE)
			_wander(delta)
		State.CHASE:
			_chase(delta, dist, dir)
		State.WINDUP:
			_face(dir, delta, 10.0)
			if _state_t >= GameConfig.ZOMBIE_WINDUP:
				_strike = 1.0
				_attack_cd = kind.get("cooldown", GameConfig.ZOMBIE_ATTACK_COOLDOWN)
				if dist <= GameConfig.ZOMBIE_REACH + 0.45 and absf(target.global_position.y - global_position.y) < 1.6:
					pending_damage += damage
				_set_state(State.CHASE)
		State.STAGGER:
			if _state_t >= 0.45:
				_set_state(State.CHASE)
		State.SPIT:
			_face(dir, delta, 8.0)
			if _state_t >= 0.7:
				spit.emit(self, global_position + Vector3.UP * (height - 0.25) + dir * 0.4, target.global_position + Vector3.UP * 1.2)
				noise.emit(self, "spit")
				_special_cd = GameConfig.SPIT_COOLDOWN * _rng.randf_range(0.8, 1.3)
				_set_state(State.CHASE)
		State.SCREAM:
			_face(dir, delta, 6.0)
			if _state_t >= 0.3 and _special_cd <= 0.0:
				_special_cd = GameConfig.SCREAM_COOLDOWN
				noise.emit(self, "scream")
				screamed.emit(self)
			if _state_t >= 1.8:
				_set_state(State.CHASE)
	rotation.y = _yaw
	_animate(delta)


func _set_state(s: int) -> void:
	state = s
	_state_t = 0.0


func _face(dir: Vector3, delta: float, rate: float) -> void:
	_yaw = lerp_angle(_yaw, atan2(dir.x, dir.z), min(1.0, delta * rate))


## 白天：离得近，或者在前方看得见，就发现你
func _notices(dist: float, dir: Vector3) -> bool:
	if dist < GameConfig.ZOMBIE_NOTICE:
		return true
	if dist > GameConfig.ZOMBIE_SIGHT or world == null:
		return false
	var facing := Vector3(sin(_yaw), 0, cos(_yaw))
	if facing.dot(dir) < 0.2:
		return false
	return not world.line_blocked(global_position + Vector3.UP * (height - 0.2), target.global_position + Vector3.UP * 1.5)


## 听到动静（枪声、跑步、打斗）：附近的僵尸都会过来
func hear(from: Vector3, radius: float) -> void:
	if dead or state != State.WANDER:
		return
	var d := Vector2(from.x - global_position.x, from.z - global_position.z).length()
	if d <= radius:
		_set_state(State.CHASE)


func _wander(delta: float) -> void:
	if _wander_wait > 0.0:
		_wander_wait -= delta
		return
	var to := _wander_to - global_position
	to.y = 0.0
	_think_wander += delta
	if to.length() < 0.6 or _think_wander > 12.0:
		# 走到了（或者卡住了），站一会儿再换个地方
		_wander_wait = _rng.randf_range(2.0, 6.0)
		_think_wander = 0.0
		if world:
			_wander_to = world.free_point(global_position, 3.0, 10.0)
		return
	_step(to.normalized(), speed * 0.45, delta)


func _chase(delta: float, dist: float, dir: Vector3) -> void:
	if dist <= GameConfig.ZOMBIE_REACH and _attack_cd <= 0.0:
		_set_state(State.WINDUP)
		noise.emit(self, "attack")
		return
	var special: String = kind.get("special", "")
	if special != "" and _special_cd <= 0.0 and world:
		var sees := not world.line_blocked(global_position + Vector3.UP * (height - 0.2), target.global_position + Vector3.UP * 1.4)
		if special == "spit" and dist > GameConfig.SPIT_RANGE.x and dist < GameConfig.SPIT_RANGE.y and sees:
			_set_state(State.SPIT)
			return
		if special == "scream" and dist < GameConfig.SCREAM_RANGE and sees:
			_set_state(State.SCREAM)
			return
	# 每隔一会儿看看能不能直线走过去；不能就按寻路绕
	_think -= delta
	if _think <= 0.0:
		_think = _rng.randf_range(0.25, 0.4)
		_direct = dist < 2.5 or world == null or (dist < 30.0 and world.walkable_line(global_position, target.global_position))
	var want := dir
	if not _direct:
		var f := world.flow_dir(global_position)
		if f != Vector3.ZERO:
			want = f
	if dist > GameConfig.ZOMBIE_REACH * 0.75:
		_step(want, speed, delta)
	# 离得近时脸朝玩家，远的时候朝走的方向
	_face(dir if dist < 4.0 else (_move_dir if _move_dir != Vector3.ZERO else dir), delta, 7.0)


func _step(want: Vector3, spd: float, delta: float) -> void:
	_move_dir = want if _move_dir == Vector3.ZERO else _move_dir.lerp(want, min(1.0, delta * 8.0)).normalized()
	position += _move_dir * spd * delta
	if world:
		position = world.push_out(position, 0.35)
	_phase += delta * (2.0 + spd * 2.2)
	_moving = spd
	if state == State.WANDER:
		_face(_move_dir, delta, 4.0)


func distance_to_target() -> float:
	if target == null:
		return INF
	var d := target.global_position - global_position
	d.y = 0.0
	return d.length()


func take_pending_damage() -> float:
	var d := pending_damage
	pending_damage = 0.0
	return d


# —— 挨打 ——

## 一条射线（o 起点、d 单位方向）打没打中这只僵尸。打中返回 {t 距离, head 是否爆头, point 命中点}
func ray_hit(o: Vector3, d: Vector3, max_t: float, radius: float) -> Dictionary:
	if dead:
		return {}
	var c := global_position
	var d2 := Vector2(d.x, d.z)
	var l2 := d2.length_squared()
	var t: float
	if l2 < 0.0001:
		# 几乎正上正下：看水平距离
		if Vector2(o.x - c.x, o.z - c.z).length() > radius:
			return {}
		t = absf(o.y - (c.y + height * 0.5))
	else:
		t = Vector2(c.x - o.x, c.z - o.z).dot(d2) / l2
		var closest := Vector2(o.x, o.z) + d2 * t
		var miss := closest.distance_to(Vector2(c.x, c.z))
		if miss > radius:
			return {}
	if t < 0.0 or t > max_t:
		return {}
	var p := o + d * t
	var y := p.y - c.y
	if y < 0.05 or y > height + 0.1:
		return {}
	return {"t": t, "head": y > height - GameConfig.HEAD_SIZE, "point": p}


## 挨一下。from 是攻击者的位置，knock 是后退的力度。返回这下有没有打死
func take_hit(amount: float, from: Vector3, knock: float, head := false) -> bool:
	if dead:
		return false
	if not head:
		amount *= 1.0 - armor
	hp -= amount
	_hit_flash = 0.12
	_set_flash(true)
	var away := global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	_hit_dir = away
	_hit_react = 1.0
	_push += away * knock
	if state == State.WANDER:
		_set_state(State.CHASE)
	if hp <= 0.0:
		_die(away)
		return true
	# 重击或爆头会踉跄，打断抬手
	if amount >= GameConfig.STAGGER_DAMAGE or (head and _rng.randf() < 0.6):
		_set_state(State.STAGGER)
	return false


func _die(away: Vector3) -> void:
	dead = true
	state = State.DEAD
	_set_flash(false)
	_death_t = 0.0
	# 朝被打的方向倒：绕着「水平且垂直于倒下方向」的轴转 90°
	_fall_axis = Vector3.UP.cross(away).normalized()
	if _fall_axis.length() < 0.5:
		_fall_axis = Vector3.RIGHT
	noise.emit(self, "death")
	died.emit(self)


func _update_death(delta: float) -> void:
	_death_t += delta
	if _push.length_squared() > 0.0001:
		position += _push * delta * 0.6
		_push = _push.move_toward(Vector3.ZERO, delta * 7.0)
	# 先腿软（0~0.25 秒），再倒下去（越倒越快），落地弹一下
	var fall := 0.0
	if _death_t > 0.15:
		var t: float = min(1.0, (_death_t - 0.15) / 0.6)
		fall = t * t
		if _death_t > 0.75:
			var b := _death_t - 0.75
			fall = 1.0 - 0.06 * sin(min(b * 10.0, PI)) * exp(-b * 4.0)
	var lie := Quaternion(_fall_axis, fall * PI * 0.5)
	quaternion = lie * Quaternion(Vector3.UP, _yaw)
	position.y = fall * 0.12
	if _skel:
		_skel.reset_bone_poses()
		var buckle: float = min(1.0, _death_t * 4.0)
		_aim("LeftUpLeg", "LeftLeg", Vector3(0.05, -0.9, 0.35 * buckle))
		_aim("RightUpLeg", "RightLeg", Vector3(-0.05, -0.9, 0.25 * buckle))
		_aim("LeftLeg", "LeftFoot", Vector3(0, -1.0, -0.7 * buckle))
		_aim("RightLeg", "RightFoot", Vector3(0, -1.0, -0.5 * buckle))
		# 胳膊甩起来，落地后摊开
		var up := 0.8 * (1.0 - fall) + 0.1
		_aim("LeftArm", "LeftForeArm", Vector3(1.0, up, -0.2))
		_aim("RightArm", "RightForeArm", Vector3(-1.0, up, -0.3))
		_aim("LeftForeArm", "LeftHand", Vector3(0.8, up * 0.7, 0.3))
		_aim("RightForeArm", "RightHand", Vector3(-0.8, up * 0.7, 0.2))
		_turn("Head", _side, 0.4 * buckle)
	if _death_t > GameConfig.CORPSE_TIME:
		position.y -= (_death_t - GameConfig.CORPSE_TIME) * 0.25
	if _death_t > GameConfig.CORPSE_TIME + 2.5:
		queue_free()


func _set_flash(on: bool) -> void:
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.albedo_color = Color(1.0, 0.1, 0.08, 0.35)
	for m in _meshes:
		m.material_overlay = _flash_mat if on else null


# —— 程序化动作：导出的包里没有动画，用代码摆骨骼 ——

func _animate(delta: float) -> void:
	if _skel == null:
		# 没骨骼的模型就整体晃一晃
		_model.rotation.z = sin(_phase) * 0.06
		_model.position.y = abs(sin(_phase)) * 0.04
		_model.rotation.x = -0.4 * _hit_react
		return
	_skel.reset_bone_poses()
	if _moving <= 0.0:
		_phase += delta * 1.2   # 站着也轻轻晃
	var s := sin(_phase)
	var run: float = clamp((_moving - 1.6) / 1.4, 0.0, 1.0)
	var walk: float = 1.0 if _moving > 0.0 else 0.15
	var swing := (0.42 + run * 0.35) * s * walk
	# 身体前倾：跑起来更低；挨打往后仰
	var lean := 0.12 + run * 0.28 - _hit_react * 0.35
	var wind := 0.0
	match state:
		State.WINDUP:
			wind = clamp(_state_t / GameConfig.ZOMBIE_WINDUP, 0.0, 1.0)
			lean -= 0.18 * wind
		State.STAGGER:
			lean -= 0.4 * (1.0 - _state_t / 0.45)
		State.SCREAM:
			lean -= 0.35
		State.SPIT:
			lean += -0.3 + 0.7 * clamp((_state_t - 0.45) / 0.25, 0.0, 1.0)
	lean += _strike * 0.35
	if _bones.has("Hips"):
		var hips: int = _bones["Hips"]
		var rest := _skel.get_bone_rest(hips)
		_skel.set_bone_pose_position(hips, rest.origin + Vector3(0, -abs(s) * 0.04 * walk - run * 0.06, 0))
		_skel.set_bone_pose_rotation(hips, Quaternion(_fwd, s * 0.05 * walk) * rest.basis.get_rotation_quaternion())
	_turn("Spine1" if _bones.has("Spine1") else "Spine", _side, lean)
	_turn("Head", _side, -lean * 0.4 + (-0.5 if state == State.SCREAM else 0.0))
	# 腿：大腿前后摆，小腿跟着弯
	_aim("LeftUpLeg", "LeftLeg", Vector3(0, -cos(swing), sin(swing)))
	_aim("RightUpLeg", "RightLeg", Vector3(0, -cos(-swing), sin(-swing)))
	_aim("LeftLeg", "LeftFoot", Vector3(0, -1.0, sin(swing) * 0.3 - max(0.0, -s) * (0.6 + run * 0.5) * walk))
	_aim("RightLeg", "RightFoot", Vector3(0, -1.0, -sin(swing) * 0.3 - max(0.0, s) * (0.6 + run * 0.5) * walk))
	# 胳膊：平时向前伸；抬手时举过头，砍下来时往前下方挥
	var arm_y := -0.25 + s * 0.05
	var arm_z := 1.0
	if state == State.WINDUP:
		arm_y = lerp(arm_y, 1.2, wind)
		arm_z = lerp(1.0, 0.35, wind)
	elif _strike > 0.0:
		arm_y = lerp(arm_y, -0.7, _strike)
	if state == State.SCREAM:
		_aim("LeftArm", "LeftForeArm", Vector3(0.9, 0.2, 0.3))
		_aim("RightArm", "RightForeArm", Vector3(-0.9, 0.2, 0.3))
		_aim("LeftForeArm", "LeftHand", Vector3(0.6, 0.5, 0.4))
		_aim("RightForeArm", "RightHand", Vector3(-0.6, 0.5, 0.4))
		return
	if state == State.STAGGER:
		arm_y = 0.3 + sin(_state_t * 20.0) * 0.2
	_aim("LeftArm", "LeftForeArm", Vector3(0.12, arm_y + run * 0.15 * s, arm_z))
	_aim("RightArm", "RightForeArm", Vector3(-0.12, arm_y - run * 0.15 * s, arm_z))
	_aim("LeftForeArm", "LeftHand", Vector3(0.05, arm_y * 0.6 + 0.0, 1.0))
	_aim("RightForeArm", "RightHand", Vector3(-0.05, arm_y * 0.6 + 0.0, 1.0))


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
