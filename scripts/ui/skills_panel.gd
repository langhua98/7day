class_name SkillsPanel
extends PanelContainer
## 7a 技能面板：顶部等级/经验/点数，5 列属性；点属性看技能，点技能看当前/下一级效果并加点。

const C = preload("res://scripts/config.gd")
const BTN_H := 64.0

var prog: Node
var _level := Label.new()
var _points := Label.new()
var _xp := ProgressBar.new()
var _xp_label := Label.new()
var _tabs := HBoxContainer.new()
var _tab_btns := {}
var _skill_list := VBoxContainer.new()
var _detail_title := Label.new()
var _detail_body := RichTextLabel.new()
var _buy_btn := Button.new()
var _hint := Label.new()
var _attr := "attPerception"
var _sel := ""


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 50
	offset_right = -50
	offset_top = 24
	offset_bottom = -24
	visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.06, 0.07, 0.96)
	sb.border_color = Color(0.55, 0.58, 0.62, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	var title := Label.new()
	title.text = "等级与技能"
	title.add_theme_font_size_override("font_size", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_level.add_theme_font_size_override("font_size", 24)
	head.add_child(_level)
	_points.add_theme_font_size_override("font_size", 24)
	_points.modulate = Color(1.0, 0.86, 0.45)
	head.add_child(_points)
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(118, BTN_H)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): visible = false)
	head.add_child(close)
	v.add_child(head)

	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 10)
	_xp.custom_minimum_size.y = 26
	_xp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp.min_value = 0.0
	_xp.max_value = 1.0
	_xp.show_percentage = false
	xp_row.add_child(_xp)
	_xp_label.add_theme_font_size_override("font_size", 18)
	_xp_label.custom_minimum_size.x = 210
	xp_row.add_child(_xp_label)
	v.add_child(xp_row)

	_tabs.add_theme_constant_override("separation", 6)
	v.add_child(_tabs)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	v.add_child(body)
	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size.x = 520
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_stretch_ratio = 0.9
	list_scroll.add_child(_skill_list)
	_skill_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(list_scroll)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_stretch_ratio = 1.1
	var dv := VBoxContainer.new()
	dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dv.add_theme_constant_override("separation", 8)
	detail_scroll.add_child(dv)
	_detail_title.add_theme_font_size_override("font_size", 26)
	dv.add_child(_detail_title)
	_detail_body.bbcode_enabled = true
	_detail_body.fit_content = true
	_detail_body.scroll_active = false
	_detail_body.custom_minimum_size.y = 210
	_detail_body.add_theme_font_size_override("normal_font_size", 19)
	dv.add_child(_detail_body)
	_buy_btn.custom_minimum_size = Vector2(0, 68)
	_buy_btn.add_theme_font_size_override("font_size", 22)
	_buy_btn.focus_mode = Control.FOCUS_NONE
	_buy_btn.pressed.connect(_buy_selected)
	dv.add_child(_buy_btn)
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.modulate = Color(1, 1, 1, 0.6)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(_hint)
	body.add_child(detail_scroll)


func bind(p: Node) -> void:
	if prog != null and prog.changed.is_connected(refresh):
		prog.changed.disconnect(refresh)
	prog = p
	if not prog.changed.is_connected(refresh):
		prog.changed.connect(refresh)
	_build_tabs()
	refresh()


func open() -> void:
	visible = true
	refresh()


func _build_tabs() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	_tab_btns.clear()
	if prog == null:
		return
	for name in prog.data.get("attributes", {}):
		var attr_name: String = name
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var b := Button.new()
		b.custom_minimum_size = Vector2(170, BTN_H)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(func(): _set_attr(attr_name))
		row.add_child(b)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(40, BTN_H)
		plus.focus_mode = Control.FOCUS_NONE
		plus.pressed.connect(func(): _buy_attr(attr_name))
		row.add_child(plus)
		_tabs.add_child(row)
		_tab_btns[name] = {"main": b, "plus": plus}
	if not _tab_btns.has(_attr) and not _tab_btns.is_empty():
		_attr = str(_tab_btns.keys()[0])


