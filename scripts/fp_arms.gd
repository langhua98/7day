class_name FpArms
extends Node3D
## 第一人称手臂：用导出的带骨骼手臂（assets/models/fp_arms.glb，肩、臂、手腕、每根手指都有骨头）。
## 素材里的动作是 Unity 人形肌肉动画，没法直接用，所以这里用两段式 IK 把手摆到镜头前，
## 手指弯成握拳（拇指压在四指外面），武器从拳心穿出；攻击按关键帧动作走（出拳、斜劈、下砸、前刺）。

## 手的位置（相机空间：x 右、y 上、-z 前，单位米）。拿到真机上不顺眼可以改这里。
const RIGHT_HAND := Vector3(0.17, -0.13, -0.36)          # 空手：右拳
const LEFT_HAND_FISTS := Vector3(-0.17, -0.14, -0.34)   # 空手：两个拳头都举在前面
const LEFT_HAND_AWAY := Vector3(-0.30, -0.55, -0.20)    # 单手武器：左手放下，基本看不到
## 拳心（握把穿过的地方）相对手腕：沿手指 / 往掌心（米）
const GRIP_OFFSET := Vector2(0.06, 0.03)
## 握把在拳头里往指尖方向斜多少（弧度），真握东西时杆不是和手腕垂直的
const GRIP_TILT := 0.3
## 手指弯曲程度（弧度）。每根手指 6 节骨头：1 是掌骨，2 是指根关节，3 和 2 同在第一节指骨里，
## 4、5 是第二、三节指骨的关节，6 是指尖。握拳时四指一共要弯大约 270°
const FINGER_CURL := [0.08, 1.15, 0.35, 1.45, 1.0]
## 握拳时拇指尖的位置（相对手骨：沿四指 / 往掌心 / 往拇指一侧，米）
const THUMB_FIST := Vector3(0.085, 0.05, 0.0)

## 枪手的位置
const PISTOL_HAND := Vector3(0.17, -0.19, -0.40)
const RIFLE_HAND := Vector3(0.15, -0.19, -0.28)
## 枪模型的枪口朝 +Z 还是 -Z（七日杀的枪都朝 +Z）
const GUN_BARREL_PLUS_Z := true
## 握把在枪身长度上的位置（从枪托那头算起）。枪模型的原点不在握把上，只能按比例估
const RIFLE_GRIP_AT := 0.36
const PISTOL_GRIP_AT := 0.22
## 没有专门的枪网格、只能用样例模型时的长度
const SAMPLE_PISTOL_LEN := 0.24
const SAMPLE_RIFLE_LEN := 0.85
## 自己没有完整枪模型的枪（猎枪只导出了瞄准镜、马格南只导出了一个零件、AK47 没有模型），借同类枪的模型
const GUN_STAND_IN := [["Magnum", "desertEaglePrefab"], ["Handgun", "pipeRevolverPrefab"], ["SMG", "smgPrefab"],
	["Rifle", "leverActionRiflePrefab"], ["MG", "tacticalAssaultRiflePrefab"],
	["Shotgun", "pumpShotgunPrefab"]]

