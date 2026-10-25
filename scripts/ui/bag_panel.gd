class_name BagPanel
extends PanelContainer
## 背包面板：45 格网格。格子里图标、右下角数量、左上角品质色条；点一下弹出「使用/装备」「丢弃」。

signal use_pressed(id: String)
signal drop_pressed(index: int)
signal compact_pressed

## 品质 1–6：灰 棕 黄 绿 蓝 紫
const QUALITY_COLORS := [Color(0.62, 0.62, 0.62), Color(0.6, 0.4, 0.22), Color(0.92, 0.8, 0.2),
	Color(0.35, 0.75, 0.3), Color(0.3, 0.55, 0.95), Color(0.65, 0.35, 0.9)]
const SLOT_SIZE := 96.0

var _title := Label.new()
var _tabs := HBoxContainer.new()
var _empty := Label.new()
var _grid := GridContainer.new()
var _menu := PanelContainer.new()
var _menu_label := Label.new()
var _use_btn := Button.new()
var _drop_btn := Button.new()
var _sel := -1
const TAP_SLOP := 24.0
var _slots: Array = []
var _equipped := ""
var _cap := 45
var _used := 0
var _filter := "all"
const FILTERS := [["all", "全部"], ["weapon", "武器"], ["food", "食物"],
	["medical", "药品"], ["material", "材料"], ["block", "方块"], ["attachment", "附件"]]


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 80
	offset_right = -80
	offset_top = 24
	offset_bottom = -24
	visible = false
	var v := VBoxContainer.new()
	add_child(v)
	var head := HBoxContainer.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var tidy := Button.new()
	tidy.text = "整理"
	tidy.custom_minimum_size = Vector2(100, 64)
	tidy.pressed.connect(func(): compact_pressed.emit())
	head.add_child(tidy)
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(110, 64)
	close.pressed.connect(func(): visible = false)
	head.add_child(close)
	v.add_child(head)
	var tab_scroll := ScrollContainer.new()
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.custom_minimum_size.y = 56
	_tabs.add_theme_constant_override("separation", 6)
	for pair in FILTERS:
		var b := Button.new()
		b.text = pair[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(96, 52)
		b.set_meta("filter", pair[0])
		var key: String = pair[0]
		b.pressed.connect(func(): _set_filter(key))
		_tabs.add_child(b)
	tab_scroll.add_child(_tabs)
	v.add_child(tab_scroll)
	var hint := Label.new()
	hint.text = "点物品使用/装备或丢弃 · 分类标签筛选"
	hint.add_theme_font_size_override("font_size", 18)
	hint.modulate = Color(1, 1, 1, 0.6)
	v.add_child(hint)
	_empty.text = "这个分类没有东西"
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_theme_font_size_override("font_size", 22)
	_empty.modulate = Color(1, 1, 1, 0.6)
	_empty.visible = false
	v.add_child(_empty)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid.columns = 9
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)
	v.add_child(scroll)
	# 点格子弹出的操作菜单
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 10)
	_menu_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(_menu_label)
	for b in [_use_btn, _drop_btn]:
		b.custom_minimum_size = Vector2(240, 72)
		mv.add_child(b)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(240, 64)
	cancel.pressed.connect(func(): _menu.visible = false)
	mv.add_child(cancel)
	_drop_btn.text = "丢弃"
	_use_btn.pressed.connect(func():
		_menu.visible = false
		if _sel >= 0 and _sel < _slots.size() and not _slots[_sel].is_empty():
			use_pressed.emit(_slots[_sel].id))
	_drop_btn.pressed.connect(func():
		_menu.visible = false
		if _sel >= 0:
			drop_pressed.emit(_sel))
	_menu.add_child(mv)
	_menu.visible = false
	_menu.z_index = 5


func _ready() -> void:
	get_parent().add_child.call_deferred(_menu)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if not visible and _menu:
			_menu.visible = false
		elif visible:
			_rebuild()


## slots: 背包格子；cap: 不超重的格数。面板关着时只记下来，打开时再画
func set_slots(slots: Array, cap: int, used: int, equipped: String) -> void:
	_slots = slots
	_cap = cap
	_used = used
	_equipped = equipped
	if visible:
		_rebuild()


