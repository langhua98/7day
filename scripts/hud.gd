class_name Hud
extends CanvasLayer
## 界面 + 触屏操作（只做 iPhone）：按键布局照吃鸡手游，左半屏摇杆移动，右半屏拖动转视角。

signal start_pressed
signal restart_pressed
signal item_used(id: String)
signal action_pressed
signal reload_pressed
signal jump_pressed
## 6a：蹲伏切换
signal crouch_pressed
signal rotate_pressed
signal scope_pressed
signal continue_pressed
signal settings_changed(settings: Dictionary)
signal quit_to_title
signal back_to_title
signal item_dropped(index: int)
signal bag_compact_pressed

var move := Vector2.ZERO          # 摇杆输出，x 右 y 前
var look_delta := Vector2.ZERO    # 本帧视角拖动量（像素）
var attack_held := false
var aim_held := false

var _root := Control.new()
var _status := Label.new()
var _blood_info := Label.new()
var _hp_bar := ProgressBar.new()
var _food_bar := ProgressBar.new()
var _stamina_bar := ProgressBar.new()
var _water_bar := ProgressBar.new()
var _effects := Label.new()
var _jump_btn := Button.new()
var _crouch_btn := Button.new()
var _rotate_btn := Button.new()
var _scope_btn := Button.new()
var _ammo_panel := PanelContainer.new()
var _ammo_mag := Label.new()
var _ammo_reserve := Label.new()
var _ammo_type := Label.new()
var _kills := Label.new()
var _toast := Label.new()
var _banner := Label.new()
var _hotbar_panel := PanelContainer.new()
var _hotbar := HBoxContainer.new()
var _hotbar_name := Label.new()
var _attack_btn := Button.new()
var _aim_btn := Button.new()
var _cross := Crosshair.new()
var _hitmarker := Label.new()
var _action_btn := Button.new()
var _action_title := Label.new()
var _action_sub := Label.new()
var _compass := Compass.new()
var _scope := ScopeOverlay.new()
var _scope_label := Label.new()
var _scope_level := 0
var _progress := ProgressBar.new()
var _progress_label := Label.new()
var _bag_btn := Button.new()
var _bag_panel := BagPanel.new()
var container_panel := ContainerPanel.new()
var _craft_btn := Button.new()
var craft_panel := CraftPanel.new()
var _start_panel := PanelContainer.new()
var _start_info := Label.new()
var _end_panel := PanelContainer.new()
var _end_label := Label.new()
var _joy_base := Panel.new()
var _joy_knob := Panel.new()
var _hurt := ColorRect.new()
var _pause_btn := Button.new()
var _pause_panel := PanelContainer.new()
var _continue_btn := Button.new()
var _perf := Label.new()
## 右上角状态图标条（饥饿、流血……），点一下显示说明
var _status_row := HBoxContainer.new()
var _status_tip := Label.new()
var _status_tip_t := 0.0
var _status_ids: Array = []
## 死亡黑屏（3c）和指向尸体背包的小箭头
var _blackout := ColorRect.new()
var _blackout_label := Label.new()
var _blackout_tween: Tween
var _bag_marker := Control.new()
var _bag_arrow := Control.new()
var _bag_marker_label := Label.new()
var _settings_panel := PanelContainer.new()
var _settings_from_start := false
var _setting_sliders := {}
var _setting_values := {}
var _quality_option: OptionButton
var _perf_toggle: CheckButton
var _start_settings_btn: Button
var _pause_settings_btn: Button
var _end_back_btn: Button
var _settings_back_btn: Button
var _settings_reset_btn: Button
## 设置：灵敏度、亮度、音量、音乐音量（倍数）、画质档位、性能面板，存在 user://settings.cfg
const DEFAULT_SETTINGS := {"sensitivity": 1.0, "brightness": 1.0, "volume": 1.0, "music": 0.8,
	"quality": 1.0, "show_perf": 0.0}
var settings := DEFAULT_SETTINGS.duplicate()
const SETTINGS_PATH := "user://settings.cfg"

var _joy_id := -1
## 按着开火键的手指
var _attack_ids := {}
var _joy_origin := Vector2.ZERO
var _look_id := -1
## 能拖动转视角的手指上一帧位置：空白处的右半屏、攻击键、瞄准键都算（边开火边转）
var _drag_last := {}
var _toast_t := 0.0
var _blood_day := false
var _aim_id := -1
var _hit_tween: Tween
## 安全区：刘海、灵动岛、底部横条让出来的边距（画布像素）。按钮都放在 _safe 里
var _safe := Control.new()
var safe_insets := Vector4.ZERO  # 左、上、右、下
const JOY_RADIUS := 90.0
const JOY_DEADZONE := 0.12
## 手指移动不超过这么多像素才算「点」，超过算滑动（背包里滑着找东西不误用物品）
const TAP_SLOP := 24.0
const QUALITY_COLORS := [Color(0.7, 0.7, 0.7), Color(0.65, 0.45, 0.25), Color(0.9, 0.8, 0.2),
	Color(0.3, 0.8, 0.3), Color(0.3, 0.55, 1.0), Color(0.7, 0.35, 1.0)]
var _status_text := ""
var _kills_text := ""
var _ammo_text := ""
var _hotbar_name_tween: Tween
var _effects_text := ""
var _banner_text := ""
var _action_text := ""
var _action_enabled := true
var _progress_text := ""
var _progress_shown := false
var _water_value := -1.0
var _stamina_value := -1.0
var _hp_value := -1.0
var _food_value := -1.0
var _hp_text := Label.new()
var _food_text := Label.new()
var _water_text := Label.new()
var _stamina_text := Label.new()


