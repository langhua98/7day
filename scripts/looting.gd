class_name LootingSystem
extends RefCounted
## 地上物品、翻容器、拾取和搜索进度。

const C = preload("res://scripts/config.gd")

var main: Node3D
var world: World
var player_sys: PlayerSystem
var inventory: InventorySystem
var hud: Hud
var rng: RandomNumberGenerator
var loot_root := Node3D.new()
var running := false

## 正在翻的容器（空字典表示没在翻）、翻了多久、开始翻时站的位置
var _search := {}
var _search_t := 0.0
var _search_from := Vector3.ZERO
var _e_down := false
## 玩家摆的储物箱：格子坐标 → {items, pos, name, r}
var crates := {}
## 容器面板正开着的容器
var _open := {}
## 尸体背包（3c）：[{items, pos, name, r, node, bag: true}]，拿空了就消失
var corpse_bags: Array = []

const CRATE_ID := "cntWoodWritableCrate"
const LOOT_SCRIPT := "res://scripts/loot.gd"


func setup(parent: Node3D, world_ref: World, player_ref: PlayerSystem, inv_ref: InventorySystem,
		hud_ref: Hud, rng_ref: RandomNumberGenerator) -> void:
	main = parent
	world = world_ref
	player_sys = player_ref
	inventory = inv_ref
	hud = hud_ref
	rng = rng_ref


func build() -> void:
	main.add_child(loot_root)
	GameState.block_changed.connect(_on_block_changed)
	hud.container_panel.closed.connect(_on_panel_closed)


func reset() -> void:
	for l in loot_root.get_children():
		l.queue_free()
	_search = {}
	_search_t = 0.0
	_search_from = Vector3.ZERO
	crates.clear()
	_clear_corpse_bags()
	_open = {}
	hud.container_panel.close_panel()
	hud.set_progress(-1.0)


func spawn_loot(pos: Vector3, id := "", quality := 0, amount := 0) -> void:
	if id == "":
		id = Assets.random_loot(rng)
	if id == "":
		return
	var vis := Assets.make_item_visual(id, C.LOOT_SIZE)
	if vis == null:
		return
	var holder := Node3D.new()
	holder.set_meta("item", id)
	if quality > 0:
		holder.set_meta("quality", quality)
	if amount > 0:
		holder.set_meta("amount", amount)
	holder.position = pos
	var spin := Node3D.new()
	spin.name = "Spin"
	spin.position.y = 0.15
	spin.add_child(vis)
	holder.add_child(spin)
	# 物品名字，走近才显示
	var label := Label3D.new()
	label.text = Assets.display_name(id) + ("  Q%d" % quality if quality > 1 else "")
	label.font = _cjk_font()
	label.font_size = 36
	label.outline_size = 10
	# 固定在屏幕上的大小，走近不会变得很大
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = 0.95
	label.visibility_range_end = 7.0
	label.modulate = Color(1, 0.95, 0.8)
	holder.add_child(label)
	# 地上一圈淡淡的光，远处也能看到
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.8, 0.4)
	glow.light_energy = 0.6
	glow.omni_range = 1.4
	glow.distance_fade_enabled = true
	# 只有身边十几米的物品亮光，同时可见的动态光不超过 8 个左右
	glow.distance_fade_begin = 14.0
	glow.distance_fade_length = 4.0
	glow.position.y = 0.5
	holder.add_child(glow)
	loot_root.add_child(holder)


func update_loot(delta: float) -> void:
	var count := 0
	for l in loot_root.get_children():
		if l.is_queued_for_deletion():
			continue
		count += 1
		var spin: Node3D = l.get_node("Spin")
		spin.rotation.y += delta * 1.2
		spin.position.y = 0.15 + sin(Time.get_ticks_msec() / 400.0 + l.position.x) * 0.05
	if count < C.LOOT_COUNT and rng.randf() < delta * 0.2:
		spawn_loot(world.free_point(player_sys.player.position, 15.0, 45.0))


func _cjk_font() -> Font:
	return Hud.game_font()


## 离玩家最近、能拾取的地上物品（优先看准星对着的）
func nearest_loot() -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var aim := -player_sys.player.global_basis.z
	for l in loot_root.get_children():
		if l.is_queued_for_deletion():
			continue
		var to: Vector3 = l.position - player_sys.player.position
		to.y = 0.0
		var d := to.length()
		if d > C.PICKUP_RADIUS:
			continue
		var score := d - (aim.dot(to / d) if d > 0.01 else 1.0) * 0.8
		if score < best_score:
			best_score = score
			best = l
	return best


