extends Node
## 刷怪相关：官方 ID 与素材文件名要能对上；昼夜/血月速度能恢复。

const AssetDB = preload("res://scripts/asset_db.gd")
const C = preload("res://scripts/config.gd")

var failures: Array[String] = []


func _ready() -> void:
	var db := AssetDB.new()
	db.zombie_models = PackedStringArray(["zombie_soldier", "zombie_nurse"])
	check_eq(db.zombie_key("soldier"), "zombie_soldier", "官方 ID 应映射到素材名")
	check_eq(db.zombie_key("nurse"), "zombie_nurse", "另一个官方 ID")
	check_eq(db.zombie_key("zombie_soldier"), "zombie_soldier", "已经是素材名时保持原样")
	check_eq(db.zombie_key("missing"), "", "没有素材时返回空")

	var walk: float = SpawnerSystem.speed_for(1.0, false, false)
	var night: float = SpawnerSystem.speed_for(1.0, true, false)
	var horde: float = SpawnerSystem.speed_for(1.0, false, true)
	check_close(walk, 1.0, 0.001, "白天用基础速度")
	check_close(night, C.ZOMBIE_NIGHT_SPEED / C.ZOMBIE_WALK_SPEED, 0.001, "夜里按比例加速")
	check_close(horde, C.ZOMBIE_HORDE_SPEED / C.ZOMBIE_WALK_SPEED, 0.001, "血月按比例加速")
	check_close(SpawnerSystem.speed_for(2.5, false, false), 2.5, 0.001, "白天恢复基础速度，不保留夜间加速")

	if failures.is_empty():
		print("PASS test_spawner")
		get_tree().quit(0)
		return
	for m in failures:
		push_error("test_spawner: " + m)
	print("FAIL test_spawner（%d 项）" % failures.size())
	get_tree().quit(1)


func check_eq(actual, expected, msg: String) -> void:
	if actual != expected:
		failures.append("%s：期望 %s，实际 %s" % [msg, expected, actual])


func check_close(actual: float, expected: float, tol: float, msg: String) -> void:
	if absf(actual - expected) > tol:
		failures.append("%s：期望 %.4f，实际 %.4f" % [msg, expected, actual])
