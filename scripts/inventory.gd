class_name InventorySystem
extends Node
## 背包数据：物品数量、拾取顺序、装备、弹匣。界面刷新通过 changed 信号或 refresh()。

signal changed

const C = preload("res://scripts/config.gd")

var main: Node3D
var hud: Hud
var arms: FpArms
var player_sys: PlayerSystem
var combat: CombatSystem
var rng: RandomNumberGenerator

var inventory := {}
var pickup_order: Array[String] = []
var equipped := ""
var mags := {}
var mags_type := {}
var ammo_choice := {}
var qualities := {}


func setup(parent: Node3D, hud_ref: Hud, arms_ref: FpArms, player_ref: PlayerSystem, rng_ref: RandomNumberGenerator) -> void:
	main = parent
	hud = hud_ref
	arms = arms_ref
	player_sys = player_ref
	rng = rng_ref


func reset() -> void:
	inventory.clear()
	pickup_order.clear()
	equipped = ""
	mags.clear()
	mags_type.clear()
	ammo_choice.clear()
	qualities.clear()
	arms.hold("")
	changed.emit()


func count(id: String) -> int:
	return int(inventory.get(id, 0))


func has(id: String, amount := 1) -> bool:
	return count(id) >= amount


func add(id: String, amount := 1) -> void:
	if amount <= 0:
		return
	inventory[id] = count(id) + amount
	if not pickup_order.has(id):
		pickup_order.append(id)
	changed.emit()


func remove(id: String, amount := 1) -> int:
	var take: int = mini(count(id), amount)
	if take <= 0:
		return 0
	inventory[id] = count(id) - take
	if inventory[id] <= 0:
		inventory.erase(id)
		pickup_order.erase(id)
		if equipped == id:
			equip("")
	changed.emit()
	return take


func refresh() -> void:
	var list := []
	for id in pickup_order:
		list.append({"id": id, "count": inventory.get(id, 0), "equipped": id == equipped,
			"quality": qualities.get(id, 0)})
	# 快捷栏：当前武器 + 能吃能用的，最多 6 格
	var bar: Array[String] = []
	if equipped != "":
		bar.append(equipped)
	var kinds := [Assets.Kind.GUN, Assets.Kind.MELEE, Assets.Kind.BLOCK, Assets.Kind.FOOD, Assets.Kind.DRINK, Assets.Kind.MEDICAL]
	for pass_ in 2:
		for k in kinds:
			for id in pickup_order:
				if bar.size() >= 6:
					break
				if id != equipped and not bar.has(id) and Assets.items_by_id[id].kind == k:
					bar.append(id)
					if pass_ == 0:
						break
	hud.set_inventory(list, bar)


func equip(id: String) -> void:
	equipped = id
	if combat:
		combat.on_equip()
	if id != "" and Assets.items_by_id[id].kind == Assets.Kind.GUN:
		if not mags.has(id):
			# 捡到的枪里还剩点子弹
			mags[id] = int(ceil(Weapons.stats(id).mag * rng.randf_range(0.3, 1.0)))
		if not mags_type.has(id):
			mags_type[id] = Weapons.default_ammo(id)
	arms.hold(id)
	if id != "":
		hud.toast("装备：%s" % Assets.display_name(id))
	changed.emit()


func pickup(id: String, quality := 0, amount := 0) -> void:
	var n: int = amount
	if n <= 0:
		n = Weapons.pickup_count(id, rng) if Weapons.is_ammo(id) else 1
	inventory[id] = inventory.get(id, 0) + n
	if not pickup_order.has(id):
		pickup_order.append(id)
	var row: Dictionary = Assets.items_by_id[id]
	if quality > 0 and row.kind in [Assets.Kind.GUN, Assets.Kind.MELEE]:
		qualities[id] = maxi(qualities.get(id, 1), quality)
	Sfx.play("loot", Vector3.INF, -8.0)
	var extra := (" ×%d" % n if n > 1 else "")
	if quality > 1:
		extra += "  Q%d" % quality
	hud.toast("捡到：%s%s" % [Assets.display_name(id), extra])
	# 捡到更好的武器自动换上
	if row.kind in [Assets.Kind.MELEE, Assets.Kind.GUN]:
		var cur: Dictionary = Assets.items_by_id.get(equipped, {})
		if cur.is_empty() or row.power > cur.get("power", 0.0):
			equip(id)
	refresh()


