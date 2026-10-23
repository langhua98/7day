extends Node
## 全局事件总线和共享状态。各系统只通过这里的信号通讯。

signal hour_changed(day: int, hour: float)
signal day_started(day: int)
signal night_started
signal dawn
signal zombie_killed(zombie: Node, by_weapon: String)
signal player_damaged(amount: float, source: String)
signal noise(pos: Vector3, radius: float, kind: String)
signal block_changed(cell: Vector3i)
signal item_used(id: String)
signal blood_moon_warning(hour: int)
signal blood_moon_started
signal blood_moon_ended(count: int)
## 死亡与重生（3c）：死在哪、在哪醒来、睡袋摆在哪（yaw 是朝向）
signal player_died(pos: Vector3)
signal player_respawned(pos: Vector3)
signal bedroll_placed(pos: Vector3, yaw: float)

const C = preload("res://scripts/config.gd")

var day := 1
var hours := C.START_HOUR
var player: Node3D
var running := false
var blood_moon := false
var blood_moons_survived := 0
## 死亡扣掉的存活天数（存活天数 = 天数 − 这个，最少 0）
var days_alive_lost := 0


func reset() -> void:
	day = 1
	hours = C.START_HOUR
	blood_moon = false
	blood_moons_survived = 0
	days_alive_lost = 0


func gamestage() -> int:
	# 还没有等级系统，先把等级当作天数；官方公式 (等级 + 存活天数) × 1.2
	var level := maxi(1, day)
	return maxi(1, floori((level + mini(days_alive(), level)) * 1.2))


## 存活天数：每死一次 −2（官方 daysAliveChangeWhenKilled），之后照常一天天涨
func days_alive() -> int:
	return maxi(0, day - days_alive_lost)


## 死了：存活天数减 n，最少减到 0
func lose_days_alive(n: int) -> void:
	var left := maxi(0, days_alive() - n)
	days_alive_lost = day - left


func current_gamestage() -> int:
	return gamestage()


func is_blood_moon() -> bool:
	return blood_moon


## 还有几天到下一次血月（0 = 今晚，正在血月时不返回 0）
func days_until_blood_moon() -> int:
	var d := int(hours / 24.0) + 1
	var rem := d % C.BLOOD_MOON_EVERY
	if blood_moon:
		return C.BLOOD_MOON_EVERY if rem == 0 else C.BLOOD_MOON_EVERY - rem
	var until := (C.BLOOD_MOON_EVERY - rem) % C.BLOOD_MOON_EVERY
	if until == 0 and fmod(hours, 24.0) >= C.DUSK_HOUR:
		until = C.BLOOD_MOON_EVERY
	return until


func next_blood_moon_day() -> int:
	return int(hours / 24.0) + 1 + days_until_blood_moon()