func _ready() -> void:
	layer = 10
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	add_child(_root)

	_hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt.color = Color(0.6, 0, 0, 0)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hurt)

	_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_scope)

	_safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_safe)
	_scope_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_scope_label.position = Vector2(-60, 70)
	_scope_label.size = Vector2(120, 40)
	_scope_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scope_label.add_theme_font_override("font", number_font())
	_scope_label.add_theme_font_size_override("font_size", 26)
	_scope_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	_scope_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_scope_label.add_theme_constant_override("outline_size", 6)
	_scope_label.visible = false
	_safe.add_child(_scope_label)

	# 左上：天数、时间、血量、饱食度
	var tl := VBoxContainer.new()
	tl.position = Vector2(28, 70)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(tl)
	_status.add_theme_font_size_override("font_size", 30)
	tl.add_child(_status)
	_blood_info.add_theme_font_size_override("font_size", 20)
	_blood_info.add_theme_color_override("font_color", Color(0.86, 0.78, 0.62, 0.9))
	tl.add_child(_blood_info)
	for pair in [["血", _hp_bar, Color(0.75, 0.12, 0.1), 16, _hp_text],
			["饿", _food_bar, Color(0.8, 0.6, 0.15), 14, _food_text],
			["水", _water_bar, Color(0.2, 0.5, 0.85), 14, _water_text],
			["力", _stamina_bar, Color(0.3, 0.7, 0.45), 8, _stamina_text]]:
		_add_stat_row(tl, pair[0], pair[1], pair[2], pair[3], pair[4])
	_effects.add_theme_font_size_override("font_size", 24)
	_effects.add_theme_color_override("font_color", Color(1, 0.55, 0.45))
	tl.add_child(_effects)

	_kills.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_kills.position = Vector2(-370, 70)
	_kills.size = Vector2(240, 40)
	_kills.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_safe.add_child(_kills)

	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-400, 120)
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
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.position = Vector2(-32, -32)
	_cross.size = Vector2(64, 64)
	_root.add_child(_cross)

	# 命中标记：打中僵尸在准星旁闪一下
	_hitmarker.text = "×"
	_hitmarker.set_anchors_preset(Control.PRESET_CENTER)
	_hitmarker.position = Vector2(-32, -34)
	_hitmarker.size = Vector2(64, 64)
	_hitmarker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hitmarker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hitmarker.add_theme_font_size_override("font_size", 46)
	_hitmarker.pivot_offset = Vector2(32, 32)
	_hitmarker.modulate = Color(1, 1, 1, 0)
	_hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hitmarker)

	# 性能面板：左上角血条下面，默认关闭
	_perf.position = Vector2(28, 168)
	_perf.size = Vector2(520, 190)
	_perf.add_theme_font_override("font", number_font())
	_perf.add_theme_font_size_override("font_size", 19)
	_perf.add_theme_color_override("font_color", Color(0.65, 1.0, 0.7))
	_perf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_perf.visible = false
	_root.add_child(_perf)

	# 底部快捷栏：外面包一层半透明圆角底板
	_hotbar_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hotbar_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hotbar_panel.offset_left = 0
	_hotbar_panel.offset_right = 0
	_hotbar_panel.offset_top = -118
	_hotbar_panel.offset_bottom = -34
	var hb_sb := StyleBoxFlat.new()
	hb_sb.bg_color = Color(0.02, 0.02, 0.02, 0.42)
	hb_sb.border_color = Color(1, 1, 1, 0.12)
	hb_sb.set_border_width_all(1)
	hb_sb.set_corner_radius_all(14)
	hb_sb.set_content_margin_all(4)
	_hotbar_panel.add_theme_stylebox_override("panel", hb_sb)
	_hotbar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hotbar.add_theme_constant_override("separation", 6)
	_hotbar_panel.add_child(_hotbar)
	_safe.add_child(_hotbar_panel)
	_hotbar_name.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar_name.position = Vector2(-300, -158)
	_hotbar_name.size = Vector2(600, 40)
	_hotbar_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hotbar_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hotbar_name.add_theme_font_size_override("font_size", 22)
	_hotbar_name.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	_hotbar_name.modulate.a = 0.0
	_hotbar_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(_hotbar_name)

	# 按键布局照吃鸡手游（和平精英 / PUBG Mobile）的默认布局：
	# 右边大开火键，开火键右上是跳，左上是开镜，左边是换弹；左手边摇杆上方一个小开火键；
	# 底部中间武器栏，下面血条，左边背包；右上角设置；拾取 / 搜索在屏幕右中。
	# 这些按钮都在 _input 里按触点自己处理：系统按钮只认第一根手指，边走边打会没反应。
	_round(_attack_btn, "开火", Control.PRESET_BOTTOM_RIGHT, Vector2(-300, -330), 160, 34)
	_round(_jump_btn, "跳", Control.PRESET_BOTTOM_RIGHT, Vector2(-130, -400), 110, 28)
	# 6a：蹲（吃鸡布局里在跳下面、开火键右下）
	_round(_crouch_btn, "蹲", Control.PRESET_BOTTOM_RIGHT, Vector2(-130, -250), 110, 28)
	_round(_aim_btn, "开镜", Control.PRESET_BOTTOM_RIGHT, Vector2(-440, -440), 110, 26)
	_round(_rotate_btn, "旋转\n0°", Control.PRESET_BOTTOM_RIGHT, Vector2(-440, -270), 100, 20)
	_round(_scope_btn, "倍镜\n无", Control.PRESET_BOTTOM_RIGHT, Vector2(-550, -270), 100, 20)
	_aim_btn.visible = false
	_rotate_btn.visible = false
	_scope_btn.visible = false

	# 搜索 / 拾取：走近容器或地上的东西才出现
	_action_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_action_btn.position = Vector2(-640, -580)
	_action_btn.size = Vector2(240, 96)
	_action_btn.pivot_offset = _action_btn.size * 0.5
	_action_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_btn.clip_text = false
	var act_sb := StyleBoxFlat.new()
	act_sb.bg_color = Color(0.02, 0.02, 0.02, 0.55)
	act_sb.border_color = Color(1, 0.82, 0.45, 0.7)
	act_sb.set_border_width_all(2)
	act_sb.set_corner_radius_all(12)
	_action_btn.add_theme_stylebox_override("normal", act_sb)
	var act_v := VBoxContainer.new()
	act_v.set_anchors_preset(Control.PRESET_FULL_RECT)
	act_v.alignment = BoxContainer.ALIGNMENT_CENTER
	act_v.add_theme_constant_override("separation", 0)
	act_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_title.add_theme_font_size_override("font_size", 26)
	_action_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	act_v.add_child(_action_title)
	_action_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_sub.add_theme_font_size_override("font_size", 16)
	_action_sub.modulate = Color(1, 1, 1, 0.75)
	_action_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	act_v.add_child(_action_sub)
	_action_btn.add_child(act_v)
	_action_btn.visible = false
	_safe.add_child(_action_btn)

	# 子弹数：弹匣里 / 背包里 / 弹种
	_ammo_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_ammo_panel.position = Vector2(-260, -240)
	_ammo_panel.size = Vector2(520, 78)
	var am_sb := StyleBoxFlat.new()
	am_sb.bg_color = Color(0.02, 0.02, 0.02, 0.42)
	am_sb.border_color = Color(1, 1, 1, 0.14)
	am_sb.set_border_width_all(1)
	am_sb.set_corner_radius_all(14)
	am_sb.set_content_margin_all(6)
	_ammo_panel.add_theme_stylebox_override("panel", am_sb)
	var am_row := HBoxContainer.new()
	am_row.alignment = BoxContainer.ALIGNMENT_CENTER
	am_row.add_theme_constant_override("separation", 10)
	_ammo_mag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_mag.custom_minimum_size = Vector2(100, 0)
	_ammo_mag.add_theme_font_size_override("font_size", 38)
	_ammo_mag.add_theme_font_override("font", Hud.number_font())
	am_row.add_child(_ammo_mag)
	_ammo_reserve.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ammo_reserve.add_theme_font_size_override("font_size", 24)
	_ammo_reserve.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	_ammo_reserve.add_theme_font_override("font", Hud.number_font())
	am_row.add_child(_ammo_reserve)
	_ammo_type.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ammo_type.add_theme_font_size_override("font_size", 20)
	_ammo_type.add_theme_color_override("font_color", Color(0.9, 0.82, 0.65, 0.9))
	am_row.add_child(_ammo_type)
	_ammo_panel.add_child(am_row)
	_ammo_panel.visible = false
	_safe.add_child(_ammo_panel)

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
	_bag_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bag_btn.position = Vector2(-400, -118)
	_bag_btn.size = Vector2(100, 84)
	_bag_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(_bag_btn)

	# 背包（scripts/ui/bag_panel.gd）和容器面板（scripts/ui/container_panel.gd）
	_bag_panel.use_pressed.connect(func(id): item_used.emit(id))
	_bag_panel.drop_pressed.connect(func(i): item_dropped.emit(i))
	_bag_panel.compact_pressed.connect(func(): bag_compact_pressed.emit())
	_safe.add_child(_bag_panel)
	_safe.add_child(container_panel)

	# 合成按钮在背包下面，面板在 scripts/ui/craft_panel.gd
	_craft_btn.text = "合成"
	_craft_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_craft_btn.position = Vector2(-220, 144)
	_craft_btn.size = Vector2(130, 64)
	_craft_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_craft_btn)
	_root.add_child(craft_panel)

	# 摇杆：平时停在左下角，手指按在左半屏哪里就移到哪里
	for p in [_joy_base, _joy_knob]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.10 if p == _joy_base else 0.35)
		sb.border_color = Color(1, 1, 1, 0.35)
		sb.set_border_width_all(3 if p == _joy_base else 0)
		sb.set_corner_radius_all(int(JOY_RADIUS) if p == _joy_base else 38)
		p.add_theme_stylebox_override("panel", sb)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_safe.add_child(p)
	_joy_base.size = Vector2(JOY_RADIUS * 2, JOY_RADIUS * 2)
	_joy_knob.size = Vector2(76, 76)
	_reset_joystick()

	_pause_btn.text = "设置"
	_pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pause_btn.position = Vector2(-110, 10)
	_pause_btn.size = Vector2(100, 80)
	_pause_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(_pause_btn)

	_build_status_bar()
	_build_compass()
	_build_start_panel()
	_build_end_panel()
	_build_pause_panel()
	_build_settings_panel()
	_build_death_ui()
	# 背包盖在摇杆上面
	get_viewport().size_changed.connect(_update_safe_area)
	_update_safe_area()


