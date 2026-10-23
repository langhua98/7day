extends SceneTree
## 楼内容器：坐标随楼旋转、只认同一层（godot --headless -s tests/test_poi_containers.gd）

func _init() -> void:
	var w := World.new()
	w.poi_containers = {"t": {"ground": 3, "list": [
		{"block": "cntFridge", "loot": "fridge", "x": -2.5, "y": 4, "z": 0.5, "rot": 0},
		{"block": "cntDesk", "loot": "woodenDesk", "x": -2.5, "y": 8, "z": 0.5, "rot": 0}]}}
	w._poi_containers("t", Vector2(10, 20), PI / 2, -3.0)
	var ok := w.containers.size() == 2
	var c: Dictionary = w.containers[0]
	# 方块数据的 x 翻过来（-2.5 → 网格本地 2.5），再转 90 度：x' = z，z' = -x
	ok = ok and c.pos.distance_to(Vector3(10.5, 1.0, 17.5)) < 0.01 and c.name == "冰箱" and c.container == "fridge"
	ok = ok and w.nearest_container(Vector3(10.5, 1.0, 18.5)) == c
	ok = ok and w.nearest_container(Vector3(10.5, 5.0, 18.5)).get("container") == "woodenDesk"
	ok = ok and w.nearest_container(Vector3(10.5, -1.5, 18.5)).is_empty()
	w.free()
	print("test_poi_containers ", "OK" if ok else "FAIL")
	quit(0 if ok else 1)
