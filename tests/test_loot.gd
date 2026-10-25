extends Node
## 2a 验收：官方掉落表、品质随 GS 提升、未知容器兜底、非品质物品 quality=0。
## 需要 assets/data/items.json 和 loot.json（先运行 tools/fetch_assets.py 和 tools/build_data.py）。
## 沙盒没有物品表时跳过，避免误报。

const C = preload("res://scripts/config.gd")

var failures: Array[String] = []
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 12345
	_run()


func _run() -> void:
	if Data.items.is_empty():
		print("SKIP test_loot（沙盒没有 items.json）")
		get_tree().quit(0)
		return
	var table := Data.get_table("loot")
	if table.is_empty():
		push_error("test_loot: 有 items.json 但没有 loot.json，先运行 tools/build_data.py --only loot")
		get_tree().quit(1)
		return
	check(table.get("containers", {}).has("garbage"), "loot.json 应有 garbage 容器")
	check(table.get("containers", {}).has("gunSafe"), "loot.json 应有 gunSafe 容器")
	check(not table.get("quality", {}).is_empty(), "loot.json 应有品质模板")
	_test_basic()
	_test_quality()
	_test_unknown()
	_test_non_quality()
	_finish()


func _test_basic() -> void:
	var got := _roll_many("garbage", 1, 120)
	check(not got.is_empty(), "垃圾桶应该能翻出东西")
	var all_known := true
	for e in got:
		if not Data.items.has(str(e.id)):
			all_known = false
		if int(e.count) < 1:
			failures.append("掉落数量应至少 1")
		if int(e.quality) < 0 or int(e.quality) > 6:
			failures.append("品质应在 0–6")
	check(all_known, "掉落物品应全部来自 items.json")
	var cars := _roll_many("cars", 1, 80)
	check(not cars.is_empty(), "车应该能翻出东西")


func _test_quality() -> void:
	var low := _qualities("gunSafe", 1, 240)
	check(not low.is_empty(), "枪柜应该能翻出有品质的物品")
	var low_max := _max(low)
	check(low_max <= 4, "GS 1 枪柜不应出 5–6 级（实际最高 %d）" % low_max)
	check(_avg(low) < 3.0, "GS 1 枪柜平均品质应低于 3（实际 %.2f）" % _avg(low))
	var high := _qualities("gunSafe", 60, 240)
	check(_max(high) >= 5, "GS 60 枪柜应能出 5 级（实际最高 %d）" % _max(high))
	# 品质函数本身：GS 1 最多 3，GS 120 能到 6
	var q1 := 0
	for i in 200:
		q1 = maxi(q1, Loot.roll_quality(1, "qualBaseTemplate", rng))
	check(q1 <= 3, "GS 1 基础品质模板最高应为 3（实际 %d）" % q1)
	var q6 := 0
	for i in 400:
		q6 = maxi(q6, Loot.roll_quality(120, "qualBaseTemplate", rng))
	check(q6 >= 6, "GS 120 基础品质模板应能出 6（实际 %d）" % q6)


func _test_unknown() -> void:
	var got := Loot.roll("这个容器不存在", 1, rng)
	check(not got.is_empty(), "未知容器应退回通用组")
	for e in got:
		check(Data.items.has(str(e.id)), "通用组掉的东西也应来自 items.json")


func _test_non_quality() -> void:
	var got := _roll_many("foodPileSmall", 1, 120)
	check(not got.is_empty(), "食物堆应该能翻出东西")
	var all_zero := true
	for e in got:
		if int(e.quality) != 0:
			all_zero = false
	check(all_zero, "食物这类没有品质的物品 quality 应为 0")


func _roll_many(container: String, gs: int, times: int) -> Array:
	var out := []
	for i in times:
		out.append_array(Loot.roll(container, gs, rng))
	return out


func _qualities(container: String, gs: int, times: int) -> Array:
	var out := []
	for e in _roll_many(container, gs, times):
		if float(Data.items.get(str(e.id), {}).get("durability", 0.0)) > 0.0:
			out.append(int(e.quality))
	return out


func _max(values: Array) -> int:
	var m := 0
	for v in values:
		m = maxi(m, int(v))
	return m


func _avg(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var s := 0.0
	for v in values:
		s += float(v)
	return s / values.size()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS test_loot")
		get_tree().quit(0)
		return
	for m in failures:
		push_error("test_loot: " + m)
	print("FAIL test_loot（%d 项）" % failures.size())
	get_tree().quit(1)
