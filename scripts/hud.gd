class_name Hud
extends CanvasLayer
## 界面 + 触屏操作：左半屏摇杆移动（推到底再往外拖是冲刺），右半屏拖动转视角，
## 右下角攻击、跳、换弹、搜索/拾取，底部快捷栏，顶上指南针，右上角背包和暂停。

signal start_pressed
signal restart_pressed
signal item_used(id: String)
signal action_pressed
signal reload_pressed
signal settings_changed

var move := Vector2.ZERO          # 摇杆输出，x 右 y 前
var look_delta := Vector2.ZERO    # 本帧视角拖动量（像素）
var attack_held := false
var sprint := false
## 设置（存在 user://settings.cfg）
var settings := {"look": 1.0, "music": 0.8, "sfx": 1.0}

var _root := Control.new()
var _status := Label.new()
var _effects := Label.new()
var _bars := {}
var _kills := Label.new()
var _toast := Label.new()
var _banner := Label.new()
var _hotbar := HBoxContainer.new()
var _attack_btn := Button.new()
var _jump_btn := Button.new()
var _reload_btn := Button.new()
var _ammo := Label.new()
var _action_btn := Button.new()
var _progress := ProgressBar.new()
var _progress_label := Label.new()
var _bag_btn := Button.new()
var _pause_btn := Button.new()
var _bag_panel := PanelContainer.new()
var _bag_grid := GridContainer.new()
var _start_panel := PanelContainer.new()
var _start_info := Label.new()
var _end_panel := PanelContainer.new()
var _end_label := Label.new()
var _pause_panel := PanelContainer.new()
var _joy_base := Panel.new()
var _joy_knob := Panel.new()
var _joy_label := Label.new()
var _hurt := ColorRect.new()
var _vignette := TextureRect.new()
var _cross := Crosshair.new()
var _compass := Compass.new()

