extends Node
## 存档原子性：主档损坏时回退到备份，旧档不会被半截写入覆盖。

const SaveGameScript = preload("res://scripts/save_game.gd")
const MAIN := "user://test_atomic_save.json"
const BAK := "user://test_atomic_save.bak"

var failures: Array[String] = []


func _ready() -> void:
	_clean()
	failures.clear()
	check(SaveGameScript.write_to(MAIN, BAK, {"version": 2, "hours": 1.0}), "第一次写入应成功")
	check_eq(SaveGameScript.read_file(MAIN).get("hours"), 1.0, "主档可读")
	check(SaveGameScript.write_to(MAIN, BAK, {"version": 2, "hours": 2.0}), "第二次写入应成功")
	check_eq(SaveGameScript.read_file(MAIN).get("hours"), 2.0, "主档更新")
	check_eq(SaveGameScript.read_file(BAK).get("hours"), 1.0, "备份保留上一版")

	# 主档被截断/损坏时，read_save_from 回退到备份
	var f := FileAccess.open(MAIN, FileAccess.WRITE)
	f.store_string("{broken")
	f.close()
	var d := SaveGameScript.read_save_from(MAIN, BAK)
	check_eq(d.get("hours"), 1.0, "主档损坏时读备份")
	check(not FileAccess.file_exists(MAIN + ".tmp"), "不留下临时文件")

	# 两个档都没了才返回空
	_clean()
	var empty := SaveGameScript.read_save_from(MAIN, BAK)
	check(empty.is_empty(), "没有存档时返回空字典")

	if failures.is_empty():
		print("PASS test_save_atomic")
		get_tree().quit(0)
		return
	for m in failures:
		push_error("test_save_atomic: " + m)
	print("FAIL test_save_atomic（%d 项）" % failures.size())
	get_tree().quit(1)


func _clean() -> void:
	for p in [MAIN, BAK, MAIN + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)


func check_eq(actual, expected, msg: String) -> void:
	if actual != expected:
		failures.append("%s：期望 %s，实际 %s" % [msg, expected, actual])