## 近战动作关键帧：[时间, 握点, 杆方向, 武器头朝向]（相机空间）。
## 伤害在 0.38 左右结算（main.gd 的 _attack），所以武器头在那一刻扫过准星。
## 单手武器（棍、斧、刀、镐、扳手…）：从右上方斜着劈到左下方
const SWING_ONE := [
	[0.0, Vector3(0.21, -0.22, -0.40), Vector3(-0.30, 1.0, -0.45), Vector3(-0.35, 0.1, -1.0)],
	[0.22, Vector3(0.28, -0.06, -0.30), Vector3(0.40, 0.85, 0.35), Vector3(-0.30, 0.55, -0.75)],
	[0.38, Vector3(0.10, -0.15, -0.50), Vector3(-0.60, 0.50, -0.65), Vector3(-0.55, -0.60, 0.10)],
	[0.55, Vector3(-0.10, -0.32, -0.42), Vector3(-0.90, -0.40, -0.25), Vector3(-0.10, -0.60, 0.80)],
	[1.0, Vector3(0.21, -0.22, -0.40), Vector3(-0.30, 1.0, -0.45), Vector3(-0.35, 0.1, -1.0)],
]
## 大锤：双手举过肩，往前下方砸
const SWING_HEAVY := [
	[0.0, Vector3(0.20, -0.26, -0.42), Vector3(-0.35, 1.0, -0.30), Vector3(-0.2, 0.0, -1.0)],
	[0.25, Vector3(0.20, 0.00, -0.22), Vector3(0.10, 0.60, 0.80), Vector3(0.0, 1.0, -0.4)],
	[0.38, Vector3(0.06, -0.16, -0.50), Vector3(-0.08, 0.40, -1.0), Vector3(0.0, -1.0, -0.4)],
	[0.55, Vector3(0.04, -0.30, -0.46), Vector3(-0.08, -0.25, -1.0), Vector3(0.0, -1.0, 0.25)],
	[1.0, Vector3(0.20, -0.26, -0.42), Vector3(-0.35, 1.0, -0.30), Vector3(-0.2, 0.0, -1.0)],
]
## 矛：端在身侧往前捅
const SWING_SPEAR := [
	[0.0, Vector3(0.22, -0.20, -0.36), Vector3(-0.18, 0.22, -1.0), Vector3(0.3, -1.0, 0.0)],
	[0.2, Vector3(0.25, -0.18, -0.22), Vector3(-0.16, 0.24, -1.0), Vector3(0.3, -1.0, 0.0)],
	[0.38, Vector3(0.10, -0.17, -0.58), Vector3(-0.08, 0.16, -1.0), Vector3(0.3, -1.0, 0.0)],
	[0.5, Vector3(0.10, -0.17, -0.56), Vector3(-0.08, 0.16, -1.0), Vector3(0.3, -1.0, 0.0)],
	[1.0, Vector3(0.22, -0.20, -0.36), Vector3(-0.18, 0.22, -1.0), Vector3(0.3, -1.0, 0.0)],
]
## 出拳：x = 拳头往前打出去多少（负数是先往回收）
const PUNCH := [
	[0.0, Vector3.ZERO], [0.15, Vector3(-0.4, 0, 0)], [0.36, Vector3(1.0, 0, 0)],
	[0.46, Vector3(1.0, 0, 0)], [1.0, Vector3.ZERO],
]
enum Grip { NONE, ONE_HAND, HEAVY, SPEAR, PISTOL, RIFLE, SMALL }

var has_arms := false
var _skel: Skeleton3D
var _bones := {}
var _root := Node3D.new()      # 手臂模型的根，转 180° 让模型的 +Z 朝镜头前方
var _weapon_mount := Node3D.new()
var _weapon: Node3D
var _grip := Grip.NONE
var _weapon_len := 0.3
var _muzzle_local := Vector3(0, 0.03, -0.3)   # 枪口在武器挂点里的位置
var _reload_t := 0.0
var _reload_total := 1.0
var _swing := 0.0
var _swing_speed := 3.0
var _punch_left := false   # 空手时左右交替出拳
var _bob := 0.0
var _sway := Vector2.ZERO
var _sway_target := Vector2.ZERO
var _aiming := false
var _rest_len := {}


func _ready() -> void:
	add_child(_root)
	_build()


func _build() -> void:
	add_child(_weapon_mount)
	_weapon_mount.position = RIGHT_HAND
	var path := "res://assets/models/fp_arms.glb"
	if not ResourceLoader.exists(path):
		push_warning("没找到 assets/models/fp_arms.glb，只显示武器")
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
		for j in FINGER_CURL.size():
			var bone := "%sHand%s%d" % [side, f, j + 1]
			if not _bones.has(bone) or FINGER_CURL[j] == 0.0:
				continue
			_bend(bone, FINGER_CURL[j] * amount)
	_wrap_thumb(side, amount)


