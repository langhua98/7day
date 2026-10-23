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

const C = preload("res://scripts/config.gd")

var day := 1
var hours := C.START_HOUR
var gamestage := 0
var player: Node3D
var running := false


func reset() -> void:
	day = 1
	hours = C.START_HOUR
	gamestage = 0


func current_gamestage() -> int:
	return maxi(1, gamestage)