## 每帧决定「搜索 / 拾取」按钮显示什么，推进翻找进度
func update_action(delta: float) -> void:
	if not _open.is_empty():
		# 面板开着：离开 2 米自动关
		var to: Vector3 = player_sys.player.position - _open.pos
		if Vector2(to.x, to.z).length() - float(_open.get("r", 0.5)) > C.CONTAINER_CLOSE_DIST or not hud.container_panel.visible:
			hud.container_panel.close_panel()
			_open = {}
		hud.set_action("")
		return
	if not _search.is_empty():
		var c: Dictionary = _search
		var need: float = C.SEARCH_TIME_CAR if c.kind == "car" else C.SEARCH_TIME
		if player_sys.player.position.distance_to(_search_from) > 0.8:
			_search = {}
			hud.set_progress(-1.0)
			hud.toast("走开了，没翻完")
		else:
			_search_t += delta
			hud.set_progress(_search_t / need, "正在翻%s…" % c.name)
			hud.set_action("")
			if _search_t >= need:
				_finish_search(c)
			return
	var loot := nearest_loot()
	if loot:
		hud.set_action("拾取\n%s" % Assets.display_name(loot.get_meta("item")))
		return
	var crate := nearest_crate()
	if not crate.is_empty():
		hud.set_action("打开\n%s" % crate.name)
		return
	var station := world.nearest_station(player_sys.player.position, C.STATION_REACH)
	if not station.is_empty():
		hud.set_action("使用\n%s" % station.name)
		return
	var c := world.nearest_container(player_sys.player.position)
	var door := _door_target(c)
	if not door.is_empty():
		hud.set_action("%s\n%s" % ["关上" if door.open else "打开", _door_name(door)])
		return
	if c.is_empty():
		hud.set_action("")
	elif c.searched and _has_items(c):
		hud.set_action("打开\n%s" % c.name)
	elif c.searched:
		hud.set_action("%s\n已翻过" % c.name, false)
	else:
		hud.set_action("搜索\n%s" % c.name)


func action() -> void:
	if not running or not _search.is_empty():
		return
	var loot := nearest_loot()
	if loot:
		var amount := int(loot.get_meta("amount", 0))
		var left := inventory.pickup(loot.get_meta("item"), int(loot.get_meta("quality", 0)), amount)
		if left <= 0:
			loot.queue_free()
		elif amount > 0 and left < amount:
			loot.set_meta("amount", left)
		return
	var crate := nearest_crate()
	if not crate.is_empty():
		open_panel(crate)
		return
	var station := world.nearest_station(player_sys.player.position, C.STATION_REACH)
	if not station.is_empty():
		hud.craft_panel.open(station.area, station.get("cell"))
		main.crafting.station_open(station.area, station.pos)
		return
	var c := world.nearest_container(player_sys.player.position)
	var door := _door_target(c)
	if not door.is_empty():
		_use_door(door)
		return
	if c.is_empty():
		return
	if c.searched:
		if _has_items(c):
			open_panel(c)
		return
	_search = c
	_search_t = 0.0
	Sfx.play("search", c.pos + Vector3.UP * 0.8)
	_search_from = player_sys.player.position


## 面前够得着的门；旁边也有容器时谁近用谁
func _door_target(container: Dictionary) -> Dictionary:
	var me: Vector3 = player_sys.player.position
	var door := world.nearest_door(me, -player_sys.player.global_basis.z, C.DOOR_REACH)
	if door.is_empty() or container.is_empty():
		return door
	var dd := Vector2(door.pos.x - me.x, door.pos.z - me.z).length()
	var dc := Vector2(container.pos.x - me.x, container.pos.z - me.z).length() - float(container.r)
	return door if dd < dc else {}


func _door_name(door: Dictionary) -> String:
	var d: Dictionary = world.interiors[door.interior].doors[door.door]
	if d.hatch:
		return "活板门"
	return "铁门" if d.metal else "门"


func _use_door(door: Dictionary) -> void:
	# 关门时人站在门洞里就不关，免得卡进门板
	if door.open and world.door_blocked_by(door.interior, door.door, player_sys.player.position, 0.35):
		hud.toast("站在门口关不上")
		return
	world.toggle_door(door.interior, door.door)
	if Sfx.has("door"):
		Sfx.play("door", door.pos)
	GameState.make_noise(door.pos, "door")