func use_item(id: String) -> void:
	if not inventory.has(id):
		return
	var row: Dictionary = Assets.items_by_id[id]
	if Weapons.is_ammo(id):
		use_ammo(id)
		refresh()
		return
	match row.kind:
		Assets.Kind.MELEE, Assets.Kind.GUN:
			equip("" if equipped == id else id)
		Assets.Kind.FOOD, Assets.Kind.DRINK, Assets.Kind.MEDICAL:
			apply_effect(id, row.kind)
		Assets.Kind.BLOCK:
			equip("" if equipped == id else id)
			if equipped == id:
				hud.toast("拿着%s：对准地面或方块点「攻击」摆放，空手或近战打方块能拆" % Assets.display_name(id))
		_:
			hud.toast("%s：材料，留着吧" % Assets.display_name(id))
	GameState.item_used.emit(id)
	refresh()


## 点背包里的子弹：手上的枪用这种子弹就换弹，不然换上背包里第一把用这种子弹的枪
func use_ammo(id: String) -> void:
	if equipped != "" and id.begins_with(Weapons.stats(equipped).ammo) and Assets.items_by_id[equipped].kind == Assets.Kind.GUN:
		ammo_choice[equipped] = id
		if combat:
			combat.reload()
		hud.toast("换弹：%s" % Weapons.ammo_label(id))
		return
	for gun in pickup_order:
		if Assets.items_by_id[gun].kind == Assets.Kind.GUN and id.begins_with(Weapons.stats(gun).ammo):
			ammo_choice[gun] = id
			equip(gun)
			if combat:
				combat.reload()
			return
	hud.toast("背包里没有用%s的枪" % Assets.display_name(id))


## 吃喝用药：按 Survival 表加减各项，再把物品用掉
func apply_effect(id: String, kind: int) -> void:
	var e := Survival.effect(id, kind)
	player_sys.add_food(e.food)
	player_sys.add_water(e.water)
	player_sys.heal(e.hp)
	player_sys.add_stamina(e.get("stamina", 0.0))
	var verb: String = {Assets.Kind.FOOD: "吃了", Assets.Kind.DRINK: "喝了"}.get(kind, "用了")
	Sfx.play({Assets.Kind.FOOD: "eat", Assets.Kind.DRINK: "drink"}.get(kind, "bandage"))
	var msg: String = verb + Assets.display_name(id)
	if e.get("stop_bleed", false) and player_sys.stop_bleed():
		msg += "，血止住了"
	if e.get("cure", false) and player_sys.cure_sickness():
		msg += "，肚子好了"
	if e.has("buff"):
		player_sys.add_buff(e.buff)
		msg += "，精神一振"
	if player_sys.roll_sickness(e.get("sick", 0.0)):
		msg += "……肚子不对劲"
	consume(id, msg)


func consume(id: String, msg: String) -> void:
	inventory[id] -= 1
	if inventory[id] <= 0:
		inventory.erase(id)
		pickup_order.erase(id)
	hud.toast(msg)


