class_name CombatSystem
extends Node
## 战斗：近战、枪械、换弹、爆炸、打方块和摆放方块。

const C = preload("res://scripts/config.gd")

var main: Node3D
var tree: SceneTree
var player_sys: PlayerSystem
var inventory: InventorySystem
var world: World
var hud: Hud
var arms: FpArms
var zombie_root: Node3D
var rng: RandomNumberGenerator
var running := false

var attack_cd := 0.0
var _reload_left := 0.0
## 拿着方块时准星指的那一格，显示一个半透明的框
var _ghost: MeshInstance3D


func setup(parent: Node3D, tree_ref: SceneTree, player_ref: PlayerSystem, inv_ref: InventorySystem,
		world_ref: World, hud_ref: Hud, arms_ref: FpArms, zombies_ref: Node3D,
		rng_ref: RandomNumberGenerator) -> void:
	main = parent
	tree = tree_ref
	player_sys = player_ref
	inventory = inv_ref
	world = world_ref
	hud = hud_ref
	arms = arms_ref
	zombie_root = zombies_ref
	rng = rng_ref


func build() -> void:
	_ghost = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 1.02
	_ghost.mesh = box
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(1, 1, 1, 0.22)
	_ghost.material_override = gm
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	main.add_child(_ghost)


func reset() -> void:
	attack_cd = 0.0
	_reload_left = 0.0
	_ghost.visible = false


func on_equip() -> void:
	_reload_left = 0.0


func update(delta: float) -> void:
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
	_update_ammo_hud()
	_update_ghost()

	attack_cd = max(0.0, attack_cd - delta)
	if hud.attack_held and attack_cd <= 0.0:
		attack()


func attack() -> void:
	hud.crosshair_kick()
	var row: Dictionary = Assets.items_by_id.get(inventory.equipped, {})
	var kind: int = row.get("kind", -1)
	if kind == Assets.Kind.GUN:
		_fire(row)
		return
	if kind == Assets.Kind.BLOCK:
		_place_block()
		return
	attack_cd = C.MELEE_COOLDOWN
	arms.swing(1.0 / C.MELEE_COOLDOWN * 0.9)
	Sfx.play("swing" if kind == Assets.Kind.MELEE else "swing_fist", Vector3.INF, -4.0)
	GameState.noise.emit(player_sys.player.global_position, 8.0, "melee")
	var dmg: float = row.get("power", C.FIST_DAMAGE) if kind == Assets.Kind.MELEE else C.FIST_DAMAGE
	if kind == Assets.Kind.MELEE:
		dmg *= Weapons.quality_mult(int(inventory.qualities.get(inventory.equipped, 1)))
	# 伤害在武器挥到准星前面时才算（和手臂动作对上，见 fp_arms.gd 的关键帧）
	var item := inventory.equipped
	await tree.create_timer(C.MELEE_COOLDOWN * 0.42).timeout
	if not running or inventory.equipped != item:
		return
	var aim := -player_sys.camera.global_basis.z
	var flat_aim := Vector3(aim.x, 0, aim.z).normalized()
	var best: Zombie = null
	var best_d := INF
	for z in zombie_root.get_children():
		if z.dead:
			continue
		var to: Vector3 = z.global_position - player_sys.player.global_position
		to.y = 0
		var d := to.length()
		if d > C.MELEE_RANGE or d < 0.001:
			continue
		if flat_aim.dot(to / d) < 0.6 and d > 0.9:
			continue
		if d < best_d:
			best_d = d
			best = z
	if best:
		# 近战往上瞄着打算爆头
		var head := player_sys.pitch > 0.12
		_hit_zombie(best, dmg * (C.HEADSHOT_MULT if head else 1.0), head,
			best.global_position + Vector3.UP * (best.height() * (0.88 if head else 0.6)), flat_aim)
	else:
		_hit_block(dmg)


## 准星指着的地方：{hit: 方块格子或 null, place: 能摆的那一格}
func _aim_block(reach: float) -> Dictionary:
	return world.ray_voxel(player_sys.camera.global_position, -player_sys.camera.global_basis.z, reach)


## 这一格会不会卡住自己或者僵尸
func _cell_occupied(c: Vector3i) -> bool:
	var box := AABB(Vector3(c), Vector3.ONE)
	var me := AABB(player_sys.player.position + Vector3(-0.3, 0.0, -0.3), Vector3(0.6, 1.8, 0.6))
	if box.intersects(me):
		return true
	for z in zombie_root.get_children():
		if z.dead:
			continue
		var zb := AABB(z.global_position + Vector3(-0.3, 0.0, -0.3), Vector3(0.6, 1.8, 0.6))
		if box.intersects(zb):
			return true
	return false


func _place_target() -> Variant:
	var aim := _aim_block(C.BUILD_REACH)
	if aim.is_empty():
		return null
	var c: Vector3i = aim.place
	if not world.can_place(c) or _cell_occupied(c):
		return null
	return c


