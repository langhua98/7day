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

## 背包格子：每格 {id, count, quality, durability}，空格是 {}。inventory 是「id → 总数」的汇总，只读。
var inventory := {}
var pickup_order: Array[String] = []
var equipped := ""
var mags := {}
var mags_type := {}
var ammo_choice := {}
## 每种武器的最高品质（汇总，只读；combat 取伤害用）
var qualities := {}
var _slots: Array = []
## 不超重的格子数（测试模式会自动扩）
var _cap := C.BAG_SLOTS


func setup(parent: Node3D, hud_ref: Hud, arms_ref: FpArms, player_ref: PlayerSystem, rng_ref: RandomNumberGenerator) -> void:
	main = parent
	hud = hud_ref
	arms = arms_ref
	player_sys = player_ref
	rng = rng_ref


func reset() -> void:
	_cap = C.BAG_SLOTS
	_slots.clear()
	_slots.resize(limit())
	for i in _slots.size():
		_slots[i] = {}
	inventory.clear()
	pickup_order.clear()
	equipped = ""
	mags.clear()
	mags_type.clear()
	ammo_choice.clear()
	qualities.clear()
	if arms:
		arms.hold("")
	changed.emit()


## 一格最多叠几个：官方 Stacknumber，没有就 1
static func stack_of(id: String) -> int:
	var info: Dictionary = Data.items.get(id, {})
	return maxi(1, int(info.get("stack", 1)))


## 背包总格数（含超重格）
func limit() -> int:
	return _cap + (0 if C.TEST_ALL_ITEMS else C.BAG_OVERLOAD_SLOTS)


func base_slots() -> int:
	return _cap


func slots() -> Array:
	return _slots


func used_slots() -> int:
	var n := 0
	for s in _slots:
		if not s.is_empty():
			n += 1
	return n


## 超重：占用格数超过 45 后每格 −10% 移速，最多 −50%
func overload() -> float:
	return clampf((used_slots() - _cap) * C.OVERLOAD_PER_SLOT, 0.0, C.OVERLOAD_MAX)


func count(id: String) -> int:
	return int(inventory.get(id, 0))


func has(id: String, amount := 1) -> bool:
	return count(id) >= amount


## 放进背包，返回放不下的数量。item 可以是物品名，或 {id, count, quality, durability}
func add(item, amount := 1) -> int:
	var left := _put(_as_slot(item, amount))
	_reindex()
	changed.emit()
	return left


func _as_slot(item, amount := 1) -> Dictionary:
	if item is Dictionary:
		return {"id": str(item.id), "count": int(item.get("count", 1)), "quality": int(item.get("quality", 0)),
			"durability": float(item.get("durability", 0.0))}
	return {"id": str(item), "count": amount, "quality": 0, "durability": 0.0}


## 先叠到同种（同品质）格子上，再放空格；测试模式下格子不够就扩
func _put(it: Dictionary) -> int:
	var id: String = it.id
	var left: int = it.count
	if left <= 0 or id == "":
		return 0
	var stack := stack_of(id)
	for s in _slots:
		if left <= 0:
			break
		if not s.is_empty() and s.id == id and int(s.quality) == int(it.quality) and s.count < stack:
			var n := mini(stack - int(s.count), left)
			s.count += n
			left -= n
	while left > 0:
		var i := _empty_index()
		if i < 0:
			if not C.TEST_ALL_ITEMS:
				break
			_cap += 9
			var old := _slots.size()
			_slots.resize(limit())
			for k in range(old, _slots.size()):
				_slots[k] = {}
			continue
		var n := mini(stack, left)
		_slots[i] = {"id": id, "count": n, "quality": int(it.quality), "durability": float(it.durability)}
		left -= n
	return left


func _empty_index() -> int:
	for i in _slots.size():
		if _slots[i].is_empty():
			return i
	return -1


## 还能放下几个
func room_for(id: String, quality := 0) -> int:
	if C.TEST_ALL_ITEMS:
		return 1 << 30
	var stack := stack_of(id)
	var n := 0
	for s in _slots:
		if s.is_empty():
			n += stack
		elif s.id == id and int(s.quality) == quality:
			n += maxi(0, stack - int(s.count))
	return n