func _finish_search(c: Dictionary) -> void:
	_search = {}
	hud.set_progress(-1.0)
	c.searched = true
	var got := roll_container(c)
	var items: Array = []
	items.resize(maxi(C.CONTAINER_SLOTS, got.size()))
	for i in items.size():
		items[i] = got[i] if i < got.size() else {}
	c["items"] = items
	if got.is_empty():
		hud.toast("%s里什么也没有" % c.name)
		return
	open_panel(c)


## 容器里有什么：有 Loot.roll（2a 的官方掉落表）就用它，没有先用 Assets.random_loot 顶上
func roll_container(c: Dictionary) -> Array:
	var out: Array = []
	if ResourceLoader.exists(LOOT_SCRIPT):
		var loot_cls = load(LOOT_SCRIPT)
		if loot_cls and loot_cls.has_method("roll"):
			for e in loot_cls.roll(str(c.get("loot_name", c.get("loot", "any"))), GameState.gamestage(), rng):
				if Assets.items_by_id.has(str(e.get("id", ""))):
					out.append({"id": str(e.id), "count": maxi(1, int(e.get("count", 1))),
						"quality": int(e.get("quality", 0)), "durability": 0.0})
			return out
	if rng.randf() < C.SEARCH_EMPTY_CHANCE:
		return out
	for i in rng.randi_range(C.SEARCH_MIN, C.SEARCH_MAX):
		var id := Assets.random_loot(rng, c.loot)
		if id == "":
			continue
		var quality := 0
		if Assets.items_by_id[id].kind in [Assets.Kind.GUN, Assets.Kind.MELEE]:
			quality = Weapons.roll_quality(GameState.gamestage(), rng)
		var n: int = Weapons.pickup_count(id, rng) if Weapons.is_ammo(id) else 1
		out.append({"id": id, "count": n, "quality": quality, "durability": 0.0})
	return out


func _has_items(c: Dictionary) -> bool:
	for s in c.get("items", []):
		if not s.is_empty():
			return true
	return false


func open_panel(c: Dictionary) -> void:
	_open = c
	Sfx.play("search", c.pos + Vector3.UP * 0.6, -6.0)
	hud.container_panel.open(c.name, c.items, inventory)


func _on_panel_closed() -> void:
	var was := _open
	_open = {}
	if was.get("bag", false) and not _has_items(was):
		_remove_corpse_bag(was)


## 离玩家最近、够得着的储物箱（尸体背包也算）
func nearest_crate() -> Dictionary:
	var best := {}
	var best_d := 1.9
	for cr in crates.values() + corpse_bags:
		var to: Vector3 = cr.pos - player_sys.player.position
		var d := Vector2(to.x, to.z).length()
		if d < best_d and absf(to.y) < 2.2:
			best_d = d
			best = cr
	return best


func _new_crate(cell: Vector3i) -> Dictionary:
	var items: Array = []
	items.resize(C.CRATE_SLOTS)
	for i in items.size():
		items[i] = {}
	return {"items": items, "pos": Vector3(cell) + Vector3(0.5, 0.0, 0.5), "name": "储物箱", "r": 0.5}


## 方块变了：摆下储物箱就登记；箱子被拆掉，里面的东西掉在地上
func _on_block_changed(cell: Vector3i) -> void:
	var v: Dictionary = world.voxels.get(cell, {})
	if v.get("id", "") == CRATE_ID:
		if not crates.has(cell):
			crates[cell] = _new_crate(cell)
		return
	if crates.has(cell):
		var cr: Dictionary = crates[cell]
		crates.erase(cell)
		if is_same(_open, cr):
			hud.container_panel.close_panel()
		for s in cr.items:
			if not s.is_empty():
				spawn_loot(world.push_out(cr.pos + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6)), 0.2),
					s.id, int(s.quality), int(s.count))


## 背包面板里点「丢弃」：整格丢在面前的地上
func drop_slot(index: int) -> void:
	var s := inventory.take_slot(index)
	if s.is_empty():
		return
	var fwd := -player_sys.player.global_basis.z
	fwd.y = 0.0
	var p: Vector3 = player_sys.player.position + fwd.normalized() * 1.2
	spawn_loot(world.push_out(p, 0.2), s.id, int(s.quality), int(s.count))
	hud.toast("丢掉了%s" % Assets.display_name(s.id))
	inventory.refresh()


# —— 尸体背包（死亡时身上的全部东西） ——