## 拇指压在食指、中指的第二节外面（握拳/握把）。拇指的关节轴是斜的，按角度弯会翘出去，
## 所以直接让指尖去够一个点：手骨静止坐标里，四指方向 f、掌心方向 p、拇指一侧 s
func _wrap_thumb(side: String, amount: float) -> void:
	var names := []
	for j in 4:
		names.append("%sHandThumb%d" % [side, j + 1])
	for n in names:
		if not _bones.has(n):
			return
	if not _bones.has(side + "HandMiddle2"):
		return
	var hb: int = _bones[side + "Hand"]
	var hand_rest := _skel.get_bone_global_rest(hb)
	var o := hand_rest.origin
	var f := (_rest_pos(side + "HandMiddle2") - o).normalized()
	var pl := Vector3.DOWN
	var th := _rest_pos(names[0]) - o
	var sd := (th - f * th.dot(f) - pl * th.dot(pl)).normalized()
	var tip_rest := _rest_pos(names[3])
	var fist := o + f * THUMB_FIST.x + pl * THUMB_FIST.y + sd * THUMB_FIST.z
	var want_rest := tip_rest.lerp(fist, amount)
	var to_pose := _skel.get_bone_global_pose(hb) * hand_rest.affine_inverse()
	var target := to_pose * want_rest
	for it in 6:
		for j in [2, 1, 0]:
			var b: int = _bones[names[j]]
			var g := _skel.get_bone_global_pose(b)
			var tip := _skel.get_bone_global_pose(_bones[names[3]]).origin
			var have := tip - g.origin
			var want := target - g.origin
			if have.length() < 0.001 or want.length() < 0.001:
				continue
			var axis := have.cross(want)
			if axis.length() < 0.00001:
				continue
			var ang: float = min(have.angle_to(want), 0.6)
			var parent_g := _skel.get_bone_global_pose(_skel.get_bone_parent(b))
			var local := parent_g.basis.inverse() * (Basis(axis.normalized(), ang) * g.basis)
			_skel.set_bone_pose_rotation(b, local.get_rotation_quaternion())


## 把一节手指弯向掌心；toward_rest 不为零时改为弯向这个方向（静止姿势下的方向）
func _bend(bone: String, angle: float, toward_rest := Vector3.ZERO, w := 1.0) -> void:
	var b: int = _bones[bone]
	var parent := _skel.get_bone_parent(b)
	var parent_g := _skel.get_bone_global_pose(parent)
	var g := parent_g * _skel.get_bone_rest(b)
	# 手指沿骨头方向伸出；掌心方向取手骨的「手掌一侧」
	var hand_g := _skel.get_bone_global_pose(_bones[bone.substr(0, bone.find("Hand") + 4)])
	var hand_rest := _skel.get_bone_global_rest(_bones[bone.substr(0, bone.find("Hand") + 4)])
	var palm := (hand_g.basis * hand_rest.basis.inverse() * Vector3.DOWN).normalized()
	var child_dir := (hand_g.basis * hand_rest.basis.inverse() * (_finger_dir_rest(bone))).normalized()
	var toward := palm
	if toward_rest != Vector3.ZERO:
		toward = (palm + (hand_g.basis * hand_rest.basis.inverse() * toward_rest).normalized() * w).normalized()
	var axis := child_dir.cross(toward).normalized()
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


