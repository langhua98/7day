extends Node
## 音效：assets/sounds/index.json 里每组几段声音，play 时随机挑一段。
## 带位置的用 3D 播放器（远了会变小声），不带位置的直接在耳边放。

const INDEX := "res://assets/sounds/index.json"
const POOL_3D := 18
const POOL_2D := 8

## 音效分条总线：Sfx、Zombies、UI；音乐走 Music（暂停菜单里分别调音量）
static func bus_for(group: String) -> String:
	if group.begins_with("zm_") or group.begins_with("zf_") or group == "scream":
		return "Zombies"
	if group == "loot":
		return "UI"
	return "Sfx"
func set_volume(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))
		AudioServer.set_bus_mute(i, v <= 0.01)

var _groups := {}      # 组名 -> [AudioStream]
var _p3: Array[AudioStreamPlayer3D] = []
var _p2: Array[AudioStreamPlayer] = []
var _loops := {}       # 名字 -> AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for bus in ["Sfx", "Music", "Zombies", "UI"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	if not FileAccess.file_exists(INDEX):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(INDEX)) != OK or not (json.data is Dictionary):
		push_warning("assets/sounds/index.json 格式不对，音效跳过")
		return
	var idx: Dictionary = json.data
	for g in idx:
		var list := []
		for path in idx[g]:
			var s = load("res://assets/" + path)
			if s is AudioStream:
				list.append(s)
		_groups[g] = list
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 6.0
		p.max_distance = 70.0
		p.attenuation_filter_cutoff_hz = 6000.0
		p.bus = "Sfx"
		add_child(p)
		_p3.append(p)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "Sfx"
		add_child(p)
		_p2.append(p)


func has(group: String) -> bool:
	return not _groups.get(group, []).is_empty()


## 播一段；at 给了就是 3D 声音
func play(group: String, at := Vector3.INF, db := 0.0, pitch_jitter := 0.08) -> void:
	var list: Array = _groups.get(group, [])
	if list.is_empty():
		return
	var stream: AudioStream = list[_rng.randi_range(0, list.size() - 1)]
	var pitch := 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	if at == Vector3.INF:
		var p := _free(_p2)
		p.stream = stream
		p.volume_db = db
		p.pitch_scale = pitch
		p.bus = bus_for(group)
		p.play()
	else:
		var p := _free(_p3)
		p.stream = stream
		p.volume_db = db
		p.pitch_scale = pitch
		p.global_position = at
		p.bus = bus_for(group)
		p.play()


func _free(pool: Array) -> Node:
	for p in pool:
		if not p.playing:
			return p
	# 全在响：抢最早开始的那个
	var best = pool[0]
	for p in pool:
		if p.get_playback_position() > best.get_playback_position():
			best = p
	return best


## 循环的环境声；target_db 是要渐变到的音量，-80 就是关掉
func loop(group: String, target_db: float, delta: float) -> void:
	var p: AudioStreamPlayer = _loops.get(group)
	if p == null:
		var list: Array = _groups.get(group, [])
		if list.is_empty():
			return
		var s: AudioStream = list[0]
		if s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(s.get_length() * s.mix_rate)
		elif "loop" in s:
			s.loop = true
		p = AudioStreamPlayer.new()
		p.stream = s
		p.volume_db = -60.0
		p.bus = bus_for(group)
		add_child(p)
		_loops[group] = p
	p.volume_db = move_toward(p.volume_db, target_db, delta * 20.0)
	if p.volume_db > -55.0 and not p.playing:
		p.play()
	elif p.volume_db <= -59.0 and p.playing:
		p.stop()


func stop_loops() -> void:
	for p in _loops.values():
		p.stop()
		p.volume_db = -60.0
