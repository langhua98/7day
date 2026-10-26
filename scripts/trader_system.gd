class_name TraderSystem
extends Node3D
## 7c 商人：固定站点、营业时间、库存 3 天一换、买卖和安全区。

const C = preload("res://scripts/config.gd")
const SAFE_RADIUS := 15.0
const TALK_RADIUS := 4.0

var main: Node3D
var world: World
var player_sys: PlayerSystem
var inventory: InventorySystem
var hud: Hud
var rng: RandomNumberGenerator
var data := {}
var site := Vector3.ZERO
var stock: Array = []       # [{id, count}]
var next_day := 1
var open := false
var _warned := false
var _label: Label3D


func setup(parent: Node3D, world_ref: World, player_ref: PlayerSystem, inv_ref: InventorySystem,
		hud_ref: Hud, rng_ref: RandomNumberGenerator) -> void:
	main = parent
	world = world_ref
	player_sys = player_ref
	inventory = inv_ref
	hud = hud_ref
	rng = rng_ref


func build() -> void:
	data = Data.get_table("traders")
	if data.is_empty():
		data = {"open": 4.0833, "close": 21.8333, "reset_days": 3, "currency": "casinoCoin",
			"sell_markdown": 0.2, "items": {}}
	_pick_site()
	position = site
	_build_stall()
	reset()


func reset() -> void:
	stock.clear()
	next_day = GameState.day + int(data.get("reset_days", 3))
	_restock()
	open = is_open_hours()
	_warned = false


func _pick_site() -> void:
	var finder := RandomNumberGenerator.new()
	finder.seed = 20261026
	for r in [80.0, 72.0, 92.0, 65.0, 105.0]:
		for i in 16:
			var a := finder.randf() * TAU
			var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
			if world.blocked(p, 3.5) or world.inside_interior(p, 3.5):
				continue
			# 离出生点 60–120 米，且不要在楼里
			site = p
			return
	site = world.free_point(Vector3(80, 0, 0), 60.0, 110.0)
	site.y = 0.0


func _build_stall() -> void:
	# 柜台、两根柱子、顶棚、招牌；没有人物模型就只放柜台（任务允许）
	_box(Vector3(3.2, 0.9, 1.2), Vector3(0, 0.45, 0), Color(0.42, 0.28, 0.14))
	_box(Vector3(0.18, 2.4, 0.18), Vector3(-1.5, 1.2, -0.5), Color(0.3, 0.22, 0.12))
	_box(Vector3(0.18, 2.4, 0.18), Vector3(1.5, 1.2, -0.5), Color(0.3, 0.22, 0.12))
	_box(Vector3(3.6, 0.18, 2.0), Vector3(0, 2.45, -0.2), Color(0.35, 0.27, 0.18))
	# 站在柜台后的人形
	_box(Vector3(0.5, 1.0, 0.35), Vector3(0, 0.5, -0.9), Color(0.22, 0.28, 0.36))
	var head := SphereMesh.new()
	head.radius = 0.22
	head.height = 0.44
	var hi := MeshInstance3D.new()
	hi.mesh = head
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.78, 0.62, 0.48)
	hi.material_override = hm
	hi.position = Vector3(0, 1.28, -0.9)
	add_child(hi)
	_label = Label3D.new()
	_label.text = "商人"
	_label.font_size = 64
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color(1.0, 0.87, 0.45)
	_label.position = Vector3(0, 2.8, 0.2)
	add_child(_label)


