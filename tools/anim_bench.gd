extends Node
## 僵尸骨骼程序动画的 CPU 耗时（不需要素材：用一副仿 Mixamo 命名的假骨骼）
## godot --headless --path . res://tools/anim_bench.tscn

const CHAIN := {
	"Hips": "", "Spine": "Hips", "Spine1": "Spine", "Spine2": "Spine1", "Neck": "Spine2", "Head": "Neck",
	"LeftShoulder": "Spine2", "LeftArm": "LeftShoulder", "LeftArmRoll": "LeftArm", "LeftForeArm": "LeftArmRoll",
	"LeftHand": "LeftForeArm", "LeftHandMiddle1": "LeftHand",
	"RightShoulder": "Spine2", "RightArm": "RightShoulder", "RightArmRoll": "RightArm", "RightForeArm": "RightArmRoll",
	"RightHand": "RightForeArm", "RightHandMiddle1": "RightHand",
	"LeftUpLeg": "Hips", "LeftLeg": "LeftUpLeg", "LeftFoot": "LeftLeg", "LeftToeBase": "LeftFoot",
	"RightUpLeg": "Hips", "RightLeg": "RightUpLeg", "RightFoot": "RightLeg", "RightToeBase": "RightFoot",
}
const OFF := {
	"Spine": Vector3(0, 0.1, 0), "Spine1": Vector3(0, 0.12, 0), "Spine2": Vector3(0, 0.12, 0), "Neck": Vector3(0, 0.15, 0),
	"Head": Vector3(0, 0.1, 0), "LeftShoulder": Vector3(0.05, 0.1, 0), "LeftArm": Vector3(0.12, 0, 0),
	"LeftArmRoll": Vector3(0.1, 0, 0), "LeftForeArm": Vector3(0.15, 0, 0), "LeftHand": Vector3(0.25, 0, 0),
	"LeftHandMiddle1": Vector3(0.08, 0, 0), "LeftUpLeg": Vector3(0.1, -0.05, 0), "LeftLeg": Vector3(0, -0.42, 0),
	"LeftFoot": Vector3(0, -0.42, 0), "LeftToeBase": Vector3(0, -0.05, 0.12),
}


func _skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	for b in CHAIN:
		var i := sk.add_bone(b)
		if CHAIN[b] != "":
			sk.set_bone_parent(i, sk.find_bone(CHAIN[b]))
		var o: Vector3 = OFF.get(b, OFF.get(b.replace("Right", "Left"), Vector3(0, 0.9, 0)))
		if b.begins_with("Right"):
			o.x = -o.x
		sk.set_bone_rest(i, Transform3D(Basis(), o))
	# 真模型还有手指等 40 多根不动的骨头，一起算进去
	var hand := sk.find_bone("LeftHand")
	for f in 40:
		var i := sk.add_bone("Finger%d" % f)
		sk.set_bone_parent(i, hand if f % 2 == 0 else sk.find_bone("RightHand"))
		sk.set_bone_rest(i, Transform3D(Basis(), Vector3(0.03, 0, 0)))
	sk.reset_bone_poses()
	return sk


func _ready() -> void:
	var zs: Array[Zombie] = []
	for n in 16:
		var z := Zombie.new()
		add_child(z)
		z._model = Node3D.new()
		z.add_child(z._model)
		z._skel = _skeleton()
		z._model.add_child(z._skel)
		for b in CHAIN:
			z._bones[b] = z._skel.find_bone(b)
		z._moving = 2.5
		z._phase = n
		z._limp = 0.4 if n % 3 == 0 else 0.0
		z._arm_style = [n % 2, (n / 2) % 2]
		zs.append(z)
	var frames := 300
	var t0 := Time.get_ticks_usec()
	for f in frames:
		for z in zs:
			z._phase += 0.2
			z._windup = 0.3 if f % 40 < 10 else -1.0
			z._animate(1.0 / 30.0)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var sum := Vector3.ZERO
	for z in zs:
		for b in z._bones.values():
			sum += z._skel.get_bone_global_pose(b).origin
	print("ANIMBENCH 每只僵尸每次 %.3f ms（16 只 x %d 次）  校验 %.4f" % [ms / frames / zs.size(), frames, sum.x + sum.y * 3.0 + sum.z * 7.0])
	get_tree().quit()