var _joy_id := -1
var _attack_id := -1
var _joy_origin := Vector2.ZERO
var _look_id := -1
var _look_last := Vector2.ZERO
var _toast_t := 0.0
var _jump_queued := false
const JOY_RADIUS := 90.0
const SETTINGS_PATH := "user://settings.cfg"


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS   # 暂停时界面照常响应
	_load_settings()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)

	# 血少的时候屏幕四周发红
	var g := Gradient.new()
	g.set_color(0, Color(0.5, 0, 0, 0))
	g.set_color(1, Color(0.55, 0, 0, 0.9))
	g.set_offset(0, 0.55)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	_vignette.texture = gt
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	_root.add_child(_vignette)

	_hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt.color = Color(0.6, 0, 0, 0)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hurt)

	# 左上：天数、时间、血量、饱食、口渴、体力、状态
	var tl := VBoxContainer.new()
	tl.position = Vector2(28, 14)
	tl.add_theme_constant_override("separation", 4)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tl)
	_status.add_theme_font_size_override("font_size", 28)
	tl.add_child(_status)
	for spec in [["hp", "血", Color(0.78, 0.12, 0.1), 16], ["food", "饱", Color(0.82, 0.6, 0.15), 12],
			["water", "水", Color(0.25, 0.55, 0.9), 12], ["stamina", "力", Color(0.55, 0.85, 0.4), 8]]:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Label.new()
		l.text = spec[1]
		l.custom_minimum_size = Vector2(26, 0)
		l.add_theme_font_size_override("font_size", 18)
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(240, spec[3])
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = 100
		var fill := StyleBoxFlat.new()
		fill.bg_color = spec[2]
		fill.set_corner_radius_all(3)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.45)
		bg.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", bg)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bar)
		tl.add_child(row)
		_bars[spec[0]] = bar
	_effects.add_theme_font_size_override("font_size", 20)
	_effects.add_theme_color_override("font_color", Color(1, 0.55, 0.45))
	tl.add_child(_effects)

	_kills.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_kills.position = Vector2(-330, 18)
	_kills.size = Vector2(300, 40)
	_kills.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_kills)

	_compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_compass.position = Vector2(-230, 12)
	_compass.size = Vector2(460, 44)
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_compass)

	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-400, 90)
	_banner.size = Vector2(800, 60)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 40)
	_banner.add_theme_color_override("font_color", Color(1, 0.25, 0.2))
	_root.add_child(_banner)

	_toast.set_anchors_preset(Control.PRESET_CENTER)
	_toast.position = Vector2(-450, 110)
	_toast.size = Vector2(900, 40)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast)

	# 准星（会随散布张开，打中时出现命中标记）
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.position = Vector2(-120, -120)
	_cross.size = Vector2(240, 240)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_cross)

	# 底部快捷栏
	_hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar.position = Vector2(-300, -104)
	_hotbar.add_theme_constant_override("separation", 8)
	_root.add_child(_hotbar)

	# 攻击、跳、换弹、搜索、背包、快捷栏都在 _input 里按触点自己处理：
	# 系统自带的按钮只认第一根手指，一边走路一边按攻击会没反应
	_add_button(_attack_btn, "攻击", Vector2(-210, -230), Vector2(170, 170), 36)
	_add_button(_jump_btn, "跳", Vector2(-160, -420), Vector2(120, 120), 30)
	_add_button(_reload_btn, "换弹", Vector2(-400, -410), Vector2(130, 90), 26)
	_reload_btn.visible = false
	_ammo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo.position = Vector2(-230, -282)
	_ammo.size = Vector2(210, 44)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ammo.add_theme_font_size_override("font_size", 28)
	_root.add_child(_ammo)
	# 搜索 / 拾取：走近容器或地上的东西才出现
	_add_button(_action_btn, "", Vector2(-430, -290), Vector2(190, 110), 26)
	_action_btn.clip_text = true
	_action_btn.visible = false

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

	_add_button(_bag_btn, "背包", Vector2(-300, 66), Vector2(130, 64), 24, Control.PRESET_TOP_RIGHT)
	_add_button(_pause_btn, "暂停", Vector2(-156, 66), Vector2(126, 64), 24, Control.PRESET_TOP_RIGHT)

	_build_bag_panel()

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
	_joy_label.text = "冲刺"
	_joy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_joy_label.size = Vector2(JOY_RADIUS * 2, 30)
	_joy_label.position = Vector2(0, -34)
	_joy_label.add_theme_color_override("font_color", Color(1, 0.75, 0.3))
	_joy_label.visible = false
	_joy_base.add_child(_joy_label)
	_reset_joystick()

	_build_pause_panel()
	_build_start_panel()
	_build_end_panel()
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


func _add_button(b: Button, text: String, pos: Vector2, size: Vector2, font: int, preset := Control.PRESET_BOTTOM_RIGHT) -> void:
	b.text = text
	b.set_anchors_preset(preset)
	b.offset_left = pos.x
	b.offset_top = pos.y
	b.offset_right = pos.x + size.x
	b.offset_bottom = pos.y + size.y
	b.add_theme_font_size_override("font_size", font)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(b)


## iPhone 横屏时刘海和底部横条那里不放按钮
func _apply_safe_area() -> void:
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	var vp := get_viewport().get_visible_rect().size
	if win.x <= 0 or safe.size.x <= 0 or OS.get_name() not in ["iOS", "Android"]:
		return
	var k := vp.x / float(win.x)
	_root.offset_left = max(0.0, safe.position.x * k - 6.0)
	_root.offset_right = -max(0.0, (win.x - safe.end.x) * k - 6.0)
	_root.offset_bottom = -max(0.0, (win.y - safe.end.y) * k * 0.5)
	_reset_joystick()


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


func _build_bag_panel() -> void:
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
	close.custom_minimum_size = Vector2(120, 60)
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


