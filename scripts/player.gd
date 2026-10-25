class_name PlayerSystem
extends RefCounted
## 玩家：移动、跳跃、体力、视角、相机、摔落和生存数值。
## main.gd 只负责创建和连接。

const C = preload("res://scripts/config.gd")

var main: Node3D
var world: World
var hud: Hud
var rng: RandomNumberGenerator
var player := Node3D.new()
var camera := Camera3D.new()
var arms: FpArms
## 背包（读超重）
var inventory: InventorySystem

var yaw := 0.0
var pitch := 0.0
var hp := C.MAX_HP
var food := C.MAX_FOOD
var water := C.MAX_WATER
var stamina := 100.0
var _sprinting := false
var _hud_t := 0.0

var _vy := 0.0
var _recoil := 0.0
var _land_dip := 0.0
var aiming := false
var _step_d := 0.0
var _grounded := true
## 这次离地以来到过的最高点（算摔落高度）
var _air_top := 0.0
## 感染度不满 1% 的零头（游戏小时累计）
var _infect_acc := 0.0
## 6a：蹲伏（HUD「蹲」按钮切换）
var crouching := false
var _crouch_h := 0.0
## 驾驶载具：位置和朝向由 vehicles.gd 同步，不走路
var driving := false


func setup(parent: Node3D, world_ref: World, hud_ref: Hud, rng_ref: RandomNumberGenerator) -> void:
	main = parent
	world = world_ref
	hud = hud_ref
	rng = rng_ref


func build() -> void:
	player.name = "Player"
	main.add_child(player)
	camera.position.y = C.PLAYER_EYE_HEIGHT
	camera.near = 0.03
	camera.far = 260.0
	camera.fov = C.BASE_FOV
	player.add_child(camera)
	arms = FpArms.new()
	camera.add_child(arms)
	GameState.player = player


func reset() -> void:
	driving = false
	arms.visible = true
	player.position = Vector3.ZERO
	crouching = false
	_crouch_h = 0.0
	GameState.player_crouching = false
	if hud:
		hud.set_crouch(false)
	player.rotation.y = 0.0
	camera.rotation.x = 0.0
	camera.position.y = C.PLAYER_EYE_HEIGHT
	camera.fov = C.BASE_FOV
	yaw = 0.0
	pitch = 0.0
	hp = C.MAX_HP
	food = C.MAX_FOOD
	water = C.MAX_WATER
	Status.clear()
	stamina = 100.0
	_sprinting = false
	_vy = 0.0
	_recoil = 0.0
	_land_dip = 0.0
	aiming = false
	arms.set_aiming(false)
	arms.set_scoped(false)
	if hud:
		hud.set_scope(0)
	_step_d = 0.0
	_grounded = true
	_air_top = 0.0
	_infect_acc = 0.0


## 上车：收起手臂，相机拉到车后
func begin_driving() -> void:
	driving = true
	aiming = false
	crouching = false
	GameState.player_crouching = false
	_vy = 0.0
	_air_top = player.position.y
	_sprinting = false
	arms.visible = false
	camera.position = Vector3(0.0, C.VEHICLE_CAM_HEIGHT, C.VEHICLE_CAM_BACK)
	camera.rotation.x = -C.VEHICLE_CAM_PITCH
	camera.fov = C.BASE_FOV


## 下车：恢复第一人称（站的位置由 vehicles.gd 放好）
func end_driving() -> void:
	driving = false
	arms.visible = true
	camera.position.y = C.PLAYER_EYE_HEIGHT
	camera.rotation.x = clampf(pitch, -1.4, 1.4)
	camera.fov = C.BASE_FOV
	_air_top = player.position.y
	_grounded = true


## 驾驶中每帧：位置和朝向由 vehicles.gd 同步，这里只跟相机
func update_driving(delta: float) -> void:
	camera.position = Vector3(0.0, C.VEHICLE_CAM_HEIGHT, C.VEHICLE_CAM_BACK)
	camera.rotation.x = lerp_angle(camera.rotation.x, -C.VEHICLE_CAM_PITCH, 1.0 - exp(-delta * 10.0))
	camera.fov = lerp(camera.fov, C.BASE_FOV + 4.0, 1.0 - exp(-delta * 6.0))
	arms.set_meta("walking", 0.0)


