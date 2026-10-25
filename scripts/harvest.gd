class_name Harvest
extends RefCounted
## 采集世界物件：材质、血量、掉落和工具类型。
## 掉落来自官方 harvest.json（tools/build_data.py 解析 blocks.xml），
## 街边模型名对不上方块的写在 assets/data/harvest_overrides.json（前缀匹配）。

const C = preload("res://scripts/config.gd")


## 用 /root 查 Data：-s 脚本模式没有自动加载时也能编译
static func _data() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Data")
	return null


## 模型名 → {material, hp}；最长前缀优先，找不到返回空
static func def(name: String) -> Dictionary:
	var data := _data()
	if data == null:
		return {}
	var table: Dictionary = data.get_table("harvest_overrides")
	var low := name.to_lower()
	var best := ""
	var found := {}
	for prefix in table:
		var p := str(prefix).to_lower()
		if p == "" or p.begins_with("_"):
			continue
		if low.begins_with(p) and p.length() > best.length():
			best = p
			found = table[prefix]
	return found


static func material(name: String) -> String:
	var d := def(name)
	return str(d.get("material", "trash"))


static func hp(name: String) -> float:
	var d := def(name)
	var mat := str(d.get("material", "trash"))
	return float(d.get("hp", C.HARVEST_HP.get(mat, 20.0)))


## 手里工具对哪种材质：扳手/拆解 → 金属，斧 → 木，镐 → 石；空手返回 ""
static func tool_kind(id: String) -> String:
	var low := id.to_lower()
	if low.contains("salvage") or low.contains("wrench"):
		return "metal"
	if low.contains("pick"):
		return "stone"
	if low.contains("axe"):
		return "wood"
	return ""


## 拆一个物件掉什么：官方 Harvest + Destroy 两份表都滚一遍。
## 对口工具 ×2，空手 ×1/3，其它工具 ×1；再乘手机版倍率，单个物品最多 15。
static func drops(material_name: String, tool: String, rng: RandomNumberGenerator) -> Array:
	var data := _data()
	if data == null:
		return []
	var table: Dictionary = data.get_table("harvest")
	var mat: Dictionary = table.get("materials", {}).get(material_name, {})
	if mat.is_empty():
		return []
	var mult := 1.0
	if tool == "":
		mult = 1.0 / 3.0
	elif tool == material_name:
		mult = 2.0
	var out := {}
	for key in ["harvest", "destroy"]:
		for row in mat.get(key, []):
			var prob := float(row.get("prob", 1.0))
			if prob < 1.0 and rng.randf() >= prob:
				continue
			var count: Array = row.get("count", [1, 1])
			var n := rng.randi_range(int(count[0]), int(count[1]))
			n = int(round(float(n) * mult * C.HARVEST_DROP_MULT))
			n = mini(n, C.HARVEST_MAX_DROPS)
			if n <= 0:
				continue
			var id := str(row.get("id", ""))
			if id == "":
				continue
			out[id] = int(out.get(id, 0)) + n
	var list := []
	for id in out:
		list.append({"id": id, "count": int(out[id])})
	return list
