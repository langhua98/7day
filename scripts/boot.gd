extends Control
## 开局载入页：先显示背景/logo，主场景准备好后再显示标题页。

var _overlay := Control.new()
var _status := Label.new()
var _bar := ProgressBar.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = Hud.game_font()
	theme.default_font_size = 24
	self.theme = theme

	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.025, 0.025, 0.03, 1.0)
	_overlay.add_child(bg)
	if ResourceLoader.exists("res://assets/ui/background.png"):
		var tr := TextureRect.new()
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.texture = load("res://assets/ui/background.png")
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_overlay.add_child(tr)

	_overlay.add_child(_logo())

	var title := Label.new()
	title.text = "七日杀 · 口袋版"
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.position = Vector2(-350, -80)
	title.size = Vector2(700, 100)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.9, 0.25, 0.18))
	_overlay.add_child(title)

	_status.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status.position = Vector2(-400, -170)
	_status.size = Vector2(800, 40)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_color", Color(0.92, 0.9, 0.82, 0.85))
	_overlay.add_child(_status)

	_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.position = Vector2(-220, -110)
	_bar.size = Vector2(440, 14)
	_bar.max_value = 1.0
	_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.75, 0.2, 0.12)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.55)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	_overlay.add_child(_bar)

	_status.text = "正在准备素材…"
	_bar.value = 0.08
	_boot.call_deferred()


func _logo() -> Control:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_CENTER)
	holder.position = Vector2(-260, -330)
	holder.size = Vector2(520, 220)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://assets/ui/7DTD_logo.png"):
		var tr := TextureRect.new()
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.texture = load("res://assets/ui/7DTD_logo.png")
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		holder.add_child(tr)
	return holder


func _boot() -> void:
	await get_tree().process_frame
	_status.text = "正在读取素材…"
	_bar.value = 0.25
	await get_tree().process_frame
	_status.text = "正在生成城市…"
	_bar.value = 0.5
	await get_tree().process_frame
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	add_child(main)
	_status.text = "正在准备界面…"
	_bar.value = 0.82
	await get_tree().process_frame
	await get_tree().process_frame
	_bar.value = 1.0
	_status.text = "完成"
	await get_tree().create_timer(0.15).timeout
	_overlay.queue_free()
