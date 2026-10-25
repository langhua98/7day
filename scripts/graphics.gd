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
## 卡顿统计：最近一段时间里比 HITCH_MS 慢的帧（性能面板显示，方便在手机上确认）
const HITCH_MS := 25.0
var _hitch_times: Array[float] = []
var _worst_ms := 0.0
var _clock := 0.0
## 着色器管线编译次数（引擎的累计计数）。画面卡一下时如果这个数跟着涨，说明是现编着色器
var _pipe_hist: Array[Vector2] = []   # (时刻, 累计次数)，留最近 10 秒


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
	world.update_detail(player.player.global_position)
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
	_clock += delta
	var ms := delta * 1000.0
	_worst_ms = maxf(_worst_ms, ms)
	if ms > HITCH_MS:
		_hitch_times.append(_clock)
	while not _hitch_times.is_empty() and _clock - _hitch_times[0] > 10.0:
		_hitch_times.pop_front()
	_lod_t += delta
	if _lod_t >= C.LOD_UPDATE_INTERVAL:
		_lod_t = 0.0
		world.update_shadows(player.player.global_position, quality)
		world.update_detail(player.player.global_position)
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
	var pipes := pipeline_compilations()
	_pipe_hist.append(Vector2(_clock, pipes))
	while _pipe_hist.size() > 1 and _clock - _pipe_hist[0].x > 10.0:
		_pipe_hist.pop_front()
	var pipes_recent := pipes - int(_pipe_hist[0].y)
	hud.set_perf("FPS %d  %.1f ms\n绘制 %d  三角面 %dk\n3D %.2f  僵尸 %d  节点 %d\n最慢 %.0f ms  10 秒内卡顿 %d 次\n着色器编译 共 %d  10 秒内 %d\n%s %s" % [
		fps, ms, draws, prims / 1000, main.get_viewport().scaling_3d_scale,
		zombie_root.get_child_count(), nodes, _worst_ms, _hitch_times.size(), pipes, pipes_recent,
		RenderingServer.get_current_rendering_driver_name(), world.full_debug(player.player.global_position)])
	_worst_ms = 0.0


## 引擎从开局到现在编译过的渲染管线总数（加载网格、换材质、第一次画某种效果都会触发）
static func pipeline_compilations() -> int:
	return int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS)
		+ Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH)
		+ Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE)
		+ Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)
		+ Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION))
