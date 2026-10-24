extends Node
## 物品分类和弹药变体：药品要能使用，钢 AP 不能被普通 AP 抢走。

const AssetDB = preload("res://scripts/asset_db.gd")
const Weapons = preload("res://scripts/weapons.gd")

var failures: Array[String] = []


func _ready() -> void:
	var db := AssetDB.new()
	for id in ["drugAntibiotics", "drugHerbalAntibiotics", "medicalFirstAidBandage"]:
		var row := {"id": id}
		db._classify(row)
		check_eq(row.kind, AssetDB.Kind.MEDICAL, "%s 应归为药品" % id)

	check_eq(Weapons.ammo_mods("ammo762mmBulletSteelAP").label, "钢AP", "钢 AP 应有独立倍率")
	check_eq(Weapons.ammo_mods("ammo762mmBulletAP").label, "AP", "普通 AP 保持原样")
	check_eq(Weapons.ammo_mods("ammo9mmBulletHP").label, "HP", "HP 保持原样")

	if failures.is_empty():
		print("PASS test_items")
		get_tree().quit(0)
		return
	for m in failures:
		push_error("test_items: " + m)
	print("FAIL test_items（%d 项）" % failures.size())
	get_tree().quit(1)


func check_eq(actual, expected, msg: String) -> void:
	if actual != expected:
		failures.append("%s：期望 %s，实际 %s" % [msg, expected, actual])