func refresh() -> void:
	if prog == null:
		return
	if _tab_btns.is_empty():
		_build_tabs()
	_level.text = "等级 %d" % prog.level
	_points.text = "技能点 %d" % prog.points
	_xp.value = prog.xp_progress()
	var need: float = prog.xp_to_next()
	_xp_label.text = ("经验 %d / %d" % [int(prog.xp), int(need)]) if need > 0.0 else "已满级"
	for name in _tab_btns:
		var e: Dictionary = prog.data.attributes.get(name, {})
		(_tab_btns[name].main as Button).text = "%s  %d/%d" % [
			str(e.get("name", name)).replace("属性：", ""), prog.attr_level(name), prog.attr_max(name)]
		(_tab_btns[name].main as Button).modulate = Color(1.0, 0.88, 0.5) if name == _attr else Color.WHITE
		(_tab_btns[name].plus as Button).disabled = not prog.can_buy_attr(name)
	_rebuild_skill_list()
	_refresh_detail()


func _set_attr(name: String) -> void:
	_attr = name
	_sel = ""
	refresh()


func _rebuild_skill_list() -> void:
	for c in _skill_list.get_children():
		c.queue_free()
	if prog == null:
		return
	var names: Array = prog.skills_for_attr(_attr)
	if names.is_empty():
		var empty := Label.new()
		empty.text = "这列还没有技能"
		empty.modulate = Color(1, 1, 1, 0.5)
		_skill_list.add_child(empty)
		return
	for name in names:
		var skill: String = name
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = BTN_H
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 19)
		b.text = "%s    %d/%d" % [prog.skill_name(skill), prog.perk_level(skill), prog.perk_max(skill)]
		b.modulate = Color(1.0, 0.88, 0.5) if skill == _sel else Color.WHITE
		b.pressed.connect(func(): _select_skill(skill))
		row.add_child(b)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(52, BTN_H)
		plus.focus_mode = Control.FOCUS_NONE
		plus.disabled = not prog.can_buy_perk(skill)
		plus.pressed.connect(func(): _buy_perk(skill))
		row.add_child(plus)
		_skill_list.add_child(row)


func _select_skill(name: String) -> void:
	_sel = name
	_refresh_detail()
	_rebuild_skill_list()


func _refresh_detail() -> void:
	if _sel == "" or prog == null:
		_detail_title.text = "选一个技能"
		_detail_body.text = "[color=#aaaaaa]左边点技能名，右边看每级效果和加点。[/color]"
		_buy_btn.text = "加点"
		_buy_btn.disabled = true
		_hint.text = "属性每级消耗的点数按 1.14 倍增加；技能按官方表。"
		return
	var lvl: int = prog.perk_level(_sel)
	var maxl: int = prog.perk_max(_sel)
	_detail_title.text = "%s  %d/%d" % [prog.skill_name(_sel), lvl, maxl]
	var t := "[font_size=19]%s[/font_size]\n\n" % _pretty(prog.skill_desc(_sel))
	if lvl > 0:
		t += "[color=#9fd58a]当前 %d 级：[/color]\n%s\n\n" % [lvl, _pretty(prog.skill_rank_text(_sel, lvl))]
	if lvl < maxl:
		t += "[color=#ffd479]下一级 %d：[/color]\n%s\n" % [lvl + 1, _pretty(prog.skill_rank_text(_sel, lvl + 1))]
	_detail_body.text = t
	if lvl >= maxl:
		_buy_btn.text = "已满级"
		_buy_btn.disabled = true
	else:
		var cost: int = prog.perk_cost(_sel)
		_buy_btn.text = "加点  （%d 点）" % cost
		_buy_btn.disabled = not prog.can_buy_perk(_sel)
	_hint.text = "剩余技能点：%d" % prog.points


## 游戏文本里的 [DECEA3] 颜色标签换成 Godot 的 BBCode
func _pretty(text: String) -> String:
	return text.replace("[DECEA3]", "[color=#DECEA3]").replace("[-]", "[/color]")


func _buy_perk(name: String) -> void:
	if prog != null and prog.buy_perk(name):
		_sel = name
		refresh()


func _buy_attr(name: String) -> void:
	if prog != null and prog.buy_attr(name):
		_attr = name
		refresh()


func _buy_selected() -> void:
	if _sel != "":
		_buy_perk(_sel)