## 吃鸡手游那样的圆形半透明按钮
func _round(b: Button, text: String, preset: int, pos: Vector2, diameter: float, font: int) -> void:
	b.text = text
	b.set_anchors_preset(preset)
	b.position = pos
	b.size = Vector2(diameter, diameter)
	b.add_theme_font_size_override("font_size", font)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.22)
		sb.border_color = Color(1, 1, 1, 0.42)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(int(diameter * 0.5))
		sb.anti_aliasing = true
		b.add_theme_stylebox_override(state, sb)
	_safe.add_child(b)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = Hud.game_font()
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


## 游戏自带字体：中文用 Noto Sans CJK，数字用七日杀界面的 Agency；没有就用系统字体
static var _font: Font
static var _num_font: Font


static func game_font() -> Font:
	if _font == null:
		var sys := SystemFont.new()
		# iPhone 上是苹方；电脑上调试时依次回退
		sys.font_names = PackedStringArray(["PingFang SC", "Hiragino Sans GB", "Heiti SC", "Noto Sans CJK SC", "Microsoft YaHei", "sans-serif"])
		_font = sys
		var path := "res://assets/fonts/NotoSansCJKjp-Medium.otf"
		if ResourceLoader.exists(path):
			var f: FontFile = load(path)
			f.fallbacks = [sys]
			_font = f
	return _font


static func number_font() -> Font:
	if _num_font == null:
		_num_font = game_font()
		var path := "res://assets/fonts/AGENCYB.ttf"
		if ResourceLoader.exists(path):
			var f: FontFile = load(path)
			f.fallbacks = [game_font()]
			_num_font = f
	return _num_font


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
	sub.text = "无尽生存：白天搜刮、合成、造基地，夜里躲僵尸，每七天一次血月。"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)
	_start_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_info.modulate = Color(1, 1, 1, 0.7)
	_start_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_start_info)
	var btn := Button.new()
	btn.text = "新的一局"
	btn.custom_minimum_size = Vector2(280, 90)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 40)
	btn.pressed.connect(func():
		_start_panel.visible = false
		start_pressed.emit())
	_continue_btn.text = "继续上次"
	_continue_btn.custom_minimum_size = Vector2(280, 80)
	_continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue_btn.add_theme_font_size_override("font_size", 34)
	_continue_btn.visible = false
	_continue_btn.pressed.connect(func():
		_start_panel.visible = false
		continue_pressed.emit())
	v.add_child(_continue_btn)
	v.add_child(btn)
	_start_settings_btn = Button.new()
	_start_settings_btn.text = "设置"
	_start_settings_btn.custom_minimum_size = Vector2(280, 76)
	_start_settings_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_start_settings_btn.add_theme_font_size_override("font_size", 32)
	_start_settings_btn.pressed.connect(func(): open_settings(true))
	v.add_child(_start_settings_btn)
	var help := Label.new()
	help.text = "左半屏拖动移动 · 右半屏拖动看 · 按住开火键开火 · 点弹药数字换弹 · 走近东西按「搜索」· 背包里选方块和形状"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(1, 1, 1, 0.6)
	help.add_theme_font_size_override("font_size", 20)
	v.add_child(help)
	var ver := Label.new()
	ver.text = build_label()
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.modulate = Color(1, 1, 1, 0.45)
	ver.add_theme_font_size_override("font_size", 18)
	v.add_child(ver)
	_root.add_child(_start_panel)


