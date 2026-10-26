class_name TraderPanel
extends PanelContainer
## 7c 商人面板：买 / 卖两页，物品网格、数量、价格、确定。

const SLOT := 84.0
const BTN_H := 60.0

var trader: TraderSystem
var quests: QuestSystem
var _buy := true
var _sel := ""
var _n := 1
var _title := Label.new()
var _coins := Label.new()
var _tabs := HBoxContainer.new()
var _grid := GridContainer.new()
var _name := Label.new()
var _info := Label.new()
var _qty := HBoxContainer.new()
var _confirm := Button.new()
var _buy_btn := Button.new()
var _sell_btn := Button.new()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 70
	offset_right = -70
	offset_top = 24
	offset_bottom = -24
	visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.065, 0.96)
	sb.border_color = Color(0.6, 0.55, 0.45, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	_title.text = "商人"
	_title.add_theme_font_size_override("font_size", 30)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_coins.add_theme_font_size_override("font_size", 22)
	_coins.modulate = Color(1.0, 0.86, 0.45)
	head.add_child(_coins)
	var quest_btn := Button.new()
	quest_btn.text = "任务"
	quest_btn.custom_minimum_size = Vector2(118, BTN_H)
	quest_btn.focus_mode = Control.FOCUS_NONE
	quest_btn.pressed.connect(func():
		if quests != null:
			quests.hud.quest_panel.open())
	head.add_child(quest_btn)
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(118, BTN_H)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): visible = false)
	head.add_child(close)
	v.add_child(head)

	_buy_btn.text = "买"
	_sell_btn.text = "卖"
	for b in [_buy_btn, _sell_btn]:
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, BTN_H)
		b.focus_mode = Control.FOCUS_NONE
		_tabs.add_child(b)
	_buy_btn.pressed.connect(func(): _set_tab(true))
	_sell_btn.pressed.connect(func(): _set_tab(false))
	v.add_child(_tabs)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)
	v.add_child(scroll)

	var detail := HBoxContainer.new()
	detail.add_theme_constant_override("separation", 12)
	var dv := VBoxContainer.new()
	dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.add_theme_font_size_override("font_size", 24)
	dv.add_child(_name)
	_info.add_theme_font_size_override("font_size", 18)
	_info.modulate = Color(1, 1, 1, 0.75)
	dv.add_child(_info)
	detail.add_child(dv)
	_qty.add_theme_constant_override("separation", 4)
	for n in [1, 5, 10]:
		var b := Button.new()
		b.text = str(n)
		b.custom_minimum_size = Vector2(62, BTN_H)
		b.focus_mode = Control.FOCUS_NONE
		b.set_meta("n", n)
		b.pressed.connect(func(): _n = n; _refresh_detail())
		_qty.add_child(b)
	detail.add_child(_qty)
	_confirm.custom_minimum_size = Vector2(220, BTN_H)
	_confirm.add_theme_font_size_override("font_size", 21)
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.pressed.connect(_do_trade)
	detail.add_child(_confirm)
	v.add_child(detail)


func bind(t: TraderSystem) -> void:
	trader = t


func open() -> void:
	visible = true
	_n = 1
	_refresh()


func _set_tab(buy: bool) -> void:
	_buy = buy
	_sel = ""
	_n = 1
	_refresh()


func _refresh() -> void:
	if trader == null:
		return
	_title.text = "商人 · %s" % ("营业中" if trader.open else "休息中")
	_coins.text = "公爵币 %d" % trader.currency_count()
	_buy_btn.button_pressed = _buy
	_sell_btn.button_pressed = not _buy
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var entries: Array = trader.stock if _buy else _sell_list()
	var ids: Array = []
	for e in entries:
		ids.append(str(e.id))
	if not ids.has(_sel):
		_sel = str(ids[0]) if not ids.is_empty() else ""
	for e in entries:
		var id := str(e.id)
		var b := BagPanel.make_slot({"id": id, "count": int(e.count)}, SLOT, id == _sel)
		b.tooltip_text = "%s\n%s %d 公爵币" % [Assets.display_name(id),
			"买价" if _buy else "卖价", trader.buy_price(id) if _buy else trader.sell_price(id)]
		b.set_meta("item", id)
		var key := id
		b.pressed.connect(func():
			_sel = key
			_refresh())
		_grid.add_child(b)
	_refresh_detail()


func _sell_list() -> Array:
	var out := []
	if trader == null:
		return out
	for id in trader.inventory.inventory:
		var n := int(trader.inventory.inventory[id])
		if n <= 0 or id == trader.currency():
			continue
		if int(Data.items.get(id, {}).get("value", 0)) <= 0:
			continue
		out.append({"id": id, "count": n})
	out.sort_custom(func(a, b): return str(Assets.display_name(a.id)) < str(Assets.display_name(b.id)))
	return out


func _refresh_detail() -> void:
	for b in _qty.get_children():
		b.button_pressed = int(b.get_meta("n")) == _n
	if _sel == "":
		_name.text = "没有可以交易的东西"
		_info.text = ""
		_confirm.disabled = true
		return
	var count := trader.stock_count(_sel) if _buy else int(trader.inventory.count(_sel))
	var price := trader.buy_price(_sel) if _buy else trader.sell_price(_sel)
	var total := price * _n
	_name.text = Assets.display_name(_sel)
	_info.text = "%s：%d 公爵币/个   库存/持有：%d   共 %d" % [
		"买价" if _buy else "卖价", price, count, total]
	_confirm.text = ("买 %d 个" if _buy else "卖 %d 个") % _n
	_confirm.disabled = count < _n or (_buy and trader.currency_count() < total)


func _do_trade() -> void:
	if _sel == "" or trader == null:
		return
	var res := trader.buy(_sel, _n) if _buy else trader.sell(_sel, _n)
	if trader.hud:
		trader.hud.toast(str(res.get("text", "")))
	_refresh()
