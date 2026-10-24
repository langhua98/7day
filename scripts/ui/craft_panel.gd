class_name CraftPanel
extends PanelContainer
## 合成面板：顶部分类标签，左边配方图标网格（能做的亮，不能做的暗），
## 右边选中配方的材料「有 / 要」（不够标红）、数量 1 / 5 / 最多、合成按钮，底部队列和进度条（点一项取消）。

const SLOT := 92.0
const BTN_H := 64.0

var crafting: Crafting
var _title := Label.new()
var _tabs := HBoxContainer.new()
var _grid := GridContainer.new()
var _name := Label.new()
var _info := Label.new()
var _ings := VBoxContainer.new()
var _reason := Label.new()
var _craft_btn := Button.new()
var _count_btns := []
var _queue_box := HBoxContainer.new()
var _queue_bar := ProgressBar.new()
var _cat := "tool"
var _sel := ""
var _n := 1
## null = 全部配方（背包里打开）；字符串 = 只看这个工作站
var _area = null
## 工作站所在方块格子；null = 背包
var _station = null
var _station_row := HBoxContainer.new()
var _fuel_btn := Button.new()
var _tool_btn := Button.new()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 100
	offset_right = -100
	offset_top = 30
	offset_bottom = -30
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)

	var head := HBoxContainer.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 30)
	head.add_child(_title)
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(110, BTN_H)
	close.pressed.connect(func(): visible = false)
	head.add_child(close)
	v.add_child(head)

	# 分类标签（横向能滑）
	var tab_scroll := ScrollContainer.new()
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.custom_minimum_size.y = BTN_H + 8
	_tabs.add_theme_constant_override("separation", 6)
	for c in Crafting.CATS:
		var b := Button.new()
		b.text = c[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(104, BTN_H)
		b.focus_mode = Control.FOCUS_NONE
		b.set_meta("cat", c[0])
		var cat: String = c[0]
		b.pressed.connect(func(): _set_cat(cat))
		_tabs.add_child(b)
	tab_scroll.add_child(_tabs)
	v.add_child(tab_scroll)

	# 篝火的燃料和锅具
	_station_row.add_theme_constant_override("separation", 8)
	_station_row.visible = false
	_fuel_btn.custom_minimum_size = Vector2(210, BTN_H)
	_tool_btn.custom_minimum_size = Vector2(210, BTN_H)
	_fuel_btn.pressed.connect(func():
		if _station != null:
			crafting.add_fuel(_station, 1)
			_refresh())
	_tool_btn.pressed.connect(func():
		if _station != null:
			crafting.toggle_tool(_station)
			_refresh())
	_station_row.add_child(_fuel_btn)
	_station_row.add_child(_tool_btn)
	v.add_child(_station_row)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	v.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.4
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)
	body.add_child(scroll)

	# 右边：选中配方的详情
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 6)
	_name.add_theme_font_size_override("font_size", 28)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_name)
	_info.add_theme_font_size_override("font_size", 20)
	_info.modulate = Color(0.8, 0.78, 0.72)
	detail.add_child(_info)
	var ing_scroll := ScrollContainer.new()
	ing_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ing_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ing_scroll.add_child(_ings)
	detail.add_child(ing_scroll)
	var counts := HBoxContainer.new()
	counts.add_theme_constant_override("separation", 6)
	for pair in [[1, "×1"], [5, "×5"], [-1, "最多"]]:
		var b := Button.new()
		b.text = pair[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(90, BTN_H)
		var n: int = pair[0]
		b.pressed.connect(func(): _set_n(n))
		b.set_meta("n", n)
		counts.add_child(b)
		_count_btns.append(b)
	detail.add_child(counts)
	_reason.add_theme_color_override("font_color", Color(1, 0.45, 0.35))
	_reason.add_theme_font_size_override("font_size", 20)
	detail.add_child(_reason)
	_craft_btn.text = "合成"
	_craft_btn.custom_minimum_size = Vector2(0, 76)
	_craft_btn.add_theme_font_size_override("font_size", 30)
	_craft_btn.pressed.connect(_on_craft)
	detail.add_child(_craft_btn)
	body.add_child(detail)

	# 底部队列
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 8)
	var ql := Label.new()
	ql.text = "队列"
	qrow.add_child(ql)
	_queue_box.add_theme_constant_override("separation", 6)
	qrow.add_child(_queue_box)
	_queue_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_bar.custom_minimum_size = Vector2(120, 22)
	_queue_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_queue_bar.max_value = 1.0
	_queue_bar.step = 0.0
	_queue_bar.show_percentage = false
	qrow.add_child(_queue_bar)
	v.add_child(qrow)


func _ready() -> void:
	GameState.craft_queue_changed.connect(func():
		if visible:
			_refresh())


func bind(c: Crafting) -> void:
	crafting = c
	crafting.inventory.changed.connect(func():
		if visible:
			_refresh.call_deferred())


## 打开面板。area = null 看全部；传工作站名只看那个工作站的配方。
## station = 工作站所在方块格子，队列和篝火燃料/工具都按它取。
func open(area = null, station = null) -> void:
	_area = area
	_station = station
	visible = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible and crafting:
		_refresh()


func _process(_delta: float) -> void:
	if visible and crafting:
		_queue_bar.value = crafting.progress(_station)


func _set_cat(cat: String) -> void:
	_cat = cat
	_sel = ""
	_refresh()


