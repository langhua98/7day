class_name ZombieAcid
extends Node3D
## 警察吐出的酸液：抛物线飞过去，落地小范围伤害。

const C = preload("res://scripts/config.gd")

var _from := Vector3.ZERO
var _vel := Vector3.ZERO
var _t := 0.0
var _time := 1.0
var _damage := 8.0
var _player_sys: PlayerSystem
var _world: World


func setup(from: Vector3, to: Vector3, damage: float, player_sys: PlayerSystem, world: World) -> void:
	_from = from
	position = from
	_damage = damage
	_player_sys = player_sys
	_world = world
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var dist := d.length()
	_time = clampf(dist / 12.0, 0.35, 1.4)
	_vel = Vector3(d.x / _time, (to.y - from.y + 0.5 * C.GRAVITY * _time * _time) / _time,
		d.z / _time)
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.4, 1.0, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 1.0, 0.25)
	mat.emission_energy_multiplier = 1.5
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _process(delta: float) -> void:
	_t += delta
	position = _from + _vel * _t + Vector3(0.0, -0.5 * C.GRAVITY * _t * _t, 0.0)
	if _t >= _time or position.y <= 0.05:
		_hit()


func _hit() -> void:
	position.y = maxf(0.05, position.y)
	Fx.impact(get_parent(), position, Vector3.UP)
	Sfx.play("hit_flesh", position, 2.0)
	GameState.make_noise(position, "explosion", 10.0)
	if _player_sys and _player_sys.player.position.distance_to(position) < 2.2:
		_player_sys.take_damage(_damage, "acid")
	queue_free()