## 一个动作在 t 时刻的样子：关键帧之间平滑过渡。
## 近战关键帧是 [时间, 握点, 杆方向（握把 → 武器头）, 武器头朝向]，都在相机空间
func _sample(keys: Array, t: float) -> Array:
	var i := 0
	while i < keys.size() - 2 and t > keys[i + 1][0]:
		i += 1
	var a: Array = keys[i]
	var b: Array = keys[i + 1]
	var u: float = clamp((t - a[0]) / max(b[0] - a[0], 0.001), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	var out := [a[1].lerp(b[1], u)]
	for j in range(2, a.size()):
		out.append((a[j] as Vector3).normalized().slerp((b[j] as Vector3).normalized(), u))
	return out


func _swing_keys() -> Array:
	match _grip:
		Grip.HEAVY:
			return SWING_HEAVY
		Grip.SPEAR:
			return SWING_SPEAR
	return SWING_ONE


## 手握住一根杆：杆从拇指一侧穿出（指向武器头），四指的指根朝 face。
## 右手的掌心 = 杆 × 指向；左手反过来。返回 [手腕位置, 掌心, 指向]
func _grip_frame(side: String, grip: Vector3, shaft: Vector3, face: Vector3) -> Array:
	var s := shaft.normalized()
	var f := (face - s * face.dot(s)).normalized()
	var palm := s.cross(f) if side == "Right" else f.cross(s)
	return [grip - f * GRIP_OFFSET.x - palm * GRIP_OFFSET.y, palm, f]


## 转头时给手臂一点惯性：先被甩一下，再慢慢回到原位
func look(px: Vector2) -> void:
	_sway_target += Vector2(-px.x, -px.y) * 0.0009
	_sway_target = _sway_target.limit_length(0.4)


func set_aiming(on: bool) -> void:
	_aiming = on


func _update_pose(delta: float) -> void:
	if not has_arms:
		return
	_skel.reset_bone_poses()
	_bob += delta
	_sway_target = _sway_target.lerp(Vector2.ZERO, 1.0 - exp(-delta * 10.0))
	_sway = _sway.lerp(_sway_target, 1.0 - exp(-delta * 18.0))
	var sway_hand := Vector3(_sway.x * 0.12, -_sway.y * 0.1, 0.0)
	var walk: float = get_meta("walking", 0.0)
	var bob := Vector3(sin(_bob * 9.0) * 0.012, -abs(cos(_bob * 9.0)) * 0.014, 0) * walk
	bob += Vector3(0, sin(_bob * 1.7) * 0.004, 0)
	var t := 0.0
	if _swing > 0.0:
		_swing = max(0.0, _swing - delta * _swing_speed)
		t = 1.0 - _swing
	var run := sway_hand
	match _grip:
		Grip.NONE:
			_pose_fists(t, bob + run)
		Grip.PISTOL, Grip.RIFLE:
			_pose_gun(t, bob + run, delta)
		_:
			var k := _sample(_swing_keys(), t)
			var g: Vector3 = k[0] + bob + run
			var fr := _grip_frame("Right", g, k[1], k[2])
			# 手肘：平时朝外下方，举高时朝外
			var pole := Vector3(0.7, -1.0, 0.3).lerp(Vector3(1.0, 0.2, 0.3), clamp(g.y + 0.1, 0.0, 1.0) * 3.0)
			_place_arm("Right", fr[0], fr[1], fr[2], pole)
			_curl("Right", 0.9)
			_update_mount(0.0, 0.0)
			if _grip == Grip.HEAVY or _grip == Grip.SPEAR:
				# 双手武器：左手握在杆上（大锤握在下面，矛握在前面）
				var shaft: Vector3 = _weapon_mount.basis.y
				var face: Vector3 = _weapon_mount.basis.z
				var at := -0.2 if _grip == Grip.HEAVY else 0.32
				var lf := _grip_frame("Left", _weapon_mount.position + shaft * at, shaft, face)
				_place_arm("Left", lf[0], lf[1], lf[2], Vector3(-0.8, -1.0, 0.2))
				_curl("Left", 0.9)
			else:
				_place_arm("Left", LEFT_HAND_AWAY + bob + sway_hand, Vector3.RIGHT, Vector3(0, -0.3, -1), Vector3(-0.6, -1.0, 0.2))
				_curl("Left", 0.6)


## 空手：两个拳头举在前面，左右交替出拳（拳头往准星直直打出去，打到头时掌心转向下）
func _pose_fists(t: float, bob: Vector3) -> void:
	var p := 0.0
	if t > 0.0:
		p = _sample(PUNCH, t)[0].x
	var right_hits := not _punch_left
	for side in ["Right", "Left"]:
		var sign := 1.0 if side == "Right" else -1.0
		var rest: Vector3 = RIGHT_HAND if side == "Right" else LEFT_HAND_FISTS
		var hit := Vector3(0.06 * sign, -0.07, -0.50)
		var mine := p if (side == "Right") == right_hits else 0.0
		var back: float = max(0.0, -mine)
		var fwd: float = max(0.0, mine)
		# 另一只手出拳时这只手往回收一点护着脸
		var guard := (p if (side == "Right") != right_hits else 0.0)
		var h := rest + Vector3(sign * -bob.x, bob.y, 0) + Vector3(0.01 * sign, -0.01, 0.05) * back
		h = h.lerp(hit, fwd) + Vector3(-0.02 * sign, 0.02, 0.04) * max(guard, 0.0)
		var palm := Vector3(-sign, 0, 0).lerp(Vector3(-sign * 0.6, -1, 0), fwd * 0.6).normalized()
		var finger := Vector3(0.18 * -sign, 0.25, -1).lerp(Vector3(-0.15 * sign, 0.3, -1), fwd)
		_place_arm(side, h, palm, finger, Vector3(0.6 * sign, -1.0, 0.0))
		_curl(side, 1.0)


func _pose_gun(t: float, bob: Vector3, delta: float) -> void:
	# 枪：手腕放平，握把略向后倾；开枪时往后上方一顿；换弹时往下压
	var kick := sin(t * PI) if t > 0.0 else 0.0
	var rl := 0.0
	if _reload_t > 0.0:
		_reload_t = max(0.0, _reload_t - delta)
		rl = sin((1.0 - _reload_t / _reload_total) * PI)
	var hand := (PISTOL_HAND if _grip == Grip.PISTOL else RIFLE_HAND) + bob + Vector3(0, 0.015, 0.06) * kick \
		+ Vector3(-0.05, -0.12, 0.06) * rl
	if _aiming:
		hand = Vector3(0.0, -0.19, -0.45) + bob
	_place_arm("Right", hand, Vector3.LEFT, Vector3(0, -0.25, -1), Vector3(0.6, -1.0, 0.2))
	_curl("Right", 0.85)
	_update_mount(kick, rl)
	if _grip == Grip.RIFLE:
		# 左手托在枪管下面
		var lh := _gun_point(Vector3(0, -0.045, _weapon_len * 0.34))
		_place_arm("Left", lh, Vector3.UP, Vector3(0.7, 0, -0.7), Vector3(-0.8, -1.0, 0))
		_curl("Left", 0.75)
	else:
		_place_arm("Left", LEFT_HAND_AWAY + bob, Vector3.RIGHT, Vector3(0, -0.3, -1), Vector3(-0.6, -1.0, 0.2))
		_curl("Left", 0.6)


## 武器摆在右手的拳心（相机空间）。近战武器已经摆正成：杆沿 +Y、握把在原点、武器头朝 +Z；
## 枪沿 Z 方向、原点在握把附近。
func _update_mount(kick: float, rl: float) -> void:
	if not _weapon:
		return
	var hb: int = _bones.RightHand
	var hand_g := _skel.get_bone_global_pose(hb)
	var hand_rest := _skel.get_bone_global_rest(hb)
	var to_now := _root.basis * hand_g.basis * hand_rest.basis.inverse()
	# 静止时：手指朝 -X，掌心朝 -Y，拇指朝 +Z
	var fingers := (to_now * Vector3.LEFT).normalized()
	var palm := (to_now * Vector3.DOWN).normalized()
	var thumb := (to_now * Vector3.BACK).normalized()
	var center := _root.transform * hand_g.origin + fingers * GRIP_OFFSET.x + palm * GRIP_OFFSET.y
	var b: Basis
	match _grip:
		Grip.PISTOL, Grip.RIFLE:
			# 枪口朝正前方，稍微往里收一点对准准星；握把落在掌心（挂点原点就是握把）；换弹时枪口往下
			var yaw := 0.0 if _aiming else (0.06 if _grip == Grip.PISTOL else 0.03)
			b = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.12 * kick + 0.5 * rl) * Basis(Vector3.UP, PI)
			center += palm * 0.01
		_:
			# 杆从拇指一侧穿出，武器头朝指根方向；握把再往指尖方向斜一点，像真握着一样
			var y := thumb
			var z := (fingers - y * fingers.dot(y)).normalized()
			b = Basis(y.cross(z), y, z) * Basis(Vector3.RIGHT, GRIP_TILT)
	b = Basis(Vector3.UP, _sway.x * 0.45) * Basis(Vector3.RIGHT, -_sway.y * 0.35) * b
	_weapon_mount.transform = Transform3D(b, center)


