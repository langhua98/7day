extends Node
## 背包图标：所有游戏物品、方块形状、配件、载具、杂志都有图标。

const C = preload("res://scripts/config.gd")

var failures: Array[String] = []


func _ready() -> void:
	var ids := {}
	for id in Assets.items_by_id:
		ids[id] = true
	for id in Data.items:
		ids[id] = true
	for id in Blocks.variant_ids():
		ids[id] = true
	for id in Attachments.IDS:
		ids[id] = true
	for id in C.VEHICLES:
		ids[id] = true
	var missing: Array[String] = []
	for id in ids:
		var zh := str(Data.items.get(id, {}).get("zh", id))
		Assets.ensure_item(id, zh)
		if Assets.icon(id) == null:
			missing.append(str(id))
	print("图标检查: %d 个物品" % ids.size())
	if missing.is_empty():
		print("PASS test_icons")
		get_tree().quit(0)
		return
	for id in missing.slice(0, 25):
		push_error("test_icons: 没有图标 " + str(id))
	print("FAIL test_icons（%d 个）" % missing.size())
	get_tree().quit(1)
