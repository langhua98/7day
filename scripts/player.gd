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
	player.position = Vector3.ZERO
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
	_step_d = 0.0
	_grounded = true


func update(delta: float) -> void:
	var look := hud.consume_look()
	arms.look(look)
	arms.set_aiming(aiming)
	var look_sens: float = C.LOOK_SENSITIVITY * hud.settings.sensitivity * (C.AIM_SENSITIVITY if aiming else 1.0)
	yaw -= look.x * look_sens
	pitch = clamp(pitch - look.y * look_sens, -1.3, 1.3)
	# 只做 iPhone 触屏：移动全靠左边摇杆
	var mv := hud.move.limit_length(1.0)
	# 冲刺：摇杆推到底往前；耗体力
	var sprint := mv.length() > 0.92 and mv.y > 0.6
	sprint = sprint and stamina > 1.0 and mv.y > 0.3 and not Status.blocked("no_sprint")
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
	_vy -= C.GRAVITY * delta
	player.position.y += _vy * delta
	if _vy > 0.0 and world.ceiling_hit(player.position, 0.3, 1.8):
		_vy = 0.0
	var floor_y := world.floor_under(player.position, 0.3)
	_grounded = player.position.y <= floor_y + 0.01
	if _grounded:
		if _vy < -3.0:
			Sfx.play("land", Vector3.INF, -6.0)
			_land_dip = minf(C.LAND_DIP_MAX, -_vy * 0.012)
		player.position.y = floor_y
		_vy = 0.0
	# 后坐力：先往上跳再回弹，只有一小部分留在准星上
	_recoil = lerp(_recoil, 0.0, 1.0 - exp(-delta * C.RECOIL_RECOVERY))
	player.rotation.y = yaw
	camera.rotation.x = clampf(pitch + _recoil, -1.4, 1.4)
	# 冲刺拉宽视野，开镜收窄，落地轻轻压头
	var fov_target := C.BASE_FOV
	if aiming:
		fov_target = C.AIM_FOV
	elif sprint:
		fov_target = C.BASE_FOV + C.SPRINT_FOV_BONUS
	camera.fov = lerp(camera.fov, fov_target, 1.0 - exp(-delta * 8.0))
	_land_dip = lerp(_land_dip, 0.0, 1.0 - exp(-delta * 9.0))
	camera.position.y = C.PLAYER_EYE_HEIGHT - _land_dip
	var fwd := -player.global_basis.z
	var right := player.global_basis.x
	var vel := (fwd * mv.y + right * mv.x) * C.PLAYER_SPEED * (C.SPRINT_MULT if sprint else 1.0) * Status.modifier("move_speed") * (1.0 - heavy)
	var before := player.position
	player.position = world.push_out(player.position + vel * delta, 0.35)
	if _grounded:
		_step_d += Vector2(player.position.x - before.x, player.position.z - before.z).length()
		if _step_d > (1.9 if sprint else 1.5):
			_step_d = 0.0
			Sfx.play("step", Vector3.INF, -10.0 if not sprint else -6.0, 0.12)
	arms.set_meta("walking", mv.length() * (1.6 if sprint else 1.0))


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
	var d: Dictionary = Status.tick(delta, dh)
	hp += float(d.hp)
	food = clampf(food + float(d.food), 0.0, C.MAX_FOOD)
	water = clampf(water + float(d.water), 0.0, C.MAX_WATER)
	if food > C.REGEN_FOOD_ABOVE and water > C.REGEN_WATER_ABOVE and not Status.losing_hp():
		hp = minf(C.MAX_HP, hp + C.HP_REGEN_PER_HOUR * dh)
	# 状态条每秒刷新 4 次就够
	_hud_t -= delta
	if _hud_t <= 0.0:
		_hud_t = 0.25
		hud.set_survival(water, "")
		hud.set_effects(Status.active())


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
	Input.vibrate_handheld(60)
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
	}


func load_data(d: Dictionary) -> void:
	hp = float(d.get("hp", C.MAX_HP))
	food = float(d.get("food", C.MAX_FOOD))
	water = float(d.get("water", C.MAX_WATER))
	stamina = float(d.get("stamina", 100.0))
	if d.has("pos"):
		player.position = world.push_out(Vector3(d.pos[0], float(d.get("y", 0.0)), d.pos[1]), 0.35)
		player.position.y = world.floor_under(player.position + Vector3.UP * 0.5, 0.3)
	yaw = float(d.get("yaw", 0.0))
	player.rotation.y = yaw
	camera.rotation.x = pitch
	GameState.player = player
