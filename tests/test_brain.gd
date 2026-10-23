extends Node
## 6a 验收：僵尸大脑的视觉、蹲伏、听觉、追击丢失、热量刷尖叫者、20 只感知耗时。
## 用空的 Node3D 当僵尸身体和玩家，不需要素材。

const C = preload("res://scripts/config.gd")

var failures: Array[String] = []


func _ready() -> void:
	var player := Node3D.new()
	add_child(player)
	var body := Node3D.new()
	add_child(body)
	GameState.hours = 12.0   # 白天
	GameState.player_crouching = false

	# 僵尸在原点面朝 +Z；玩家在正前方 10 米：看得见
	var b := ZombieBrain.new()
	player.position = Vector3(0, 0, 10)
	check(b.sees(body, player, null), "白天正前方 10 米应看见")
	# 背后 3 米：看不见（站着也一样）
	player.position = Vector3(0, 0, -3)
	check(not b.sees(body, player, null), "背后 3 米不应看见")
	# 蹲着从背后 1 米走过：看不见
	GameState.player_crouching = true
	player.position = Vector3(0.8, 0, -0.8)
	check(not b.sees(body, player, null), "蹲着贴背后走过不应被发现")
	# 蹲着正前方 20 米：白天视距 25 × 0.5 = 12.5，看不见
	player.position = Vector3(0, 0, 20)
	check(not b.sees(body, player, null), "蹲着正前方 20 米看不见")
	GameState.player_crouching = false
	check(b.sees(body, player, null), "站着正前方 20 米看得见")
	# 夜里视距 15 米
	GameState.hours = 23.0
	check(not b.sees(body, player, null), "夜里正前方 20 米看不见")
	GameState.hours = 12.0

	# 看见 → 追击；丢失 8 秒 → 调查；到达后停 10 秒 → 游荡
	b.sense(body, player, null)
	check(b.state == ZombieBrain.State.CHASE, "看见后追击")
	player.position = Vector3(0, 0, -10)
	b.sense(body, player, null)
	for i in 90:
		b.tick(0.1, body, player, false)
	check(b.state == ZombieBrain.State.INVESTIGATE, "丢失目标 8 秒后调查")
	body.position = b.last_pos
	for i in 110:
		b.tick(0.1, body, player, false)
	check(b.state == ZombieBrain.State.WANDER or b.state == ZombieBrain.State.IDLE, "调查 10 秒后回到游荡")

	# 听觉：枪声 45 米，40 米外的僵尸来查看
	var b2 := ZombieBrain.new()
	b2.hear(Vector3(40, 0, 0), "pistol")
	check(b2.state == ZombieBrain.State.INVESTIGATE, "听到枪声去调查")
	check(b2.tick(0.1, body, player, false).distance_to(Vector3(40, 0, 0)) < 0.01, "调查目标是枪声位置")
	check_eq(C.NOISE.pistol, 45.0, "手枪噪音 45 米")
	# 血月僵尸直接追
	var b3 := ZombieBrain.new()
	b3.tick(0.1, body, player, true)
	check(b3.state == ZombieBrain.State.CHASE, "血月僵尸直接追击")

	# 热量：同一格开 100 枪刷尖叫者；衰减 30%
	var heat := HeatMap.new()
	var fired := [0]
	heat.overflow.connect(func(_p): fired[0] += 1)
	for i in 60:
		heat.add(Vector3(5, 0, 5), C.HEAT.shot)
	heat._on_hour(1, 1.0)
	check(absf(heat.value_at(Vector3(5, 0, 5)) - 42.0) < 0.01, "每小时衰减 30%%（%.1f）" % heat.value_at(Vector3(5, 0, 5)))
	var spot := Vector3(70, 0, 70)   # 另一格
	for i in 300:   # 合成 300 秒（每秒 0.2）+ 开枪 45 次
		heat.add(spot, C.HEAT.craft_per_sec)
	for i in 45:
		heat.add(spot, C.HEAT.shot)
	check_eq(fired[0], 1, "长时间合成开枪刷出尖叫者")
	check(heat.value_at(spot) < 6.0, "刷完清零后重新累计（%.1f）" % heat.value_at(spot))
	var loaded := HeatMap.new()
	heat.add(Vector3(100, 0, 100), 7.0)
	loaded.load_data(heat.save_data())
	check(absf(loaded.value_at(Vector3(100, 0, 100)) - 7.0) < 0.01, "热量存档读档")

	# AI 预算：20 只僵尸，每帧 6 只做感知（不含遮挡射线），测平均耗时
	var bodies: Array = []
	var brains: Array = []
	for i in 20:
		var n := Node3D.new()
		add_child(n)
		n.position = Vector3(randf_range(-30, 30), 0, randf_range(-30, 30))
		bodies.append(n)
		brains.append(ZombieBrain.new())
	var t0 := Time.get_ticks_usec()
	var frames := 600
	var idx := 0
	for f in frames:
		for k in C.AI_SENSE_PER_FRAME:
			idx = (idx + 1) % 20
			brains[idx].sense(bodies[idx], player, null)
		for i in 20:
			brains[i].tick(1.0 / 60.0, bodies[i], player, false)
	var per_frame := float(Time.get_ticks_usec() - t0) / frames / 1000.0
	print("AI 每帧耗时（20 只，大脑部分）：%.4f 毫秒" % per_frame)
	check(per_frame < 2.0, "20 只 AI 每帧 < 2 毫秒")

	if failures.is_empty():
		print("test_brain: 全部通过")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("失败：", f)
		get_tree().quit(1)


func check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)


func check_eq(a, b, msg: String) -> void:
	if a != b:
		failures.append("%s：%s != %s" % [msg, str(a), str(b)])
