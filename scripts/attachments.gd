class_name Attachments
## 可拆装的倍镜。目前用程序图标，不依赖素材。

const DEFS := {
	"scope2x": {"zh": "2倍镜", "level": 2},
	"scope4x": {"zh": "4倍镜", "level": 4},
}
const IDS := ["scope2x", "scope4x"]

static var _icons := {}


static func is_scope(id: String) -> bool:
	return DEFS.has(id)


static func label(id: String) -> String:
	return str(DEFS.get(id, {}).get("zh", id))


static func scope_fov(id: String) -> float:
	if id == "scope2x":
		return GameConfig.SCOPE_FOV_RIFLE
	if id == "scope4x":
		return GameConfig.SCOPE_FOV_SNIPER
	return GameConfig.AIM_FOV


static func icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var center := Vector2(32, 32)
	for y in 64:
		for x in 64:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if d <= 22.0:
				img.set_pixel(x, y, Color(0.12, 0.12, 0.13, 1.0) if d > 15.0 else Color(0.03, 0.03, 0.035, 1.0))
			elif d <= 26.0:
				img.set_pixel(x, y, Color(0.55, 0.5, 0.38, 1.0))
	var tex := ImageTexture.create_from_image(img)
	_icons[id] = tex
	return tex
