extends Node
## 官方配置表 JSON。文件由 tools/build_data.py 生成到 assets/data/。
## 文件不存在时返回空表，不报错。

const DIR := "res://assets/data"

var items := {}
var _tables := {}


func _ready() -> void:
	reload()


func reload() -> void:
	_tables.clear()
	items = {}
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file in dir.get_files():
		var name := file.trim_suffix(".remap").trim_suffix(".import")
		if not name.ends_with(".json"):
			continue
		var path := "%s/%s" % [DIR, name]
		if not FileAccess.file_exists(path):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			_tables[name.get_basename()] = data
	items = _tables.get("items", {})


func get_table(name: String) -> Dictionary:
	var table = _tables.get(name, {})
	return table if table is Dictionary else {}
