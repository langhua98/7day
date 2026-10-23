extends Node
## 枪弹验收：官方 items.xml 的弹匣、射速、换弹、弹药类型进入 Weapons.stats。

func _ready() -> void:
	var failures: Array[String] = []
	var pistol := Weapons.stats("gunHandgunT1Pistol")
	if int(pistol.get("mag", 0)) != 15:
		failures.append("手枪弹匣应为 15，实际 %s" % pistol.get("mag"))
	if str(pistol.get("ammo", "")) != "ammo9mm":
		failures.append("手枪弹药应为 ammo9mm，实际 %s" % pistol.get("ammo"))
	var ar := Weapons.stats("gunMGT2TacticalAR")
	if int(ar.get("mag", 0)) != 30:
		failures.append("战术 AR 弹匣应为 30，实际 %s" % ar.get("mag"))
	if str(ar.get("ammo", "")) != "ammo762mm":
		failures.append("战术 AR 弹药应为 ammo762mm，实际 %s" % ar.get("ammo"))
	var shotgun := Weapons.stats("gunShotgunT0PipeShotgun")
	if int(shotgun.get("mag", 0)) != 1:
		failures.append("管子霰弹枪弹匣应为 1，实际 %s" % shotgun.get("mag"))
	if absf(float(shotgun.get("reload", 0.0)) - 2.6) > 0.01:
		failures.append("霰弹枪换弹应为 2.6s，实际 %s" % shotgun.get("reload"))
	var rifle := Weapons.stats("gunRifleT1HuntingRifle")
	if int(rifle.get("mag", 0)) != 1:
		failures.append("猎枪弹匣应为 1，实际 %s" % rifle.get("mag"))
	if Weapons.ammo_count({"ammo9mmBulletBall": 5, "ammo9mmBulletHP": 2, "ammo762mmBulletBall": 1}, "gunHandgunT1Pistol") != 7:
		failures.append("9mm 子弹应能同时算 Ball 和 HP")
	if Data.items.get("gunHandgunT1Pistol", {}).get("magazine", 0) != 15:
		failures.append("items.json 应包含官方 MagazineSize")
	if Weapons.default_ammo("gunHandgunT1Pistol") != "ammo9mmBulletBall":
		failures.append("手枪默认弹应为 9mm Ball")
	if absf(float(Weapons.ammo_mods("ammo9mmBulletHP").get("entity", 0.0)) - 1.25) > 0.001:
		failures.append("HP 弹伤害倍率应为 1.25")
	if absf(float(Weapons.ammo_mods("ammo9mmBulletAP").get("entity", 0.0)) - 0.9) > 0.001:
		failures.append("AP 弹伤害倍率应为 0.9")
	if Weapons.ammo_label("ammo9mmBulletHP") != "9mm HP":
		failures.append("HUD 弹种名应为 9mm HP")
	if failures.is_empty():
		print("PASS test_weapons")
		get_tree().quit(0)
	else:
		for f in failures:
			push_error("test_weapons: " + f)
		print("FAIL test_weapons（%d 项）" % failures.size())
		get_tree().quit(1)
