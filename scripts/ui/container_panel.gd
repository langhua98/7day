class_name ContainerPanel
extends PanelContainer
## 容器面板：上半是容器格子，下半是背包。点一下在两边之间转移，「全部拿走」，离开 2 米由 looting 关掉。

signal closed

var inventory: InventorySystem
## 正在看的容器的格子（直接改这个数组，存档跟着容器走）
var items: Array = []
var _title := Label.new()
var _hint := Label.new()
var _top_label := Label.new()
var _top := GridContainer.new()
var _bottom := GridContainer.new()
var _bag_label := Label.new()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 80
	offset_right = -80
	offset_top = 24
	offset_bottom = -24
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var all := Button.new()
	all.text = "全部拿走"
	all.custom_minimum_size = Vector2(150, 64)
	all.pressed.connect(take_all)
	head.add_child(all)
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(110, 64)
	close.pressed.connect(close_panel)
	head.add_child(close)
	v.add_child(head)
	_hint.text = "点容器物品拿到背包，点背包物品放进容器"
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.modulate = Color(1, 1, 1, 0.6)
	v.add_child(_hint)
	_top_label.text = "容器"
	_top_label.add_theme_font_size_override("font_size", 24)
	_top_label.modulate = Color(1, 0.9, 0.72)
	v.add_child(_top_label)
	for pair in [[_top, 0.42], [_bottom, 0.58]]:
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.size_flags_stretch_ratio = pair[1]
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var g: GridContainer = pair[0]
		g.columns = 9
		g.add_theme_constant_override("h_separation", 6)
		g.add_theme_constant_override("v_separation", 6)
		scroll.add_child(g)
		if g == _bottom:
			v.add_child(_bag_label)
		v.add_child(scroll)


func open(title: String, container_items: Array, inv: InventorySystem) -> void:
	inventory = inv
	items = container_items
	_title.text = title
	visible = true
	if not inventory.changed.is_connected(_rebuild):
		inventory.changed.connect(_rebuild)
	_rebuild()


func close_panel() -> void:
	if not visible:
		return
	visible = false
	if inventory and inventory.changed.is_connected(_rebuild):
		inventory.changed.disconnect(_rebuild)
	closed.emit()


## 容器第 i 格 → 背包（放不下的留在容器里）
func take(i: int) -> void:
	if i < 0 or i >= items.size() or items[i].is_empty():
		return
	var s: Dictionary = items[i]
	var left := inventory.add(s)
	if left > 0:
		s.count = left
		inventory.hud.toast("背包满了")
	else:
		items[i] = {}
	Sfx.play("loot", Vector3.INF, -10.0)
	inventory.refresh()
	_rebuild()


## 背包第 i 格 → 容器
func put(i: int) -> void:
	var free := -1
	for k in items.size():
		if items[k].is_empty():
			free = k
			break
	if free < 0:
		inventory.hud.toast("箱子满了")
		return
	var s := inventory.take_slot(i)
	if s.is_empty():
		return
	items[free] = s
	inventory.refresh()
	_rebuild()


func take_all() -> void:
	for i in items.size():
		if not items[i].is_empty():
			take(i)
			if not items[i].is_empty():
				break


func _rebuild() -> void:
	if not visible:
		return
	_top_label.text = "容器 · %d 格" % items.size()
	for g in [_top, _bottom]:
		for c in g.get_children():
			g.remove_child(c)
			c.queue_free()
	for i in items.size():
		var b := BagPanel.make_slot(items[i], BagPanel.SLOT_SIZE)
		var idx := i
		b.pressed.connect(func(): take(idx))
		_top.add_child(b)
	var bag := inventory.slots()
	var cap: int = inventory.base_slots()
	_bag_label.text = "背包 %d / %d 格（点一下放进去）" % [inventory.used_slots(), cap]
	for i in bag.size():
		var b := BagPanel.make_slot(bag[i], BagPanel.SLOT_SIZE, false, i >= cap)
		var idx := i
		b.pressed.connect(func(): put(idx))
		_bottom.add_child(b)

