extends SceneTree
## 性能测量：开一局，刷 12 只僵尸，在几个固定位置朝 8 个方向各看一眼，
## 打印每帧三角面、绘制次数、贴图显存的平均值和最大值。
## 用法：xvfb-run godot --path . --rendering-driver opengl3 -s tools/bench.gd
## （测量值和手机上不完全一样，主要用来对比优化前后）

const SPOTS := [Vector3(0, 0, 0), Vector3(38, 0, 5), Vector3(-5, 0, 76), Vector3(114, 0, -76), Vector3(-76, 0, -40)]

var main: Node


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_ready_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _ready_run() -> void:
	await _frames(5)
	main._start(true)
	main.hud.visible = false
	for i in 12:
		main._spawn_zombie(1, false, false)
	await _frames(10)
	var prims := []
	var draws := []
	for p in SPOTS:
		main.player.position = main.world.push_out(p, 0.5)
		for k in 8:
			main.yaw = k * TAU / 8
			main.player.rotation.y = main.yaw
			main.camera.rotation.x = 0.0
			await _frames(3)
			prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var tex := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	var buf := Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)
	print("BENCH 三角面 平均 %d 最大 %d" % [_avg(prims), prims.max()])
	print("BENCH 绘制次数 平均 %d 最大 %d" % [_avg(draws), draws.max()])
	print("BENCH 贴图显存 %.0f MB，网格显存 %.0f MB" % [tex / 1e6, buf / 1e6])
	print("BENCH 节点数 %d" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	quit()


func _avg(a: Array) -> int:
	var s := 0.0
	for v in a:
		s += v
	return int(s / max(a.size(), 1))
