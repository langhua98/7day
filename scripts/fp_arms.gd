class_name FpArms
extends Node3D
## 第一人称手臂：用导出的带骨骼手臂（assets/models/fp_arms.glb，肩、臂、手腕、每根手指都有骨头）。
## 素材里的动作是 Unity 人形肌肉动画，没法直接用，所以这里用两段式 IK 把手摆到镜头前，
## 手指弯成握拳，武器挂在右手掌心，挥动时让手沿一条弧线运动。

## 手的位置（相机空间：x 右、y 上、-z 前，单位米）。拿到真机上不顺眼可以改这里。
const RIGHT_HAND := Vector3(0.20, -0.20, -0.40)
const LEFT_HAND_FISTS := Vector3(-0.20, -0.21, -0.38)   # 空手：两个拳头都举在前面
const LEFT_HAND_GUN := Vector3(-0.03, -0.17, -0.58)     # 枪：左手在前面托着
const LEFT_HAND_AWAY := Vector3(-0.30, -0.55, -0.20)    # 单手武器：左手放下，基本看不到
## 武器在手里往前倾多少（弧度）
const WEAPON_TILT := 0.55
## 手指弯曲程度（弧度）：近节、中节、远节
const FINGER_CURL := [1.25, 1.45, 0.9]

enum Pose { FISTS, MELEE, GUN }

var has_arms := false
var _skel: Skeleton3D
var _bones := {}
var _root := Node3D.new()      # 手臂模型的根，转 180° 让模型的 +Z 朝镜头前方
var _weapon_mount := Node3D.new()
var _weapon: Node3D
var _pose := Pose.FISTS
var _swing := 0.0
var _swing_speed := 3.0
var _gun := false
var _bob := 0.0
var _rest_len := {}


func _ready() -> void:
	add_child(_root)
	_build()


func _build() -> void:
	var path := "res://assets/models/fp_arms.glb"
	if not ResourceLoader.exists(path):
		push_warning("没找到 assets/models/fp_arms.glb，只显示武器")
		add_child(_weapon_mount)
		_weapon_mount.position = RIGHT_HAND
		return
	var scene: PackedScene = load(path)
	var inst := scene.instantiate()
	_root.add_child(inst)
	# 素材里男女手臂各一套，只留男性
	for n in inst.get_children():
		if n.name.to_lower().begins_with("female"):
			n.queue_free()
	var skels := inst.find_children("*", "Skeleton3D", true, false)
	for k in skels:
		if not k.get_parent().name.to_lower().begins_with("female"):
			_skel = k
	if _skel == null:
		return
	# 导出时重名的骨头带了 _2 之类的后缀，去掉
	var suffix := RegEx.create_from_string("_\\d+$")
	for i in _skel.get_bone_count():
		_bones[suffix.sub(_skel.get_bone_name(i), "")] = i
	for side in ["Right", "Left"]:
		if not (_bones.has(side + "Arm") and _bones.has(side + "ForeArm") and _bones.has(side + "Hand")):
			return
	has_arms = true
	_apply_texture()
	# 让模型里的 CameraNode 正好落在镜头位置上
	_root.basis = Basis(Vector3.UP, PI)
	var cam_node := Vector3(0, 0.26, 0.27)
	if _bones.has("CameraNode"):
		cam_node = _skel.get_bone_global_rest(_bones.CameraNode).origin
	_root.position = -(_root.basis * cam_node)
	for side in ["Right", "Left"]:
		var a := _rest_pos(side + "Arm")
		var f := _rest_pos(side + "ForeArm")
		var h := _rest_pos(side + "Hand")
		_rest_len[side] = [a.distance_to(f), f.distance_to(h)]
	# 武器挂在右手骨上
	var att := BoneAttachment3D.new()
	att.bone_name = _skel.get_bone_name(_bones.RightHand)
	_skel.add_child(att)
	att.add_child(_weapon_mount)
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_update_pose(0.0)