func _set_n(n: int) -> void:
	_n = n
	_refresh_detail()


## 数量按钮选的是「最多」时，按材料算能做几批
func batch_count() -> int:
	if _sel == "":
		return 1
	return maxi(1, crafting.max_count(_sel)) if _n < 0 else _n


func _refresh() -> void:
	if crafting == null:
		return
	var where: String = "背包" if _area == null else Crafting.AREA_NAMES.get(_area, str(_area))
	_title.text = "合成 · %s" % where
	_refresh_station()
	for b in _tabs.get_children():
		b.button_pressed = b.get_meta("cat") == _cat
		b.visible = not crafting.list(b.get_meta("cat"), _area).is_empty()
	var keys := crafting.list(_cat, _area)
	if keys.is_empty():
		# 当前分类空了就跳到第一个有配方的分类
		for c in Crafting.CATS:
			if not crafting.list(c[0], _area).is_empty():
				_cat = c[0]
				keys = crafting.list(_cat, _area)
				for b in _tabs.get_children():
					b.button_pressed = b.get_meta("cat") == _cat
				break
	if not keys.has(_sel):
		_sel = keys[0] if not keys.is_empty() else ""
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for key in keys:
		var r := crafting.recipe(key)
		var b := BagPanel.make_slot({"id": r.id, "count": int(r.get("count", 1)), "quality": 0}, SLOT, key == _sel)
		b.tooltip_text = str(r.zh)
		b.modulate = Color.WHITE if crafting.can_craft(key) else Color(0.45, 0.45, 0.45)
		b.set_meta("recipe", key)
		if b.icon == null:
			# 没图标的物品显示名字
			b.text = Assets.display_name(r.id)
			b.clip_text = true
			b.add_theme_font_size_override("font_size", 16)
		var k: String = key
		b.pressed.connect(func():
			_sel = k
			_refresh())
		_grid.add_child(b)
	_refresh_detail()
	_refresh_queue()


func _refresh_station() -> void:
	var show: bool = _station != null and _area == "campfire" and crafting != null
	_station_row.visible = show
	if not show:
		return
	var st: Dictionary = crafting.station_state(_station)
	_fuel_btn.text = "燃料：木头 ×%d" % int(st.get("fuel", 0))
	var tool := str(st.get("tool", ""))
	_tool_btn.text = "锅具：%s" % (Assets.display_name(tool) if tool != "" else "无")


func _refresh_detail() -> void:
	for b in _count_btns:
		b.button_pressed = b.get_meta("n") == _n
	for c in _ings.get_children():
		_ings.remove_child(c)
		c.queue_free()
	if _sel == "":
		_name.text = "这里没有能做的东西"
		_info.text = ""
		_reason.text = ""
		_craft_btn.disabled = true
		return
	var r := crafting.recipe(_sel)
	var n := batch_count()
	var out := int(r.get("count", 1))
	_name.text = Assets.display_name(r.id) + (" ×%d" % (out * n) if out * n > 1 else "")
	var area := str(r.get("area", ""))
	var info := "地点：%s   时间：%s" % [Crafting.AREA_NAMES.get(area, area), _secs(crafting.time_of(_sel) * n)]
	if str(r.get("tool", "")) != "":
		info += "\n工具：%s" % Assets.display_name(r.tool)
	_info.text = info
	for ing in crafting.ingredients(_sel, n):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var ic := TextureRect.new()
		ic.texture = Assets.icon(ing.id)
		ic.custom_minimum_size = Vector2(44, 44)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(ic)
		var nm := Label.new()
		nm.text = Assets.display_name(ing.id)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		row.add_child(nm)
		var cnt := Label.new()
		cnt.text = "%d / %d" % [ing.have, ing.need]
		cnt.add_theme_color_override("font_color", Color(0.6, 0.95, 0.5) if ing.have >= ing.need else Color(1, 0.4, 0.32))
		row.add_child(cnt)
		_ings.add_child(row)
	var why := crafting.why_not(_sel, n, _station)
	_reason.text = why
	_craft_btn.disabled = why != ""


func _refresh_queue() -> void:
	for c in _queue_box.get_children():
		_queue_box.remove_child(c)
		c.queue_free()
	var qlist: Array = crafting.queue_for(_station)
	for i in GameConfig.CRAFT_QUEUE_MAX:
		var s := {}
		if i < qlist.size():
			var q: Dictionary = qlist[i]
			var r := crafting.recipe(q.key)
			s = {"id": r.get("id", ""), "count": (int(q.n) - int(q.done)) * int(r.get("count", 1)), "quality": 0}
		var b := BagPanel.make_slot(s, 72.0, i == 0 and not s.is_empty())
		var idx := i
		if not s.is_empty():
			b.tooltip_text = "点一下取消，退还材料"
			b.pressed.connect(func(): crafting.cancel(idx, _station))
		_queue_box.add_child(b)
	_queue_bar.value = crafting.progress(_station)


func _on_craft() -> void:
	if _sel == "":
		return
	var n := batch_count()
	if crafting.craft(_sel, n, _station):
		var r := crafting.recipe(_sel)
		if crafting.hud:
			crafting.hud.toast("开始合成：%s ×%d" % [Assets.display_name(r.id), n * int(r.get("count", 1))])
	_refresh()


static func _secs(t: float) -> String:
	return "%.0f 秒" % t if t < 60.0 else "%d 分 %02d 秒" % [int(t) / 60, int(t) % 60]