## 测试模式：全部物品直接进背包，枪装满，每种子弹、每种方块给足。
func give_all_items(top_up := false) -> void:
	# 测试模式：官方物品表里的东西全部进背包，数量按类别给
	for id in Data.items:
		var info: Dictionary = Data.items[id]
		var row: Dictionary = Assets.ensure_item(id, str(info.get("zh", id)))
		var kind: int = row.kind
		var want := 20
		if kind in [Assets.Kind.GUN, Assets.Kind.MELEE]:
			want = 1
		elif kind in [Assets.Kind.FOOD, Assets.Kind.DRINK, Assets.Kind.MEDICAL]:
			want = 5
		elif kind == Assets.Kind.BLOCK:
			want = C.TEST_BLOCKS
		elif Weapons.is_ammo(id):
			want = C.TEST_AMMO
		if inventory.get(id, 0) < want:
			inventory[id] = want
		if not pickup_order.has(id):
			pickup_order.append(id)
		if kind == Assets.Kind.GUN:
			if not mags.has(id):
				mags[id] = Weapons.stats(id).mag
			if not mags_type.has(id):
				mags_type[id] = Weapons.default_ammo(id)
	if top_up:
		return
	# 快捷栏先放手枪和步枪（不然按字母排第一把是弓）
	for id in ["gunMGT2TacticalAR", "gunHandgunT0PipePistol"]:
		if pickup_order.has(id):
			pickup_order.erase(id)
			pickup_order.push_front(id)
	for id in ["gunMGT2TacticalAR", "gunHandgunT0PipePistol", "gunHandgunT1Pistol"]:
		if inventory.has(id):
			equip(id)
			return
	for id in ["meleeWpnClubT1BaseballBat", "meleeToolPickT1IronPickaxe"]:
		if inventory.has(id):
			equip(id)
			break


## 正式模式开局：给一把手枪、一把步枪和子弹，拿枪在手上
func give_starter_kit() -> void:
	var pistol := _find_gun(["gunHandgunT1Pistol", "gunHandgunT0PipePistol"], "Pistol")
	var rifle := _find_gun(["gunMGT2TacticalAR", "gunMGT1AK47"], "MG")
	_give_starter_gun(pistol)
	_give_starter_gun(rifle)
	if rifle != "":
		equip(rifle)
	elif pistol != "":
		equip(pistol)
	refresh()
	if equipped != "":
		hud.toast("开局：背包里有枪和子弹")


func _find_gun(preferred: Array, keyword: String) -> String:
	for id in preferred:
		if Assets.items_by_id.has(id) and Assets.items_by_id[id].kind == Assets.Kind.GUN:
			return id
	for row in Assets.items:
		var id: String = row.id
		if row.kind == Assets.Kind.GUN and not id.ends_with("Parts") and not id.begins_with("gunBot"):
			if keyword == "" or id.contains(keyword):
				return id
	return ""


func _find_ammo(prefix: String) -> String:
	for row in Assets.items:
		if Weapons.is_ammo(row.id) and row.id.begins_with(prefix):
			return row.id
	return ""


func _give_starter_gun(id: String) -> void:
	if id == "":
		return
	inventory[id] = maxi(1, inventory.get(id, 0))
	if not pickup_order.has(id):
		pickup_order.append(id)
	if not mags.has(id):
		mags[id] = Weapons.stats(id).mag
	if not mags_type.has(id):
		mags_type[id] = Weapons.default_ammo(id)
	var ammo := Weapons.default_ammo(id)
	if not Assets.items_by_id.has(ammo):
		ammo = _find_ammo(Weapons.stats(id).ammo)
	if ammo != "":
		inventory[ammo] = maxi(inventory.get(ammo, 0), C.STARTER_AMMO)
		if not pickup_order.has(ammo):
			pickup_order.append(ammo)


func save_data() -> Dictionary:
	return {"inventory": inventory, "order": pickup_order, "equipped": equipped, "mags": mags, "mags_type": mags_type, "ammo_choice": ammo_choice, "qualities": qualities}


func load_data(d: Dictionary) -> void:
	for id in d.get("inventory", {}):
		if Assets.items_by_id.has(id):
			inventory[id] = int(d.inventory[id])
	for id in d.get("order", []):
		if inventory.has(id):
			pickup_order.append(id)
	for id in d.get("mags", {}):
		mags[id] = int(d.mags[id])
	for id in d.get("mags_type", {}):
		mags_type[id] = str(d.mags_type[id])
	for id in d.get("ammo_choice", {}):
		ammo_choice[id] = str(d.ammo_choice[id])
	for id in d.get("qualities", {}):
		qualities[id] = int(d.qualities[id])
	for id in mags:
		if not mags_type.has(id):
			mags_type[id] = Weapons.default_ammo(id)
	if C.TEST_ALL_ITEMS:
		give_all_items(true)
	var eq: String = d.get("equipped", "")
	equip(eq if inventory.has(eq) else "")
	refresh()
