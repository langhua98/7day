extends Node
## 地面活板门要平铺，不能按竖直门板处理。

const PoiInteriorScript = preload("res://scripts/poi_interior.gd")

var failures: Array[String] = []


func _ready() -> void:
	var it := PoiInteriorScript.new()
	it.doors = [{"x0": 0, "y0": 0, "z0": 0, "x1": 1, "y1": 0, "z1": 1,
		"axis": "x", "metal": false, "hatch": true, "block": "", "open": false, "swing": 1}]
	var closed := it.door_transform(0)
	var s := closed.basis.get_scale()
	check_close(s.y, PoiInteriorScript.DOOR_T, 0.001, "关着的活板门厚度应朝上")
	check(s.x > 1.0 and s.z > 1.0, "关着的活板门应平铺在 xz 平面")

	it.set_door(0, true)
	var opened := it.door_transform(0)
	var os := opened.basis.get_scale()
	check_close(os.x, 2.0, 0.001, "打开的活板门宽度不变")
	check(absf(opened.basis.z.y) > 1.0, "打开的活板门应翻起来")

	if failures.is_empty():
		print("PASS test_doors")
		get_tree().quit(0)
		return
	for m in failures:
		push_error("test_doors: " + m)
	print("FAIL test_doors（%d 项）" % failures.size())
	get_tree().quit(1)


func check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)


func check_close(actual: float, expected: float, tol: float, msg: String) -> void:
	if absf(actual - expected) > tol:
		failures.append("%s：期望 %.4f，实际 %.4f" % [msg, expected, actual])
