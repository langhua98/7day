extends "res://tests/test_base.gd"
## 画质预设必须完整、数值单调，避免菜单选到一半缺参数。

const C = preload("res://scripts/config.gd")

const REQUIRED := ["name", "fps", "scale_min", "scale_max", "scale_start", "shadow_distance",
	"shadow_atlas", "poi_shadow_distance", "prop_shadow_distance", "poi_range", "car_range",
	"prop_range", "small_range", "deco_range", "decal_range"]


func _initialize() -> void:
	check_eq(C.QUALITY_PRESETS.size(), 3, "应有省电/均衡/高清三档")
	check_eq(C.QUALITY_PRESETS[0].fps, 30, "省电锁 30 帧")
	check_eq(C.QUALITY_PRESETS[1].fps, 60, "均衡锁 60 帧")
	check_eq(C.QUALITY_PRESETS[2].fps, 60, "高清锁 60 帧")
	for i in C.QUALITY_PRESETS.size():
		var p: Dictionary = C.QUALITY_PRESETS[i]
		for key in REQUIRED:
			check(p.has(key), "预设 %d 缺少 %s" % [i, key])
		if not p.has("scale_min"):
			continue
		check(p.scale_min < p.scale_max, "预设 %d：scale_min 应小于 scale_max" % i)
		check(p.scale_start >= p.scale_min and p.scale_start <= p.scale_max,
			"预设 %d：scale_start 应在范围内" % i)
		var ranges := [p.shadow_distance, p.poi_shadow_distance, p.prop_shadow_distance,
			p.poi_range, p.car_range, p.prop_range, p.small_range, p.deco_range, p.decal_range]
		for v in ranges:
			check(v >= 0.0, "预设 %d：距离不能为负" % i)
		check(p.small_range <= p.prop_range and p.prop_range <= p.car_range,
			"预设 %d：小件/道具/车的可见距离应递增" % i)
		check(p.poi_range <= 260.0, "预设 %d：楼不能超过相机远裁剪" % i)
	check(C.QUALITY_PRESETS[2].scale_max > C.QUALITY_PRESETS[1].scale_max,
		"高清的渲染比例上限应高于均衡")
	finish("test_config")