func _update_ghost() -> void:
	var row: Dictionary = Assets.items_by_id.get(inventory.equipped, {})
	var c = _place_target() if row.get("kind", -1) == Assets.Kind.BLOCK else null
	_ghost.visible = c != null
	if c != null:
		_ghost.position = Vector3(c) + Vector3.ONE * 0.5


func _place_block() -> void:
	attack_cd = C.BUILD_COOLDOWN
	if inventory.inventory.get(inventory.equipped, 0) <= 0:
		return
	var c = _place_target()
	if c == null:
		return
	world.add_voxel(c, inventory.equipped)
	GameState.block_changed.emit(c)
	arms.swing(6.0)
	Sfx.play("land", Vector3(c) + Vector3.ONE * 0.5, -4.0)
	if not C.TEST_INFINITE:
		inventory.remove(inventory.equipped)
		inventory.refresh()


## 空手或近战打到方块：扣耐久，打碎了方块回到背包
func _hit_block(dmg: float) -> void:
	var aim := _aim_block(C.MELEE_RANGE + 0.6)
	if aim.is_empty() or aim.hit == null:
		return
	var c: Vector3i = aim.hit
	var at := player_sys.camera.global_position - player_sys.camera.global_basis.z * float(aim.t)
	Fx.impact(main, at + player_sys.camera.global_basis.z * 0.05, player_sys.camera.global_basis.z)
	Sfx.play("bullet_wall", at, -4.0)
	var got := world.damage_voxel(c, dmg)
	GameState.block_changed.emit(c)
	if got != "":
		if not C.TEST_INFINITE:
			inventory.add(got)
			inventory.refresh()
		hud.toast("拆掉了%s" % Assets.display_name(got))
	else:
		var vox = world.voxels.get(c)
		if vox:
			hud.toast("%s 耐久 %d%%" % [Assets.display_name(vox.id), int(world.voxel_health(c) * 100.0)])


## 开枪：每颗弹丸从镜头沿准星方向射出，先打中的是僵尸还是墙
func _fire(row: Dictionary) -> void:
	var st := Weapons.stats(inventory.equipped).duplicate()
	if _reload_left > 0.0:
		return
	var left: int = inventory.mags.get(inventory.equipped, 0)
	if left <= 0:
		attack_cd = 0.35
		Sfx.play("empty")
		if Weapons.ammo_count(inventory.inventory, inventory.equipped) > 0 or C.TEST_INFINITE:
			reload()
		else:
			hud.toast("没子弹了，翻翻警车和武器包")
		return
	inventory.mags[inventory.equipped] = left - 1
	var ammo_id: String = inventory.mags_type.get(inventory.equipped, "")
	var mods := Weapons.ammo_mods(ammo_id)
	st.damage = float(st.damage) * float(mods.get("entity", 1.0))
	st.damage *= Weapons.quality_mult(int(inventory.qualities.get(inventory.equipped, 1)))
	if player_sys.aiming:
		st.spread = float(st.spread) * 0.5
	attack_cd = st.rate
	arms.swing(7.0)
	Fx.muzzle(arms, arms.muzzle_position())
	Sfx.play(st.fire_snd, Vector3.INF, -2.0, 0.05)
	Input.vibrate_handheld(20)
	GameState.noise.emit(player_sys.player.global_position, 45.0, "gun")
	var kick: float = 0.012 + st.damage * 0.0004 * st.pellets
	player_sys.add_recoil(kick)
	player_sys.pitch = clampf(player_sys.pitch + kick * C.RECOIL_AIM_SHARE, -1.3, 1.3)
	var eye := player_sys.camera.global_position
	var aim := -player_sys.camera.global_basis.z
	for p in st.pellets:
		var dir := (aim + player_sys.camera.global_basis.x * rng.randfn(0.0, st.spread) + player_sys.camera.global_basis.y * rng.randfn(0.0, st.spread)).normalized()
		_shoot_ray(eye, dir, st)


func _shoot_ray(eye: Vector3, dir: Vector3, st: Dictionary) -> void:
	var reach: float = st.range
	# 墙：沿射线每 0.25 米查一次楼的占地图；地面：y < 0
	var wall_t := reach
	var t := 0.5
	while t < reach:
		var p := eye + dir * t
		if p.y < 0.0 or (p.y < 30.0 and world.line_blocked(p, p)):
			wall_t = t
			break
		if world.blocked(Vector3(p.x, 0, p.z), 0.0) and p.y < 1.4:
			wall_t = t   # 车、箱子这种矮的东西
			break
		if world.has_voxel(World.cell_of(p)):
			wall_t = t   # 自己摆的方块
			break
		t += 0.25
	# 僵尸：当成竖着的胶囊
	var best: Zombie = null
	var best_t := wall_t
	var best_y := 0.0
	for z in zombie_root.get_children():
		if z.dead:
			continue
		var zp: Vector3 = z.global_position
		var oc := Vector2(zp.x - eye.x, zp.z - eye.z)
		var d2 := Vector2(dir.x, dir.z)
		var dd := d2.length_squared()
		if dd < 1e-6:
			continue
		var tt := oc.dot(d2) / dd
		if tt <= 0.0 or tt >= best_t:
			continue
		var miss := (Vector2(eye.x, eye.z) + d2 * tt - Vector2(zp.x, zp.z)).length()
		var y := eye.y + dir.y * tt
		if miss < 0.38 and y > zp.y + 0.1 and y < zp.y + z.height() * 1.02:
			best = z
			best_t = tt
			best_y = y
	var hit := eye + dir * best_t
	if st.blast > 0.0:
		_explode(hit, st)
		return
	if best:
		var head := best_y > best.head_height() - 0.12
		_hit_zombie(best, st.damage * (C.HEADSHOT_MULT if head else 1.0), head, hit, dir)
	elif best_t < reach:
		Fx.impact(main, hit - dir * 0.05, -dir)
		if best_t < 25.0:
			Sfx.play("bullet_wall", hit, -6.0)


