class_name Hud
extends CanvasLayer
## 界面 + 触屏操作：左半屏摇杆移动，右半屏拖动转视角，右下角攻击键，底部快捷栏。

signal start_pressed
signal restart_pressed
signal item_used(id: String)
signal action_pressed
signal reload_pressed
signal jump_pressed

var move := Vector2.ZERO          # 摇杆输出，x 右 y 前
var look_delta := Vector2.ZERO    # 本帧视角拖动量（像素）
var attack_held := false

var _root := Control.new()
var _status := Label.new()
var _hp_bar := ProgressBar.new()
var _food_bar := ProgressBar.new()
var _stamina_bar := ProgressBar.new()
var _reload_btn := Button.new()
var _jump_btn := Button.new()
var _ammo := Label.new()
var _kills := Label.new()
var _toast := Label.new()
var _banner := Label.new()
var _hotbar := HBoxContainer.new()
var _attack_btn := Button.new()
var _action_btn := Button.new()
var _progress := ProgressBar.new()
var _progress_label := Label.new()
var _bag_btn := Button.new()
var _bag_panel := PanelContainer.new()
var _bag_grid := GridContainer.new()
var _start_panel := PanelContainer.new()
var _start_info := Label.new()
var _end_panel := PanelContainer.new()
var _end_label := Label.new()
var _joy_base := Panel.new()
var _joy_knob := Panel.new()
var _hurt := ColorRect.new()

var _joy_id := -1
var _attack_id := -1
var _joy_origin := Vector2.ZERO
var _look_id := -1
var _look_last := Vector2.ZERO
var _toast_t := 0.0
const JOY_RADIUS := 90.0