func _apply_texture() -> void:
	var tex: Texture2D = null
	for t in GameConfig.FP_ARMS_TEXTURES:
		var p := "res://assets/textures/%s" % t
		if ResourceLoader.exists(p):
			tex = load(p)
			break
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.8
	mat.disable_receive_shadows = true
	if tex:
		mat.albedo_texture = tex
	else:
		mat.albedo_color = Color(0.72, 0.58, 0.48)
	for m in _skel.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = mat


func _rest_pos(bone: String) -> Vector3:
	return _skel.get_bone_global_rest(_bones[bone]).origin


## 相机空间 → 手臂模型空间
func _to_rig(p: Vector3) -> Vector3:
	return _root.transform.affine_inverse() * p


func _dir_to_rig(d: Vector3) -> Vector3:
	return (_root.basis.inverse() * d).normalized()


# —— 摆姿势 ——

## 把一根骨头转到：指向 dir（朝子骨头的方向），手掌一侧朝 side。
## 静止姿势里两条手臂都是 T 字平举、掌心朝下，所以静止时的「手掌一侧」是 -Y。
func _set_frame(bone: String, child_pos_rest: Vector3, dir: Vector3, side: Vector3) -> void:
	var b: int = _bones[bone]
	var parent := _skel.get_bone_parent(b)
	var parent_g := _skel.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var rest_g := _skel.get_bone_global_rest(b)
	var dir_rest := (child_pos_rest - rest_g.origin).normalized()
	var side_rest := Vector3.DOWN
	var want := _frame(dir, side)
	var have := _frame(dir_rest, side_rest)
	var new_basis := want * have.inverse() * rest_g.basis
	var local := parent_g.basis.inverse() * new_basis
	_skel.set_bone_pose_rotation(b, local.get_rotation_quaternion())


func _frame(dir: Vector3, side: Vector3) -> Basis:
	var x := dir.normalized()
	var y := (side - x * side.dot(x))
	if y.length() < 0.001:
		y = x.cross(Vector3.FORWARD)
	y = y.normalized()
	return Basis(x, y, x.cross(y))


## 两段式 IK：肩 → 肘 → 手。pole 是手肘大致朝的方向。
func _place_arm(side: String, hand_cam: Vector3, palm_cam: Vector3, finger_cam: Vector3, pole_cam: Vector3) -> void:
	var s := _skel.get_bone_global_pose(_bones[side + "Arm"]).origin
	var h := _to_rig(hand_cam)
	var lens: Array = _rest_len[side]
	var l1: float = lens[0]
	var l2: float = lens[1]
	var to_h := h - s
	var d: float = clamp(to_h.length(), 0.05, (l1 + l2) * 0.999)
	var dir := to_h.normalized()
	var pole := _dir_to_rig(pole_cam)
	pole = (pole - dir * pole.dot(dir)).normalized()
	# 余弦定理求肘部位置
	var a: float = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var hgt: float = sqrt(max(l1 * l1 - a * a, 0.0))
	var elbow := s + dir * a + pole * hgt
	var hand_t := s + dir * d
	var palm := _dir_to_rig(palm_cam)
	_set_frame(side + "Arm", _rest_pos(side + "ForeArm"), elbow - s, palm)
	_set_frame(side + "ForeArm", _rest_pos(side + "Hand"), hand_t - elbow, palm)
	# 小臂上的扭转骨保持跟小臂一致（它们的静止姿势与小臂相同），手腕单独定向
	var finger_child := side + "HandMiddle1"
	_set_frame(side + "Hand", _rest_pos(finger_child) if _bones.has(finger_child) else _rest_pos(side + "Hand") + Vector3.LEFT, _dir_to_rig(finger_cam), palm)


