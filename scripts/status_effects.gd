class_name StatusEffects
extends Node
## 状态效果系统（自动加载为 Status）。饥饿、口渴、流血、腹泻、咖啡因……都在这里。
## 定义表在 config.gd 的 STATUS；持续时间、剩余时间都按「游戏小时」。
## 本身不改玩家数值：tick() 返回这段时间对血/饱食/水的增减，由 player.gd 应用。
##
## 给其它系统用的接口：
##   add(id, hours := -1.0, stacks := 1)   hours < 0 用表里默认值，0 = 一直有
##   remove(id) / has(id) / remaining(id) / stacks(id) / set_stacks(id, n)
##   modifier(stat) 倍率（默认 1）  offset(stat) 加值（默认 0）  blocked(flag) 是否禁止某动作
##   active() 当前状态列表（HUD 用）  save_data() / load_data(d)

signal status_added(id: String)
signal status_removed(id: String)

const C = preload("res://scripts/config.gd")

## id → {"left": 剩余游戏小时（0 = 一直有）, "stacks": 层数}
var _active := {}


func clear() -> void:
	for id in _active.keys():
		status_removed.emit(id)
	_active.clear()


static func def(id: String) -> Dictionary:
	return C.STATUS.get(id, {})


func add(id: String, hours := -1.0, stack_count := 1) -> void:
	var d := def(id)
	if d.is_empty():
		push_warning("未知状态 %s" % id)
		return
	var h: float = float(d.get("hours", 0.0)) if hours < 0.0 else hours
	if _active.has(id):
		var e: Dictionary = _active[id]
		if d.get("stack", false):
			e.stacks = mini(int(e.stacks) + stack_count, int(d.get("max_stack", 99)))
		# 一直有的不变成限时；限时的取更长的那个
		if float(e.left) > 0.0:
			e.left = 0.0 if h <= 0.0 else maxf(float(e.left), h)
		return
	_active[id] = {"left": h, "stacks": maxi(1, stack_count)}
	status_added.emit(id)


func remove(id: String) -> bool:
	if not _active.has(id):
		return false
	_active.erase(id)
	status_removed.emit(id)
	return true


## 条件型状态（饥饿、口渴）：on 为真就加上（一直有），否则移除
func toggle(id: String, on: bool) -> void:
	if on and not _active.has(id):
		add(id, 0.0)
	elif not on and _active.has(id):
		remove(id)


func has(id: String) -> bool:
	return _active.has(id)


## 剩余游戏小时；没有返回 0；一直有返回 INF
func remaining(id: String) -> float:
	if not _active.has(id):
		return 0.0
	var left := float(_active[id].left)
	return INF if left <= 0.0 else left


func stacks(id: String) -> int:
	return int(_active[id].stacks) if _active.has(id) else 0


## 直接设层数（感染度用层数表示百分比）；≤ 0 就移除
func set_stacks(id: String, n: int) -> void:
	if n <= 0:
		remove(id)
		return
	if not _active.has(id):
		add(id, -1.0, n)
	_active[id].stacks = mini(n, int(def(id).get("max_stack", 99)))


## 倍率修正，所有状态相乘，例如 modifier("stamina_regen")
func modifier(stat: String) -> float:
	var m := 1.0
	for id in _active:
		var mult: Dictionary = def(id).get("mult", {})
		if mult.has(stat):
			m *= float(mult[stat])
	return m


## 加值修正，所有状态相加（叠加时乘层数），例如 offset("stamina_max")
func offset(stat: String) -> float:
	var v := 0.0
	for id in _active:
		var add_d: Dictionary = def(id).get("add", {})
		if add_d.has(stat):
			v += float(add_d[stat]) * int(_active[id].stacks)
	return v


## 有没有状态禁止某动作，例如 blocked("no_sprint")
func blocked(flag: String) -> bool:
	for id in _active:
		if flag in def(id).get("flags", []):
			return true
	return false


## 有没有正在掉血的状态（掉血时不自然回血）
func losing_hp() -> bool:
	for id in _active:
		var d := def(id)
		if float(d.get("hp", 0.0)) < 0.0 or float(d.get("hp_sec", 0.0)) < 0.0:
			return true
	return false


## 推进 delta 真实秒、dh 游戏小时。返回 {"hp", "food", "water"} 的增减，并清掉到期的状态
func tick(delta: float, dh: float) -> Dictionary:
	var out := {"hp": 0.0, "food": 0.0, "water": 0.0}
	var expired := []
	for id in _active:
		var e: Dictionary = _active[id]
		var d := def(id)
		var n := float(e.stacks)
		var span := dh
		var secs := delta
		# 到期那一帧只结算剩下的部分
		if float(e.left) > 0.0:
			if dh >= float(e.left):
				span = float(e.left)
				secs = delta * span / dh if dh > 0.0 else delta
				expired.append(id)
			else:
				e.left = float(e.left) - dh
		out.hp += (float(d.get("hp", 0.0)) * span + float(d.get("hp_sec", 0.0)) * secs) * n
		out.food += float(d.get("food", 0.0)) * span * n
		out.water += float(d.get("water", 0.0)) * span * n
	for id in expired:
		remove(id)
	return out


## HUD 用：[{id, zh, short, desc, left, stacks, bad}]，坏状态排前面
func active() -> Array:
	var list := []
	for id in _active:
		var d := def(id)
		list.append({"id": id, "zh": display_name(id), "short": str(d.get("short", "?")),
			"desc": description(id), "left": remaining(id), "stacks": int(_active[id].stacks),
			"bad": bool(d.get("bad", false)), "unit": str(d.get("unit", ""))})
	list.sort_custom(func(a, b): return a.bad and not b.bad)
	return list


## 中文名：先用官方 buffs.json（build_data 生成），没有就用 config 里的
func display_name(id: String) -> String:
	var d := def(id)
	var official: Dictionary = _official(d)
	var zh := str(official.get("zh", ""))
	return zh if zh != "" else str(d.get("zh", id))


func description(id: String) -> String:
	# 说明写的是本游戏的实际数值，官方说明只作补充
	return str(def(id).get("desc", ""))


func _official(d: Dictionary) -> Dictionary:
	var name := str(d.get("buff", ""))
	if name == "" or not is_inside_tree():
		return {}
	var data := get_node_or_null("/root/Data")
	if data == null:
		return {}
	var row = data.get_table("buffs").get(name, {})
	return row if row is Dictionary else {}


func save_data() -> Dictionary:
	var s := {}
	for id in _active:
		s[id] = [float(_active[id].left), int(_active[id].stacks)]
	return {"status": s}


## 读档。旧存档没有 status，就把旧的 bleed/sick/buff（真实秒）换算成游戏小时
func load_data(d: Dictionary, seconds_per_hour := 60.0) -> void:
	clear()
	if d.has("status") and d.status is Dictionary:
		for id in d.status:
			if def(id).is_empty():
				continue
			var row = d.status[id]
			var left := float(row[0]) if row is Array and row.size() > 0 else 0.0
			var n := int(row[1]) if row is Array and row.size() > 1 else 1
			_active[id] = {"left": maxf(0.0, left), "stacks": maxi(1, n)}
			status_added.emit(id)
		return
	var sph := maxf(0.001, seconds_per_hour)
	for pair in [["bleed", "bleeding"], ["sick", "dysentery"], ["buff", "caffeine"]]:
		var secs := float(d.get(pair[0], 0.0))
		if secs > 0.0:
			add(pair[1], secs / sph)
