extends Node
## 0b 验收：build_data.py 生成的 items.json 能被 Data 单例读到。

func _ready() -> void:
	var failures: Array[String] = []
	if Data.items.is_empty():
		failures.append("Data.items 为空（先运行 tools/build_data.py 或 fetch_assets.py）")
	var ammo: Dictionary = Data.items.get("ammo9mmBulletBall", {})
	if int(ammo.get("stack", 0)) != 300:
		failures.append("ammo9mmBulletBall.stack 应为 300，实际 %s" % ammo.get("stack"))
	if not Data.items.has("frameShapes") or float(Data.items["frameShapes"].get("durability", 0)) <= 0.0:
		failures.append("方块 frameShapes 应从官方方块表进入 items.json")
	if Data.get_table("items").size() != Data.items.size():
		failures.append("Data.get_table('items') 和 Data.items 不一致")
	if failures.is_empty():
		print("PASS test_data")
		get_tree().quit(0)
	else:
		for f in failures:
			push_error("test_data: " + f)
		print("FAIL test_data（%d 项）" % failures.size())
		get_tree().quit(1)