## 安装包编号（GitHub 上的第几次编译 + 提交号），CI 编译时写进 build_info.json；本地运行显示「本地版本」
static func build_label() -> String:
	if not FileAccess.file_exists("res://build_info.json"):
		return "本地版本"
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://build_info.json"))
	if not d is Dictionary:
		return "本地版本"
	return "安装包 7day-%s · %s" % [d.get("run", "?"), d.get("commit", "?")]


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
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 30)
	var again := Button.new()
	again.text = "再来一局"
	again.custom_minimum_size = Vector2(240, 86)
	again.add_theme_font_size_override("font_size", 34)
	again.pressed.connect(func():
		_end_panel.visible = false
		restart_pressed.emit())
	btns.add_child(again)
	_end_back_btn = Button.new()
	_end_back_btn.text = "回标题"
	_end_back_btn.custom_minimum_size = Vector2(240, 86)
	_end_back_btn.add_theme_font_size_override("font_size", 34)
	_end_back_btn.pressed.connect(func():
		_end_panel.visible = false
		back_to_title.emit())
	btns.add_child(_end_back_btn)
	v.add_child(btns)
	_root.add_child(_end_panel)


func _build_pause_panel() -> void:
	_pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	_pause_panel.custom_minimum_size = Vector2(520, 0)
	_pause_panel.position = Vector2(-260, -220)
	_pause_panel.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	_pause_panel.add_child(v)
	var title := Label.new()
	title.text = "暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	v.add_child(title)
	var resume := Button.new()
	resume.text = "继续游戏"
	resume.custom_minimum_size = Vector2(340, 84)
	resume.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	resume.add_theme_font_size_override("font_size", 32)
	resume.pressed.connect(func(): set_paused(false))
	v.add_child(resume)
	_pause_settings_btn = Button.new()
	_pause_settings_btn.text = "设置"
	_pause_settings_btn.custom_minimum_size = Vector2(340, 80)
	_pause_settings_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pause_settings_btn.add_theme_font_size_override("font_size", 30)
	_pause_settings_btn.pressed.connect(func(): open_settings(false))
	v.add_child(_pause_settings_btn)
	var quit := Button.new()
	quit.text = "存档并回标题"
	quit.custom_minimum_size = Vector2(340, 80)
	quit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit.add_theme_font_size_override("font_size", 30)
	quit.pressed.connect(func():
		set_paused(false)
		quit_to_title.emit())
	v.add_child(quit)
	var ver := Label.new()
	ver.text = build_label()
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.modulate = Color(1, 1, 1, 0.45)
	ver.add_theme_font_size_override("font_size", 18)
	v.add_child(ver)
	_root.add_child(_pause_panel)


func _build_settings_panel() -> void:
	_settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_panel.visible = false
	_root.add_child(_settings_panel)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_panel.add_child(center)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(660, 0)
	v.add_theme_constant_override("separation", 8)
	center.add_child(v)
	var title := Label.new()
	title.text = "设置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	v.add_child(title)
	_settings_group(v, "操作")
	_add_setting_row(v, "sensitivity", "视角灵敏度", 0.3, 2.5, 0.05)
	_settings_group(v, "画面")
	_add_setting_row(v, "brightness", "亮度", 0.5, 1.8, 0.05)
	var qh := HBoxContainer.new()
	var ql := Label.new()
	ql.text = "画质"
	ql.custom_minimum_size = Vector2(180, 0)
	qh.add_child(ql)
	_quality_option = OptionButton.new()
	for i in GameConfig.QUALITY_PRESETS.size():
		_quality_option.add_item(GameConfig.QUALITY_PRESETS[i].name, i)
	_quality_option.selected = clampi(int(settings.quality), 0, GameConfig.QUALITY_PRESETS.size() - 1)
	_quality_option.custom_minimum_size = Vector2(360, 52)
	_quality_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quality_option.item_selected.connect(_on_quality_selected)
	qh.add_child(_quality_option)
	v.add_child(qh)
	_perf_toggle = CheckButton.new()
	_perf_toggle.text = "显示性能信息"
	_perf_toggle.button_pressed = settings.show_perf > 0.5
	_perf_toggle.toggled.connect(_on_show_perf_toggled)
	v.add_child(_perf_toggle)
	_settings_group(v, "声音")
	_add_setting_row(v, "volume", "音效音量", 0.0, 1.0, 0.05)
	_add_setting_row(v, "music", "音乐音量", 0.0, 1.0, 0.05)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 26)
	_settings_reset_btn = Button.new()
	_settings_reset_btn.text = "恢复默认"
	_settings_reset_btn.custom_minimum_size = Vector2(220, 68)
	_settings_reset_btn.add_theme_font_size_override("font_size", 28)
	_settings_reset_btn.pressed.connect(_reset_settings)
	btns.add_child(_settings_reset_btn)
	_settings_back_btn = Button.new()
	_settings_back_btn.text = "返回"
	_settings_back_btn.custom_minimum_size = Vector2(220, 68)
	_settings_back_btn.add_theme_font_size_override("font_size", 28)
	_settings_back_btn.pressed.connect(close_settings)
	btns.add_child(_settings_back_btn)
	v.add_child(btns)


