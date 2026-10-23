class_name Atmosphere
extends RefCounted
## 天空、太阳/月亮、雾、环境光、音乐和血月横幅。

const C = preload("res://scripts/config.gd")

var main: Node3D
var world_seed := 0
var music: MusicDirector
var hud: Hud
var sun := DirectionalLight3D.new()
var env := Environment.new()
var sky_mat := ShaderMaterial.new()
var _cloud_day := -1
var _horde_announced := false
var _night_announced := -1


func build(parent: Node3D, seed_value: int) -> void:
	main = parent
	world_seed = seed_value
	var we := WorldEnvironment.new()
	var sky := Sky.new()
	sky_mat.shader = load("res://scripts/sky.gdshader")
	sky.sky_material = sky_mat
	var stars := _load_cube("MilkyWay_V_Cross_1024")
	if stars:
		sky_mat.set_shader_parameter("stars", stars)
		sky_mat.set_shader_parameter("has_stars", true)
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_density = 0.018
	env.fog_sky_affect = 0.25
	we.environment = env
	main.add_child(we)

	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	main.add_child(sun)


func set_brightness(value: float) -> void:
	env.tonemap_exposure = value


func reset() -> void:
	_horde_announced = false
	_night_announced = -1


func set_night_announced(day: int, hour: float) -> void:
	_night_announced = day if hour >= C.DUSK_HOUR else -1


func update_sky(game_hours: float) -> void:
	var hour := fmod(game_hours, 24.0)
	# 太阳高度：6 点日出、20 点日落，中午最高；夜里是负数
	var elev: float
	if hour >= C.SUNRISE and hour <= C.SUNSET:
		elev = sin(PI * (hour - C.SUNRISE) / (C.SUNSET - C.SUNRISE))
	else:
		var night_len := 24.0 - (C.SUNSET - C.SUNRISE)
		var t := fmod(hour - C.SUNSET + 24.0, 24.0) / night_len
		elev = -sin(PI * t) * 0.6
	var light: float = smoothstep(-0.12, 0.3, elev)
	var dusk: float = clamp(1.0 - abs(elev) * 4.0, 0.0, 1.0)
	var sun_up: float = max(elev, 0.12)
	# 夜里这盏灯当月光用，从另一侧照过来
	sun.rotation = Vector3(-asin(sun_up) - 0.05, deg_to_rad(35.0 if elev > 0.0 else 215.0), 0)
	sun.light_energy = lerp(C.MOON_LIGHT, 1.0, light)
	sun.light_color = Color(0.62, 0.7, 1.0).lerp(Color(1.0, 0.96, 0.88), light).lerp(Color(1.0, 0.62, 0.4), dusk * light)
	var day_sky := Color(0.30, 0.50, 0.80)
	var night_sky := Color(0.07, 0.1, 0.2)
	var day := int(game_hours / 24.0) + 1
	var horde := GameState.is_blood_moon()
	var blood_evening := day % C.BLOOD_MOON_EVERY == 0 and hour >= 18.0
	if horde or blood_evening:
		night_sky = Color(0.35, 0.05, 0.04)
		if horde:
			sun.light_color = sun.light_color.lerp(Color(1.0, 0.32, 0.22), 0.75)
	sky_mat.set_shader_parameter("top_color", night_sky.lerp(day_sky, light))
	var horizon := Color(0.16, 0.19, 0.28).lerp(Color(0.66, 0.70, 0.74), light).lerp(Color(0.95, 0.6, 0.4), dusk * 0.6)
	if horde or blood_evening:
		horizon = horizon.lerp(Color(0.5, 0.08, 0.05), 1.0 - light)
	sky_mat.set_shader_parameter("horizon_color", horizon)
	sky_mat.set_shader_parameter("ground_color", Color(0.12, 0.12, 0.13).lerp(Color(0.25, 0.22, 0.18), light))
	sky_mat.set_shader_parameter("night", 1.0 - light)
	sky_mat.set_shader_parameter("cloud_turn", game_hours * 0.01)
	var lit := Color(0.22, 0.24, 0.3).lerp(Color(1.0, 0.98, 0.94), light).lerp(Color(1.0, 0.7, 0.5), dusk * light)
	if horde:
		lit = lit.lerp(Color(0.6, 0.15, 0.1), 1.0 - light)
	sky_mat.set_shader_parameter("cloud_lit", lit)
	sky_mat.set_shader_parameter("cloud_dark", lit * Color(0.45, 0.47, 0.55))
	# 每天换一种云：薄云、积云、阴天
	if day != _cloud_day:
		_cloud_day = day
		var kinds := ["WhispyClouds", "FluffyClouds", "ThickOvercastClouds"]
		var cube := _load_cube(kinds[(day + world_seed) % kinds.size()])
		sky_mat.set_shader_parameter("has_clouds", cube != null)
		if cube:
			sky_mat.set_shader_parameter("clouds", cube)
	env.fog_light_color = horizon
	# 环境光不跟天空走，夜里也保证能看清地面和僵尸
	env.ambient_light_color = C.NIGHT_AMBIENT.lerp(Color(0.78, 0.75, 0.7), light)
	if horde:
		env.ambient_light_color = env.ambient_light_color.lerp(Color(0.6, 0.25, 0.22), 1.0 - light)
	env.ambient_light_energy = lerp(C.NIGHT_AMBIENT_ENERGY, 0.45, light)
	env.fog_density = lerp(0.014, 0.0045, light)


## 天空全景图（由 fetch_assets 把七日杀的六面立方体贴图拼成）
func _load_cube(name: String) -> Texture2D:
	var path := "res://assets/sky/%s/pano.png" % name
	return load(path) if ResourceLoader.exists(path) else null


func update_music(delta: float, night: bool, horde: bool, zombie_root: Node3D) -> void:
	var nearest := INF
	for z in zombie_root.get_children():
		if not z.dead:
			nearest = min(nearest, z.distance_to_target())
	var want := "Exp"
	if horde and not Assets.music["Bld"].is_empty():
		want = "Bld"
	elif nearest < C.COMBAT_DISTANCE:
		want = "Cbt"
	elif night or nearest < C.TENSION_DISTANCE:
		want = "Sus"
	music.request(want, delta)
	# 环境声：白天风声，夜里虫鸣
	Sfx.loop("amb_day", -80.0 if night else -14.0, delta)
	Sfx.loop("amb_night", -12.0 if night else -80.0, delta)


func update_banner(day: int, hour: float, night: bool, horde: bool) -> void:
	if horde:
		hud.set_banner("血月尸潮！撑到天亮！")
		if not _horde_announced:
			_horde_announced = true
	elif day % C.BLOOD_MOON_EVERY == 0 and hour >= 21.0:
		hud.set_banner("血月即将升起")
	elif day % C.BLOOD_MOON_EVERY == 0 and hour >= 18.0:
		hud.set_banner("今晚是血月……")
	elif night:
		if _night_announced != day:
			_night_announced = day
			hud.toast("天黑了，僵尸会跑起来")
		hud.set_banner("")
	else:
		hud.set_banner("")
