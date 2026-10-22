class_name Sfx
extends Node
## 音效。assets/sounds/ 里有同名文件（如 gun_pistol.wav、groan_2.ogg）就用文件，
## 没有就用代码合成的声音（枪声、脚步、僵尸低吼、尖叫……），保证不缺声音。
## play() 是 2D（自己的脚步、开枪、受伤），play_at() 是 3D（僵尸、远处的爆炸），会随距离变小。

const RATE := 22050
const DIR := "res://assets/sounds"
## 每种声音合成几个变体，轮流用，听起来不会太机械
const VARIANTS := {"groan": 3, "footstep": 4, "hit_flesh": 2, "attack": 2}

var volume_db := 0.0
var _streams := {}     # 名字 -> Array[AudioStream]
var _pool2d: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _next2d := 0
var _next3d := 0
var _rng := RandomNumberGenerator.new()
var _makers := {}
var _todo: Array = []


func _ready() -> void:
	_rng.seed = 7
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "Sfx"
		add_child(p)
		_pool2d.append(p)
	for i in 14:
		var p := AudioStreamPlayer3D.new()
		p.bus = "Sfx"
		p.unit_size = 5.0
		p.max_distance = 70.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool3d.append(p)
	_load_files()
	_prepare()


## 合成要一点时间（手机上约 1 秒），所以开局界面时每帧合成一个；还没合成的声音第一次用时当场合成
func _process(_delta: float) -> void:
	if not _todo.is_empty():
		_synth(_todo.pop_back())


func play(name: String, vol_db := 0.0, pitch := 1.0) -> void:
	var s := _pick(name)
	if s == null:
		return
	var p := _pool2d[_next2d]
	_next2d = (_next2d + 1) % _pool2d.size()
	p.stream = s
	p.volume_db = vol_db + volume_db
	p.pitch_scale = pitch * _rng.randf_range(0.95, 1.05)
	p.play()


func play_at(name: String, pos: Vector3, vol_db := 0.0, pitch := 1.0) -> void:
	var s := _pick(name)
	if s == null:
		return
	# 找一个空闲的播放器，没有就抢最早的那个
	var p: AudioStreamPlayer3D = null
	for i in _pool3d.size():
		var c := _pool3d[(_next3d + i) % _pool3d.size()]
		if not c.playing:
			p = c
			break
	if p == null:
		p = _pool3d[_next3d]
	_next3d = (_next3d + 1) % _pool3d.size()
	p.global_position = pos
	p.stream = s
	p.volume_db = vol_db + volume_db
	p.pitch_scale = pitch * _rng.randf_range(0.92, 1.08)
	p.play()


func _pick(name: String) -> AudioStream:
	if not _streams.has(name) and _makers.has(name):
		_synth(name)
		_todo.erase(name)
	var list: Array = _streams.get(name, [])
	if list.is_empty():
		return null
	return list[_rng.randi_range(0, list.size() - 1)]


## assets/sounds/<名字>.wav 或 <名字>_2.ogg 这样的文件，按名字前缀归类
func _load_files() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	var re := RegEx.create_from_string("^([a-z_]+?)(_\\d+)?\\.(wav|ogg|mp3)$")
	for f in DirAccess.get_files_at(DIR):
		var name := f.trim_suffix(".remap").trim_suffix(".import")
		var m := re.search(name.to_lower())
		if m == null:
			continue
		var res = load("%s/%s" % [DIR, name])
		if res is AudioStream:
			var key := m.get_string(1)
			if not _streams.has(key):
				_streams[key] = []
			if not _streams[key].has(res):
				_streams[key].append(res)


# —— 合成 ——

func _synth_all() -> void:
	_prepare()
	while not _todo.is_empty():
		_synth(_todo.pop_back())


func _synth(name: String) -> void:
	if _streams.has(name):
		return   # 有真实音效文件就不合成
	var list := []
	for v in VARIANTS.get(name, 1):
		list.append(_to_stream(_makers[name].call()))
	_streams[name] = list


