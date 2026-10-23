extends Node
## 主场景冒烟：用正常项目启动方式运行，自动加载（Assets/Sfx）才会生效。
## 没有素材也能启动，检查画质切换、性能面板和命中标记不报错。

const MAIN = preload("res://scenes/main.tscn")
const C = preload("res://scripts/config.gd")

var failures: Array[String] = []
var _elapsed := 0.0
var _settings_existed := false
var _settings_data := PackedByteArray()


func _ready() -> void:
	# 测试会改画质设置，先备份玩家自己的设置，结束时还原
	if FileAccess.file_exists("user://settings.cfg"):
		_settings_existed = true
		_settings_data = FileAccess.get_file_as_bytes("user://settings.cfg")
	_run.call_deferred()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > 120.0:
		push_error("test_smoke 超时")
		_restore_settings()
		get_tree().quit(1)


func _run() -> void:
	print("SMOKE run")
	var main := MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	check(main.hud != null, "HUD 应已创建")
	check(main.world != null, "世界应已创建")
	if main.hud == null or main.world == null:
		_finish()
		return
	check(main.hud.settings.has("quality"), "设置里应有 quality")
	check(main.hud.settings.has("show_perf"), "设置里应有 show_perf")

	main._apply_quality(1)
	check_eq(Engine.max_fps, 60, "均衡档应锁 60 帧")
	check_eq(main._quality, 1, "当前画质应为均衡")
	check_close(main.sun.directional_shadow_max_distance, C.QUALITY_PRESETS[1].shadow_distance,
		0.01, "阴影距离应跟预设一致")
	var scale: float = main.get_viewport().scaling_3d_scale
	check(scale >= C.QUALITY_PRESETS[1].scale_min - 0.001 and scale <= C.QUALITY_PRESETS[1].scale_max + 0.001,
		"3D 比例应在均衡档范围内")

	main.hud.set_perf_visible(true)
	main.hud.set_perf("FPS 60  16.7ms")
	main.hud.hitmarker(true)
	check(main.hud._perf.visible, "性能面板应可见")
	check(main.hud._hitmarker.modulate.a > 0.0, "命中标记应显示")

	main._apply_quality(0)
	check_eq(Engine.max_fps, 30, "省电档应锁 30 帧")
	check_close(main.sun.directional_shadow_max_distance, C.QUALITY_PRESETS[0].shadow_distance,
		0.01, "省电档阴影距离应更短")
	main._apply_quality(1)

	main.hud._on_quality_selected(2)
	check_eq(main._quality, 2, "菜单切高清应生效")
	main.hud._on_quality_selected(1)

	# fresh=false 不写存档，测试不覆盖玩家进度
	main._start(false)
	await get_tree().process_frame
	check(main.running, "开局后 running 应为 true")
	check(main.hp > 0.0, "开局应满血")
	main.hud._on_show_perf_toggled(true)
	check(main.hud._perf.visible, "设置里的性能开关应生效")
	main.hud._on_show_perf_toggled(false)

	# 手动跑 3 秒游戏逻辑，检查天空、动态分辨率、生存循环不报错
	main.set_process(false)
	var hours_before: float = main.game_hours
	for i in 180:
		main._process(1.0 / 60.0)
	main.set_process(true)
	check(main.game_hours > hours_before, "游戏时间应前进")
	check(main.running, "3 秒后不应结束")
	var scale_now: float = main.get_viewport().scaling_3d_scale
	check(scale_now >= C.QUALITY_PRESETS[1].scale_min - 0.001 and scale_now <= C.QUALITY_PRESETS[1].scale_max + 0.001,
		"运行中 3D 比例仍在范围内")

	# 后坐力应回落，落地应有镜头下压
	main._recoil = 0.2
	for i in 30:
		main._update_player(1.0 / 60.0)
	check(main._recoil < 0.2, "后坐力应逐渐回弹")
	main.player.position.y = 0.001
	main._vy = -5.0
	main._update_player(1.0 / 60.0)
	check(main._land_dip > 0.0, "落地应产生镜头下压")

	# 有素材时顺便跑一遍枪和近战的持握/挥动，合并 PR #5 的手臂关键帧后不要报错
	var gun_id := ""
	for row in Assets.items:
		if row.kind == Assets.Kind.GUN:
			gun_id = row.id
			break
	if gun_id != "":
		main.inventory[gun_id] = 1
		main.mags[gun_id] = 30
		main._equip(gun_id)
		for i in 20:
			main._update_player(1.0 / 60.0)
			main.arms._update_pose(1.0 / 60.0)
		check(main.equipped == gun_id, "持枪姿势不应报错")
	var melee_id := ""
	for row in Assets.items:
		if row.kind == Assets.Kind.MELEE:
			melee_id = row.id
			break
	if melee_id != "":
		main.inventory[melee_id] = 1
		main._equip(melee_id)
		main.arms.swing(6.0)
		for i in 60:
			main._update_player(1.0 / 60.0)
			main.arms._update_pose(1.0 / 60.0)
		check(main.equipped == melee_id, "近战挥动姿势不应报错")
	_finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s：期望 %s，实际 %s" % [message, expected, actual])


func check_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s：期望 %.4f，实际 %.4f" % [message, expected, actual])


func _restore_settings() -> void:
	if _settings_existed:
		var f := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		if f:
			f.store_buffer(_settings_data)
	elif FileAccess.file_exists("user://settings.cfg"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))


func _finish() -> void:
	_restore_settings()
	if failures.is_empty():
		print("PASS test_smoke")
		get_tree().quit(0)
		return
	for f in failures:
		push_error("test_smoke: " + f)
	print("FAIL test_smoke（%d 项）" % failures.size())
	get_tree().quit(1)
