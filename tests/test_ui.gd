extends Node
## iOS 触屏验收：按钮不重叠、点击能触发、摇杆有死区。

var hud: Hud
var failures: Array[String] = []


func _ready() -> void:
	hud = Hud.new()
	add_child(hud)
	await get_tree().process_frame
	hud._start_panel.visible = false  # 当作已经开局
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

	# 摇杆拖出圈外：底座跟着手指走，往回一拖马上反向
	hud._touch_down(9, left)
	drag.index = 9
	drag.position = left + Vector2(200, 0)
	hud._input(drag)
	check(hud._joy_origin.distance_to(left + Vector2(110, 0)) < 1.0, "拖出圈外摇杆底座应跟手")
	drag.position = left + Vector2(60, 0)
	hud._input(drag)
	check(hud.move.x < -0.3, "跟手后往回拖应马上反向")
	hud._touch_up(9)

	# 按住攻击拖动：边打边转视角
	hud.consume_look()
	hud._touch_down(10, attack.get_center())
	drag.index = 10
	drag.position = attack.get_center() + Vector2(-30, 12)
	hud._input(drag)
	check(hud.attack_held, "拖动时攻击应保持按住")
	check(hud.consume_look().distance_to(Vector2(-30, 12)) < 0.01, "按住攻击拖动应转视角")
	hud._touch_up(10)
	check(not hud.attack_held, "松开攻击应取消")

	# 右半屏空白处拖动转视角
	var right := Vector2(hud.get_viewport().get_visible_rect().size.x * 0.6, 300)
	hud._touch_down(11, right)
	drag.index = 11
	drag.position = right + Vector2(40, -5)
	hud._input(drag)
	check(hud.consume_look().distance_to(Vector2(40, -5)) < 0.01, "右半屏拖动应转视角")
	hud._touch_up(11)
	drag.position = right + Vector2(80, 0)
	hud._input(drag)
	check(hud.consume_look() == Vector2.ZERO, "松手后不应再转视角")

	# 快捷栏居中，不和摇杆、攻击键重叠
	hud.set_inventory([{"id": "a", "count": 1}, {"id": "b", "count": 2}, {"id": "c", "count": 1}], ["a", "b", "c"])
	await get_tree().process_frame
	var bar: Rect2 = hud._hotbar.get_global_rect()
	var mid := hud.get_viewport().get_visible_rect().size.x * 0.5
	check(absf(bar.get_center().x - mid) < 2.0, "快捷栏应水平居中")
	check(not bar.intersects(attack), "快捷栏和攻击不能重叠")
	check(not bar.intersects(hud._joy_base.get_global_rect()), "快捷栏和摇杆不能重叠")
	var used: Array[String] = []
	hud.item_used.connect(func(id): used.append(id))
	var slot_b: Control = hud._hotbar.get_child(1)
	hud._touch_down(12, slot_b.get_global_rect().get_center())
	hud._touch_up(12)
	check(used == ["b"], "点快捷栏第 2 格应使用 b")

	# 背包：点一下用物品，滑动不用；点背包外面关掉
	hud.open_bag()
	await get_tree().process_frame
	var bag_slot: Button = hud._bag_grid.get_child(0)
	var at := bag_slot.get_global_rect().get_center()
	used.clear()
	hud._bag_slot_input(bag_slot, "a", _mouse(at, true))
	hud._bag_slot_input(bag_slot, "a", _mouse(at + Vector2(0, 60), false))
	check(used.is_empty(), "在背包里滑动不应使用物品")
	hud._bag_slot_input(bag_slot, "a", _mouse(at, true))
	hud._bag_slot_input(bag_slot, "a", _mouse(at + Vector2(3, 4), false))
	check(used == ["a"], "在背包里点一下应使用物品")
	var outside := InputEventScreenTouch.new()
	outside.index = 13
	outside.pressed = true
	outside.position = Vector2(4, 4)
	hud._input(outside)
	check(not hud._bag_panel.visible, "点背包外面应关掉背包")

	# 安全区：刘海和底部横条让出来，按钮整体往里收
	var attack_before := hud._attack_btn.get_global_rect()
	var stats_before: Vector2 = hud._status.get_global_rect().position
	hud.apply_safe_insets(Vector4(90, 0, 90, 40))
	await get_tree().process_frame
	var vp := hud.get_viewport().get_visible_rect().size
	check(hud._attack_btn.get_global_rect().end.x <= vp.x - 90, "攻击键应避开右边刘海")
	check(is_equal_approx(hud._attack_btn.get_global_rect().position.x, attack_before.position.x - 90), "攻击键应左移 90")
	check(hud._attack_btn.get_global_rect().end.y <= vp.y - 40, "攻击键应避开底部横条")
	check(hud._status.get_global_rect().position.x >= stats_before.x + 89, "左上状态应避开左边刘海")
	check(hud._joy_base.get_global_rect().position.x >= 90, "摇杆应避开左边刘海")
	hud._touch_down(14, hud._attack_btn.get_global_rect().get_center())
	check(hud.attack_held, "安全区下攻击键仍能按")
	hud._touch_up(14)
	hud.apply_safe_insets(Vector4.ZERO)

	# 切后台：松开所有手指并自动暂停
	hud._touch_down(15, hud._attack_btn.get_global_rect().get_center())
	hud._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not hud.attack_held, "切后台应松开攻击")
	check(hud._pause_panel.visible, "游戏中切后台应自动暂停")
	hud.set_paused(false)

	_finish()


func _mouse(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	return ev


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
