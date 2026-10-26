class_name ZombieBrain
extends RefCounted
## 僵尸大脑：状态机和感官（视觉、听觉）。决定往哪走、能不能出手；身体在 zombie_body.gd。
## 感知由 spawner 轮询（每帧最多 AI_SENSE_PER_FRAME 只），噪音由 spawner 转给半径内的僵尸。

const C = preload("res://scripts/config.gd")

enum State { SLEEP, IDLE, WANDER, INVESTIGATE, CHASE, ATTACK_BLOCK, STAGGER, DEAD }
const STATE_NAMES := ["睡眠", "发呆", "游荡", "调查", "追击", "砸方块", "硬直", "死亡"]

var state := State.WANDER
## 最后听到/看到的位置（调查目标）
var last_pos := Vector3.INF
## 游荡的目标点
var wander_pos := Vector3.INF
var can_see := false

var _lost_t := 0.0
var _linger_t := 0.0
var _idle_t := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()
	_idle_t = _rng.randf_range(0.0, 4.0)
	state = State.IDLE


## 每帧调用：计时、状态转换。返回要走去的位置（INF = 原地不动）
func tick(delta: float, body: Node3D, target: Node3D, horde: bool) -> Vector3:
	if state == State.DEAD or state == State.SLEEP:
		return Vector3.INF
	# 血月僵尸直接追，不看感官
	if horde and target:
		state = State.CHASE
		_lost_t = 0.0
		return target.global_position
	match state:
		State.CHASE:
			if target == null:
				state = State.WANDER
				return Vector3.INF
			if can_see:
				_lost_t = 0.0
				last_pos = target.global_position
			else:
				_lost_t += delta
				if _lost_t >= C.ZOMBIE_LOSE_TARGET:
					investigate(last_pos)
			# 追击时一直往玩家走（看不见时靠流场绕路）
			return target.global_position
		State.INVESTIGATE:
			if last_pos == Vector3.INF:
				state = State.WANDER
				return Vector3.INF
			if _flat(body.global_position, last_pos) < 1.5:
				_linger_t += delta
				if _linger_t >= C.ZOMBIE_INVESTIGATE_LINGER:
					state = State.WANDER
					wander_pos = Vector3.INF
				return Vector3.INF
			return last_pos
		State.WANDER:
			# 夜里也会游荡，只是白天慢走为主
			if wander_pos == Vector3.INF or _flat(body.global_position, wander_pos) < 1.0:
				if _rng.randf() < 0.4:
					state = State.IDLE
					_idle_t = _rng.randf_range(2.0, 6.0)
					return Vector3.INF
				var a := _rng.randf() * TAU
				var r := _rng.randf_range(2.0, C.ZOMBIE_WANDER_RADIUS)
				wander_pos = body.global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
			return wander_pos
		State.IDLE:
			_idle_t -= delta
			if _idle_t <= 0.0:
				state = State.WANDER
				wander_pos = Vector3.INF
			return Vector3.INF
	return Vector3.INF


## 视觉（轮询调用）：前方扇形、白天/夜里视距、蹲下减半、被楼和方块挡住看不见
func sense(body: Node3D, target: Node3D, world: World) -> void:
	if state == State.DEAD or target == null:
		can_see = false
		return
	# 睡眠中：5 米内看到玩家才醒，蹲下减半
	if state == State.SLEEP:
		can_see = false
		var to := target.global_position - body.global_position
		to.y = 0.0
		var how_far := to.length()
		var sight := C.SLEEP_SIGHT * (C.SLEEP_SIGHT_CROUCH_MULT if GameState.player_crouching else 1.0)
		if GameState.player_crouching:
			sight *= Progression.sight_mult()
		if how_far > sight:
			return
		if world and world.line_blocked(body.global_position + Vector3.UP * 1.6,
				target.global_position + Vector3.UP * 1.0):
			return
		if body.has_method("wake"):
			body.wake()
		return
	can_see = sees(body, target, world)
	if can_see:
		last_pos = target.global_position
		if state != State.CHASE:
			chase()


func sees(body: Node3D, target: Node3D, world: World) -> bool:
	var to := target.global_position - body.global_position
	to.y = 0.0
	var dist := to.length()
	var touch := dist <= C.ZOMBIE_SENSE_TOUCH and not GameState.player_crouching
	if not touch:
		var range_m := C.ZOMBIE_SIGHT_NIGHT if GameState.is_night() else C.ZOMBIE_SIGHT_DAY
		if GameState.player_crouching:
			range_m *= C.ZOMBIE_SIGHT_CROUCH_MULT * Progression.sight_mult()
		if dist > range_m:
			return false
		# 身体的正面是 +Z（body.rotation.y = atan2(dir.x, dir.z)）
		var fwd := body.global_basis.z
		fwd.y = 0.0
		if dist > 0.01 and fwd.length() > 0.01:
			var cos_half := cos(deg_to_rad(C.ZOMBIE_SIGHT_FOV * 0.5))
			if fwd.normalized().dot(to / dist) < cos_half:
				return false
	if world:
		var eye_h := 1.0 if GameState.player_crouching else 1.6
		if world.line_blocked(body.global_position + Vector3.UP * 1.6, target.global_position + Vector3.UP * eye_h):
			return false
	return true


## 听到噪音：走去声音的位置查看（正在追的不受影响）
func hear(pos: Vector3, _kind: String) -> void:
	if state == State.DEAD or state == State.CHASE or state == State.SLEEP:
		return
	investigate(pos)


func investigate(pos: Vector3) -> void:
	if pos == Vector3.INF:
		state = State.WANDER
		return
	state = State.INVESTIGATE
	last_pos = Vector3(pos.x, 0.0, pos.z)
	_linger_t = 0.0


func chase() -> void:
	if state == State.DEAD:
		return
	state = State.CHASE
	_lost_t = 0.0


## 被打：直接追（打它的人位置已知）
func on_hit() -> void:
	chase()


func die() -> void:
	state = State.DEAD


func chasing() -> bool:
	return state == State.CHASE


## 当前状态的移速倍率
func speed_mult() -> float:
	match state:
		State.WANDER:
			return C.ZOMBIE_WANDER_SPEED_MULT
		State.INVESTIGATE:
			return 0.8
	return 1.0


func state_name() -> String:
	return STATE_NAMES[state]


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
