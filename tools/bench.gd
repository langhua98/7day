extends Node
## 性能压力场景：市中心 + 16 只血月僵尸 + 2000 个方块，在 5 个位置朝 8 个方向各看一眼，
## 打印每帧绘制次数、三角面、贴图显存，对照预算（≤200 次、≤40 万面、≤300 MB）。
## 一条命令：xvfb-run godot --path . --rendering-driver opengl3 res://tools/bench.tscn
## 电脑上的数字和手机不完全一样，主要用来对比改动前后。不会写存档。

const MAIN = preload("res://scenes/main.tscn")
const SPOTS := [Vector3(0, 0, 0), Vector3(38, 0, 5), Vector3(-5, 0, 76), Vector3(114, 0, -76), Vector3(-76, 0, -40)]
const ZOMBIES := 16
const BLOCKS := 2000
const BUDGET_DRAWS := 200
const BUDGET_PRIMS := 400000
const BUDGET_TEX_MB := 300.0

var main: Node


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	main = MAIN.instantiate()
	add_child(main)
	await _frames(5)
	main.start(true)
	main.hud.visible = false
	var world: World = main.world
	# 2000 个方块：出生点旁边砌一圈 5 层高的墙，再往外铺几排
	var placed := 0
	var ids := Blocks.TYPES.map(func(t): return t[0])
	var r := 6
	while placed < BLOCKS and r < 40:
		for x in range(-r, r + 1):
			for z in [-r, r]:
				for y in 5:
					if placed < BLOCKS and world.can_place(Vector3i(x, y, z)):
						world.add_voxel(Vector3i(x, y, z), ids[placed % ids.size()])
						placed += 1
		r += 3
	var pl: Node3D = main.player_sys.player
	for i in ZOMBIES:
		main.spawner.spawn_zombie(7, true, true, pl.position)
	await _frames(10)
	var prims := []
	var draws := []
	for p in SPOTS:
		pl.position = world.push_out(p, 0.5)
		for k in 8:
			main.player_sys.yaw = k * TAU / 8
			pl.rotation.y = main.player_sys.yaw
			main.player_sys.camera.rotation.x = 0.0
			await _frames(3)
			prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var tex := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1e6
	var buf := Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1e6
	print("BENCH 方块 %d 个（%d 个绘制组），僵尸 %d 只" % [placed, world.voxel_draw_groups(), main.spawner.alive_count()])
	print("BENCH 绘制次数 平均 %d 最大 %d（预算 %d）" % [_avg(draws), draws.max(), BUDGET_DRAWS])
	print("BENCH 三角面 平均 %d 最大 %d（预算 %d）" % [_avg(prims), prims.max(), BUDGET_PRIMS])
	print("BENCH 贴图显存 %.0f MB（预算 %.0f），网格显存 %.0f MB" % [tex, BUDGET_TEX_MB, buf])
	print("BENCH 节点数 %d" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var ok: bool = draws.max() <= BUDGET_DRAWS and prims.max() <= BUDGET_PRIMS and tex <= BUDGET_TEX_MB
	print("BENCH %s" % ("达标" if ok else "超预算"))
	get_tree().quit(0)


func _avg(a: Array) -> int:
	var s := 0.0
	for v in a:
		s += v
	return int(s / max(a.size(), 1))
