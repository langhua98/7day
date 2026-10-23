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
var bleed_t := 0.0
var sick_t := 0.0
var buff_t := 0.0
var stamina := 100.0

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
	bleed_t = 0.0
	sick_t = 0.0
	buff_t = 0.0
	stamina = 100.0
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
	# 电脑上调试：WASD 移动、方向键看
	var mv := hud.move
	if Input.is_physical_key_pressed(KEY_W): mv.y += 1
	if Input.is_physical_key_pressed(KEY_S): mv.y -= 1
	if Input.is_physical_key_pressed(KEY_A): mv.x -= 1
	if Input.is_physical_key_pressed(KEY_D): mv.x += 1
	if Input.is_physical_key_pressed(KEY_LEFT): yaw += delta * 2.0
	if Input.is_physical_key_pressed(KEY_RIGHT): yaw -= delta * 2.0
	if Input.is_physical_key_pressed(KEY_UP): pitch = min(pitch + delta * 1.5, 1.3)
	if Input.is_physical_key_pressed(KEY_DOWN): pitch = max(pitch - delta * 1.5, -1.3)
	mv = mv.limit_length(1.0)
	# 冲刺：摇杆推到底往前，或者按 Shift；耗体力
	var sprint := (mv.length() > 0.92 and mv.y > 0.6) or Input.is_physical_key_pressed(KEY_SHIFT)
	sprint = sprint and stamina > 1.0 and mv.y > 0.3
	# 背包超重：变慢，不能冲刺
	var heavy: float = inventory.overload() if inventory else 0.0
	if heavy > 0.0:
		sprint = false
	if sprint:
		stamina = max(0.0, stamina - C.SPRINT_DRAIN * delta)
	else:
		stamina = min(100.0, stamina + C.STAMINA_REGEN * (C.BUFF_STAMINA_MULT if buff_t > 0.0 else 1.0) * delta * (0.5 if mv.length() > 0.1 else 1.0))
	hud.set_stamina(stamina)
	# 跳：简单的竖直速度和重力
	if Input.is_physical_key_pressed(KEY_C):
		jump()
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
	var vel := (fwd * mv.y + right * mv.x) * C.PLAYER_SPEED * (C.SPRINT_MULT if sprint else 1.0) * (1.0 - heavy)
	var before := player.position
	player.position = world.push_out(player.position + vel * delta, 0.35)
	if _grounded:
		_step_d += Vector2(player.position.x - before.x, player.position.z - before.z).length()
		if _step_d > (1.9 if sprint else 1.5):
			_step_d = 0.0
			Sfx.play("step", Vector3.INF, -10.0 if not sprint else -6.0, 0.12)
	arms.set_meta("walking", mv.length() * (1.6 if sprint else 1.0))


func update_survival(delta: float) -> void:
	food = max(0.0, food - C.FOOD_DRAIN * delta)
	water = max(0.0, water - C.WATER_DRAIN * delta * (C.SICK_WATER_MULT if sick_t > 0.0 else 1.0))
	if food <= 0.0:
		hp -= C.STARVE_DAMAGE * delta
	if water <= 0.0:
		hp -= C.THIRST_DAMAGE * delta
	if bleed_t > 0.0:
		bleed_t -= delta
		hp -= C.BLEED_DAMAGE * delta
	sick_t = maxf(0.0, sick_t - delta)
	buff_t = maxf(0.0, buff_t - delta)
	if food > 60.0 and water > 50.0 and bleed_t <= 0.0:
		hp = min(C.MAX_HP, hp + delta * 0.4)
	var st := []
	if bleed_t > 0.0: st.append("流血")
	if sick_t > 0.0: st.append("腹泻")
	if buff_t > 0.0: st.append("咖啡因")
	if water < 20.0: st.append("口渴")
	if food < 20.0: st.append("饥饿")
	hud.set_survival(water, "  ".join(st))


func jump() -> void:
	if _grounded and stamina > 8.0:
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
		if bleed_t <= 0.0:
			hud.toast("你在流血！用绷带止血")
		bleed_t = C.BLEED_TIME


func add_food(value: float) -> void:
	food = clampf(food + value, 0.0, C.MAX_FOOD)


func add_water(value: float) -> void:
	water = clampf(water + value, 0.0, C.MAX_WATER)


func heal(value: float) -> void:
	hp = clampf(hp + value, 1.0, C.MAX_HP)


func add_stamina(value: float) -> void:
	stamina = minf(100.0, stamina + value)


func stop_bleed() -> bool:
	var had := bleed_t > 0.0
	bleed_t = 0.0
	return had


func cure_sickness() -> bool:
	var had := sick_t > 0.0
	sick_t = 0.0
	return had


func add_buff(seconds: float) -> void:
	buff_t = maxf(buff_t, seconds)


func roll_sickness(chance: float) -> bool:
	if rng.randf() < chance:
		sick_t = C.SICK_TIME
		return true
	return false


func save_data() -> Dictionary:
	return {
		"hp": hp, "food": food, "water": water, "stamina": stamina,
		"bleed": bleed_t, "sick": sick_t, "buff": buff_t,
		"pos": [player.position.x, player.position.z], "y": player.position.y, "yaw": yaw,
	}


func load_data(d: Dictionary) -> void:
	hp = float(d.get("hp", C.MAX_HP))
	food = float(d.get("food", C.MAX_FOOD))
	water = float(d.get("water", C.MAX_WATER))
	stamina = float(d.get("stamina", 100.0))
	bleed_t = float(d.get("bleed", 0.0))
	sick_t = float(d.get("sick", 0.0))
	buff_t = float(d.get("buff", 0.0))
	if d.has("pos"):
		player.position = world.push_out(Vector3(d.pos[0], float(d.get("y", 0.0)), d.pos[1]), 0.35)
		player.position.y = world.floor_under(player.position + Vector3.UP * 0.5, 0.3)
	yaw = float(d.get("yaw", 0.0))
	player.rotation.y = yaw
	camera.rotation.x = pitch
	GameState.player = player