func _settings_group(parent: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = "— " + text + " —"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", Color(0.85, 0.7, 0.45))
	parent.add_child(l)


func _add_setting_row(parent: VBoxContainer, key: String, text: String, min_v: float, max_v: float, step_v: float) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(180, 0)
	h.add_child(l)
	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step_v
	sl.value = settings[key]
	sl.custom_minimum_size = Vector2(360, 52)
	sl.focus_mode = Control.FOCUS_NONE
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sl)
	var val := Label.new()
	val.text = _setting_text(key, sl.value)
	val.custom_minimum_size = Vector2(84, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	sl.value_changed.connect(func(x):
		settings[key] = x
		val.text = _setting_text(key, x)
		_save_settings()
		settings_changed.emit(settings))
	parent.add_child(h)
	_setting_sliders[key] = sl
	_setting_values[key] = val


func _setting_text(key: String, value: float) -> String:
	if key == "sensitivity":
		return "%.1f×" % value
	return "%d%%" % roundi(value * 100.0)


func _reset_settings() -> void:
	for k in DEFAULT_SETTINGS:
		settings[k] = DEFAULT_SETTINGS[k]
	for key in _setting_sliders:
		var sl: HSlider = _setting_sliders[key]
		sl.set_value_no_signal(settings[key])
		_setting_values[key].text = _setting_text(key, settings[key])
	_quality_option.selected = clampi(int(settings.quality), 0, GameConfig.QUALITY_PRESETS.size() - 1)
	_perf_toggle.set_pressed_no_signal(settings.show_perf > 0.5)
	_save_settings()
	settings_changed.emit(settings)


func open_settings(from_start: bool) -> void:
	_settings_from_start = from_start
	if not from_start:
		_pause_panel.visible = false
	_settings_panel.visible = true


func close_settings() -> void:
	_settings_panel.visible = false
	if _settings_from_start:
		_start_panel.visible = true
	else:
		_pause_panel.visible = true
func set_paused(on: bool) -> void:
	if on:
		_release_touches()
	if not on:
		_settings_panel.visible = false
	_pause_panel.visible = on
	get_tree().paused = on


func show_start(can_continue: bool) -> void:
	_release_touches()
	close_game_panels()
	set_scope(0)
	_settings_panel.visible = false
	_continue_btn.visible = can_continue
	_start_panel.visible = true
	_end_panel.visible = false


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		for k in settings:
			settings[k] = float(cf.get_value("settings", k, settings[k]))
		settings.quality = clampf(settings.quality, 0.0, GameConfig.QUALITY_PRESETS.size() - 1.0)
		settings.show_perf = 1.0 if settings.show_perf > 0.5 else 0.0


func _save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("settings", k, settings[k])
	cf.save(SETTINGS_PATH)


func _on_quality_selected(index: int) -> void:
	settings.quality = float(clampi(index, 0, GameConfig.QUALITY_PRESETS.size() - 1))
	_save_settings()
	settings_changed.emit(settings)


func _on_show_perf_toggled(on: bool) -> void:
	settings.show_perf = 1.0 if on else 0.0
	_save_settings()
	settings_changed.emit(settings)


func set_start_info(text: String) -> void:
	_start_info.text = text


func show_end(text: String) -> void:
	_release_touches()
	close_game_panels()
	set_scope(0)
	_settings_panel.visible = false
	_end_label.text = text
	_end_panel.visible = true


func close_game_panels() -> void:
	_bag_panel.visible = false
	craft_panel.visible = false
	container_panel.close_panel()


## 蹲着时按钮高亮
func set_crouch(on: bool) -> void:
	_crouch_btn.text = "站" if on else "蹲"
	_crouch_btn.self_modulate = Color(1.0, 0.85, 0.4) if on else Color.WHITE


func set_block_controls(rot: int, on: bool) -> void:
	_rotate_btn.visible = on
	if on:
		_rotate_btn.text = "旋转\n%d°" % (rot * 90)


func set_scope_button(text: String, on: bool) -> void:
	_scope_btn.visible = on
	if on:
		_scope_btn.text = text


## 拿着枪时显示「弹匣 / 背包」子弹数和换弹键；text 为空就隐藏
func set_ammo(text: String) -> void:
	if text == _ammo_text and text != "":
		return
	_ammo_text = text
	if text == "":
		_ammo_panel.visible = false
		_aim_btn.visible = false
		aim_held = false
		_cross.set_state(false, false)
		return
	var reloading := text.begins_with("换弹中")
	var parts := text.split("  ")
	var nums := parts[0].split(" / ")
	var mag := int(nums[0]) if nums.size() > 0 and nums[0].is_valid_int() else 0
	var reserve := nums[1] if nums.size() > 1 else ""
	var label := parts[1] if parts.size() > 1 else ""
	set_ammo_data(mag, reserve, label, reloading, maxi(mag, 1))


func set_ammo_data(mag: int, reserve: String, label: String, reloading: bool, capacity: int) -> void:
	_ammo_panel.visible = true
	_aim_btn.visible = true
	var low := capacity > 3 and mag > 0 and mag <= maxi(1, int(ceil(float(capacity) * 0.25)))
	var empty := not reloading and mag <= 0
	_ammo_mag.text = "…" if reloading else str(mag)
	_ammo_reserve.text = "" if reloading else "/ " + str(reserve)
	_ammo_type.text = "换弹中…" if reloading else ("空 · 点这里换弹" if empty else str(label))
	_ammo_mag.add_theme_color_override("font_color",
		Color(1, 0.3, 0.22, 0.95) if empty else (Color(1, 0.7, 0.25, 0.95) if low else Color(1, 1, 1, 0.95)))
	_ammo_type.add_theme_color_override("font_color",
		Color(1, 0.35, 0.25, 0.95) if empty else (Color(1, 0.75, 0.3, 0.95) if low else Color(0.9, 0.82, 0.65, 0.9)))
	_cross.set_state(low, empty)


func set_survival(water: float, effects: String) -> void:
	if not is_equal_approx(water, _water_value):
		_water_value = water
		_water_bar.value = water
		_set_stat_text(_water_text, water, water < 25.0)
	if effects != _effects_text:
		_effects_text = effects
		_effects.text = effects


func set_stamina(v: float) -> void:
	if is_equal_approx(v, _stamina_value):
		return
	_stamina_value = v
	_stamina_bar.value = v
	_set_stat_text(_stamina_text, v, v < 20.0)


func set_status(day: int, hour: float, hp: float, food: float, kills: int, zombies: int, night: bool,
		blood_day := false, blood_now := false, next_blood := 0) -> void:
	var h := int(hour)
	var m := int((hour - h) * 60.0)
	var status := "第 %d 天  %02d:%02d %s" % [day, h, m, "夜" if night else ""]
	if status != _status_text:
		_status_text = status
		_status.text = status
	if blood_day != _blood_day:
		_blood_day = blood_day
		_status.add_theme_color_override("font_color", Color(1, 0.35, 0.25) if blood_day else Color(0.95, 0.92, 0.85))
	_blood_info.text = "血月中" if blood_now else "下次血月：第 %d 天" % next_blood
	if not is_equal_approx(hp, _hp_value):
		_hp_value = hp
		_hp_bar.value = hp
		_set_stat_text(_hp_text, hp, hp < 30.0)
	if not is_equal_approx(food, _food_value):
		_food_value = food
		_food_bar.value = food
		_set_stat_text(_food_text, food, food < 25.0)
	var kills_text := "击杀 %d   附近 %d" % [kills, zombies]
	if kills_text != _kills_text:
		_kills_text = kills_text
		_kills.text = kills_text


func set_banner(text: String) -> void:
	if text == _banner_text:
		return
	_banner_text = text
	_banner.text = text


## 搜索 / 拾取按钮上的字；空字符串就隐藏。enabled=false 时变灰（比如容器已经翻过了）
func set_action(text: String, enabled := true) -> void:
	if text == _action_text and enabled == _action_enabled:
		return
	_action_text = text
	_action_enabled = enabled
	_action_btn.visible = text != ""
	var lines := text.split("\n")
	_action_title.text = lines[0] if lines.size() > 0 else ""
	_action_sub.text = lines[1] if lines.size() > 1 else ""
	_action_btn.modulate = Color.WHITE if enabled else Color(1, 1, 1, 0.45)
	if text != "":
		_action_btn.scale = Vector2(1.05, 1.05)
		var tw := create_tween()
		tw.tween_property(_action_btn, "scale", Vector2.ONE, 0.12)


## 翻找进度：value < 0 隐藏
func set_progress(value: float, text := "") -> void:
	var show := value >= 0.0
	if show == _progress_shown and (not show or text == _progress_text):
		if show:
			_progress.value = value
		return
	_progress_shown = show
	_progress_text = text
	_progress.visible = show
	_progress_label.visible = show
	if show:
		_progress.value = value
		_progress_label.text = text


## 暂停菜单里的「显示性能信息」
func set_perf_visible(on: bool) -> void:
	_perf.visible = on


func set_perf(text: String) -> void:
	if text != _perf.text:
		_perf.text = text


func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast_t = 2.2


func _build_death_ui() -> void:
	# 指向尸体背包：顶部中间一个会转的三角 + 距离
	_bag_marker.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_bag_marker.position = Vector2(-160, 150)
	_bag_marker.size = Vector2(320, 50)
	_bag_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag_marker.visible = false
	_root.add_child(_bag_marker)
	_bag_arrow.position = Vector2(30, 25)
	_bag_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tri := Polygon2D.new()
	tri.polygon = PackedVector2Array([Vector2(0, -18), Vector2(13, 14), Vector2(0, 7), Vector2(-13, 14)])
	tri.color = Color(1.0, 0.55, 0.4)
	_bag_arrow.add_child(tri)
	_bag_marker.add_child(_bag_arrow)
	_bag_marker_label.position = Vector2(56, 4)
	_bag_marker_label.size = Vector2(260, 42)
	_bag_marker_label.add_theme_font_size_override("font_size", 26)
	_bag_marker_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.65))
	_bag_marker_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_bag_marker_label.add_theme_constant_override("outline_size", 6)
	_bag_marker.add_child(_bag_marker_label)
	# 死亡黑屏，盖在所有界面上面
	_blackout.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blackout.color = Color(0, 0, 0, 0)
	_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blackout.visible = false
	_root.add_child(_blackout)
	_blackout_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blackout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blackout_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_blackout_label.add_theme_font_size_override("font_size", 48)
	_blackout_label.add_theme_color_override("font_color", Color(0.85, 0.2, 0.15))
	_blackout.add_child(_blackout_label)


