extends Node
## 6d 睡眠僵尸：进楼刷出、睡着、枪声吵醒、杀光记清空、存读档保留。

const MAIN = preload("res://scenes/main.tscn")

var main
var failures: Array[String] = []
var signals: Array[String] = []


func _ready() -> void:
	_run.call_deferred()
	_timer(180)


func _timer(sec: float) -> void:
	var t := Timer.new()
	t.wait_time = sec
	t.one_shot = true
	t.timeout.connect(func():
		if is_inside_tree() and not _done:
			_check(false, "超时")
			_finish())
	add_child(t)
	t.start()


var _done := false


func _check(cond: bool, what: String) -> void:
	if cond:
		print("PASS ", what)
	else:
		failures.append(what)
		print("FAIL ", what)


func _run() -> void:
	if not FileAccess.file_exists("res://assets/poi/sleepers.json"):
		print("SKIP 没有 sleepers.json（先跑 fetch_assets）")
		_finish()
		return
	main = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.start(true)
	await get_tree().process_frame
	var sl: Sleepers = main.sleepers
	sl._ensure_volumes()
	_check(not sl.volumes.is_empty(), "有完整楼时应加载睡眠区")
	if sl.volumes.is_empty():
		_finish()
		return
	GameState.poi_cleared.connect(func(poi): signals.append(poi))

	# 挑一个 1-3 只的区；优先整栋只有这一个睡眠区的
	var v: Dictionary = {}
	var single := false
	for cand in sl.volumes:
		if int(cand.max) < 1 or int(cand.max) > 3 or sl.cleared_areas.has(str(cand.key)):
			continue
		var same := 0
		for other in sl.volumes:
			if str(other.poi) == str(cand.poi):
				same += 1
		if v.is_empty():
			v = cand
		if same == 1:
			v = cand
			single = true
			break
	_check(not v.is_empty(), "找到一个睡眠区")
	if v.is_empty():
		_finish()
		return

	var center: Vector3 = Vector3(v.base) + Basis(Vector3.UP, float(v.rot)) * Vector3(v.center)
	var p: Vector3 = center
	p.y = center.y - float(v.half.y) + 0.6
	main.player_sys.player.position = p
	sl.update(0.1)
	_check(bool(v.spawned) and v.zombies.size() > 0, "进入睡眠区应刷出睡眠僵尸")
	var sleeping := 0
	for z in v.zombies:
		if is_instance_valid(z) and not z.dead and z.brain.state == ZombieBrain.State.SLEEP:
			sleeping += 1
	_check(sleeping > 0 and sleeping == v.zombies.size(), "睡眠区刷出的僵尸都应睡着")

	# 睡眠中不该主动追玩家
	var chasing_before := 0
	for z in v.zombies:
		if is_instance_valid(z) and z.brain.state == ZombieBrain.State.CHASE:
			chasing_before += 1
	_check(chasing_before == 0, "没被吵醒前不应追玩家")

	# 枪声（45 米）吵醒
	GameState.make_noise(center + Vector3.UP, "shotgun")
	await get_tree().process_frame
	var awake := 0
	for z in v.zombies:
		if is_instance_valid(z) and not z.dead and z.brain.state != ZombieBrain.State.SLEEP:
			awake += 1
	_check(awake > 0, "枪声应吵醒睡眠僵尸")

	# 杀光 → 记清空、发信号
	for z in v.zombies:
		if is_instance_valid(z) and not z.dead:
			z.take_hit(999999.0, z.global_position + Vector3(0, 0, 1))
	await get_tree().process_frame
	sl.update(0.1)
	_check(bool(v.cleared), "杀光后区域应标记清空")
	_check(sl.cleared_areas.has(str(v.key)), "清空记录应写入 cleared")
	if single:
		_check(sl.cleared(str(v.poi)), "整栋清空时 cleared_poi 为 true")
	_check(signals.has(str(v.poi)), "清空应发出 GameState.poi_cleared")

	# 存档 / 读档
	var saved := sl.save_data()
	sl.reset()
	_check(sl.cleared_areas.is_empty(), "重开或重置后清空记录应清空")
	sl.load_data(saved)
	_check(sl.cleared_areas.has(str(v.key)), "读档应恢复清空记录")
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	if failures.is_empty():
		print("PASS test_sleepers")
	else:
		print("FAIL test_sleepers：", "; ".join(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