func _build_pause_panel() -> void:
	_pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	_pause_panel.position = Vector2(-330, -280)
	_pause_panel.size = Vector2(660, 560)
	_pause_panel.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	_pause_panel.add_child(v)
	var title := Label.new()
	title.text = "暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	v.add_child(title)
	for spec in [["look", "视角灵敏度", 0.3, 2.5], ["music", "音乐音量", 0.0, 1.0], ["sfx", "音效音量", 0.0, 1.0]]:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = spec[1]
		l.custom_minimum_size = Vector2(170, 0)
		row.add_child(l)
		var s := HSlider.new()
		s.min_value = spec[2]
		s.max_value = spec[3]
		s.step = 0.05
		s.value = settings[spec[0]]
		s.custom_minimum_size = Vector2(380, 50)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var key: String = spec[0]
		s.value_changed.connect(func(val):
			settings[key] = val
			_save_settings()
			settings_changed.emit())
		row.add_child(s)
		v.add_child(row)
	var resume := Button.new()
	resume.text = "继续"
	resume.custom_minimum_size = Vector2(0, 80)
	resume.add_theme_font_size_override("font_size", 32)
	resume.pressed.connect(func(): set_paused(false))
	v.add_child(resume)
	var restart := Button.new()
	restart.text = "重新开始"
	restart.custom_minimum_size = Vector2(0, 70)
	restart.pressed.connect(func():
		set_paused(false)
		restart_pressed.emit())
	v.add_child(restart)
	_root.add_child(_pause_panel)


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
	help.text = "左半屏拖动移动，推到底再往外拖是冲刺 · 右半屏拖动看 · 按住攻击 · 跳能跳上路障\n走近垃圾桶、车、箱子按「搜索」· 地上的东西按「拾取」· 打头伤害高 · 夜里僵尸会跑"
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
	_end_label.add_theme_font_size_override("font_size", 40)
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


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		for k in settings:
			settings[k] = cf.get_value("game", k, settings[k])


func _save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("game", k, settings[k])
	cf.save(SETTINGS_PATH)


# —— 对外接口 ——

func set_start_info(text: String) -> void:
	_start_info.text = text


func show_end(text: String) -> void:
	attack_held = false
	_end_label.text = text
	_end_panel.visible = true


## 切到后台（来电话、回桌面）自动暂停
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		if is_inside_tree() and not (_start_panel.visible or _end_panel.visible or _pause_panel.visible):
			set_paused(true)


func set_paused(on: bool) -> void:
	_pause_panel.visible = on
	get_tree().paused = on
	if on:
		_release_all()


func set_status(day: int, hour: float, kills: int, zombies: int, night: bool) -> void:
	var h := int(hour)
	var m := int((hour - h) * 60.0)
	_status.text = "第 %d 天  %02d:%02d %s" % [day, h, m, "夜" if night else ""]
	_kills.text = "击杀 %d   附近 %d" % [kills, zombies]


func set_vitals(hp: float, food: float, water: float, stamina: float, effects: String) -> void:
	_bars.hp.value = hp
	_bars.food.value = food
	_bars.water.value = water
	_bars.stamina.value = stamina
	_effects.text = effects
	_vignette.modulate.a = clamp((45.0 - hp) / 35.0, 0.0, 1.0) * (0.75 + 0.25 * sin(Time.get_ticks_msec() / 160.0))


## heading：朝向（弧度，北是 0、顺时针）；home：市中心路口的方位，NAN 表示不显示
func set_compass(heading: float, home: float) -> void:
	_compass.heading = heading
	_compass.home = home
	_compass.queue_redraw()


func set_banner(text: String) -> void:
	_banner.text = text


## 枪：显示弹匣/备弹、换弹按钮；近战：都隐藏
func set_weapon(is_gun: bool, ammo_text: String, can_reload: bool) -> void:
	_attack_btn.text = "开火" if is_gun else "攻击"
	_ammo.visible = is_gun
	_ammo.text = ammo_text
	_reload_btn.visible = is_gun and can_reload


## 准星张开多少（0~1）
func set_spread(v: float) -> void:
	_cross.spread = v
	_cross.queue_redraw()


## 命中标记：0 打中身体，1 爆头，2 打死
func hit_marker(kind: int) -> void:
	_cross.hit = 0.25
	_cross.hit_kind = kind
	_cross.queue_redraw()


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
	_toast_t = 2.4