func _ready() -> void:
	layer = 10
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)

	_hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt.color = Color(0.6, 0, 0, 0)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hurt)

	# 左上：天数、时间、血量、饱食度
	var tl := VBoxContainer.new()
	tl.position = Vector2(28, 18)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tl)
	_status.add_theme_font_size_override("font_size", 30)
	tl.add_child(_status)
	for pair in [[_hp_bar, Color(0.75, 0.12, 0.1)], [_food_bar, Color(0.8, 0.6, 0.15)], [_stamina_bar, Color(0.3, 0.7, 0.45)]]:
		var bar: ProgressBar = pair[0]
		bar.custom_minimum_size = Vector2(260, 16 if bar != _stamina_bar else 8)
		bar.show_percentage = false
		bar.max_value = 100
		var fill := StyleBoxFlat.new()
		fill.bg_color = pair[1]
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.45)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", bg)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tl.add_child(bar)

	_kills.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_kills.position = Vector2(-260, 18)
	_kills.size = Vector2(230, 40)
	_kills.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_kills)

	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-400, 90)
	_banner.size = Vector2(800, 60)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 40)
	_banner.add_theme_color_override("font_color", Color(1, 0.25, 0.2))
	_root.add_child(_banner)

	_toast.set_anchors_preset(Control.PRESET_CENTER)
	_toast.position = Vector2(-400, 60)
	_toast.size = Vector2(800, 40)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast)

	# 准星
	var cross := Label.new()
	cross.text = "+"
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-10, -22)
	cross.add_theme_font_size_override("font_size", 32)
	cross.modulate = Color(1, 1, 1, 0.6)
	_root.add_child(cross)

	# 底部快捷栏
	_hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar.position = Vector2(-330, -104)
	_hotbar.add_theme_constant_override("separation", 8)
	_root.add_child(_hotbar)

	_attack_btn.text = "攻击"
	_attack_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_attack_btn.position = Vector2(-210, -230)
	_attack_btn.size = Vector2(170, 170)
	_attack_btn.add_theme_font_size_override("font_size", 36)
	# 攻击、背包、快捷栏都在 _input 里按触点自己处理：
	# 系统自带的按钮只认第一根手指，一边走路一边按攻击会没反应
	_attack_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_attack_btn)

	# 搜索 / 拾取：走近容器或地上的东西才出现
	_action_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_action_btn.position = Vector2(-420, -280)
	_action_btn.size = Vector2(190, 110)
	_action_btn.add_theme_font_size_override("font_size", 26)
	_action_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_btn.clip_text = true
	_action_btn.visible = false
	_root.add_child(_action_btn)

	# 换弹、跳：按钮也在 _input 里按触点处理
	for pair in [[_reload_btn, "换弹", Vector2(-420, -400), Vector2(160, 100)], [_jump_btn, "跳", Vector2(-190, -380), Vector2(130, 110)]]:
		var b: Button = pair[0]
		b.text = pair[1]
		b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		b.position = pair[2]
		b.size = pair[3]
		b.add_theme_font_size_override("font_size", 28)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(b)
	_reload_btn.visible = false
	# 子弹数：弹匣里 / 背包里
	_ammo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo.position = Vector2(-230, -280)
	_ammo.size = Vector2(210, 44)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ammo.add_theme_font_size_override("font_size", 30)
	_ammo.visible = false
	_root.add_child(_ammo)

	# 翻找进度条（屏幕中间偏下）
	_progress.set_anchors_preset(Control.PRESET_CENTER)
	_progress.position = Vector2(-180, 70)
	_progress.size = Vector2(360, 22)
	_progress.show_percentage = false
	_progress.max_value = 1.0
	_progress.step = 0.0
	var pf := StyleBoxFlat.new()
	pf.bg_color = Color(0.85, 0.7, 0.3)
	var pb := StyleBoxFlat.new()
	pb.bg_color = Color(0, 0, 0, 0.55)
	_progress.add_theme_stylebox_override("fill", pf)
	_progress.add_theme_stylebox_override("background", pb)
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.visible = false
	_root.add_child(_progress)
	_progress_label.set_anchors_preset(Control.PRESET_CENTER)
	_progress_label.position = Vector2(-180, 30)
	_progress_label.size = Vector2(360, 36)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.visible = false
	_root.add_child(_progress_label)

	_bag_btn.text = "背包"
	_bag_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_bag_btn.position = Vector2(-160, 70)
	_bag_btn.size = Vector2(130, 64)
	_bag_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bag_btn)

	# 背包
	_bag_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bag_panel.offset_left = 140
	_bag_panel.offset_right = -140
	_bag_panel.offset_top = 60
	_bag_panel.offset_bottom = -60
	_bag_panel.visible = false
	var bag_v := VBoxContainer.new()
	_bag_panel.add_child(bag_v)
	var bag_title := HBoxContainer.new()
	var bt := Label.new()
	bt.text = "背包（点物品使用 / 装备）"
	bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_title.add_child(bt)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func(): _bag_panel.visible = false)
	bag_title.add_child(close)
	bag_v.add_child(bag_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bag_grid.columns = 7
	_bag_grid.add_theme_constant_override("h_separation", 8)
	_bag_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_bag_grid)
	bag_v.add_child(scroll)
	_root.add_child(_bag_panel)

	# 摇杆：平时停在左下角，手指按在左半屏哪里就移到哪里
	for p in [_joy_base, _joy_knob]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.10 if p == _joy_base else 0.35)
		sb.border_color = Color(1, 1, 1, 0.35)
		sb.set_border_width_all(3 if p == _joy_base else 0)
		sb.set_corner_radius_all(200)
		p.add_theme_stylebox_override("panel", sb)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(p)
	_joy_base.size = Vector2(JOY_RADIUS * 2, JOY_RADIUS * 2)
	_joy_knob.size = Vector2(76, 76)
	_reset_joystick()

	_build_start_panel()
	_build_end_panel()


func _make_theme() -> Theme:
	var t := Theme.new()
	var f := SystemFont.new()
	# iPhone 上是苹方；电脑上调试时依次回退
	f.font_names = PackedStringArray(["PingFang SC", "Hiragino Sans GB", "Heiti SC", "Noto Sans CJK SC", "Microsoft YaHei", "sans-serif"])
	t.default_font = f
	t.default_font_size = 24
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.06, 0.05, 0.92)
	panel.set_corner_radius_all(14)
	panel.set_content_margin_all(24)
	t.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.11, 0.1, 0.72) if state != "pressed" else Color(0.45, 0.1, 0.08, 0.85)
		sb.border_color = Color(0.8, 0.75, 0.6, 0.35)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(12)
		sb.set_content_margin_all(8)
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_color", "Label", Color(0.95, 0.92, 0.85))
	t.set_constant("outline_size", "Label", 6)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	return t


