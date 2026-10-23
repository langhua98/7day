extends Node
## iOS 触屏验收：按钮不重叠、点击能触发、摇杆有死区。

var hud: Hud
var failures: Array[String] = []


func _ready() -> void:
	hud = Hud.new()
	add_child(hud)
	await get_tree().process_frame
	hud.set_ammo("12 / 120  9mm 普通")
	hud.set_action("搜索\n垃圾桶")

	var attack: Rect2 = hud._attack_btn.get_global_rect()
	var aim: Rect2 = hud._aim_btn.get_global_rect()
	var reload: Rect2 = hud._reload_btn.get_global_rect()
	var jump: Rect2 = hud._jump_btn.get_global_rect()
	var action: Rect2 = hud._action_btn.get_global_rect()
	var bag: Rect2 = hud._bag_btn.get_global_rect()
	var pause: Rect2 = hud._pause_btn.get_global_rect()
	check(not attack.intersects(aim), "攻击和瞄准不能重叠")
	check(not aim.intersects(action), "瞄准和搜索不能重叠")
	check(not reload.intersects(aim), "换弹和瞄准不能重叠")
	check(not jump.intersects(reload), "跳和换弹不能重叠")
	check(not bag.intersects(pause), "背包和暂停不能重叠")
	check(attack.size.x >= 150 and attack.size.y >= 150, "攻击键至少 150×150")
	check(reload.size.y >= 80 and jump.size.y >= 80, "换弹/跳键至少 80 高")
	check(aim.get_center().y < attack.get_center().y, "瞄准在攻击上方")
	check(action.get_center().x < aim.get_center().x, "搜索在瞄准左侧")

	hud._touch_down(1, aim.get_center())
	check(hud.aim_held, "按住瞄准应生效")
	hud._touch_up(1)
	check(not hud.aim_held, "松开瞄准应取消")

	hud._touch_down(2, attack.get_center())
	check(hud.attack_held, "按住攻击应生效")
	hud._touch_up(2)
	check(not hud.attack_held, "松开攻击应取消")

	var reloads := [0]
	var jumps := [0]
	var actions := [0]
	hud.reload_pressed.connect(func(): reloads[0] += 1)
	hud.jump_pressed.connect(func(): jumps[0] += 1)
	hud.action_pressed.connect(func(): actions[0] += 1)
	hud._touch_down(3, reload.get_center())
	check_eq(reloads[0], 1, "点换弹应发信号")
	hud._touch_up(3)
	hud._touch_down(4, jump.get_center())
	check_eq(jumps[0], 1, "点跳应发信号")
	hud._touch_up(4)
	hud._touch_down(5, action.get_center())
	check_eq(actions[0], 1, "点搜索应发信号")
	hud._touch_up(5)

	hud._touch_down(6, bag.get_center())
	check(hud._bag_panel.visible, "点背包应打开")
	hud._bag_panel.visible = false
	hud._touch_down(7, pause.get_center())
	check(hud._pause_panel.visible, "点暂停应打开")
	hud.set_paused(false)

	# 摇杆：先 10px 不应该移动，推到 90px 才移动
	var left := Vector2(200, 500)
	hud._touch_down(8, left)
	check(hud._joy_id == 8, "左半屏应启动摇杆")
	var drag := InputEventScreenDrag.new()
	drag.index = 8
	drag.position = hud._joy_origin + Vector2(10, 0)
	hud._input(drag)
	check(hud.move.length() < 0.01, "摇杆死区内不应移动")
	drag.position = hud._joy_origin + Vector2(90, 0)
	hud._input(drag)
	check(hud.move.x > 0.7, "摇杆推到底应接近满速")
	hud._touch_up(8)
	check(hud.move == Vector2.ZERO, "松手摇杆应归零")

	_finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s：期望 %s，实际 %s" % [message, expected, actual])


func _finish() -> void:
	if failures.is_empty():
		print("PASS test_ui")
		get_tree().quit(0)
		return
	for f in failures:
		push_error("test_ui: " + f)
	print("FAIL test_ui（%d 项）" % failures.size())
	get_tree().quit(1)
