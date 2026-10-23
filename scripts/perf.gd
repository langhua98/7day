class_name PerfGovernor
extends RefCounted
## 动态 3D 分辨率：按平均帧时间在 min_scale~max_scale 之间调整。
## 只负责算比例，不碰引擎，方便无头测试。

var min_scale := 0.5
var max_scale := 1.0
var scale := 1.0
var target_fps := 60.0
var interval := 0.5
var down_ratio := 1.15
var up_ratio := 0.9
var down_step := 0.05
var up_step := 0.03

var _time := 0.0
var _frames := 0
var _frame_time := 0.0


func configure(p_min: float, p_max: float, p_start: float, p_target_fps: float,
		p_interval := 0.5, p_down := 1.15, p_up := 0.9) -> void:
	min_scale = p_min
	max_scale = p_max
	scale = clampf(p_start, min_scale, max_scale)
	target_fps = maxf(p_target_fps, 1.0)
	interval = maxf(p_interval, 0.05)
	down_ratio = p_down
	up_ratio = p_up
	_reset()


func step(delta: float) -> float:
	_time += delta
	_frames += 1
	_frame_time += delta
	if _time >= interval:
		var avg := _frame_time / maxf(_frames, 1.0)
		var target := 1.0 / target_fps
		if avg > target * down_ratio:
			scale = maxf(min_scale, scale - down_step)
		elif avg < target * up_ratio:
			scale = minf(max_scale, scale + up_step)
		_reset()
	return scale


func _reset() -> void:
	_time = 0.0
	_frames = 0
	_frame_time = 0.0