func _rebuild() -> void:
	var names := {"all": "全部", "weapon": "武器", "food": "食物",
		"medical": "药品", "material": "材料", "block": "方块", "attachment": "附件"}
	_title.text = "背包 %d / %d 格" % [_used, _cap] + ("   超重：走得慢，不能冲刺" if _used > _cap else "")
	if _filter != "all":
		_title.text += " · " + str(names.get(_filter, ""))
	_title.add_theme_color_override("font_color", Color(1, 0.45, 0.35) if _used > _cap else Color(0.95, 0.92, 0.85))
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var indices: Array[int] = []
	for i in _slots.size():
		var s: Dictionary = _slots[i]
		if _filter == "all" or (not s.is_empty() and _matches(str(s.id), _filter)):
			indices.append(i)
	_empty.visible = _filter != "all" and indices.is_empty()
	for i in indices:
		var b := make_slot(_slots[i], SLOT_SIZE, _equipped != "" and _slots[i].get("id", "") == _equipped, i >= _cap)
		var idx := i
		# 背包能上下滑着找：手指按下后挪动超过 TAP_SLOP 算滑动，不打开菜单
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.button_mask = 0
		b.gui_input.connect(func(ev: InputEvent): _slot_input(b, idx, ev))
		_grid.add_child(b)
	for b in _tabs.get_children():
		b.button_pressed = b.get_meta("filter") == _filter


static func _matches(id: String, filter: String) -> bool:
	var kind: int = int(Assets.items_by_id.get(id, {}).get("kind", -1))
	match filter:
		"weapon":
			return kind in [Assets.Kind.GUN, Assets.Kind.MELEE]
		"food":
			return kind in [Assets.Kind.FOOD, Assets.Kind.DRINK]
		"medical":
			return kind == Assets.Kind.MEDICAL
		"material":
			return kind == Assets.Kind.RESOURCE
		"block":
			return kind == Assets.Kind.BLOCK
		"attachment":
			return kind == Assets.Kind.ATTACHMENT
		_:
			return true


func _set_filter(key: String) -> void:
	_filter = key
	_rebuild()


func _slot_input(b: Button, i: int, ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton) or ev.button_index != MOUSE_BUTTON_LEFT:
		return
	if ev.pressed:
		b.set_meta("down_at", ev.global_position)
	elif b.has_meta("down_at"):
		var from: Vector2 = b.get_meta("down_at")
		b.remove_meta("down_at")
		if ev.global_position.distance_to(from) <= TAP_SLOP and b.get_global_rect().has_point(ev.global_position):
			_open_menu(i)


func _open_menu(i: int) -> void:
	if i >= _slots.size() or _slots[i].is_empty():
		return
	_sel = i
	var s: Dictionary = _slots[i]
	var row: Dictionary = Assets.items_by_id.get(s.id, {})
	var kind: int = row.get("kind", -1)
	_menu_label.text = Assets.display_name(s.id) + (" ×%d" % s.count if s.count > 1 else "") + \
		("  Q%d" % s.quality if int(s.quality) > 0 else "")
	if kind in [Assets.Kind.GUN, Assets.Kind.MELEE, Assets.Kind.BLOCK]:
		_use_btn.text = "卸下" if s.id == _equipped else "装备"
	elif kind in [Assets.Kind.FOOD, Assets.Kind.DRINK, Assets.Kind.MEDICAL]:
		_use_btn.text = "使用"
	elif kind == Assets.Kind.ATTACHMENT:
		_use_btn.text = "装到当前枪"
	elif Weapons.is_ammo(s.id):
		_use_btn.text = "装进枪里"
	else:
		_use_btn.text = "查看"
	_menu.visible = true
	_menu.reset_size()
	var parent_size: Vector2 = (_menu.get_parent() as Control).size if _menu.get_parent() is Control else size
	_menu.position = (parent_size - _menu.size) * 0.5


## 一个格子按钮：图标、右下角数量、左上角品质色条。overflow = 超重格（红边）
static func make_slot(s: Dictionary, size: float, equipped := false, overflow := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.3, 0.22, 0.08, 0.85) if equipped else Color(0.12, 0.11, 0.1, 0.72)
	sb.border_color = Color(1, 0.8, 0.3) if equipped else (Color(0.9, 0.3, 0.25, 0.8) if overflow else Color(0.8, 0.75, 0.6, 0.3))
	sb.set_border_width_all(3 if equipped or overflow else 2)
	sb.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", sb)
	if s.is_empty():
		return b
	b.icon = Assets.icon(s.id)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.set_meta("item", s.id)
	if int(s.count) > 1:
		var n := Label.new()
		n.text = str(s.count)
		n.add_theme_font_size_override("font_size", 18)
		n.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		n.position = Vector2(size - 60, size - 28)
		n.size = Vector2(54, 24)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(n)
	var q := int(s.get("quality", 0))
	if q > 0:
		var bar := ColorRect.new()
		bar.color = QUALITY_COLORS[clampi(q, 1, 6) - 1]
		bar.position = Vector2(5, 5)
		bar.size = Vector2(size * 0.4, 6)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bar)
	return b
