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
	# 有的僵尸组里的模型没下载，刷失败就再试
	var tries := 0
	var made := 0
	while made < ZOMBIES and tries < 300:
		if main.spawner.spawn_zombie(7, true, true, pl.position) != null:
			made += 1
		tries += 1
	# 只量我们刷的这 16 只：停掉平时的自动刷怪
	main.spawner.spawn_cd = 1e9
	await _frames(10)
	var prims := []
	var draws := []
	for p in SPOTS:
		pl.position = world.push_out(p, 0.5)
		# 僵尸跟着搬到身边，每个位置都在画 16 只；血月自己刷出来的多余的删掉
		var zs: Array = main.spawner.zombie_root.get_children()
		for i in zs.size():
			if i >= ZOMBIES:
				zs[i].free()
			else:
				zs[i].position = world.free_point(pl.position, 4.0, 14.0)
		for k in 8:
			main.player_sys.yaw = k * TAU / 8
			pl.rotation.y = main.player_sys.yaw
			main.player_sys.camera.rotation.x = 0.0
			await _frames(3)
			prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			if OS.get_cmdline_user_args().has("--verbose"):
				print("BENCH  %s 方向 %d：绘制 %d，三角面 %d" % [p, k, draws[-1], prims[-1]])
	if OS.get_cmdline_user_args().has("--verbose"):
		await _breakdown(world, pl)
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


## 在最费的方向上依次隐藏僵尸、方块，看各占多少
func _breakdown(world: World, pl: Node3D) -> void:
	pl.position = world.push_out(Vector3(-5, 0, 76), 0.5)
	main.player_sys.yaw = 7 * TAU / 8
	pl.rotation.y = main.player_sys.yaw
	for z in main.spawner.zombie_root.get_children():
		z.position = world.free_point(pl.position, 4.0, 14.0)
	await _frames(3)
	print("BENCH 全部：绘制 %d 三角面 %d" % _now())
	main.spawner.zombie_root.visible = false
	await _frames(3)
	print("BENCH 不画僵尸：绘制 %d 三角面 %d" % _now())
	var vr := world.get_node_or_null("Voxels")
	if vr:
		vr.visible = false
	await _frames(3)
	print("BENCH 再不画方块：绘制 %d 三角面 %d" % _now())
	var full := 0
	for n in world.get_children():
		if n is MeshInstance3D and n.visibility_range_begin > 0.0:
			n.visible = false
			full += 1
	await _frames(3)
	print("BENCH 再不画 %d 栋楼的远景网格：绘制 %d 三角面 %d" % ([full] + _now()))
	main.spawner.zombie_root.visible = true
	if vr:
		vr.visible = true


func _now() -> Array:
	return [int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))]