func _build_start_panel() -> void:
	_start_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 22)
	_start_panel.add_child(v)
	var title := Label.new()
	title.text = "七日杀 · 口袋版"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.85, 0.2, 0.15))
	v.add_child(title)
	var sub := Label.new()
	sub.text = "活过七天。第七天夜里是血月尸潮，撑到第八天早上 6 点就算赢。"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	_start_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_info.modulate = Color(1, 1, 1, 0.7)
	_start_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_start_info)
	var btn := Button.new()
	btn.text = "开始"
	btn.custom_minimum_size = Vector2(280, 90)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 40)
	btn.pressed.connect(func():
		_start_panel.visible = false
		start_pressed.emit())
	v.add_child(btn)
	var help := Label.new()
	help.text = "左半屏拖动移动 · 右半屏拖动看 · 按住攻击 · 走近垃圾桶、车、箱子按「搜索」· 地上的东西按「拾取」"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(1, 1, 1, 0.6)
	help.add_theme_font_size_override("font_size", 20)
	v.add_child(help)
	_root.add_child(_start_panel)


func _build_end_panel() -> void:
	_end_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_panel.visible = false
	var end_bg := StyleBoxFlat.new()
	end_bg.bg_color = Color(0.05, 0.0, 0.0, 0.6)
	_end_panel.add_theme_stylebox_override("panel", end_bg)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 26)
	_end_panel.add_child(v)
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_label.add_theme_font_size_override("font_size", 44)
	v.add_child(_end_label)
	var btn := Button.new()
	btn.text = "再来一局"
	btn.custom_minimum_size = Vector2(280, 90)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 36)
	btn.pressed.connect(func():
		_end_panel.visible = false
		restart_pressed.emit())
	v.add_child(btn)
	_root.add_child(_end_panel)


func set_start_info(text: String) -> void:
	_start_info.text = text


func show_end(text: String) -> void:
	attack_held = false
	_end_label.text = text
	_end_panel.visible = true


## 拿着枪时显示「弹匣 / 背包」子弹数和换弹键；text 为空就隐藏
func set_ammo(text: String) -> void:
	_ammo.visible = text != ""
	_ammo.text = text
	_reload_btn.visible = text != ""


func set_stamina(v: float) -> void:
	_stamina_bar.value = v


func set_status(day: int, hour: float, hp: float, food: float, kills: int, zombies: int, night: bool) -> void:
	var h := int(hour)
	var m := int((hour - h) * 60.0)
	_status.text = "第 %d 天  %02d:%02d %s" % [day, h, m, "夜" if night else ""]
	_hp_bar.value = hp
	_food_bar.value = food
	_kills.text = "击杀 %d   附近 %d" % [kills, zombies]


func set_banner(text: String) -> void:
	_banner.text = text


## 搜索 / 拾取按钮上的字；空字符串就隐藏。enabled=false 时变灰（比如容器已经翻过了）
func set_action(text: String, enabled := true) -> void:
	_action_btn.visible = text != ""
	_action_btn.text = text
	_action_btn.modulate = Color.WHITE if enabled else Color(1, 1, 1, 0.45)


## 翻找进度：value < 0 隐藏
func set_progress(value: float, text := "") -> void:
	var show := value >= 0.0
	_progress.visible = show
	_progress_label.visible = show
	if show:
		_progress.value = value
		_progress_label.text = text


func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast_t = 2.2


func hurt() -> void:
	_hurt.color.a = 0.35


## inventory: [{id, count, equipped}]
func set_inventory(list: Array, hotbar_ids: Array) -> void:
	for c in _hotbar.get_children():
		c.queue_free()
	for id in hotbar_ids:
		_hotbar.add_child(_slot(id, list))
	for c in _bag_grid.get_children():
		c.queue_free()
	for e in list:
		_bag_grid.add_child(_slot(e.id, list, true))