## 受伤：屏幕闪红，准星周围显示是哪个方向打来的（rel：相对朝向的角度，NAN 表示不显示方向）
func hurt(rel := NAN) -> void:
	_hurt.color.a = 0.35
	if not is_nan(rel):
		_cross.hurt_dirs.append([rel, 1.2])
		_cross.queue_redraw()


func consume_jump() -> bool:
	var j := _jump_queued
	_jump_queued = false
	return j


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
	var vp := _root.size if _root.is_inside_tree() and _root.size.x > 0 else Vector2(1280, 720)
	var home := Vector2(JOY_RADIUS + 70, vp.y - JOY_RADIUS - 70)
	_joy_base.position = home - _joy_base.size * 0.5
	_joy_knob.position = home - _joy_knob.size * 0.5
	_joy_base.modulate.a = 0.6
	_joy_knob.modulate.a = 0.6
	_joy_label.visible = false


func _slot(id: String, list: Array, with_name := false) -> Control:
	var entry: Dictionary = {}
	for e in list:
		if e.id == id:
			entry = e
	var b := Button.new()
	b.custom_minimum_size = Vector2(110, 140) if with_name else Vector2(92, 92)
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
	if _cross.tick(delta):
		_cross.queue_redraw()


func consume_look() -> Vector2:
	var d: Vector2 = look_delta * settings.look
	look_delta = Vector2.ZERO
	return d


func _panel_open() -> bool:
	return _bag_panel.visible or _start_panel.visible or _end_panel.visible or _pause_panel.visible


func _press_attack(pressed: bool) -> void:
	attack_held = pressed
	_attack_btn.modulate = Color(1.6, 0.7, 0.6) if pressed else Color.WHITE


func _release_all() -> void:
	_attack_id = -1
	_press_attack(false)
	_joy_id = -1
	_look_id = -1
	move = Vector2.ZERO
	sprint = false
	_reset_joystick()


func _hit(c: Control, pos: Vector2, grow := 0.0) -> bool:
	return c.visible and c.get_global_rect().grow(grow).has_point(pos)


func _touch_down(index: int, pos: Vector2) -> void:
	if _hit(_attack_btn, pos, 20):
		_attack_id = index
		_press_attack(true)
		return
	if _hit(_jump_btn, pos, 10):
		_jump_queued = true
		_flash(_jump_btn)
		return
	if _hit(_reload_btn, pos, 10):
		reload_pressed.emit()
		_flash(_reload_btn)
		return
	if _hit(_action_btn, pos, 12):
		action_pressed.emit()
		return
	if _hit(_bag_btn, pos):
		_bag_panel.visible = true
		_release_all()
		return
	if _hit(_pause_btn, pos):
		set_paused(true)
		return
	for slot in _hotbar.get_children():
		if (slot as Control).get_global_rect().has_point(pos):
			item_used.emit(slot.get_meta("item"))
			return
	var half := get_viewport().get_visible_rect().size.x * 0.5
	if pos.x < half and _joy_id == -1:
		_joy_id = index
		_joy_origin = pos
		# 摇杆挂在界面根节点下，根节点因为安全区可能缩进了，换成它的坐标
		var local := pos - _root.global_position
		_joy_base.position = local - _joy_base.size * 0.5
		_joy_knob.position = local - _joy_knob.size * 0.5
		_joy_base.modulate.a = 1.0
		_joy_knob.modulate.a = 1.0
	elif pos.x >= half and _look_id == -1:
		_look_id = index
		_look_last = pos


func _flash(b: Button) -> void:
	b.modulate = Color(1.6, 1.2, 0.7)
	var tw := create_tween()
	tw.tween_property(b, "modulate", Color.WHITE, 0.2)