## 死亡黑屏：on = true 变黑并显示 text，false 慢慢亮回来
func set_blackout(on: bool, text := "") -> void:
	if _blackout_tween:
		_blackout_tween.kill()
	_blackout_label.text = text
	_blackout.visible = true
	if on:
		_release_touches()
	_blackout_tween = create_tween()
	_blackout_tween.tween_property(_blackout, "color:a", 1.0 if on else 0.0, 0.35 if on else 0.8)
	if not on:
		_blackout_tween.tween_callback(func(): _blackout.visible = false)


func blackout_visible() -> bool:
	return _blackout.visible and _blackout.color.a > 0.5


## 尸体背包方向：angle 是相对视线的角度（弧度，0 = 正前方，正数在右边），dist 米；dist < 0 隐藏
func set_bag_marker(angle: float, dist: float) -> void:
	_bag_marker.visible = dist >= 0.0
	if dist < 0.0:
		return
	_bag_arrow.rotation = angle
	_bag_marker_label.text = "尸体背包 %d 米" % roundi(dist)


func hurt() -> void:
	_hurt.color.a = 0.35


## 背包格子交给背包面板画
func set_bag(slots: Array, cap: int, used: int, equipped: String) -> void:
	_bag_panel.set_slots(slots, cap, used, equipped)


## inventory: [{id, count, equipped}]
func set_inventory(list: Array, hotbar_ids: Array) -> void:
	for c in _hotbar.get_children():
		c.queue_free()
	for id in hotbar_ids:
		_hotbar.add_child(_slot(id, list))
	var eq_name := ""
	for e in list:
		if e.get("equipped", false):
			eq_name = Assets.display_name(str(e.id))
			break
	if eq_name != _hotbar_name.text:
		_hotbar_name.text = eq_name
		if _hotbar_name_tween and _hotbar_name_tween.is_valid():
			_hotbar_name_tween.kill()
		_hotbar_name.modulate.a = 1.0 if eq_name != "" else 0.0
		if eq_name != "":
			_hotbar_name_tween = create_tween()
			_hotbar_name_tween.tween_interval(1.2)
			_hotbar_name_tween.tween_property(_hotbar_name, "modulate:a", 0.0, 0.5)


## 刘海 / 灵动岛 / 底部横条：读系统给的安全区，换算成画布像素
func _update_safe_area() -> void:
	var ins := Vector4.ZERO
	if OS.has_feature("mobile"):
		var screen := Vector2(DisplayServer.screen_get_size())
		var safe := Rect2(DisplayServer.get_display_safe_area())
		var canvas := get_viewport().get_visible_rect().size
		if screen.x > 0.0 and screen.y > 0.0 and safe.size.x > 0.0:
			var k := canvas / screen
			ins = Vector4(safe.position.x * k.x, safe.position.y * k.y,
				(screen.x - safe.end.x) * k.x, (screen.y - safe.end.y) * k.y)
			# 横屏时刘海可能在左也可能在右，转一下手机就换边：两边都让出来
			var side := maxf(ins.x, ins.z)
			ins.x = side
			ins.z = side
	apply_safe_insets(ins)


func apply_safe_insets(ins: Vector4) -> void:
	safe_insets = Vector4(maxf(ins.x, 0.0), maxf(ins.y, 0.0), maxf(ins.z, 0.0), maxf(ins.w, 0.0))
	_safe.offset_left = safe_insets.x
	_safe.offset_top = safe_insets.y
	_safe.offset_right = -safe_insets.z
	_safe.offset_bottom = -safe_insets.w
	if _joy_id == -1:
		_reset_joystick()


