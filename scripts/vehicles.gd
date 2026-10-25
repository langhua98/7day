class_name Vehicles
extends RefCounted
## 载具管理：从背包摆车、上下车、驾驶输入、存档。

const C = preload("res://scripts/config.gd")

var main: Node3D
var world: World
var player_sys: PlayerSystem
var inventory: InventorySystem
var hud: Hud
var rng: RandomNumberGenerator
var root := Node3D.new()
var list: Array[Vehicle] = []
## 正开着车：current 是那辆，玩家位置/朝向每帧跟着它
var driving := false
var current: Vehicle = null


func setup(parent: Node3D, world_ref: World, player_ref: PlayerSystem, inv_ref: InventorySystem,
		hud_ref: Hud, rng_ref: RandomNumberGenerator) -> void:
	main = parent
	world = world_ref
	player_sys = player_ref
	inventory = inv_ref
	hud = hud_ref
	rng = rng_ref


func build() -> void:
	root.name = "Vehicles"
	main.add_child(root)


func reset() -> void:
	if driving and player_sys:
		player_sys.end_driving()
	driving = false
	current = null
	for v in list:
		if v.node and is_instance_valid(v.node):
			v.node.queue_free()
	list.clear()
	if hud:
		hud.set_driving(false)
		hud.set_speed(0.0)


func count() -> int:
	return list.size()


## 离玩家最近、够得着的载具（没有返回 null）
func nearest(pos: Vector3) -> Vehicle:
	var best: Vehicle = null
	var best_d := INF
	for v in list:
		var d := Vector2(v.pos.x - pos.x, v.pos.z - pos.z).length()
		if d <= C.VEHICLE_MOUNT_DIST + v.radius * 0.5 and d < best_d:
			best_d = d
			best = v
	return best


## 准星前面的落点（摆载具时的预览框）。放不下返回空字典
func preview(item_id: String) -> Dictionary:
	if not C.VEHICLES.has(item_id) or list.size() >= C.VEHICLE_LIMIT:
		return {}
	var eye: Vector3 = player_sys.camera.global_position
	var dir: Vector3 = -player_sys.camera.global_basis.z
	var hit := Vector3.ZERO
	var found := false
	var t := 0.0
	while t < C.BUILD_REACH:
		t += 0.25
		var p := eye + dir * t
		if p.y < 0.0:
			p.y = 0.0
			hit = p
			found = true
			break
		if world.solid_at(p):
			hit = p
			found = true
			break
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.01:
		flat = Vector3(0.0, 0.0, -1.0)
	flat = flat.normalized()
	if not found:
		hit = player_sys.player.position + flat * (C.VEHICLE_PLACE_DIST + 2.0)
	var at := Vector3(hit.x, 0.0, hit.z)
	at.y = world.floor_under(at + Vector3.UP * 0.4, 0.5)
	var mine := Vector2(at.x - player_sys.player.position.x, at.z - player_sys.player.position.z).length()
	if mine < C.VEHICLE_PLACE_DIST:
		return {}
	var r := float(C.VEHICLES[item_id].get("radius", 1.2))
	if world.blocked(at, r * 0.8):
		return {}
	return {"pos": at, "rot": player_sys.yaw, "radius": r}


## 摆一辆（测试和读档也走这里）。到上限返回 null
func place(item_id: String, at: Vector3, yaw: float) -> Vehicle:
	if not C.VEHICLES.has(item_id):
		return null
	if list.size() >= C.VEHICLE_LIMIT:
		if hud:
			hud.toast("载具到上限了（%d 辆）" % C.VEHICLE_LIMIT)
		return null
	var v := Vehicle.new()
	v.setup(world, item_id, at, yaw)
	if v.node:
		root.add_child(v.node)
	list.append(v)
	return v


## 拿着载具物品点开火：在准星前面摆一辆，正式模式扣一个
func place_from_item() -> bool:
	var id := inventory.equipped
	if not C.VEHICLES.has(id):
		return false
	if int(inventory.inventory.get(id, 0)) <= 0:
		return false
	var pv := preview(id)
	if pv.is_empty():
		hud.toast("这里放不下：找块空地，离自己远一点")
		return false
	var v := place(id, pv.pos, float(pv.rot))
	if v == null:
		return false
	if not C.TEST_INFINITE:
		inventory.remove(id, 1)
		if int(inventory.inventory.get(id, 0)) <= 0 and inventory.equipped == id:
			inventory.equip("")
		inventory.refresh()
	hud.toast("摆好了%s，走近点「驾驶」" % Assets.display_name(id))
	return true


func try_mount() -> bool:
	if driving:
		return false
	var v := nearest(player_sys.player.position)
	if v == null:
		return false
	current = v
	driving = true
	v.speed = 0.0
	player_sys.player.position = v.pos
	player_sys.yaw = v.rot
	player_sys.player.rotation.y = v.rot
	player_sys.begin_driving()
	hud.set_driving(true)
	hud.set_speed(0.0)
	return true


func exit_vehicle() -> void:
	if not driving or current == null:
		return
	var v := current
	driving = false
	current = null
	v.speed = 0.0
	var basis := Basis(Vector3.UP, v.rot)
	var at := v.pos
	var placed := false
	for off: Vector3 in [Vector3(v.radius + 1.0, 0.0, 0.0), Vector3(-v.radius - 1.0, 0.0, 0.0),
			Vector3(0.0, 0.0, v.radius + 1.4), Vector3(0.0, 0.0, -v.radius - 1.4)]:
		var p: Vector3 = v.pos + basis * off
		if not world.blocked(p, 0.4):
			at = p
			placed = true
			break
	if not placed:
		at = world.push_out(v.pos + basis * Vector3(v.radius + 1.0, 0.0, 0.0), 0.4)
	player_sys.player.position = Vector3(at.x, world.floor_under(at + Vector3.UP * 0.3, 0.35), at.z)
	player_sys.yaw = v.rot
	player_sys.player.rotation.y = v.rot
	player_sys.end_driving()
	hud.set_driving(false)
	hud.set_speed(0.0)


## 驾驶中每帧：车往前开，玩家跟着车
func update(delta: float) -> void:
	if not driving or current == null:
		return
	current.update(delta, hud.move.x, hud.drive.y)
	player_sys.player.position = current.pos
	player_sys.yaw = current.rot
	player_sys.player.rotation.y = current.rot
	player_sys.update_driving(delta)
	hud.set_speed(current.speed_kmh())


func save_data() -> Dictionary:
	var arr := []
	for v in list:
		arr.append(v.save_state())
	return {"vehicles": arr}


func load_data(d: Dictionary) -> void:
	reset()
	for e in d.get("vehicles", []):
		if not (e is Dictionary):
			continue
		var p = e.get("pos", [])
		if not (p is Array) or p.size() < 3:
			continue
		var id := str(e.get("id", ""))
		if not C.VEHICLES.has(id):
			continue
		place(id, Vector3(float(p[0]), float(p[1]), float(p[2])), float(e.get("rot", 0.0)))