func _prepare() -> void:
	_makers = {
		"gun_pistol": _gun.bind(0.45, 130.0, 0.9),
		"gun_rifle": _gun.bind(0.75, 85.0, 1.0),
		"gun_shotgun": _gun.bind(0.95, 60.0, 0.6),
		"gun_bow": _bow,
		"explosion": _gun.bind(1.6, 40.0, 0.35),
		"dry_fire": _click.bind(0.0),
		"reload": _reload,
		"swing": _swing,
		"hit_flesh": _hit.bind(false),
		"headshot": _hit.bind(true),
		"groan": _voice.bind(1.4, 85.0, 70.0, 0.25, [480.0, 1050.0]),
		"attack": _voice.bind(0.6, 135.0, 120.0, 0.45, [650.0, 1300.0]),
		"death": _voice.bind(1.0, 120.0, 55.0, 0.3, [420.0, 900.0]),
		"scream": _voice.bind(1.9, 820.0, 1050.0, 0.2, [1800.0, 3000.0]),
		"player_hurt": _voice.bind(0.35, 210.0, 140.0, 0.15, [700.0, 1200.0]),
		"spit": _spit,
		"acid": _sizzle,
		"footstep": _footstep,
		"land": _thump.bind(0.18, 70.0),
		"heartbeat": _heartbeat,
		"pickup": _blip,
		"search": _rustle,
		"eat": _eat,
		"drink": _drink,
	}
	_todo = _makers.keys().filter(func(n): return not _streams.has(n))


func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## 一阶低通的系数
func _lp(cutoff: float) -> float:
	return 1.0 - exp(-TAU * cutoff / RATE)


func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)


## 枪声：开头一下很亮的爆音，接着低频的「砰」，最后是在楼间回荡的尾音
func _gun(length: float, boom_hz: float, bright: float) -> PackedFloat32Array:
	var b := _buf(length)
	var lo := 0.0
	var lo2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := _noise()
		lo += _lp(lerp(5000.0, 400.0, min(1.0, t * 8.0)) * bright) * (n - lo)
		lo2 += _lp(500.0) * (n - lo2)
		var crack := n * exp(-t * 90.0) * 0.9
		var body := lo * exp(-t * 14.0) * 1.2
		var boom := sin(TAU * boom_hz * t * (1.0 - t * 0.6)) * exp(-t * 18.0) * 0.9
		var tail := lo2 * exp(-t * 4.5) * 0.5
		b[i] = (crack + body + boom + tail) * 0.8
	return b


func _bow() -> PackedFloat32Array:
	var b := _buf(0.4)
	for i in b.size():
		var t := float(i) / RATE
		var f := 190.0 * (1.0 + 0.3 * exp(-t * 30.0))
		b[i] = (sin(TAU * f * t) * 0.6 + sin(TAU * f * 2.0 * t) * 0.25) * exp(-t * 11.0) + _noise() * exp(-t * 120.0) * 0.4
	return b


func _click(at: float, length := 0.06) -> PackedFloat32Array:
	var b := _buf(at + length)
	var hp := 0.0
	var prev := 0.0
	for i in range(int(at * RATE), b.size()):
		var t := float(i) / RATE - at
		var n := _noise()
		hp = 0.7 * (hp + n - prev)
		prev = n
		b[i] = hp * exp(-t * 120.0) * 0.8 + sin(TAU * 1800.0 * t) * exp(-t * 200.0) * 0.3
	return b


func _reload() -> PackedFloat32Array:
	var b := _buf(0.75)
	for part in [[0.0, 1.0], [0.42, 0.9], [0.6, 1.2]]:
		var c := _click(part[0])
		for i in c.size():
			if i < b.size():
				b[i] += c[i] * part[1]
	# 弹匣滑进去的摩擦声
	var lo := 0.0
	for i in range(int(0.1 * RATE), int(0.38 * RATE)):
		var t := float(i) / RATE - 0.1
		lo += _lp(2500.0) * (_noise() - lo)
		b[i] += lo * sin(PI * t / 0.28) * 0.25
	return b


func _swing() -> PackedFloat32Array:
	var b := _buf(0.3)
	var lo := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lo += _lp(500.0 + 2500.0 * sin(PI * t / 0.3)) * (_noise() - lo)
		b[i] = lo * sin(PI * t / 0.3) * 0.9
	return b


func _hit(head: bool) -> PackedFloat32Array:
	var b := _buf(0.3)
	var lo := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lo += _lp(900.0) * (_noise() - lo)
		var v := sin(TAU * 95.0 * t) * exp(-t * 28.0) * 0.8 + lo * exp(-t * 22.0) * 0.9
		if head and _rng.randf() < 0.02 * exp(-t * 15.0) * 10.0:
			v += _noise() * 0.6   # 骨头碎的噼啪声
		b[i] = v
	return b