func _reset_joystick() -> void:
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	var home := Vector2(JOY_RADIUS + 70, vp.y - JOY_RADIUS - 70)
	_joy_base.position = home - _joy_base.size * 0.5
	_joy_knob.position = home - _joy_knob.size * 0.5
	_joy_base.modulate.a = 0.6
	_joy_knob.modulate.a = 0.6


func _slot(id: String, list: Array, with_name := false) -> Control:
	var entry: Dictionary = {}
	for e in list:
		if e.id == id:
			entry = e
	var b := Button.new()
	b.custom_minimum_size = Vector2(110, 110 if not with_name else 140)
	b.icon = Assets.icon(id)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	var count: int = entry.get("count", 0)
	var label := Assets.display_name(id) if with_name else ""
	if count > 1:
		label += ("\n" if with_name else "") + "×%d" % count
	b.text = label
	b.add_theme_font_size_override("font_size", 18)
	b.clip_text = true
	if entry.get("equipped", false):
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.3, 0.22, 0.08, 0.85)
		sb.border_color = Color(1, 0.8, 0.3)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(12)
		b.add_theme_stylebox_override("normal", sb)
	b.set_meta("item", id)
	if with_name:
		b.pressed.connect(func(): item_used.emit(id))
	else:
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 快捷栏在 _input 里处理
	return b


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t < 0.6:
			_toast.modulate.a = max(0.0, _toast_t / 0.6)
	if _hurt.color.a > 0.0:
		_hurt.color.a = max(0.0, _hurt.color.a - delta * 0.8)


func consume_look() -> Vector2:
	var d := look_delta
	look_delta = Vector2.ZERO
	return d


func _panel_open() -> bool:
	return _bag_panel.visible or _start_panel.visible or _end_panel.visible


func _press_attack(pressed: bool) -> void:
	attack_held = pressed
	_attack_btn.modulate = Color(1.6, 0.7, 0.6) if pressed else Color.WHITE


func _touch_down(index: int, pos: Vector2) -> void:
	if _attack_btn.get_global_rect().grow(20).has_point(pos):
		_attack_id = index
		_press_attack(true)
		return
	if _reload_btn.visible and _reload_btn.get_global_rect().grow(10).has_point(pos):
		reload_pressed.emit()
		return
	if _jump_btn.get_global_rect().grow(10).has_point(pos):
		jump_pressed.emit()
		return
	if _action_btn.visible and _action_btn.get_global_rect().grow(12).has_point(pos):
		action_pressed.emit()
		return
	if _bag_btn.get_global_rect().has_point(pos):
		_bag_panel.visible = true
		_press_attack(false)
		return
	for slot in _hotbar.get_children():
		if (slot as Control).get_global_rect().has_point(pos):
			item_used.emit(slot.get_meta("item"))
			return
	var half := get_viewport().get_visible_rect().size.x * 0.5
	if pos.x < half and _joy_id == -1:
		_joy_id = index
		_joy_origin = pos
		_joy_base.position = pos - _joy_base.size * 0.5
		_joy_knob.position = pos - _joy_knob.size * 0.5
		_joy_base.modulate.a = 1.0
		_joy_knob.modulate.a = 1.0
	elif pos.x >= half and _look_id == -1:
		_look_id = index
		_look_last = pos


func _touch_up(index: int) -> void:
	if index == _attack_id:
		_attack_id = -1
		_press_attack(false)
	elif index == _joy_id:
		_joy_id = -1
		move = Vector2.ZERO
		_reset_joystick()
	elif index == _look_id:
		_look_id = -1


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if not _panel_open():
				_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		if event.index == _joy_id:
			var d: Vector2 = event.position - _joy_origin
			if d.length() > JOY_RADIUS:
				d = d.normalized() * JOY_RADIUS
			_joy_knob.position = _joy_origin + d - _joy_knob.size * 0.5
			move = Vector2(d.x, -d.y) / JOY_RADIUS
		elif event.index == _look_id:
			look_delta += event.position - _look_last
			_look_last = event.position