## 近战武器模型的朝向各不一样（有的杆沿 Y，有的沿 Z，有的原点在中间），
## 按包围盒摆正：最长的一边当杆（+Y），第二长的一边是武器头伸出去的方向（+Z）。
## grip_at：手握在离杆尾多远的地方（占杆长的比例）
func _align_melee(mi: MeshInstance3D, grip_at: float) -> void:
	var bb := mi.mesh.get_aabb()
	var lo := bb.position
	var hi := bb.end
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var order := [0, 1, 2]
	order.sort_custom(func(a, b): return bb.size[a] > bb.size[b])
	var li: int = order[0]
	var fi: int = order[1]
	var l: Vector3 = axes[li]
	# 杆沿 Y 的模型（七日杀原本的朝向）武器头在上面，原点一般就是握把；原点在杆中间的（大锤、钢镐、矛）
	# 改成握在杆尾附近，不然挥下去时后半截杆会戳到镜头前。别的方向的：离原点远的一头是武器头
	var grip := Vector3.ZERO
	if li != 1 and -lo[li] > hi[li]:
		l = -l
	var butt: float = lo[li] if l[li] > 0.0 else hi[li]
	if li != 1 or -lo[li] > bb.size[li] * grip_at:
		grip = l * (butt * l[li] + bb.size[li] * grip_at)
		grip[(li + 1) % 3] = bb.get_center()[(li + 1) % 3]
		grip[(li + 2) % 3] = bb.get_center()[(li + 2) % 3]
	var f: Vector3 = axes[fi]
	if -lo[fi] > hi[fi]:
		f = -f
	var m := Basis(l.cross(f), l, f)   # 摆正后的轴 → 模型原来的轴
	var to_held := m.inverse()
	mi.transform = Transform3D(to_held, -(to_held * grip))