## 手指弯向掌心
func _curl(side: String, amount: float) -> void:
	for f in ["Index", "Middle", "Ring", "Pinky"]:
		for j in 3:
			var bone := "%sHand%s%d" % [side, f, j + 1]
			if not _bones.has(bone):
				continue
			_bend(bone, FINGER_CURL[j] * amount)
	for j in 3:
		var bone := "%sHandThumb%d" % [side, j + 1]
		if _bones.has(bone):
			_bend(bone, [0.35, 0.5, 0.45][j] * amount)


func _bend(bone: String, angle: float) -> void:
	var b: int = _bones[bone]
	var parent := _skel.get_bone_parent(b)
	var parent_g := _skel.get_bone_global_pose(parent)
	var g := parent_g * _skel.get_bone_rest(b)
	# 手指沿骨头方向伸出；掌心方向取手骨的「手掌一侧」
	var hand_g := _skel.get_bone_global_pose(_bones[bone.substr(0, bone.find("Hand") + 4)])
	var hand_rest := _skel.get_bone_global_rest(_bones[bone.substr(0, bone.find("Hand") + 4)])
	var palm := (hand_g.basis * hand_rest.basis.inverse() * Vector3.DOWN).normalized()
	var child_dir := (hand_g.basis * hand_rest.basis.inverse() * (_finger_dir_rest(bone))).normalized()
	var axis := child_dir.cross(palm).normalized()
	if axis.length() < 0.5:
		return
	var new_basis := Basis(axis, angle) * g.basis
	var local := parent_g.basis.inverse() * new_basis
	_skel.set_bone_pose_rotation(b, local.get_rotation_quaternion())


func _finger_dir_rest(bone: String) -> Vector3:
	var b: int = _bones[bone]
	var g := _skel.get_bone_global_rest(b).origin
	var p := _skel.get_bone_global_rest(_skel.get_bone_parent(b)).origin
	var d := g - p
	return d.normalized() if d.length() > 0.0001 else Vector3.LEFT


func _update_pose(delta: float) -> void:
	if not has_arms:
		return
	_skel.reset_bone_poses()
	_bob += delta
	var walk: float = get_meta("walking", 0.0)
	var bob := Vector3(sin(_bob * 9.0) * 0.012, -abs(cos(_bob * 9.0)) * 0.014, 0) * walk
	bob += Vector3(0, sin(_bob * 1.7) * 0.004, 0)
	var t := 0.0
	if _swing > 0.0:
		_swing = max(0.0, _swing - delta * _swing_speed)
		t = 1.0 - _swing
	# 挥动：先抬起后拉（0~0.35），再向前下方劈到准星（0.35~0.7），然后收回
	var lift := 0.0
	var strike := 0.0
	if t > 0.0:
		if t < 0.35:
			lift = smoothstep(0.0, 0.35, t)
		elif t < 0.7:
			lift = 1.0 - smoothstep(0.35, 0.55, t)
			strike = smoothstep(0.35, 0.55, t)
		else:
			strike = 1.0 - smoothstep(0.7, 1.0, t)
	var hand := RIGHT_HAND + bob
	var tilt := WEAPON_TILT
	if _gun:
		hand += Vector3(0, 0.01, 0.05) * strike * 3.0  # 后坐
		lift = 0.0
		strike = 0.0
	hand += Vector3(0.04, 0.16, 0.10) * lift + Vector3(-0.14, 0.02, -0.18) * strike
	tilt += -0.9 * lift + 1.2 * strike
	# 右手：拳眼朝上，手指（握拳前）朝前，掌心朝左
	var fwd := Vector3(0, 0, -1).rotated(Vector3.RIGHT, -0.15)
	var up := Vector3.UP.rotated(Vector3.RIGHT, -tilt)
	var finger := fwd.rotated(Vector3.RIGHT, -tilt * 0.5)
	_place_arm("Right", hand, Vector3.LEFT, finger, Vector3(0.6, -1.0, 0.2))
	_curl("Right", 1.0)
	# 左手
	match _pose:
		Pose.FISTS:
			var lh := LEFT_HAND_FISTS + Vector3(-bob.x, bob.y, 0)
			_place_arm("Left", lh, Vector3.RIGHT, fwd, Vector3(-0.6, -1.0, 0.2))
			_curl("Left", 1.0)
		Pose.GUN:
			_place_arm("Left", LEFT_HAND_GUN + bob, Vector3.UP, Vector3(0.6, 0, -1), Vector3(-0.8, -1.0, 0))
			_curl("Left", 0.55)
		_:
			_place_arm("Left", LEFT_HAND_AWAY + bob, Vector3.RIGHT, Vector3(0, -0.3, -1), Vector3(-0.6, -1.0, 0.2))
			_curl("Left", 0.6)
	_weapon_mount_frame(up)