func _reset_joystick() -> void:
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	var home := Vector2(safe_insets.x + JOY_RADIUS + 40, vp.y - safe_insets.w - JOY_RADIUS - 70)
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
	b.custom_minimum_size = Vector2(76, 76) if not with_name else Vector2(110, 140)
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
		sb.bg_color = Color(0.3, 0.22, 0.08, 0.9)
		sb.border_color = Color(1, 0.8, 0.3)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(12)
		b.add_theme_stylebox_override("normal", sb)
		if not with_name:
			b.pivot_offset = Vector2(38, 38)
			b.scale = Vector2(1.06, 1.06)
	b.set_meta("item", id)
	var quality: int = int(entry.get("quality", 0))
	if quality > 1:
		var ql := Label.new()
		ql.text = "Q%d" % quality
		ql.position = Vector2(6, 6)
		ql.add_theme_font_size_override("font_size", 16)
		ql.add_theme_color_override("font_color", QUALITY_COLORS[clampi(quality, 1, 6) - 1])
		ql.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ql)
	b.focus_mode = Control.FOCUS_NONE
	if with_name:
		# 背包里能上下滑着找：手指按下后挪动超过 TAP_SLOP 就算滑动，不用这个物品
		b.gui_input.connect(func(ev: InputEvent): _bag_slot_input(b, id, ev))
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.button_mask = 0  # 不走按钮自己的「按下」，由 _bag_slot_input 判断点还是滑
	else:
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 快捷栏在 _input 里处理
	return b


func _bag_slot_input(b: Button, id: String, ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton) or ev.button_index != MOUSE_BUTTON_LEFT:
		return
	if ev.pressed:
		b.set_meta("down_at", ev.global_position)
		_flash(b)
	elif b.has_meta("down_at"):
		var from: Vector2 = b.get_meta("down_at")
		b.remove_meta("down_at")
		if ev.global_position.distance_to(from) <= TAP_SLOP and b.get_global_rect().has_point(ev.global_position):
			_tap_feedback()
			item_used.emit(id)


func _process(delta: float) -> void:
	if _status_tip_t > 0.0:
		_status_tip_t -= delta
		_status_tip.visible = _status_tip_t > 0.0
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t < 0.6:
			_toast.modulate.a = max(0.0, _toast_t / 0.6)
	if _hurt.color.a > 0.0:
		_hurt.color.a = max(0.0, _hurt.color.a - delta * 0.8)


## 打中僵尸：准星旁闪一个 ×，爆头变红
func hitmarker(headshot := false) -> void:
	if _hit_tween and _hit_tween.is_valid():
		_hit_tween.kill()
	_hitmarker.modulate = Color(1.0, 0.32, 0.22, 1.0) if headshot else Color(1, 1, 1, 0.9)
	_hitmarker.scale = Vector2(1.35, 1.35)
	_hit_tween = create_tween()
	_hit_tween.set_parallel(true)
	_hit_tween.tween_property(_hitmarker, "scale", Vector2.ONE, 0.16)
	_hit_tween.tween_property(_hitmarker, "modulate:a", 0.0, 0.24)


## 开枪/攻击时准星轻轻放大再回弹
func crosshair_kick() -> void:
	_cross.kick()


func crosshair_color() -> Color:
	return _cross.color


func consume_look() -> Vector2:
	var d := look_delta
	look_delta = Vector2.ZERO
	return d


func _panel_open() -> bool:
	return _bag_panel.visible or container_panel.visible or craft_panel.visible or _start_panel.visible \
		or _end_panel.visible or _pause_panel.visible or _settings_panel.visible or _blackout.visible


func _press_attack(pressed: bool) -> void:
	attack_held = pressed
	_attack_btn.modulate = Color(1.6, 0.7, 0.6) if pressed else Color.WHITE


func _flash(control: Control) -> void:
	control.modulate = Color(1.5, 1.3, 0.9)
	var tw := create_tween()
	tw.tween_property(control, "modulate", Color.WHITE, 0.12)


## 点按钮时轻轻震一下（iPhone 的触感反馈）
func _tap_feedback() -> void:
	Input.vibrate_handheld(12)


func _press_button(control: Control) -> void:
	_flash(control)
	_tap_feedback()


func open_bag() -> void:
	_release_touches()
	_bag_panel.visible = true


## 切到后台、下拉通知中心、来电话：手指都算松开；游戏中就自动暂停
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_release_touches()
		if _in_game():
			set_paused(true)


func _in_game() -> bool:
	return is_inside_tree() and not _start_panel.visible and not _end_panel.visible \
		and not _pause_panel.visible and not get_tree().paused


func release_touches() -> void:
	_release_touches()


func _release_touches() -> void:
	_attack_ids.clear()
	_press_attack(false)
	_drag_last.clear()
	_aim_id = -1
	aim_held = false
	_aim_btn.modulate = Color.WHITE
	_joy_id = -1
	move = Vector2.ZERO
	_reset_joystick()
	_look_id = -1


func _touch_down(index: int, pos: Vector2) -> void:
	if _aim_btn.visible and _aim_btn.get_global_rect().grow(12).has_point(pos):
		_aim_id = index
		_drag_last[index] = pos
		aim_held = true
		_aim_btn.modulate = Color(1.6, 0.7, 0.6)
		return
	if _attack_btn.get_global_rect().grow(16).has_point(pos):
		_attack_ids[index] = true
		_drag_last[index] = pos  # 按住开火再拖动可以边打边转视角
		_press_attack(true)
		return
	if _ammo_panel.visible and _ammo_panel.get_global_rect().grow(8).has_point(pos):
		_press_button(_ammo_panel)
		reload_pressed.emit()
		return
	if _scope_btn.visible and _scope_btn.get_global_rect().grow(10).has_point(pos):
		_press_button(_scope_btn)
		scope_pressed.emit()
		return
	if _rotate_btn.visible and _rotate_btn.get_global_rect().grow(10).has_point(pos):
		_press_button(_rotate_btn)
		rotate_pressed.emit()
		return
	if _jump_btn.get_global_rect().grow(10).has_point(pos):
		_press_button(_jump_btn)
		jump_pressed.emit()
		return
	if _crouch_btn.get_global_rect().grow(10).has_point(pos):
		_press_button(_crouch_btn)
		crouch_pressed.emit()
		return
	if _action_btn.visible and _action_btn.get_global_rect().grow(12).has_point(pos):
		_press_button(_action_btn)
		action_pressed.emit()
		return
	if _pause_btn.get_global_rect().grow(10).has_point(pos):
		_tap_feedback()
		set_paused(true)
		return
	if _status_touch(pos):
		return
	if _bag_btn.get_global_rect().grow(10).has_point(pos):
		open_bag()
		_press_button(_bag_btn)
		return
	if _craft_btn.get_global_rect().grow(10).has_point(pos):
		craft_panel.open()
		_release_touches()
		_flash(_craft_btn)
		return
	for slot in _hotbar.get_children():
		if (slot as Control).get_global_rect().grow(4).has_point(pos):
			_press_button(slot)
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
		_drag_last[index] = pos