## 整理背包：叠得下的合并，测试模式同品质的唯一物品只留一个，再按类别和名字排序
func compact() -> void:
	var kept: Array = []
	for s in _slots:
		if s.is_empty():
			continue
		var id := str(s.get("id", ""))
		var stack := stack_of(id)
		if stack <= 1:
			if C.TEST_ALL_ITEMS:
				var dup := false
				for k in kept:
					if str(k.id) == id and int(k.quality) == int(s.quality) and is_equal_approx(float(k.durability), float(s.durability)):
						dup = true
						break
				if dup:
					continue
			kept.append(s.duplicate(true))
			continue
		var left := int(s.count)
		for k in kept:
			if left <= 0:
				break
			if str(k.id) == id and int(k.quality) == int(s.quality) and int(k.count) < stack:
				var n := mini(stack - int(k.count), left)
				k.count += n
				left -= n
		while left > 0:
			var n := mini(stack, left)
			kept.append({"id": id, "count": n, "quality": int(s.quality), "durability": float(s.durability)})
			left -= n
	kept.sort_custom(func(a, b):
		var ka := int(Assets.items_by_id.get(str(a.id), {}).get("kind", 99))
		var kb := int(Assets.items_by_id.get(str(b.id), {}).get("kind", 99))
		if ka != kb:
			return ka < kb
		return Assets.display_name(str(a.id)) < Assets.display_name(str(b.id)))
	var n := maxi(limit(), kept.size())
	_slots.clear()
	_slots.resize(n)
	for i in n:
		_slots[i] = kept[i] if i < kept.size() else {}
	_reindex()
	changed.emit()


func remove(id: String, amount := 1) -> int:
	var take: int = mini(count(id), amount)
	if take <= 0:
		return 0
	var need := take
	# 从后往前扣，先扣零头
	for i in range(_slots.size() - 1, -1, -1):
		if need <= 0:
			break
		var s: Dictionary = _slots[i]
		if s.is_empty() or s.id != id:
			continue
		var n := mini(int(s.count), need)
		s.count -= n
		need -= n
		if s.count <= 0:
			_slots[i] = {}
	_reindex()
	if not inventory.has(id) and equipped == id:
		equip("")
	changed.emit()
	return take


## 取出整格（容器面板、丢弃用）
func take_slot(i: int) -> Dictionary:
	if i < 0 or i >= _slots.size() or _slots[i].is_empty():
		return {}
	var s: Dictionary = _slots[i]
	_slots[i] = {}
	_reindex()
	if not inventory.has(s.id) and equipped == s.id:
		equip("")
	changed.emit()
	return s


## 死亡：拿走身上全部物品（含手上的），返回非空格子，背包清空
func take_all() -> Array:
	var out: Array = []
	for i in _slots.size():
		if not _slots[i].is_empty():
			out.append(_slots[i])
			_slots[i] = {}
	_reindex()
	equip("")
	changed.emit()
	return out


## 格子变了以后重算汇总：id → 总数、拾取顺序、武器品质
func _reindex() -> void:
	inventory.clear()
	qualities.clear()
	for s in _slots:
		if s.is_empty():
			continue
		inventory[s.id] = int(inventory.get(s.id, 0)) + int(s.count)
		if int(s.quality) > 0:
			qualities[s.id] = maxi(int(qualities.get(s.id, 0)), int(s.quality))
	for id in pickup_order.duplicate():
		if not inventory.has(id):
			pickup_order.erase(id)
	for s in _slots:
		if not s.is_empty() and not pickup_order.has(s.id):
			pickup_order.append(s.id)


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
	hud.set_bag(_slots, _cap, used_slots(), equipped)


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


## 捡起来，返回放不下的数量（放不下的留在原地）
func pickup(id: String, quality := 0, amount := 0) -> int:
	var n: int = amount
	if n <= 0:
		n = Weapons.pickup_count(id, rng) if Weapons.is_ammo(id) else 1
	var row: Dictionary = Assets.items_by_id[id]
	if not row.kind in [Assets.Kind.GUN, Assets.Kind.MELEE]:
		quality = 0
	var left := _put({"id": id, "count": n, "quality": quality, "durability": 0.0})
	_reindex()
	changed.emit()
	if left >= n:
		hud.toast("背包满了（%d 格），放不下%s" % [limit(), Assets.display_name(id)])
		return left
	n -= left
	if overload() > 0.0:
		hud.toast("背包超重：走得慢了，也不能冲刺")
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
	return left


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
	if e.get("splint", false):
		msg += player_sys.apply_splint()
	if e.get("cast", false):
		msg += player_sys.apply_cast()
	if e.has("infection"):
		msg += player_sys.treat_infection(int(e.infection))
	if e.has("buff"):
		player_sys.add_buff(float(e.buff))
		msg += "，精神一振"
	if player_sys.roll_sickness(e.get("sick", 0.0)):
		msg += "……肚子不对劲"
	consume(id, msg)