func update(delta: float) -> void:
	if driving:
		return
	var look := hud.consume_look()
	arms.look(look)
	arms.set_aiming(aiming)
	var scope := 0
	if aiming and inventory and inventory.equipped != "":
		scope = Weapons.scope_level(inventory.equipped, inventory.scope_of(inventory.equipped))
	arms.set_scoped(scope >= 2)
	hud.set_scope(scope)
	var look_sens: float = C.LOOK_SENSITIVITY * hud.settings.sensitivity * (C.AIM_SENSITIVITY if aiming else 1.0)
	# 开镜瞄准辅助：准星贴近僵尸头时只降灵敏度，不吸附
	if aiming and hud.settings.aim_assist > 0.5 and _near_zombie_head():
		look_sens *= C.AIM_ASSIST_MULT
	yaw -= look.x * look_sens
	pitch = clamp(pitch - look.y * look_sens, -1.3, 1.3)
	# 只做 iPhone 触屏：移动全靠左边摇杆
	var mv := hud.move.limit_length(1.0)
	# 冲刺：设置开着时摇杆推到外圈 90% 往前；耗体力
	var sprint: bool = hud.settings.auto_sprint > 0.5 and mv.length() > 0.9 and mv.y > 0.3
	sprint = sprint and stamina > 1.0 and mv.y > 0.3 and not Status.blocked("no_sprint") and not crouching
	# 背包超重：变慢，不能冲刺
	var heavy: float = inventory.overload() if inventory else 0.0
	if heavy > 0.0:
		sprint = false
	_sprinting = sprint
	# 体力上限、恢复速度受状态影响（口渴 −25 上限，饥饿恢复减半，咖啡因 ×2.2）
	var st_max := stamina_max()
	if sprint:
		stamina = max(0.0, stamina - C.SPRINT_DRAIN * delta)
	else:
		stamina = stamina + C.STAMINA_REGEN * Status.modifier("stamina_regen") * delta * (0.5 if mv.length() > 0.1 else 1.0)
	stamina = minf(stamina, st_max)
	hud.set_stamina(stamina)
	# 跳（hud 的跳键调 jump()）：简单的竖直速度和重力
	# 地面是 0；站在自己摆的方块上就是方块顶
	# 楼里的梯子：推摇杆往前爬上去、往后爬下来，不受重力，也不算摔
	if world.ladder_at(player.position):
		_vy = mv.y * C.LADDER_SPEED
		_air_top = player.position.y
	else:
		_vy -= C.GRAVITY * delta
	player.position.y += _vy * delta
	if _vy > 0.0 and world.ceiling_hit(player.position, 0.3, 1.8):
		_vy = 0.0
	var floor_y := world.floor_under(player.position, 0.3)
	var was_grounded := _grounded
	_grounded = player.position.y <= floor_y + 0.01
	if not _grounded:
		_air_top = maxf(_air_top, player.position.y)
	if _grounded:
		if _vy < -3.0:
			Sfx.play("land", Vector3.INF, -6.0)
			_land_dip = minf(C.LAND_DIP_MAX, -_vy * 0.012)
		player.position.y = floor_y
		_vy = 0.0
		if not was_grounded:
			land(_air_top - floor_y)
		_air_top = floor_y
	# 后坐力：先往上跳再回弹，只有一小部分留在准星上
	_recoil = lerp(_recoil, 0.0, 1.0 - exp(-delta * C.RECOIL_RECOVERY))
	player.rotation.y = yaw
	camera.rotation.x = clampf(pitch + _recoil, -1.4, 1.4)
	# 冲刺拉宽视野，开镜收窄，落地轻轻压头
	var fov_target := C.BASE_FOV
	if aiming:
		if inventory and inventory.equipped != "":
			fov_target = Weapons.scope_fov(inventory.equipped, inventory.scope_of(inventory.equipped))
		else:
			fov_target = C.AIM_FOV
	elif sprint:
		fov_target = C.BASE_FOV + C.SPRINT_FOV_BONUS
	camera.fov = lerp(camera.fov, fov_target, 1.0 - exp(-delta * 8.0))
	_land_dip = lerp(_land_dip, 0.0, 1.0 - exp(-delta * 9.0))
	_crouch_h = lerp(_crouch_h, C.CROUCH_DROP if crouching else 0.0, 1.0 - exp(-delta * 10.0))
	camera.position.y = C.PLAYER_EYE_HEIGHT - _land_dip - _crouch_h
	var fwd := -player.global_basis.z
	var right := player.global_basis.x
	var vel := (fwd * mv.y + right * mv.x) * C.PLAYER_SPEED * (C.SPRINT_MULT if sprint else 1.0) \
		* Status.modifier("move_speed") * (1.0 - heavy) * (C.CROUCH_SPEED_MULT if crouching else 1.0)
	var before := player.position
	player.position = world.push_out(player.position + vel * delta, 0.35)
	if _grounded:
		_step_d += Vector2(player.position.x - before.x, player.position.z - before.z).length()
		if _step_d > (1.9 if sprint else 1.5):
			_step_d = 0.0
			Sfx.play("step", Vector3.INF, -16.0 if crouching else (-10.0 if not sprint else -6.0), 0.12)
			# 脚步噪音：冲刺 8、走路 4、蹲走 1.5 米
			GameState.make_noise(player.global_position, "crouch" if crouching else ("sprint" if sprint else "walk"))
	arms.set_meta("walking", mv.length() * (1.6 if sprint else 1.0))