func _touch_up(index: int) -> void:
	_drag_last.erase(index)
	if index == _aim_id:
		_aim_id = -1
		aim_held = false
		_aim_btn.modulate = Color.WHITE
	elif _attack_ids.has(index):
		_attack_ids.erase(index)
		_press_attack(not _attack_ids.is_empty())
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
			elif _bag_panel.visible and not _bag_panel.get_global_rect().has_point(event.position):
				# 点背包外面的空白就关掉背包
				_bag_panel.visible = false
				get_viewport().set_input_as_handled()
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		if _panel_open():
			return
		if event.index == _joy_id:
			var d: Vector2 = event.position - _joy_origin
			if d.length() > JOY_RADIUS:
				# 手指拖出圈外：摇杆跟着手指走，往回拖马上就能转向
				d = d.normalized() * JOY_RADIUS
				_joy_origin = event.position - d
				_joy_base.position = _joy_origin - _joy_base.size * 0.5
			_joy_knob.position = _joy_origin + d - _joy_knob.size * 0.5
			var raw := Vector2(d.x, -d.y) / JOY_RADIUS
			if raw.length() <= JOY_DEADZONE:
				move = Vector2.ZERO
			else:
				move = raw.normalized() * clampf((raw.length() - JOY_DEADZONE) / (1.0 - JOY_DEADZONE), 0.0, 1.0)
		elif _drag_last.has(event.index):
			look_delta += event.position - _drag_last[event.index]
			_drag_last[event.index] = event.position


# —— 状态图标条 ——


func _build_compass() -> void:
	_compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_compass.position = Vector2(-360, 14)
	_compass.size = Vector2(720, 44)
	_compass.font = Hud.game_font()
	_safe.add_child(_compass)


func set_compass(yaw: float, markers: Array) -> void:
	_compass.set_data(yaw, markers)


func compass_relative(bearing: float) -> float:
	return _compass.relative_angle(bearing)


func set_scope(level: int) -> void:
	if level == _scope_level:
		return
	_scope_level = level
	_scope.visible = level >= 2
	_scope_label.visible = level >= 2
	if level >= 2:
		_scope_label.text = "%d×" % level


## 打中僵尸时在命中位置飘一个伤害数字
func damage_number(amount: float, headshot: bool, world_pos: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(world_pos):
		return
	var at := cam.unproject_position(world_pos)
	var l := Label.new()
	l.text = str(roundi(amount))
	l.add_theme_font_override("font", number_font())
	l.add_theme_font_size_override("font_size", 34 if headshot else 26)
	l.add_theme_color_override("font_color", Color(1, 0.35, 0.25) if headshot else Color(1, 1, 1, 0.95))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = at + Vector2(-40, -32)
	l.size = Vector2(80, 40)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 38, 0.65)
	tw.tween_property(l, "modulate:a", 0.0, 0.65)
	tw.chain().tween_callback(l.queue_free)


func _add_stat_row(parent: VBoxContainer, name: String, bar: ProgressBar, color: Color, height: int,
		value: Label) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = name
	label.custom_minimum_size = Vector2(28, 0)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color.lightened(0.18))
	row.add_child(label)
	bar.custom_minimum_size = Vector2(210, height)
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = 100
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	value.text = "100"
	value.custom_minimum_size = Vector2(52, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 18)
	value.add_theme_color_override("font_color", Color(0.92, 0.9, 0.82))
	row.add_child(value)
	parent.add_child(row)


func _set_stat_text(label: Label, value: float, low: bool) -> void:
	label.text = str(roundi(value))
	label.add_theme_color_override("font_color", Color(1, 0.35, 0.25) if low else Color(0.92, 0.9, 0.82))


func _build_status_bar() -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	holder.offset_left = -700
	holder.offset_right = -30
	holder.offset_top = 146
	holder.offset_bottom = 214
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(holder)
	_status_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_status_row.alignment = BoxContainer.ALIGNMENT_END
	_status_row.add_theme_constant_override("separation", 6)
	_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_status_row)
	_status_tip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_status_tip.offset_left = -700
	_status_tip.offset_right = -30
	_status_tip.offset_top = 270
	_status_tip.offset_bottom = 350
	_status_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_tip.add_theme_font_size_override("font_size", 22)
	_status_tip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_status_tip.add_theme_constant_override("outline_size", 6)
	_status_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_tip.visible = false
	_root.add_child(_status_tip)


## 剩余游戏小时 → "1:30"；一直有的不显示时间
static func status_time_text(left: float) -> String:
	if left == INF or left <= 0.0:
		return ""
	var mins := ceili(left * 60.0)
	return "%d:%02d" % [mins / 60, mins % 60]


## list 来自 Status.active()：[{id, zh, short, desc, left, stacks, bad}]
func set_effects(list: Array) -> void:
	var ids := list.map(func(e): return e.id)
	if ids != _status_ids:
		_status_ids = ids
		for c in _status_row.get_children():
			c.queue_free()
		for e in list:
			var b := Button.new()
			b.custom_minimum_size = Vector2(66, 66)
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 18)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.55, 0.1, 0.08, 0.8) if e.bad else Color(0.12, 0.42, 0.2, 0.8)
			sb.set_corner_radius_all(10)
			sb.border_color = Color(1, 1, 1, 0.35)
			sb.set_border_width_all(2)
			for st in ["normal", "hover", "pressed"]:
				b.add_theme_stylebox_override(st, sb)
			_status_row.add_child(b)
	var buttons := _status_row.get_children().filter(func(c): return not c.is_queued_for_deletion())
	for i in mini(buttons.size(), list.size()):
		var e: Dictionary = list[i]
		var b: Button = buttons[i]
		var t := status_time_text(float(e.left))
		var label: String = str(e.short) + (" ×%d" % e.stacks if int(e.stacks) > 1 else "")
		# 感染这类按百分比显示
		if str(e.get("unit", "")) == "%":
			label = "%s\n%d%%" % [e.short, int(e.stacks)]
		b.text = label if t == "" else "%s\n%s" % [label, t]
		b.set_meta("info", e)


func _status_touch(pos: Vector2) -> bool:
	for b in _status_row.get_children():
		if b.is_queued_for_deletion() or not (b as Control).get_global_rect().grow(6).has_point(pos):
			continue
		var e: Dictionary = b.get_meta("info", {})
		if e.is_empty():
			return true
		_flash(b)
		var t := status_time_text(float(e.left))
		var pct := (" %d%%" % int(e.stacks)) if str(e.get("unit", "")) == "%" else ""
		_status_tip.text = "%s%s：%s%s" % [e.zh, pct, e.desc, ("  剩余 " + t) if t != "" else ""]
		_status_tip.visible = true
		_status_tip_t = 3.5
		return true
	return false