## 嗓音：锯齿波声带 + 两个共振峰，f0 从 f_start 滑到 f_end，rough 是沙哑程度
func _voice(length: float, f_start: float, f_end: float, rough: float, formants: Array) -> PackedFloat32Array:
	var b := _buf(length)
	var phase := 0.0
	var vib := _rng.randf() * TAU
	var s1 := [0.0, 0.0]
	var s2 := [0.0, 0.0]
	var f0j := _rng.randf_range(0.9, 1.1)
	for i in b.size():
		var t := float(i) / RATE
		var k := t / length
		var f0: float = lerp(f_start, f_end, k) * f0j * (1.0 + 0.04 * sin(vib + t * 31.0) + rough * 0.15 * _noise())
		phase = fmod(phase + f0 / RATE, 1.0)
		var src := (phase * 2.0 - 1.0) + _noise() * rough
		var y := _svf(src, formants[0], 6.0, s1) + _svf(src, formants[1], 8.0, s2) * 0.6
		var env := sin(PI * min(1.0, k * 1.15)) * (1.0 - k * 0.3)
		b[i] = y * env * 0.7
	return b


## 状态变量滤波器的带通，state 是 [low, band]
func _svf(x: float, f: float, q: float, state: Array) -> float:
	var g := 2.0 * sin(PI * min(f, RATE * 0.2) / RATE)
	var low: float = state[0] + g * state[1]
	var high: float = x - low - state[1] / q
	var band: float = state[1] + g * high
	state[0] = low
	state[1] = band
	return band


func _spit() -> PackedFloat32Array:
	var b := _buf(0.5)
	var st := [0.0, 0.0]
	for i in b.size():
		var t := float(i) / RATE
		var am := 0.5 + 0.5 * sin(TAU * 24.0 * t)
		b[i] = _svf(_noise(), 380.0, 3.0, st) * am * sin(PI * t / 0.5) * 1.4
	return b


func _sizzle() -> PackedFloat32Array:
	var b := _buf(0.7)
	var hp := 0.0
	var prev := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := _noise() * (1.0 if _rng.randf() < 0.3 else 0.2)
		hp = 0.8 * (hp + n - prev)
		prev = n
		b[i] = hp * exp(-t * 4.0) * 0.5
	return b


func _footstep() -> PackedFloat32Array:
	var b := _buf(0.14)
	var lo := 0.0
	var cut := _rng.randf_range(300.0, 700.0)
	for i in b.size():
		var t := float(i) / RATE
		lo += _lp(cut) * (_noise() - lo)
		b[i] = lo * exp(-t * 40.0) * 1.6 + sin(TAU * 60.0 * t) * exp(-t * 50.0) * 0.4
	return b


func _thump(length: float, hz: float) -> PackedFloat32Array:
	var b := _buf(length)
	var lo := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lo += _lp(400.0) * (_noise() - lo)
		b[i] = sin(TAU * hz * t) * exp(-t * 25.0) * 0.9 + lo * exp(-t * 30.0)
	return b


func _heartbeat() -> PackedFloat32Array:
	var b := _buf(0.8)
	for at in [0.0, 0.22]:
		for i in range(int(at * RATE), int((at + 0.2) * RATE)):
			var t: float = float(i) / RATE - at
			b[i] += sin(TAU * 52.0 * t) * exp(-t * 22.0) * (1.0 if at == 0.0 else 0.7)
	return b


func _blip() -> PackedFloat32Array:
	var b := _buf(0.18)
	for i in b.size():
		var t := float(i) / RATE
		var f := 660.0 if t < 0.07 else 990.0
		b[i] = sin(TAU * f * t) * 0.35 * exp(-fmod(t, 0.07) * 25.0)
	return b


func _rustle() -> PackedFloat32Array:
	var b := _buf(0.6)
	var st := [0.0, 0.0]
	var am := 0.0
	for i in b.size():
		if i % 600 == 0:
			am = _rng.randf_range(0.1, 1.0)
		b[i] = _svf(_noise(), 2200.0, 1.5, st) * am * 0.6
	return b


func _eat() -> PackedFloat32Array:
	var b := _buf(0.6)
	var lo := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lo += _lp(1500.0) * (_noise() - lo)
		var bite := exp(-fmod(t, 0.2) * 25.0)
		b[i] = lo * bite * 0.9
	return b


func _drink() -> PackedFloat32Array:
	var b := _buf(0.7)
	for i in b.size():
		var t := float(i) / RATE
		var k := fmod(t, 0.23)
		b[i] = sin(TAU * (180.0 + 400.0 * k) * k) * exp(-k * 18.0) * 0.6
	return b
