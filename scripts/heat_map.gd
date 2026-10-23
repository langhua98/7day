class_name HeatMap
extends RefCounted
## 热量（官方 heat map 简化）：世界按 32 米分格累计热量，到 100 在附近刷一只尖叫者并清零。
## 开枪 +1/次（订阅 GameState.noise 的枪声），合成、篝火每秒通过 GameState.heat 加；每游戏小时衰减 30%。

const C = preload("res://scripts/config.gd")
const GUN_KINDS := ["pistol", "rifle", "shotgun", "explosion"]

## 某格热量满了：spawner 在这里刷尖叫者
signal overflow(center: Vector3)

var cells := {}   # Vector2i → 热量


func connect_signals() -> void:
	if not GameState.noise.is_connected(_on_noise):
		GameState.noise.connect(_on_noise)
		GameState.heat.connect(_on_heat)
		GameState.hour_changed.connect(_on_hour)


func reset() -> void:
	cells.clear()


func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / C.HEAT_CELL), floori(pos.z / C.HEAT_CELL))


func value_at(pos: Vector3) -> float:
	return float(cells.get(cell_of(pos), 0.0))


func add(pos: Vector3, amount: float) -> void:
	var k := cell_of(pos)
	var v: float = float(cells.get(k, 0.0)) + amount * C.TEST_HEAT_MULT
	if v >= C.HEAT_SCREAMER:
		cells.erase(k)
		overflow.emit(pos)
	else:
		cells[k] = v


func _on_noise(pos: Vector3, _radius: float, kind: String) -> void:
	if kind in GUN_KINDS:
		add(pos, C.HEAT.shot)


func _on_heat(pos: Vector3, amount: float, _kind: String) -> void:
	add(pos, amount)


func _on_hour(_day: int, _hour: float) -> void:
	for k in cells.keys():
		var v: float = cells[k] * (1.0 - C.HEAT_DECAY_PER_HOUR)
		if v < 0.5:
			cells.erase(k)
		else:
			cells[k] = v


func save_data() -> Dictionary:
	var out := {}
	for k in cells:
		out["%d,%d" % [k.x, k.y]] = cells[k]
	return out


func load_data(d: Dictionary) -> void:
	cells.clear()
	for key in d:
		var p := String(key).split(",")
		if p.size() == 2:
			cells[Vector2i(int(p[0]), int(p[1]))] = float(d[key])
