class_name QuestPanel
extends PanelContainer
## 7d 商人任务面板：5 个委托、当前任务、交任务/放弃、三选一奖励。

const BTN_H := 58.0

var quests: QuestSystem
var _title := Label.new()
var _list := VBoxContainer.new()
var _active_box := VBoxContainer.new()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 90
	offset_right = -90
	offset_top = 30
	offset_bottom = -30
	visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.06, 0.07, 0.97)
	sb.border_color = Color(0.6, 0.58, 0.5, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	_title.text = "商人任务"
	_title.add_theme_font_size_override("font_size", 30)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(118, BTN_H)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): visible = false)
	head.add_child(close)
	v.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	v.add_child(scroll)
	_active_box.add_theme_constant_override("separation", 6)
	v.add_child(_active_box)


func bind(q: QuestSystem) -> void:
	quests = q


func open() -> void:
	visible = true
	refresh()


func refresh() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for c in _active_box.get_children():
		_active_box.remove_child(c)
		c.queue_free()
	if quests == null:
		return
	_title.text = "商人任务 · 已完成 %d" % quests.completed
	if not quests.active.is_empty():
		_build_active()
		return
	if quests.offers.is_empty():
		_list.add_child(_label("暂时没有委托"))
		return
	for i in quests.offers.size():
		var o: Dictionary = quests.offers[i]
		var row := HBoxContainer.new()
		var info := Label.new()
		info.text = "%s   [%s]   %s   %d 公爵币 + %d 经验" % [
			o.get("name", "任务"), "T%d" % int(o.get("tier", 1)),
			_target_label(o), int(o.get("coins", 0)), int(o.get("xp", 0))]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.clip_text = true
		row.add_child(info)
		var b := Button.new()
		b.text = "接取"
		b.custom_minimum_size = Vector2(130, BTN_H)
		b.focus_mode = Control.FOCUS_NONE
		var idx := i
		b.pressed.connect(func():
			if quests.accept(idx):
				refresh())
		row.add_child(b)
		_list.add_child(row)


func _build_active() -> void:
	var a: Dictionary = quests.active
	var name := str(a.get("name", "任务"))
	var kind := str(a.get("kind", ""))
	var state := str(a.get("state", "go"))
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 22)
	if state == "return":
		info.text = "%s：已完成，回商人交任务" % name
	elif state == "reward":
		info.text = "%s：选一件奖励" % name
	elif kind == "buried":
		info.text = "%s：挖宝 %d/5（目标：%s）" % [name, int(a.get("progress", 0)),
			_target_label(a)]
	else:
		info.text = "%s：%s（目标：%s）" % [name, "清剿睡眠僵尸" if kind == "clear" else "取回补给",
			_target_label(a)]
	_active_box.add_child(info)
	if state == "reward":
		var choices: Array = a.get("choices", [])
		for id in choices:
			var b := Button.new()
			b.text = "拿 %s" % Assets.display_name(str(id))
			b.custom_minimum_size = Vector2(0, BTN_H)
			b.focus_mode = Control.FOCUS_NONE
			var pick := str(id)
			b.pressed.connect(func():
				if quests.choose_reward(pick):
					refresh())
			_active_box.add_child(b)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if state == "return":
		var turn := Button.new()
		turn.text = "交任务"
		turn.custom_minimum_size = Vector2(180, BTN_H)
		turn.focus_mode = Control.FOCUS_NONE
		turn.disabled = not quests.can_turn_in(quests.player_sys.player.position)
		turn.pressed.connect(func():
			if quests.turn_in():
				refresh())
		row.add_child(turn)
	var give := Button.new()
	give.text = "放弃"
	give.custom_minimum_size = Vector2(140, BTN_H)
	give.focus_mode = Control.FOCUS_NONE
	give.pressed.connect(func():
		quests.abandon()
		refresh())
	row.add_child(give)
	_active_box.add_child(row)
	if state == "return" and not quests.can_turn_in(quests.player_sys.player.position):
		_active_box.add_child(_label("到商人身边才能交任务"))


func _target_label(o: Dictionary) -> String:
	var poi := str(o.get("poi", ""))
	if poi != "":
		return poi
	return "埋藏点"


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.modulate = Color(1, 1, 1, 0.7)
	return l