func _touch_up(index: int) -> void:
	if index == _attack_id:
		_attack_id = -1
		_press_attack(false)
	elif index == _joy_id:
		_joy_id = -1
		move = Vector2.ZERO
		sprint = false
		_reset_joystick()
	elif index == _look_id:
		_look_id = -1


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		if event.pressed:
			if not _panel_open():
				_touch_down(event.index, pos)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		if event.index == _joy_id:
			var d: Vector2 = event.position - _joy_origin
			# 往前推到底再往外拖 → 冲刺
			sprint = d.length() > JOY_RADIUS * 1.3 and d.y < -JOY_RADIUS * 0.8
			_joy_label.visible = sprint
			_joy_knob.modulate = Color(1.0, 0.75, 0.35) if sprint else Color.WHITE
			if d.length() > JOY_RADIUS:
				d = d.normalized() * JOY_RADIUS
			_joy_knob.position = _joy_origin - _root.global_position + d - _joy_knob.size * 0.5
			move = Vector2(d.x, -d.y) / JOY_RADIUS
		elif event.index == _look_id:
			look_delta += event.position - _look_last
			_look_last = event.position


# —— 准星：四条短线，散布大时张开；命中时出现斜叉；受伤方向的红色弧 ——

class Crosshair extends Control:
	var spread := 0.0
	var hit := 0.0
	var hit_kind := 0
	var hurt_dirs := []   # [[相对角度, 剩余时间]]

	func tick(delta: float) -> bool:
		var dirty := false
		if hit > 0.0:
			hit = max(0.0, hit - delta)
			dirty = true
		for h in hurt_dirs:
			h[1] -= delta
			dirty = true
		hurt_dirs = hurt_dirs.filter(func(h): return h[1] > 0.0)
		return dirty

	func _draw() -> void:
		var c := size * 0.5
		var gap := 7.0 + spread * 26.0
		var col := Color(1, 1, 1, 0.75)
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + d * gap, c + d * (gap + 10.0), Color(0, 0, 0, 0.5), 4.0)
			draw_line(c + d * gap, c + d * (gap + 10.0), col, 2.0)
		if hit > 0.0:
			var hc: Color = [Color(1, 1, 1), Color(1, 0.3, 0.2), Color(1, 0.15, 0.1)][hit_kind]
			hc.a = clamp(hit / 0.15, 0.0, 1.0)
			var r := 12.0 + (6.0 if hit_kind > 0 else 0.0)
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(c + d.normalized() * 6.0, c + d.normalized() * r, hc, 3.0 if hit_kind == 2 else 2.0)
		for h in hurt_dirs:
			var a: float = h[0] - PI / 2.0   # 0 = 正前方 = 屏幕上方
			var alpha: float = clamp(h[1], 0.0, 1.0)
			draw_arc(c, 100.0, a - 0.35, a + 0.35, 16, Color(1, 0.1, 0.05, 0.8 * alpha), 8.0)


# —— 指南针：顶上的方位条，黄色三角是市中心路口 ——

class Compass extends Control:
	var heading := 0.0
	var home := NAN
	const SPAN := 1.6   # 显示多少弧度
	const NAMES := {0: "北", 45: "东北", 90: "东", 135: "东南", 180: "南", 225: "西南", 270: "西", 315: "西北"}

	func _draw() -> void:
		var w := size.x
		var c := w * 0.5
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.3))
		var font := get_theme_default_font()
		for deg in range(0, 360, 15):
			var rel := wrapf(deg_to_rad(deg) - heading, -PI, PI)
			if absf(rel) > SPAN * 0.5:
				continue
			var x := c + rel / SPAN * w
			if NAMES.has(deg):
				var t: String = NAMES[deg]
				var fs := 22 if deg % 90 == 0 else 16
				var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(font, Vector2(x - tw * 0.5, 30), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					Color(1, 0.4, 0.3) if deg == 0 else Color(1, 1, 1, 0.9))
			else:
				draw_line(Vector2(x, 30), Vector2(x, 40), Color(1, 1, 1, 0.5), 2.0)
		if not is_nan(home):
			var rel := wrapf(home - heading, -PI, PI)
			var x: float = c + clamp(rel / SPAN, -0.5, 0.5) * w
			draw_colored_polygon(PackedVector2Array([Vector2(x - 7, 44), Vector2(x + 7, 44), Vector2(x, 34)]), Color(1, 0.8, 0.2))
		draw_line(Vector2(c, 0), Vector2(c, 8), Color(1, 1, 1), 2.0)
