class_name ScopeOverlay
extends ColorRect
## 高倍镜开镜时盖在 3D 画面上：圆形镜筒 + 十字准星，中间透明。

var _mat: ShaderMaterial


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.TRANSPARENT
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://scripts/ui/scope.gdshader")
	material = _mat
	visible = false
	_update_aspect()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_aspect()


func _update_aspect() -> void:
	if _mat and size.y > 0.0:
		_mat.set_shader_parameter("aspect", size.x / size.y)
