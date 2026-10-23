extends "res://tests/test_base.gd"
## 动态分辨率调节器：稳定时不动，掉帧时降，余量足时升，且不越界。


func _initialize() -> void:
	var g := PerfGovernor.new()
	g.configure(0.5, 0.8, 0.7, 60.0, 0.5, 1.15, 0.9)
	check_close(g.scale, 0.7, 0.0001, "起始比例")
	check_close(g.step(1.0 / 60.0), 0.7, 0.0001, "step 应返回当前比例")

	for i in 120:
		g.step(1.0 / 60.0)
	check_close(g.scale, 0.7, 0.0001, "稳定 60 帧不应改变比例")

	for i in 120:
		g.step(1.0 / 45.0)
	check_close(g.scale, 0.5, 0.0001, "45 帧应降到下限")

	for i in 600:
		g.step(1.0 / 100.0)
	check_close(g.scale, 0.8, 0.0001, "高帧率应升到上限")

	# 30 帧档：30 帧稳定，20 帧掉到下限
	var low := PerfGovernor.new()
	low.configure(0.45, 0.6, 0.55, 30.0, 0.5, 1.15, 0.9)
	for i in 120:
		low.step(1.0 / 30.0)
	check_close(low.scale, 0.55, 0.0001, "30 帧稳定不应改变比例")
	for i in 120:
		low.step(1.0 / 20.0)
	check_close(low.scale, 0.45, 0.0001, "20 帧应降到下限")

	# 极端帧时间也不能越界
	for i in 30:
		low.step(2.0)
	check_close(low.scale, 0.45, 0.0001, "长时间卡顿仍保留下限")
	for i in 3000:
		low.step(0.001)
	check_close(low.scale, 0.6, 0.0001, "极快帧率仍保留上限")
	finish("test_perf")
