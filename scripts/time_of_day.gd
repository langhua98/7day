class_name TimeOfDay
extends RefCounted
## 时间推进：一天 24 真实分钟（测试模式 3 分钟），血月每 7 天一次。
## 总小时数从第 1 天 0:00 起算，和第 0 步存档里的 hours 兼容。

const C = preload("res://scripts/config.gd")

var hours := C.START_HOUR
var day := 1
var night := false
var blood_moon := false
var blood_moons_survived := 0
## 测试用：一天多少真实秒；<= 0 时读 config
var seconds_per_day := 0.0

var _warned_18 := false
var _warned_21 := false
var _last_hour := -1


func reset() -> void:
	hours = C.START_HOUR
	day = 1
	night = false
	blood_moon = false
	blood_moons_survived = 0
	_warned_18 = false
	_warned_21 = false
	_last_hour = -1
	_sync()


func _day_length() -> float:
	if seconds_per_day > 0.0:
		return seconds_per_day
	return C.FAST_DAY_SECONDS if C.TEST_FAST_TIME else C.DAY_LENGTH_MIN * 60.0


func update(delta: float) -> void:
	var old_day := day
	hours += delta * 24.0 / _day_length()
	day = int(hours / 24.0) + 1
	var hour := fmod(hours, 24.0)
	if day != old_day:
		_warned_18 = false
		_warned_21 = false
		GameState.day_started.emit(day)
	var hour_int := int(hour)
	if hour_int != _last_hour:
		_last_hour = hour_int
		GameState.hour_changed.emit(day, hour)

	var was_night := night
	night = hour >= C.DUSK_HOUR or hour < C.DAWN_HOUR
	if night and not was_night:
		GameState.night_started.emit()
	elif not night and was_night:
		GameState.dawn.emit()

	var moon_day := day % C.BLOOD_MOON_EVERY == 0
	# 先发 18/21 点预警，再在 22 点进入血月
	if moon_day:
		if hour >= 18.0 and not _warned_18:
			_warned_18 = true
			GameState.blood_moon_warning.emit(18)
		if hour >= 21.0 and not _warned_21:
			_warned_21 = true
			GameState.blood_moon_warning.emit(21)
	if moon_day and not blood_moon and hour >= C.DUSK_HOUR:
		blood_moon = true
		GameState.blood_moon = true
		GameState.blood_moon_started.emit()
	elif blood_moon and hour >= C.DAWN_HOUR and hour < C.DUSK_HOUR:
		blood_moon = false
		blood_moons_survived += 1
		GameState.blood_moon = false
		GameState.blood_moon_ended.emit(blood_moons_survived)
	_sync()


## 读档/测试用：直接设总小时数，不触发信号
func set_time(total_hours: float) -> void:
	hours = total_hours
	day = int(hours / 24.0) + 1
	var hour := fmod(hours, 24.0)
	night = hour >= C.DUSK_HOUR or hour < C.DAWN_HOUR
	var moon_day := day % C.BLOOD_MOON_EVERY == 0
	blood_moon = (moon_day and hour >= C.DUSK_HOUR) or (day % C.BLOOD_MOON_EVERY == 1 and hour < C.DAWN_HOUR)
	_warned_18 = moon_day and hour >= 18.0
	_warned_21 = moon_day and hour >= 21.0
	_last_hour = int(hour)
	_sync()


func _sync() -> void:
	GameState.hours = hours
	GameState.day = day
	GameState.blood_moon = blood_moon
	GameState.blood_moons_survived = blood_moons_survived


func save_data() -> Dictionary:
	return {"hours": hours, "blood_moons_survived": blood_moons_survived}


func load_data(d: Dictionary) -> void:
	blood_moons_survived = int(d.get("blood_moons_survived", 0))
	set_time(float(d.get("hours", C.START_HOUR)))
