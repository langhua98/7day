extends Node
## 世界空间查询：刷怪点不能悬空、不能刷进楼里；矮方块不能挡住高处视线。

const MAIN = preload("res://scenes/main.tscn")

class SightWorld extends World:
	var sight_blocked := false
	func line_blocked(_a: Vector3, _b: Vector3) -> bool:
		return sight_blocked


var failures: Array[String] = []
var main: Node3D


func _ready() -> void:
	main = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	var world: World = main.world

	# 玩家/刷怪点中心在楼上时，地面刷怪点应回到地面
	var p := world.free_point(Vector3(0, 8, 0), 1.0, 3.0)
	check_close(p.y, 0.0, 0.001, "free_point 应落在地面，不继承中心高度")

	# 楼内范围（哪怕可走）不能作为随机刷怪点；用独立世界，避免真实素材影响
	var iw := World.new()
	var it := PoiInterior.new()
	it.rect = Rect2(Vector2(10, 10), Vector2(4, 4))
	iw.interiors.append(it)
	check(iw.inside_interior(Vector3(11, 0, 11)), "楼内应算被占")
	iw.interiors.pop_back()
	check(not iw.inside_interior(Vector3(11, 0, 11)), "移走楼后同一位置不再占")
	iw.free()

	# 自己摆的 y=0 矮方块只挡脚边，不挡 3 米高处的视线
	var cell := Vector3i(5, 0, 5)
	world.voxels[cell] = {"id": "frameShapes", "hp": 100.0}
	world._low[Vector2i(5, 5)] = 1
	check(world._point_blocked(Vector3(5.5, 1.0, 5.5)), "脚边视线应被矮方块挡住")
	check(not world._point_blocked(Vector3(5.5, 3.0, 5.5)), "3 米高处不应被矮方块挡住")

	# 隔墙不能搜容器：用可控视线的世界，避免真实地图影响
	var sw := SightWorld.new()
	sw.containers.append({"pos": Vector3(20, 0, 20), "r": 0.5, "indoor": false, "name": "测试柜"})
	var near := Vector3(18.5, 0, 20)
	check(not sw.nearest_container(near).is_empty(), "没有墙时能找到容器")
	sw.sight_blocked = true
	check(sw.nearest_container(near).is_empty(), "隔墙不能搜容器")
	sw.free()
	world.voxels.erase(cell)
	world._low.erase(Vector2i(5, 5))

	# 凌晨读档/跨午夜不应重复提示“天黑了”
	main.atmosphere.set_night_announced(3, 0.5)
	check_eq(main.atmosphere._night_announced, 3, "凌晨读档应记住今晚已经提示过")
	main.atmosphere.update_banner(4, 0.5, true, false)
	check_eq(main.atmosphere._night_announced, 3, "跨午夜不重复提示")

	if failures.is_empty():
		print("PASS test_world")
		get_tree().quit(0)
		return
	for m in failures:
		push_error("test_world: " + m)
	print("FAIL test_world（%d 项）" % failures.size())
	get_tree().quit(1)


func check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)


func check_close(actual: float, expected: float, tol: float, msg: String) -> void:
	if absf(actual - expected) > tol:
		failures.append("%s：期望 %.4f，实际 %.4f" % [msg, expected, actual])


func check_eq(actual, expected, msg: String) -> void:
	if actual != expected:
		failures.append("%s：期望 %s，实际 %s" % [msg, expected, actual])