func _explode(at: Vector3, st: Dictionary) -> void:
	Sfx.play("explosion", at, 6.0)
	Fx.impact(main, at, Vector3.UP)
	Fx.blood(main, at, Vector3.UP, true)
	for z in zombie_root.get_children():
		if z.dead:
			continue
		var d: float = z.global_position.distance_to(Vector3(at.x, 0, at.z))
		if d < st.blast:
			_hit_zombie(z, st.damage * (1.0 - d / st.blast * 0.6), false, z.global_position + Vector3.UP, (z.global_position - at).normalized())
	if player_sys.player.position.distance_to(Vector3(at.x, 0, at.z)) < st.blast * 0.6:
		player_sys.take_damage(25.0, "explosion")


func _hit_zombie(z: Zombie, dmg: float, head: bool, at: Vector3, dir: Vector3) -> void:
	z.take_hit(dmg, player_sys.player.global_position, head)
	Fx.blood(main, at, dir.normalized() + Vector3.UP * 0.2, head)
	var gun: bool = Assets.items_by_id.get(inventory.equipped, {}).get("kind", -1) == Assets.Kind.GUN
	Sfx.play("bullet_flesh" if gun else "hit_flesh", at, -2.0)
	GameState.noise.emit(player_sys.player.global_position, 6.0, "hit")
	hud.hitmarker(head)
	if head:
		hud.toast("爆头！")


func reload() -> void:
	var row: Dictionary = Assets.items_by_id.get(inventory.equipped, {})
	if row.get("kind", -1) != Assets.Kind.GUN or _reload_left > 0.0:
		return
	var st := Weapons.stats(inventory.equipped)
	if inventory.mags.get(inventory.equipped, 0) >= st.mag:
		return
	if Weapons.ammo_count(inventory.inventory, inventory.equipped) <= 0 and not C.TEST_INFINITE:
		hud.toast("没有这把枪的子弹")
		return
	_reload_left = st.reload
	arms.reload(st.reload)
	Sfx.play(st.reload_snd)


func _finish_reload() -> void:
	var st := Weapons.stats(inventory.equipped)
	var need: int = st.mag - inventory.mags.get(inventory.equipped, 0)
	if C.TEST_INFINITE:
		# 测试模式：直接装满，不扣背包里的子弹
		inventory.mags[inventory.equipped] = st.mag
		if not inventory.mags_type.has(inventory.equipped):
			inventory.mags_type[inventory.equipped] = Weapons.default_ammo(inventory.equipped)
		return
	var ammo_list := Weapons.ammo_in(inventory.inventory, inventory.equipped)
	if ammo_list.is_empty():
		return
	# 优先用玩家在背包里点过的弹种，否则用背包里最多的那种
	var ammo_id: String = inventory.ammo_choice.get(inventory.equipped, "")
	if ammo_id == "" or inventory.inventory.get(ammo_id, 0) <= 0 or not ammo_id.begins_with(st.ammo):
		ammo_id = ammo_list[0]
	var take: int = mini(need, inventory.inventory[ammo_id])
	inventory.inventory[ammo_id] -= take
	inventory.mags[inventory.equipped] = inventory.mags.get(inventory.equipped, 0) + take
	inventory.mags_type[inventory.equipped] = ammo_id
	if inventory.inventory[ammo_id] <= 0:
		inventory.inventory.erase(ammo_id)
		inventory.pickup_order.erase(ammo_id)
	inventory.refresh()


func _update_ammo_hud() -> void:
	var row: Dictionary = Assets.items_by_id.get(inventory.equipped, {})
	if row.get("kind", -1) != Assets.Kind.GUN:
		hud.set_ammo("")
		return
	var text := "%d / %s" % [inventory.mags.get(inventory.equipped, 0),
		"∞" if C.TEST_INFINITE else str(Weapons.ammo_count(inventory.inventory, inventory.equipped))]
	var label := Weapons.ammo_label(inventory.mags_type.get(inventory.equipped, ""))
	if label != "":
		text += "  " + label
	if _reload_left > 0.0:
		text = "换弹中…"
	hud.set_ammo(text)
