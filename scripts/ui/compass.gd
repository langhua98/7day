class_name Compass
extends Control
## 屏幕顶部的方向条：N/E/S/W、刻度和睡袋/尸体背包标记。

const RANGE_DEG := 90.0
var heading := 0.0   # 玩家朝向的角度：0 北，90 东
var markers: Array = []
var font: Font
var _bg := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(720, 44)
	_bg.bg_color = Color(0.02, 0.02, 0.02, 0.42)
	_bg.border_color = Color(1, 1, 1, 0.12)
	_bg.set_border_width_all(1)
	_bg.set_corner_radius_all(12)


func set_data(yaw: float, new_markers: Array) -> void:
	heading = -rad_to_deg(yaw)
	markers = new_markers
	queue_redraw()


func relative_angle(bearing: float) -> float:
	return fposmod(bearing - heading + 180.0, 360.0) - 180.0


func _x_for(rel: float) -> float:
	var half := size.x * 0.5 - 24.0
	return size.x * 0.5 + clampf(rel / RANGE_DEG, -1.0, 1.0) * half


func _draw() -> void:
	draw_style_box(_bg, Rect2(Vector2.ZERO, size))
	if font == null:
		return
	var names := {0: "N", 90: "E", 180: "S", 270: "W",
		45: "NE", 135: "SE", 225: "SW", 315: "NW"}
	for bearing in range(0, 360, 15):
		var rel := relative_angle(float(bearing))
		if absf(rel) > RANGE_DEG:
			continue
		var x := _x_for(rel)
		var major: bool = bearing % 90 == 0
		draw_line(Vector2(x, size.y - 10.0), Vector2(x, size.y - 4.0),
			Color(1, 1, 1, 0.55 if major else 0.28), 2.0 if major else 1.0)
		if names.has(bearing):
			draw_string(font, Vector2(x - 24.0, size.y - 14.0), names[bearing],
				HORIZONTAL_ALIGNMENT_CENTER, 48.0, 18, Color(0.95, 0.92, 0.85, 0.95))
	for m in markers:
		var rel := relative_angle(float(m.get("bearing", 0.0)))
		if absf(rel) > RANGE_DEG:
			continue
		var x := _x_for(rel)
		var col: Color = m.get("color", Color.WHITE)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 5, 2), Vector2(x + 5, 2), Vector2(x, 10)]), col)
	draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.5 - 4, 0), Vector2(size.x * 0.5 + 4, 0),
		Vector2(size.x * 0.5, 7)]), Color(1, 0.85, 0.45, 0.95))