func _box(size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.92
	mi.material_override = mat
	mi.position = at
	add_child(mi)


func is_open_hours() -> bool:
	var h := fmod(GameState.hours, 24.0)
	return h >= float(data.get("open", 4.0833)) and h < float(data.get("close", 21.8333))


func currency() -> String:
	return str(data.get("currency", "casinoCoin"))


func currency_count() -> int:
	return inventory.count(currency())


func is_near(p: Vector3, radius := SAFE_RADIUS) -> bool:
	var d := p - site
	d.y = 0.0
	return d.length() <= radius


func update(_delta: float) -> void:
	var now := is_open_hours()
	var close_h := float(data.get("close", 21.8333))
	var h := fmod(GameState.hours, 24.0)
	if not _warned and h >= close_h - 10.0 / 60.0 and h < close_h:
		_warned = true
		hud.toast("商人还有 10 分钟关门")
	if open and not now:
		if is_near(player_sys.player.position, SAFE_RADIUS):
			_move_player_out()
			hud.toast("商人关门了，你被请到门外")
		open = false
	elif not open and now:
		open = true
		_warned = false
		if is_near(player_sys.player.position, TALK_RADIUS):
			hud.toast("商人开始营业了")
	if GameState.day >= next_day:
		next_day = GameState.day + int(data.get("reset_days", 3))
		_restock()
		hud.toast("商人的货已经换了")
	if _label:
		_label.text = "商人" if open else "商人（休息）"
		_label.modulate = Color(1.0, 0.87, 0.45) if open else Color(0.6, 0.6, 0.6)


func _move_player_out() -> void:
	var d := player_sys.player.position - site
	d.y = 0.0
	if d.length() < 0.5:
		d = Vector3(1, 0, 0)
	player_sys.player.position = site + d.normalized() * (SAFE_RADIUS + 1.5)
	player_sys.player.position = world.push_out(player_sys.player.position, 0.35)
	player_sys.player.position.y = maxf(0.0, world.floor_under(player_sys.player.position, 0.3))


func open_panel() -> void:
	if not open:
		hud.toast("商人休息了（04:05–21:50）")
		return
	if not is_near(player_sys.player.position, TALK_RADIUS):
		return
	hud.trader_panel.open()


func _restock() -> void:
	stock.clear()
	var picker := RandomNumberGenerator.new()
	var reset_days := maxi(1, int(data.get("reset_days", 3)))
	picker.seed = int(GameState.day / reset_days) * 7919 + GameState.gamestage() * 31 + 101
	var pool: Array = []
	var pool_values: Dictionary = data.get("items", {})
	for id in pool_values:
		if not Assets.items_by_id.has(id):
			continue
		var row: Dictionary = Data.items.get(id, {})
		var value := int(row.get("value", 0))
		var kind: int = Assets.items_by_id[id].kind
		if value <= 0 or kind in [Assets.Kind.OTHER, Assets.Kind.BLOCK, Assets.Kind.ATTACHMENT, Assets.Kind.VEHICLE]:
			continue
		var tags := str(row.get("tags", ""))
		var tier := 0
		for t in 4:
			if tags.contains("T%d" % t):
				tier = t
		if tier > 1 + int(GameState.gamestage() / 15):
			continue
		pool.append(id)
	if pool.is_empty():
		return
	var n := mini(18, pool.size())
	for i in n:
		var idx := picker.randi_range(0, pool.size() - 1)
		var id := str(pool[idx])
		pool.remove_at(idx)
		var stack := maxi(1, int(Data.items.get(id, {}).get("stack", 1)))
		var count := 1
		if stack >= 20:
			count = picker.randi_range(10, mini(60, stack))
		elif stack >= 2:
			count = picker.randi_range(1, mini(5, stack))
		stock.append({"id": id, "count": count})


func buy_price(id: String) -> int:
	var value := float(Data.items.get(id, {}).get("value", 0))
	return maxi(1, int(round(value * Progression.buy_mult())))


func sell_price(id: String) -> int:
	var value := float(Data.items.get(id, {}).get("value", 0))
	return maxi(1, int(floor(value * float(data.get("sell_markdown", 0.2)) * Progression.sell_mult())))


func stock_count(id: String) -> int:
	for e in stock:
		if str(e.id) == id:
			return int(e.count)
	return 0


func buy(id: String, n: int) -> Dictionary:
	if not open or not is_near(player_sys.player.position, TALK_RADIUS):
		return {"ok": false, "text": "离商人太远了"}
	var entry: Dictionary = {}
	for e in stock:
		if str(e.id) == id:
			entry = e
			break
	if entry.is_empty() or int(entry.count) < n:
		return {"ok": false, "text": "货不够了"}
	var cost := buy_price(id) * n
	if inventory.count(currency()) < cost:
		return {"ok": false, "text": "公爵币不够（要 %d）" % cost}
	inventory.remove(currency(), cost)
	var left := inventory.add(id, n)
	if left > 0 and main.looting:
		main.looting.spawn_loot(player_sys.player.position, id, 0, left)
	entry.count = int(entry.count) - n
	if int(entry.count) <= 0:
		stock.erase(entry)
	return {"ok": true, "text": "买了 %s ×%d（%d 公爵币）" % [Assets.display_name(id), n, cost]}


func sell(id: String, n: int) -> Dictionary:
	if not open or not is_near(player_sys.player.position, TALK_RADIUS):
		return {"ok": false, "text": "离商人太远了"}
	if inventory.count(id) < n:
		return {"ok": false, "text": "数量不够"}
	var got := sell_price(id) * n
	inventory.remove(id, n)
	inventory.add(currency(), got)
	return {"ok": true, "text": "卖了 %s ×%d（得到 %d 公爵币）" % [Assets.display_name(id), n, got]}


func save_data() -> Dictionary:
	var list := []
	for e in stock:
		list.append({"id": e.id, "count": int(e.count)})
	return {"trader_stock": list, "trader_next_day": next_day}


func load_data(d: Dictionary) -> void:
	stock.clear()
	for e in d.get("trader_stock", []):
		if e is Dictionary and Assets.items_by_id.has(str(e.get("id", ""))):
			stock.append({"id": str(e.id), "count": maxi(1, int(e.get("count", 1)))})
	next_day = maxi(GameState.day, int(d.get("trader_next_day", GameState.day + 3)))
	open = is_open_hours()
	if stock.is_empty():
		_restock()
