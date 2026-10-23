extends Node
## 跑动卡顿测量：玩家推满摇杆沿街一直往前跑，记录每一帧的耗时，找出卡顿帧（比中位数慢很多的帧），
## 并标出那一帧有没有跑寻路距离场、阴影开关、动态分辨率变化。最后单独计时这几个周期性的活。
## 一条命令（只量 CPU，不画画面）：
##   godot --headless --path . res://tools/run_bench.tscn
## 带画面：xvfb-run godot --path . --rendering-driver opengl3 res://tools/run_bench.tscn
## 不会写存档。

const MAIN = preload("res://scenes/main.tscn")
## 沿 z=0 这条街从西往东跑，穿过市中心的十字路口（四栋完整重建的楼就在路口四角）
const START := Vector3(-140, 0, 0)
const RUN_SECONDS := 50.0
## 比中位数慢这么多倍算一次卡顿
const SPIKE_RATIO := 2.0

var main: Node
var _frames: Array[Dictionary] = []
var _last_us := 0
var _running := false
var _t := 0.0
var _prev_flow := 0.0
var _prev_lod := 0.0
var _prev_scale := 0.0
var _prev_zombies := 0


func _ready() -> void:
	# 让帧时间反映真实工作量：不锁帧、不等垂直同步
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	process_priority = 1000   # 在 main 之后跑，读到这一帧更新后的计时器
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	main = MAIN.instantiate()
	add_child(main)
	await _wait(5)
	main.start(true)
	main.graphics.apply_quality(1)
	Engine.max_fps = 0
	var pl: Node3D = main.player_sys.player
	pl.position = main.world.push_out(START, 0.5)
	main.player_sys.yaw = -PI / 2   # 朝 +x
	await _wait(30)
	_prev_flow = main.spawner._flow_t
	_prev_lod = main.graphics._lod_t
	_prev_scale = main.get_viewport().scaling_3d_scale
	_prev_zombies = main.spawner.zombie_root.get_child_count()
	_last_us = Time.get_ticks_usec()
	_running = true


func _process(delta: float) -> void:
	if not _running:
		return
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0
	_last_us = now
	var flow_ran: bool = main.spawner._flow_t > _prev_flow
	var lod_ran: bool = main.graphics._lod_t < _prev_lod
	var sc: float = main.get_viewport().scaling_3d_scale
	var scale_changed := not is_equal_approx(sc, _prev_scale)
	_prev_flow = main.spawner._flow_t
	_prev_lod = main.graphics._lod_t
	_prev_scale = sc
	var zn: int = main.spawner.zombie_root.get_child_count()
	var spawned := zn > _prev_zombies
	_prev_zombies = zn
	var pl: Node3D = main.player_sys.player
	_frames.append({"t": _t, "ms": ms, "proc": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"flow": flow_ran, "lod": lod_ran, "scale": scale_changed, "spawn": spawned, "x": pl.position.x,
		"prims": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
	# 推满摇杆往前（冲刺），体力不让它耗光
	main.hud.move = Vector2(0, 1)
	main.player_sys.stamina = 100.0
	main.player_sys.yaw = -PI / 2
	_t += delta
	if _t >= RUN_SECONDS or pl.position.x > 140.0:
		_running = false
		main.hud.move = Vector2.ZERO
		_report()


func _report() -> void:
	var list: Array = _frames.map(func(f): return f.ms)
	list.sort()
	var med: float = list[list.size() / 2]
	var p99: float = list[int(list.size() * 0.99)]
	var spikes := _frames.filter(func(f): return f.ms > med * SPIKE_RATIO and f.ms > 4.0)
	print("RUN 帧数 %d，跑了 %.1f 秒，从 x=%.0f 到 x=%.0f" % [_frames.size(), _t, _frames[0].x, _frames[-1].x])
	print("RUN 帧时间 中位 %.2f ms，99%% %.2f ms，最慢 %.2f ms" % [med, p99, list[-1]])
	var tags := {"flow": 0, "lod": 0, "scale": 0, "spawn": 0, "none": 0}
	for f in spikes:
		var any := false
		for k in ["flow", "lod", "scale", "spawn"]:
			if f[k]:
				tags[k] += 1
				any = true
		if not any:
			tags.none += 1
	print("RUN 卡顿帧（> %.1f ms）%d 个：同帧跑了寻路 %d、阴影开关 %d、分辨率变化 %d、刷僵尸 %d、都没有 %d" % [
		med * SPIKE_RATIO, spikes.size(), tags.flow, tags.lod, tags.scale, tags.spawn, tags.none])
	for f in spikes.slice(0, 30):
		print("RUN   t=%.2f x=%.0f %.1f ms 脚本 %.1f ms %s%s%s%s 面 %dk" % [f.t, f.x, f.ms, f.proc,
			" 寻路" if f.flow else "", " 阴影" if f.lod else "", " 分辨率" if f.scale else "",
			" 刷僵尸" if f.spawn else "", int(f.prims / 1000)])
	# 单独计时周期性的活
	var w: World = main.world
	var pos: Vector3 = main.player_sys.player.position
	print("RUN 单独计时：寻路距离场 %.2f ms，阴影开关 %.2f ms" % [
		_time(func(): w.update_flow(pos)), _time(func(): w.update_shadows(pos, 1))])
	get_tree().quit(0)


func _time(f: Callable, n := 10) -> float:
	var t := Time.get_ticks_usec()
	for i in n:
		f.call()
	return (Time.get_ticks_usec() - t) / 1000.0 / n
