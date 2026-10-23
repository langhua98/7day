class_name GraphicsSystem
extends RefCounted
## 画质档位、动态 3D 分辨率、近处阴影开关和性能面板。

const C = preload("res://scripts/config.gd")

var main: Node3D
var world: World
var atmosphere: Atmosphere
var player: PlayerSystem
var hud: Hud
var zombie_root: Node3D

var quality := 1
var _applied := false
var _governor := PerfGovernor.new()
var _sky_t := 0.0
var _lod_t := 0.0
var _perf_t := 0.0


func setup(parent: Node3D, world_ref: World, atmo: Atmosphere, player_ref: PlayerSystem,
		hud_ref: Hud, zombies: Node3D) -> void:
	main = parent
	world = world_ref
	atmosphere = atmo
	player = player_ref
	hud = hud_ref
	zombie_root = zombies
	# 先按均衡档锁帧，读完设置后再切到玩家选的档位
	Engine.max_fps = C.QUALITY_PRESETS[1].fps


## 设置变化时调用；只有画质档位真的变了才重建阴影和可见距离
func apply_settings(st: Dictionary) -> void:
	var q := clampi(int(st.get("quality", 1)), 0, C.QUALITY_PRESETS.size() - 1)
	if not _applied or q != quality:
		_applied = true
		apply_quality(q)
	hud.set_perf_visible(float(st.get("show_perf", 0.0)) > 0.5 and GameState.running)


func apply_quality(level: int) -> void:
	quality = clampi(level, 0, C.QUALITY_PRESETS.size() - 1)
	var p: Dictionary = C.QUALITY_PRESETS[quality]
	Engine.max_fps = int(p.fps)
	_governor.configure(p.scale_min, p.scale_max, p.scale_start, p.fps, C.PERF_UPDATE_INTERVAL)
	main.get_viewport().scaling_3d_scale = _governor.scale
	var sun := atmosphere.sun
	sun.shadow_enabled = quality > 0
	sun.directional_shadow_max_distance = p.shadow_distance
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if quality < 2 \
		else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	RenderingServer.directional_shadow_atlas_set_size(int(p.shadow_atlas), true)
	world.apply_quality(quality, p)
	world.update_shadows(player.player.global_position, quality)
	_perf_t = 0.0


## 开局 / 继续时调用：僵尸恢复处理，阴影按玩家位置刷新
func on_start() -> void:
	zombie_root.process_mode = Node.PROCESS_MODE_INHERIT
	_sky_t = 0.0
	_lod_t = 0.0
	apply_quality(quality)
	hud.set_perf_visible(hud.settings.show_perf > 0.5)


## 回到标题或死亡：结算界面不跑僵尸 AI 和骨骼，省电
func on_stop() -> void:
	zombie_root.process_mode = Node.PROCESS_MODE_DISABLED
	hud.set_perf_visible(false)


## 天空不必每帧算，到点了返回 true
func sky_due(delta: float) -> bool:
	_sky_t += delta
	if _sky_t >= C.SKY_UPDATE_INTERVAL:
		_sky_t = 0.0
		return true
	return false


func update(delta: float) -> void:
	_lod_t += delta
	if _lod_t >= C.LOD_UPDATE_INTERVAL:
		_lod_t = 0.0
		world.update_shadows(player.player.global_position, quality)
	var s := _governor.step(delta)
	var vp := main.get_viewport()
	if not is_equal_approx(s, vp.scaling_3d_scale):
		vp.scaling_3d_scale = s
	_update_perf(delta)


func _update_perf(delta: float) -> void:
	if hud.settings.show_perf <= 0.5:
		return
	_perf_t += delta
	if _perf_t < C.PERF_UPDATE_INTERVAL:
		return
	_perf_t = 0.0
	var fps := int(Engine.get_frames_per_second())
	var ms := 1000.0 / maxf(fps, 1.0)
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	hud.set_perf("FPS %d  %.1f ms\n绘制 %d  三角面 %dk\n3D %.2f  僵尸 %d  节点 %d" % [
		fps, ms, draws, prims / 1000, main.get_viewport().scaling_3d_scale,
		zombie_root.get_child_count(), nodes])
