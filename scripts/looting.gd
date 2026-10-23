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


func reset() -> void:
	for l in loot_root.get_children():
		l.queue_free()
	_search = {}
	_search_t = 0.0
	_search_from = Vector3.ZERO
	hud.set_progress(-1.0)


func update(delta: float) -> void:
	if not running:
		return
	if Input.is_physical_key_pressed(KEY_E) and not _e_down:
		action()
	_e_down = Input.is_physical_key_pressed(KEY_E)


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
	glow.distance_fade_begin = 25.0
	glow.distance_fade_length = 5.0
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
	var c := world.nearest_container(player_sys.player.position)
	if c.is_empty():
		hud.set_action("")
	elif c.searched:
		hud.set_action("%s\n已翻过" % c.name, false)
	else:
		hud.set_action("搜索\n%s" % c.name)


func action() -> void:
	if not running or not _search.is_empty():
		return
	var loot := nearest_loot()
	if loot:
		inventory.pickup(loot.get_meta("item"), int(loot.get_meta("quality", 0)), int(loot.get_meta("amount", 0)))
		loot.queue_free()
		return
	var c := world.nearest_container(player_sys.player.position)
	if c.is_empty() or c.searched:
		return
	_search = c
	_search_t = 0.0
	Sfx.play("search", c.pos + Vector3.UP * 0.8)
	_search_from = player_sys.player.position


func _finish_search(c: Dictionary) -> void:
	_search = {}
	hud.set_progress(-1.0)
	c.searched = true
	if rng.randf() < C.SEARCH_EMPTY_CHANCE:
		hud.toast("%s里什么也没有" % c.name)
		return
	var n := rng.randi_range(C.SEARCH_MIN, C.SEARCH_MAX)
	var names := []
	for i in n:
		var id := Assets.random_loot(rng, c.loot)
		if id == "":
			continue
		var quality := 0
		if Assets.items_by_id[id].kind in [Assets.Kind.GUN, Assets.Kind.MELEE]:
			quality = Weapons.roll_quality(GameState.gamestage(), rng)
		# 掉在容器和玩家之间的地上
		var dir: Vector3 = player_sys.player.position - c.pos
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
		var p: Vector3 = c.pos + dir * (c.r + 0.5) + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
		spawn_loot(world.push_out(p, 0.2), id, quality)
		names.append(Assets.display_name(id) + (" Q%d" % quality if quality > 1 else ""))
	hud.toast("翻到：" + "、".join(names) if not names.is_empty() else "%s里什么也没有" % c.name)