## 在死亡位置放一个尸体背包，items 是背包格子（非空的）
func add_corpse_bag(pos: Vector3, items: Array) -> Dictionary:
	var list: Array = items.duplicate()
	while list.size() < C.CONTAINER_SLOTS:
		list.append({})
	var bag := {"items": list, "pos": pos, "name": "尸体背包", "r": 0.4, "bag": true}
	bag.node = _corpse_bag_node(pos)
	main.add_child(bag.node)
	corpse_bags.append(bag)
	return bag


func _remove_corpse_bag(bag: Dictionary) -> void:
	corpse_bags.erase(bag)
	if bag.get("node") and is_instance_valid(bag.node):
		bag.node.queue_free()
	hud.toast("尸体背包拿空了")


func _clear_corpse_bags() -> void:
	for b in corpse_bags:
		if b.get("node") and is_instance_valid(b.node):
			b.node.queue_free()
	corpse_bags.clear()


## 尸体背包的样子：云盘有模型（assets/world/corpse_bag.obj）就用，没有先用棕色小方块顶上
func _corpse_bag_node(pos: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.position = pos
	var mi := MeshInstance3D.new()
	var path := "res://assets/world/corpse_bag.obj"
	if ResourceLoader.exists(path) and load(path) is Mesh:
		mi.mesh = load(path)
		var tex := "res://assets/world/corpse_bag.png"
		var mat := StandardMaterial3D.new()
		if ResourceLoader.exists(tex):
			mat.albedo_texture = load(tex)
		mi.material_override = mat
	else:
		var box := BoxMesh.new()
		box.size = Vector3(0.55, 0.35, 0.4)
		mi.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.36, 0.25, 0.14)
		mi.material_override = mat
		mi.position.y = 0.175
	holder.add_child(mi)
	var label := Label3D.new()
	label.text = "尸体背包"
	label.font = _cjk_font()
	label.font_size = 36
	label.outline_size = 10
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = 0.9
	label.visibility_range_end = 12.0
	label.modulate = Color(1, 0.6, 0.5)
	holder.add_child(label)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.45, 0.35)
	glow.light_energy = 0.8
	glow.omni_range = 1.8
	glow.position.y = 0.6
	holder.add_child(glow)
	return holder


## 存档：容器里没拿完的东西、储物箱里的东西
func save_data() -> Dictionary:
	var left := {}
	for i in world.containers.size():
		var c: Dictionary = world.containers[i]
		if c.has("items"):
			left[str(i)] = _pack(c.items)
	var cr := []
	for cell in crates:
		cr.append([cell.x, cell.y, cell.z, _pack(crates[cell].items)])
	var bags := []
	for b in corpse_bags:
		bags.append({"pos": [b.pos.x, b.pos.y, b.pos.z], "items": _pack(b.items)})
	return {"container_items": left, "crates": cr, "corpse_bags": bags}


## 在 world.voxel_load 之后调用
func load_data(d: Dictionary) -> void:
	var left: Dictionary = d.get("container_items", {})
	for k in left:
		var i := int(k)
		if i < world.containers.size():
			world.containers[i]["items"] = _unpack(left[k], C.CONTAINER_SLOTS)
	crates.clear()
	for cell in world.voxels:
		if world.voxels[cell].id == CRATE_ID:
			crates[cell] = _new_crate(cell)
	for e in d.get("crates", []):
		if e is Array and e.size() >= 4:
			var cell := Vector3i(int(e[0]), int(e[1]), int(e[2]))
			if crates.has(cell):
				crates[cell].items = _unpack(e[3], C.CRATE_SLOTS)
	_clear_corpse_bags()
	for e in d.get("corpse_bags", []):
		if e is Dictionary and e.get("pos") is Array and e.pos.size() >= 3:
			var items := _unpack(e.get("items", []), C.CONTAINER_SLOTS)
			if _has_items({"items": items}):
				add_corpse_bag(Vector3(float(e.pos[0]), float(e.pos[1]), float(e.pos[2])), items)


static func _pack(items: Array) -> Array:
	var out := []
	for s in items:
		out.append(s if not s.is_empty() else null)
	return out


static func _unpack(list, size: int) -> Array:
	var out: Array = []
	if list is Array:
		for e in list:
			if e is Dictionary and Assets.items_by_id.has(str(e.get("id", ""))):
				out.append({"id": str(e.id), "count": int(e.get("count", 1)), "quality": int(e.get("quality", 0)),
					"durability": float(e.get("durability", 0.0))})
			else:
				out.append({})
	while out.size() < size:
		out.append({})
	return out