## 武器挂点：掌心中间，武器的 +Y（握把方向）朝拳眼（上），+Z 朝前
func _weapon_mount_frame(_up_cam: Vector3) -> void:
	if not _weapon:
		return
	var hb: int = _bones.RightHand
	var hand_g := _skel.get_bone_global_pose(hb)
	var hand_rest := _skel.get_bone_global_rest(hb)
	var to_world := hand_g.basis * hand_rest.basis.inverse()   # 静止 → 当前 的旋转
	# 静止时：手指朝 -X，掌心朝 -Y，拇指朝 +Z（模型的前方）
	var fingers := to_world * Vector3.LEFT
	var palm := to_world * Vector3.DOWN
	var thumb := to_world * Vector3.BACK
	var grip_up := thumb.normalized()
	var grip_fwd := fingers.normalized()
	var grip_x := grip_up.cross(grip_fwd).normalized()
	var center := hand_g.origin + fingers * 0.055 + palm * 0.03 + thumb * 0.01
	var g := Transform3D(Basis(grip_x, grip_up, grip_x.cross(grip_up)), center)
	# BoneAttachment3D 跟着手骨走，这里算相对手骨的变换
	_weapon_mount.transform = hand_g.affine_inverse() * g


## 换手上的东西：有模型用模型（真实大小，原点就是握把），没模型用图标
func hold(item_id: String) -> void:
	if _weapon:
		_weapon.queue_free()
		_weapon = null
	_pose = Pose.FISTS
	_gun = false
	if item_id == "":
		return
	var row: Dictionary = Assets.items_by_id.get(item_id, {})
	_gun = row.get("kind", -1) == Assets.Kind.GUN
	_pose = Pose.GUN if _gun else Pose.MELEE
	var holder := Node3D.new()
	var vis: Node3D = null
	if row.get("model", "") != "":
		vis = Assets.make_item_mesh(row.model)
		if vis == null:
			# 只有样例 glb 的物品：缩放到合适大小，底部当握把
			vis = Assets.make_model(row.model, GameConfig.HELD_SIZE, false, Assets.icon_tint(item_id))
			if vis:
				vis.position.y = -0.08
	if vis:
		holder.add_child(vis)
	else:
		var tex := Assets.icon(item_id)
		if tex == null:
			return
		var sp := Sprite3D.new()
		sp.texture = tex
		sp.pixel_size = 0.2 / max(tex.get_width(), 1)
		sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sp.position = Vector3(0, 0.08, 0)
		holder.add_child(sp)
	_weapon_mount.add_child(holder)
	_weapon = holder
	for m in holder.find_children("*", "GeometryInstance3D", true, false):
		(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func swing(speed := 3.0) -> void:
	if _swing <= 0.0:
		_swing = 1.0
		_swing_speed = speed


func is_swinging() -> bool:
	return _swing > 0.0


func _process(delta: float) -> void:
	if has_arms:
		_update_pose(delta)
	elif _swing > 0.0:
		_swing = max(0.0, _swing - delta * _swing_speed)
		_weapon_mount.rotation.x = -1.1 * sin((1.0 - _swing) * PI)
