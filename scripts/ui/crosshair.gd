class_name Crosshair
extends Control
## 四条短线加中点的准星；开枪时四线向外弹开再回收。

const BASE_GAP := 7.0
const LINE_LEN := 10.0
const LINE_W := 2.4

var gap := BASE_GAP:
	set(value):
		gap = value
		queue_redraw()
var color := Color(1, 1, 1, 0.75):
	set(value):
		color = value
		queue_redraw()
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(64, 64)


func _draw() -> void:
	var c := size * 0.5
	var g := gap
	var e := g + LINE_LEN
	draw_line(c + Vector2(0, -g), c + Vector2(0, -e), color, LINE_W, true)
	draw_line(c + Vector2(0, g), c + Vector2(0, e), color, LINE_W, true)
	draw_line(c + Vector2(-g, 0), c + Vector2(-e, 0), color, LINE_W, true)
	draw_line(c + Vector2(g, 0), c + Vector2(e, 0), color, LINE_W, true)
	draw_circle(c, LINE_W * 1.15, color)


func set_state(low: bool, empty: bool) -> void:
	color = Color(1.0, 0.25, 0.2, 0.95) if empty else (
		Color(1.0, 0.65, 0.2, 0.9) if low else Color(1, 1, 1, 0.75))


func kick() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	gap = 13.0
	_tween = create_tween()
	_tween.tween_property(self, "gap", BASE_GAP, 0.14)