## 枪上一点（相对握把，单位米，+Z 朝枪口）→ FpArms 空间
func _gun_point(p: Vector3) -> Vector3:
	return _weapon_mount.transform * p


## 换手上的东西：有模型用模型（真实大小，原点就是握把），没模型用图标
func hold(item_id: String) -> void:
	if _weapon:
		_weapon.queue_free()
		_weapon = null
	_grip = Grip.NONE
	if item_id == "":
		return
	var row: Dictionary = Assets.items_by_id.get(item_id, {})
	var kind: int = row.get("kind", -1)
	var holder := Node3D.new()
	if kind == Assets.Kind.BLOCK:
		# 建造方块：手里托着一块小方块
		var cube := Blocks.make_node(item_id)
		cube.scale = Vector3.ONE * 0.11
		cube.position = Vector3(-0.055, -0.02, -0.055)
		holder.add_child(cube)
		_grip = Grip.SMALL
		_mount(holder)
		return
	var vis: Node3D = null
	var size := Vector3(0.1, 0.3, 0.1)
	if row.get("model", "") == "" and kind == Assets.Kind.GUN:
		vis = _stand_in_gun(item_id)
	if row.get("model", "") != "":
		vis = Assets.make_item_mesh(row.model, Assets.icon_tint(item_id))
		if vis is MeshInstance3D:
			size = (vis as MeshInstance3D).mesh.get_aabb().size
			# 有的导出网格缩得极小，或者只导出了一个零件（比如猎枪只有瞄准镜），当作没有模型
			if size.length() < 0.03 or (kind == Assets.Kind.GUN and max(size.x, size.y, size.z) < 0.2):
				vis.free()
				vis = null
			elif kind != Assets.Kind.GUN:
				var long: float = max(size.x, size.y, size.z)
				var heavy: bool = item_id.to_lower().contains("sledge") or row.get("power", 0.0) >= 40.0
				_align_melee(vis, 0.4 if long > 1.4 else (0.3 if heavy else 0.12))
				size = Vector3(0.1, long, 0.1)
		if vis == null and kind == Assets.Kind.GUN:
			vis = _stand_in_gun(item_id)
		if vis == null:
			# 只有样例 glb 的物品：缩放到合适大小，底部当握把
			var held: float = GameConfig.HELD_SIZE
			if kind == Assets.Kind.GUN:
				held = SAMPLE_PISTOL_LEN if "Handgun" in item_id else SAMPLE_RIFLE_LEN
			vis = Assets.make_model(row.model, held, false, Assets.icon_tint(item_id))
			if vis:
				size = Vector3(0.1, held, 0.1)
				if kind != Assets.Kind.GUN:
					vis.position.y = -0.08
	if kind == Assets.Kind.GUN and vis:
		_fit_gun(vis, item_id)
	elif kind == Assets.Kind.GUN:
		_grip = Grip.PISTOL
	elif item_id.to_lower().contains("knuckles"):
		# 拳套：还是出拳
		if vis:
			vis.free()
		return
	elif size.y > 1.4:
		_grip = Grip.SPEAR
	elif item_id.to_lower().contains("sledge") or row.get("power", 0.0) >= 40.0:
		_grip = Grip.HEAVY
	elif max(size.x, size.y, size.z) < 0.25:
		_grip = Grip.SMALL
	else:
		_grip = Grip.ONE_HAND
	if vis:
		holder.add_child(vis)
	else:
		var tex := Assets.icon(item_id)
		if tex == null:
			return
		var sp := Sprite3D.new()
		sp.texture = tex
		sp.pixel_size = 0.16 / max(tex.get_width(), 1)
		sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sp.position = Vector3(0, 0.05, 0)
		holder.add_child(sp)
		_grip = Grip.SMALL
	_mount(holder)