## 准星是不是贴着某只僵尸的头（开镜辅助用）
func _near_zombie_head() -> bool:
	var sp = main.get("spawner") if main else null
	if sp == null:
		return false
	var eye := camera.global_position
	var fwd := -camera.global_basis.z
	var cos_lim := cos(deg_to_rad(C.AIM_ASSIST_ANGLE))
	for z in sp.zombie_root.get_children():
		if z.dead:
			continue
		var to: Vector3 = z.global_position + Vector3.UP * z.height() * 0.86 - eye
		var d := to.length()
		if d < 2.0 or d > C.AIM_ASSIST_RANGE:
			continue
		if fwd.dot(to / d) >= cos_lim:
			return true
	return false


## 体力上限：100 加上状态修正（口渴 −25），最少 10
func stamina_max() -> float:
	return maxf(10.0, 100.0 + Status.offset("stamina_max"))


## 生存数值：delta 真实秒，dh 这一帧走过的游戏小时
func update_survival(delta: float, dh: float) -> void:
	var hunger_mult := C.SPRINT_HUNGER_MULT if _sprinting else 1.0
	food = maxf(0.0, food - C.FOOD_PER_HOUR * dh * hunger_mult * Status.modifier("food_drain"))
	water = maxf(0.0, water - C.WATER_PER_HOUR * dh * hunger_mult * Status.modifier("water_drain"))
	# 条件型状态跟着饱食、水分走
	Status.toggle("hungry", food < C.HUNGRY_BELOW)
	Status.toggle("starving", food <= 0.0)
	Status.toggle("thirsty", water < C.THIRSTY_BELOW)
	Status.toggle("dehydrated", water <= 0.0)
	_update_infection(dh)
	var d: Dictionary = Status.tick(delta, dh)
	hp += float(d.hp)
	food = clampf(food + float(d.food), 0.0, C.MAX_FOOD)
	water = clampf(water + float(d.water), 0.0, C.MAX_WATER)
	if food > C.REGEN_FOOD_ABOVE and water > C.REGEN_WATER_ABOVE and not Status.losing_hp():
		hp = minf(C.MAX_HP, hp + C.HP_REGEN_PER_HOUR * dh)
	# 感染到 100% 就死
	if infection() >= C.INFECTION_MAX:
		hp = 0.0
	# 状态条每秒刷新 4 次就够
	_hud_t -= delta
	if _hud_t <= 0.0:
		_hud_t = 0.25
		hud.set_survival(water, "")
		hud.set_effects(Status.active())


## 落地：h 是这次下落的高度（米）。超过 3 米掉血，3–4 米可能扭伤，4 米以上骨折
func land(h: float) -> void:
	if h <= C.FALL_SAFE:
		return
	take_damage((h - C.FALL_SAFE) * C.FALL_DAMAGE_PER_M, "fall")
	if h > C.FRACTURE_HEIGHT:
		break_leg()
	elif h > C.SPRAIN_HEIGHT and rng.randf() < C.SPRAIN_CHANCE:
		sprain_leg()


## 扭伤（已经骨折就不叠扭伤）
func sprain_leg() -> void:
	if has_fracture():
		return
	if not Status.has("sprain"):
		hud.toast("你扭伤了腿！用夹板固定")
	Status.remove("sprain_splinted")
	Status.add("sprain")


## 骨折：之前的扭伤、夹板、石膏都作废
func break_leg() -> void:
	for id in ["sprain", "sprain_splinted", "fracture_splinted", "fracture_cast"]:
		Status.remove(id)
	if not Status.has("fracture"):
		hud.toast("你的腿骨折了！用夹板或石膏")
		hud.vibrate(200)
	Status.add("fracture")


func has_fracture() -> bool:
	return Status.has("fracture") or Status.has("fracture_splinted") or Status.has("fracture_cast")


## 被僵尸打中：流血、感染、大块头还可能打断腿
func zombie_hit(amount: float, zombie_type: String, big := false) -> void:
	take_damage(amount, "zombie", C.BLEED_CHANCE)
	if rng.randf() < C.INFECTION_CHANCE:
		infect()
	if not big:
		big = zombie_type in C.BIG_ZOMBIE_MODELS
	if big and rng.randf() < C.BIG_HIT_FRACTURE_CHANCE:
		break_leg()


## 感染：已经感染就不变，否则从 1% 开始
func infect() -> void:
	if Status.has("infection"):
		return
	hud.toast("伤口感染了！找抗生素")
	_infect_acc = 0.0
	Status.set_stacks("infection", C.INFECTION_START)


func infection() -> int:
	return Status.stacks("infection")