func consume(id: String, msg: String) -> void:
	remove(id, 1)
	hud.toast(msg)


## 测试模式：全部物品直接进背包，枪装满，每种子弹、每种方块给足。
func give_all_items(top_up := false) -> void:
	# 测试模式：官方物品表里的东西全部进背包，数量按类别给
	for id in Data.items:
		var info: Dictionary = Data.items[id]
		var row: Dictionary = Assets.ensure_item(id, str(info.get("zh", id)))
		var kind: int = row.kind
		var stack := stack_of(id)
		var want := mini(20, stack)
		if kind in [Assets.Kind.GUN, Assets.Kind.MELEE]:
			want = 1
		elif kind in [Assets.Kind.FOOD, Assets.Kind.DRINK, Assets.Kind.MEDICAL]:
			want = mini(5, stack)
		elif kind == Assets.Kind.BLOCK:
			want = mini(C.TEST_BLOCKS, stack)
		elif Weapons.is_ammo(id):
			want = mini(C.TEST_AMMO, stack)
		var have := count(id)
		if have < want:
			_put({"id": id, "count": want - have, "quality": 0, "durability": 0.0})
		if kind == Assets.Kind.GUN:
			if not mags.has(id):
				mags[id] = Weapons.stats(id).mag
			if not mags_type.has(id):
				mags_type[id] = Weapons.default_ammo(id)
	_reindex()
	changed.emit()
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
	if count(id) <= 0:
		_put({"id": id, "count": 1, "quality": 0, "durability": 0.0})
	if not mags.has(id):
		mags[id] = Weapons.stats(id).mag
	if not mags_type.has(id):
		mags_type[id] = Weapons.default_ammo(id)
	var ammo := Weapons.default_ammo(id)
	if not Assets.items_by_id.has(ammo):
		ammo = _find_ammo(Weapons.stats(id).ammo)
	if ammo != "" and count(ammo) < C.STARTER_AMMO:
		_put({"id": ammo, "count": C.STARTER_AMMO - count(ammo), "quality": 0, "durability": 0.0})
	_reindex()


func save_data() -> Dictionary:
	var packed := []
	for sl in _slots:
		packed.append(sl if not sl.is_empty() else null)
	return {"bag": packed, "bag_cap": _cap, "inventory": inventory, "order": pickup_order, "equipped": equipped,
		"mags": mags, "mags_type": mags_type, "ammo_choice": ammo_choice, "qualities": qualities}


func load_data(d: Dictionary) -> void:
	var bag: Array = d.get("bag", [])
	if not bag.is_empty():
		# 新存档：按格子原样恢复
		_cap = maxi(C.BAG_SLOTS, int(d.get("bag_cap", C.BAG_SLOTS))) if C.TEST_ALL_ITEMS else C.BAG_SLOTS
		_slots.resize(maxi(limit(), bag.size()))
		for i in _slots.size():
			var e = bag[i] if i < bag.size() else null
			_slots[i] = _as_slot(e) if e is Dictionary and Assets.items_by_id.has(str(e.get("id", ""))) else {}
	else:
		# 旧存档「id → 数量」：按拾取顺序转成格子，品质给武器那一格
		var old_q: Dictionary = d.get("qualities", {})
		var ids: Array = []
		for id in d.get("order", []):
			if d.get("inventory", {}).has(id) and not ids.has(id):
				ids.append(id)
		for id in d.get("inventory", {}):
			if not ids.has(id):
				ids.append(id)
		for id in ids:
			if Assets.items_by_id.has(id):
				_put({"id": id, "count": int(d.inventory[id]), "quality": int(old_q.get(id, 0)), "durability": 0.0})
	_reindex()
	for id in d.get("order", []):
		if pickup_order.has(id):
			pickup_order.erase(id)
			pickup_order.append(id)
	for id in d.get("mags", {}):
		mags[id] = int(d.mags[id])
	for id in d.get("mags_type", {}):
		mags_type[id] = str(d.mags_type[id])
	for id in d.get("ammo_choice", {}):
		ammo_choice[id] = str(d.ammo_choice[id])
	for id in mags:
		if not mags_type.has(id):
			mags_type[id] = Weapons.default_ammo(id)
	if C.TEST_ALL_ITEMS:
		give_all_items(true)
	var eq: String = d.get("equipped", "")
	equip(eq if inventory.has(eq) else "")
	refresh()