func _mount(holder: Node3D) -> void:
	_weapon_mount.add_child(holder)
	_weapon = holder
	for m in holder.find_children("*", "GeometryInstance3D", true, false):
		(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _stand_in_gun(item_id: String) -> Node3D:
	for pair in GUN_STAND_IN:
		if pair[0] in item_id and Assets.has_model(pair[1]):
			return Assets.make_item_mesh(pair[1], Assets.icon_tint(item_id))
	return null


## 按枪的包围盒找握把和枪口：枪口朝 +Z，握把在从枪托算起一定比例的位置。
## 把模型挪到握把落在挂点原点上。
func _fit_gun(vis: Node3D, item_id: String) -> void:
	var box: AABB = Assets._bounds(vis, Transform3D.IDENTITY)
	if box.size == Vector3.ZERO:
		box = AABB(Vector3(-0.03, -0.05, -0.15), Vector3(0.06, 0.1, 0.3))
	if not GUN_BARREL_PLUS_Z:
		box = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * box
		vis.rotate_y(PI)
	var length := box.size.z
	_grip = Grip.RIFLE if length > 0.5 and not "Handgun" in item_id else Grip.PISTOL
	_weapon_len = length
	var at := RIFLE_GRIP_AT if _grip == Grip.RIFLE else PISTOL_GRIP_AT
	var grip := Vector3(box.get_center().x, box.position.y + box.size.y * 0.55, box.position.z + length * at)
	vis.position -= grip
	_muzzle_local = Vector3(0, box.end.y - box.size.y * 0.3 - grip.y, box.end.z - grip.z)


## 换弹：枪往下压、往里收，再抬回来
func reload(seconds: float) -> void:
	_reload_total = max(seconds, 0.1)
	_reload_t = _reload_total


func is_reloading() -> bool:
	return _reload_t > 0.0


## 枪口在 FpArms 空间里的位置（放枪口火光用）
func muzzle_position() -> Vector3:
	return _gun_point(_muzzle_local + Vector3(0, 0, 0.03))


## 枪口朝向（FpArms 空间，放火舌用）
func muzzle_direction() -> Vector3:
	return (_weapon_mount.basis * Vector3.BACK).normalized()   # 挂好的枪口统一朝枪的 +Z


func swing(speed := 3.0) -> void:
	if _swing <= 0.0:
		_swing = 1.0
		_swing_speed = speed
		_punch_left = not _punch_left


func is_swinging() -> bool:
	return _swing > 0.0


func _process(delta: float) -> void:
	if has_arms:
		_update_pose(delta)
	elif _swing > 0.0:
		_swing = max(0.0, _swing - delta * _swing_speed)
		_weapon_mount.rotation.x = -1.1 * sin((1.0 - _swing) * PI)


func is_gun() -> bool:
	return _grip == Grip.PISTOL or _grip == Grip.RIFLE
