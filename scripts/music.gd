class_name MusicDirector
extends Node
## 按局势切换音乐：探索 Exp / 紧张 Sus / 战斗 Cbt / 血月 Bld，两个播放器交叉淡入淡出。

var state := ""
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _rng := RandomNumberGenerator.new()
var _last := {}
var _pending := ""
var _pending_t := 0.0


func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -60.0
		p.bus = "Master"
		p.finished.connect(_on_finished.bind(i))
		add_child(p)
		_players.append(p)


## 请求切换；为避免来回跳，新状态要持续一小会儿才生效（进入战斗立刻生效）
func request(new_state: String, delta: float) -> void:
	if new_state == state:
		_pending = ""
		return
	if new_state != _pending:
		_pending = new_state
		_pending_t = 0.0
	_pending_t += delta
	var wait := 0.0 if new_state in ["Cbt", "Bld"] else 4.0
	if _pending_t >= wait:
		_switch(new_state)


func _switch(new_state: String) -> void:
	var list: PackedStringArray = Assets.music.get(new_state, PackedStringArray())
	if list.is_empty() and new_state == "Bld":
		list = Assets.music.get("Cbt", PackedStringArray())
	state = new_state
	_pending = ""
	if list.is_empty():
		return
	var next := 1 - _active
	var stream = load(_pick(list, new_state))
	if stream == null:
		return
	_players[next].stream = stream
	_players[next].volume_db = -40.0
	_players[next].play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_players[next], "volume_db", GameConfig.MUSIC_VOLUME_DB, GameConfig.MUSIC_FADE)
	tw.tween_property(_players[_active], "volume_db", -60.0, GameConfig.MUSIC_FADE)
	tw.chain().tween_callback(_players[_active].stop)
	_active = next


func _pick(list: PackedStringArray, key: String) -> String:
	var choice := list[_rng.randi_range(0, list.size() - 1)]
	if list.size() > 1 and choice == _last.get(key, ""):
		choice = list[(list.find(choice) + 1) % list.size()]
	_last[key] = choice
	return choice


## 一段放完接着放同类的下一段
func _on_finished(i: int) -> void:
	if i != _active or state == "":
		return
	var list: PackedStringArray = Assets.music.get(state, PackedStringArray())
	if list.is_empty() and state == "Bld":
		list = Assets.music.get("Cbt", PackedStringArray())
	if list.is_empty():
		return
	_players[i].stream = load(_pick(list, state))
	_players[i].play()


func stop_all() -> void:
	for p in _players:
		p.stop()
	state = ""