## 感染度每游戏小时涨 1%，到 100% 死亡
func _update_infection(dh: float) -> void:
	if not Status.has("infection"):
		_infect_acc = 0.0
		return
	_infect_acc += C.INFECTION_PER_HOUR * dh
	if _infect_acc >= 1.0:
		var n := floori(_infect_acc)
		_infect_acc -= n
		Status.set_stacks("infection", mini(C.INFECTION_MAX, infection() + n))


## 用药改感染度，amount 负数是降低；返回提示（没感染返回空）
func treat_infection(amount: int) -> String:
	if not Status.has("infection") or amount >= 0:
		return ""
	var n := infection() + amount
	Status.set_stacks("infection", n)
	return "，感染治好了" if n <= 0 else "，感染降到 %d%%" % n


## 夹板：扭伤 → 已固定 6 小时；骨折 → 打夹板 3 天
func apply_splint() -> String:
	if Status.remove("fracture"):
		Status.add("fracture_splinted")
		return "，腿打上了夹板"
	if Status.remove("sprain"):
		Status.add("sprain_splinted")
		return "，扭伤固定好了"
	return ""


## 石膏：骨折（含打夹板的）→ 打石膏 1 天；扭伤也能用
func apply_cast() -> String:
	if Status.remove("fracture") or Status.remove("fracture_splinted"):
		Status.add("fracture_cast")
		return "，腿打上了石膏"
	if Status.remove("sprain") or Status.remove("sprain_splinted"):
		return "，扭伤好了"
	return ""


func toggle_crouch() -> void:
	crouching = not crouching
	GameState.player_crouching = crouching
	hud.set_crouch(crouching)


func jump() -> void:
	if _grounded and stamina > 8.0 and not Status.blocked("no_jump"):
		_vy = C.JUMP_SPEED
		stamina -= 8.0
		Sfx.play("jump", Vector3.INF, -6.0)


func add_recoil(amount: float) -> void:
	_recoil += amount


func take_damage(amount: float, source: String, bleed_chance := 0.0) -> void:
	hp -= amount
	hud.hurt()
	hud.vibrate(60)
	GameState.player_damaged.emit(amount, source)
	if source == "zombie":
		Sfx.play("pain", Vector3.INF, -3.0)
	if bleed_chance > 0.0 and rng.randf() < bleed_chance:
		if not Status.has("bleeding"):
			hud.toast("你在流血！用绷带止血")
		Status.add("bleeding")


func add_food(value: float) -> void:
	food = clampf(food + value, 0.0, C.MAX_FOOD)


func add_water(value: float) -> void:
	water = clampf(water + value, 0.0, C.MAX_WATER)


func heal(value: float) -> void:
	hp = clampf(hp + value, 1.0, C.MAX_HP)


func add_stamina(value: float) -> void:
	stamina = minf(stamina_max(), stamina + value)


## 物品效果 → 状态（survival.gd 的效果表输出这些）
func stop_bleed() -> bool:
	return Status.remove("bleeding")


func cure_sickness() -> bool:
	return Status.remove("dysentery")


## 咖啡因，hours 游戏小时
func add_buff(hours: float) -> void:
	Status.add("caffeine", hours)


func roll_sickness(chance: float) -> bool:
	if chance > 0.0 and rng.randf() < chance:
		Status.add("dysentery")
		return true
	return false


## 重生（3c）：搬到 pos，血、饱食、水按 frac 比例，体力回满，停止下落
func revive(pos: Vector3, frac: float) -> void:
	player.position = world.push_out(pos, 0.35) if world else pos
	if world:
		player.position.y = world.floor_under(player.position + Vector3.UP * 0.5, 0.3)
	hp = C.MAX_HP * frac
	food = C.MAX_FOOD * frac
	water = C.MAX_WATER * frac
	stamina = stamina_max()
	_vy = 0.0
	_recoil = 0.0
	_sprinting = false
	_grounded = true


func save_data() -> Dictionary:
	return {
		"hp": hp, "food": food, "water": water, "stamina": stamina,
		"pos": [player.position.x, player.position.z], "y": player.position.y, "yaw": yaw,
		"infect_acc": _infect_acc,
	}


func load_data(d: Dictionary) -> void:
	hp = float(d.get("hp", C.MAX_HP))
	food = float(d.get("food", C.MAX_FOOD))
	water = float(d.get("water", C.MAX_WATER))
	stamina = float(d.get("stamina", 100.0))
	_infect_acc = float(d.get("infect_acc", 0.0))
	if d.has("pos"):
		player.position = world.push_out(Vector3(d.pos[0], float(d.get("y", 0.0)), d.pos[1]), 0.35)
		player.position.y = world.floor_under(player.position + Vector3.UP * 0.5, 0.3)
	yaw = float(d.get("yaw", 0.0))
	player.rotation.y = yaw
	_air_top = player.position.y
	_grounded = true
	camera.rotation.x = pitch
	GameState.player = player
