class_name RespawnSystem
extends RefCounted
## 死亡与重生（3c）：睡袋、死后黑屏、在睡袋或出生点醒来、尸体背包、濒死创伤、存活天数 −2。
## C.PERMADEATH = true 时不走这里，main.gd 用老的「死了就结算」。

const C = preload("res://scripts/config.gd")
const BEDROLL_MODEL := "res://assets/world/bedroll.obj"
const BEDROLL_TEX := "res://assets/world/bedroll.png"

var main: Node3D
var world: World
var player_sys: PlayerSystem
var inventory: InventorySystem
var looting: LootingSystem
var hud: Hud
## 出生点（没有睡袋时在这里醒来）
var spawn_point := Vector3.ZERO
## 睡袋：{pos, yaw, node}，没有是空字典
var bedroll := {}
## 正在黑屏（死了还没醒）
var dying := false
var _marker_t := 0.0


func setup(parent: Node3D, world_ref: World, player_ref: PlayerSystem, inv_ref: InventorySystem,
		looting_ref: LootingSystem, hud_ref: Hud) -> void:
	main = parent
	world = world_ref
	player_sys = player_ref
	inventory = inv_ref
	looting = looting_ref
	hud = hud_ref


func build() -> void:
	GameState.bedroll_placed.connect(place_bedroll)


func reset() -> void:
	_remove_bedroll()
	dying = false
	GameState.days_alive_lost = 0
	if hud:
		hud.set_bag_marker(0.0, -1.0)
		if hud.blackout_visible():
			hud.set_blackout(false)


## 开局：测试模式背包里给一个睡袋
func on_start(fresh: bool) -> void:
	if fresh and C.TEST_ALL_ITEMS and Assets.items_by_id.has(C.BEDROLL_ID) and not inventory.has(C.BEDROLL_ID):
		inventory.add(C.BEDROLL_ID, 1)


# —— 睡袋 ——

func has_bedroll() -> bool:
	return not bedroll.is_empty()


## 摆睡袋：同时只能有一个，摆新的旧的消失
func place_bedroll(pos: Vector3, yaw: float, quiet := false) -> void:
	var had := has_bedroll()
	_remove_bedroll()
	bedroll = {"pos": pos, "yaw": yaw, "node": _bedroll_node(pos, yaw)}
	main.add_child(bedroll.node)
	if not quiet:
		hud.toast("睡袋摆好了，旧的那个没了" if had else "睡袋摆好了：死了会在这里醒来")


func _remove_bedroll() -> void:
	if bedroll.get("node") and is_instance_valid(bedroll.node):
		bedroll.node.queue_free()
	bedroll = {}


## 睡袋的样子：有云盘模型（tools/fetch_assets.py 从 respawnpoints.zip 取）就用，没有先用墨绿色扁方块
func _bedroll_node(pos: Vector3, yaw: float) -> Node3D:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = yaw
	var mi := MeshInstance3D.new()
	var mesh: Mesh = load(BEDROLL_MODEL) if ResourceLoader.exists(BEDROLL_MODEL) else null
	if mesh:
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if ResourceLoader.exists(BEDROLL_TEX):
			mat.albedo_texture = load(BEDROLL_TEX)
		else:
			mat.albedo_color = Blocks.info(C.BEDROLL_ID).get("color", Color.DARK_OLIVE_GREEN)
		mi.material_override = mat
		# 模型单位不一定是米：按最长边缩到 2 米，底部贴地
		var box := mesh.get_aabb()
		var longest := maxf(box.size.x, box.size.z)
		var s := 2.0 / longest if longest > 0.01 else 1.0
		mi.scale = Vector3.ONE * s
		mi.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * s
	else:
		var b := BoxMesh.new()
		b.size = Vector3(0.8, 0.12, 1.9)
		mi.mesh = b
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Blocks.info(C.BEDROLL_ID).get("color", Color.DARK_OLIVE_GREEN)
		mi.material_override = mat
		mi.position.y = 0.06
	holder.add_child(mi)
	var label := Label3D.new()
	label.text = "睡袋"
	label.font = Hud.game_font()
	label.font_size = 32
	label.outline_size = 10
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 0.6
	label.visibility_range_end = 10.0
	holder.add_child(label)
	return holder


## 醒来的位置：睡袋，没有就在出生点
func respawn_point() -> Vector3:
	return bedroll.pos if has_bedroll() else spawn_point


# —— 死亡 ——

## 死了：东西变成尸体背包留在原地，存活天数 −2，黑屏 2 秒后醒来。
## main.gd 在这之前停住游戏，收到 player_respawned 再恢复
func die() -> void:
	if dying:
		return
	dying = true
	var pos := player_sys.player.position
	var items := inventory.take_all()
	if not items.is_empty():
		looting.add_corpse_bag(pos, items)
	inventory.refresh()
	GameState.lose_days_alive(C.DAYS_ALIVE_LOST_ON_DEATH)
	GameState.player_died.emit(pos)
	Status.clear()
	Status.add("near_death_trauma")
	var at := respawn_point()
	player_sys.revive(at, C.RESPAWN_STATS)
	Sfx.play("death")
	hud.set_blackout(true, "你死了")
	main.get_tree().create_timer(C.DEATH_BLACKOUT).timeout.connect(respawn_now)


## 黑屏结束：只负责揭开黑屏；复活数值在 die() 里已经结算
func respawn_now() -> void:
	if not dying:
		return
	dying = false
	hud.set_blackout(false)
	hud.toast("你死了，在睡袋醒来" if has_bedroll() else "你死了，在出生点醒来（没有睡袋）")
	GameState.player_respawned.emit(player_sys.player.position)


## 每帧：HUD 上指向最近的尸体背包（每秒更新 10 次就够）
func update(delta: float) -> void:
	_marker_t -= delta
	if _marker_t > 0.0:
		return
	_marker_t = 0.1
	var me := player_sys.player
	var best := {}
	var best_d := INF
	for b in looting.corpse_bags:
		var d: float = me.position.distance_to(b.pos)
		if d < best_d:
			best_d = d
			best = b
	if best.is_empty():
		hud.set_bag_marker(0.0, -1.0)
		return
	var to: Vector3 = best.pos - me.position
	var fwd := -me.global_basis.z
	var right := me.global_basis.x
	hud.set_bag_marker(atan2(to.dot(right), to.dot(fwd)), best_d)


# —— 存档：睡袋位置、存活天数扣了多少（尸体背包在 looting，濒死创伤在 Status） ——

func save_data() -> Dictionary:
	var d := {"days_alive_lost": GameState.days_alive_lost}
	if has_bedroll():
		d["bedroll"] = [bedroll.pos.x, bedroll.pos.y, bedroll.pos.z, bedroll.yaw]
	return d


func load_data(d: Dictionary) -> void:
	_remove_bedroll()
	GameState.days_alive_lost = int(d.get("days_alive_lost", 0))
	var b = d.get("bedroll")
	if b is Array and b.size() >= 4:
		place_bedroll(Vector3(float(b[0]), float(b[1]), float(b[2])), float(b[3]), true)
