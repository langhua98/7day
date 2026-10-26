extends Node
## 7b：杂志升级、配方解锁、技能书效果、存读档。

const MAIN = preload("res://scenes/main.tscn")

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()
	var t := Timer.new()
	t.wait_time = 120.0
	t.one_shot = true
	t.timeout.connect(func():
		if not _done:
			_check(false, "超时")
			_finish())
	add_child(t)
	t.start()


var _done := false


func _check(cond: bool, what: String) -> void:
	if cond:
		print("PASS ", what)
	else:
		failures.append(what)
		print("FAIL ", what)


func _run() -> void:
	if Books.data.get("categories", {}).is_empty() or Books.data.get("magazines", {}).is_empty():
		print("SKIP test_books（没有 books.json）")
		_finish()
		return
	_check(Books.data.categories.size() >= 20, "应有官方制作技能类别")
	_check(Books.data.magazines.size() >= 20, "应有技能杂志")
	_check(Books.data.books.size() >= 15, "应有技能书")
	_check(Books.recipe_requirement("gunHandgunT1Pistol").get("level", 0) >= 1, "手枪配方要有杂志等级要求")

	var main = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.start(false)
	await get_tree().process_frame
	var craft: Crafting = main.crafting
	craft.recipes_all_unlocked = false
	Books.reset()
	var key := "gunHandgunT1Pistol"
	_check(not craft.is_unlocked(key), "没读杂志时手枪配方应锁着")
	var why := craft.why_not(key)
	_check(why.contains("手枪") and why.contains("级"), "锁着的配方要提示杂志等级：%s" % why)
	var req := Books.recipe_requirement(key)
	var need := int(req.get("level", 1))

	Assets.ensure_item("handgunsSkillMagazine", Books.item_name("handgunsSkillMagazine"))
	main.inventory.add("handgunsSkillMagazine", need + 2)
	for i in need:
		main.inventory.use_item("handgunsSkillMagazine")
	_check(Books.category_level(str(req.category)) == need, "读杂志提升类别等级")
	_check(craft.is_unlocked(key), "读到等级后配方解锁")
	_check(main.inventory.count("handgunsSkillMagazine") == 2, "读杂志要消耗物品")

	# 再读一本，下一档手枪（马格南 3 级）还没到
	var magnum := "gunHandgunT2Magnum44"
	var mreq := Books.recipe_requirement(magnum)
	if not mreq.is_empty():
		_check(not craft.is_unlocked(magnum) if need < int(mreq.level) else true, "高一级的配方还锁着")
		main.inventory.use_item("handgunsSkillMagazine")
		_check(Books.category_level(str(req.category)) == mini(5, need + 1), "继续读还能升级")

	# 技能书：读一次给永久小加成，再读不消耗
	var book := "bookShotgunMessiahDamage"
	Assets.ensure_item(book, Books.item_name(book))
	main.inventory.add(book, 2)
	var dmg0 := Books.damage_mult("weapon,shotgun,perkBoomstick")
	main.inventory.use_item(book)
	_check(Books.read_books.has(book), "读书记录已读")
	_check(Books.damage_mult("weapon,shotgun,perkBoomstick") > dmg0, "读书后霰弹枪伤害加成")
	_check(main.inventory.count(book) == 1, "读书消耗一本")
	main.inventory.use_item(book)
	_check(main.inventory.count(book) == 1, "同一本书不重复消耗")

	# 存读档
	var saved := Books.save_data()
	var lvl := Books.category_level(str(req.category))
	Books.reset()
	Books.load_data(saved)
	_check(Books.category_level(str(req.category)) == lvl, "读档恢复杂志等级")
	_check(Books.read_books.has(book), "读档恢复已读书")
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	if failures.is_empty():
		print("PASS test_books")
	else:
		print("FAIL test_books：", "; ".join(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
