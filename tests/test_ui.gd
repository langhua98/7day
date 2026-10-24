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
	var jump: Rect2 = hud._jump_btn.get_global_rect()
	var action: Rect2 = hud._action_btn.get_global_rect()
	var bag: Rect2 = hud._bag_btn.get_global_rect()
	var pause: Rect2 = hud._pause_btn.get_global_rect()
	var ammo: Rect2 = hud._ammo_panel.get_global_rect()
	check(not attack.intersects(aim), "攻击和瞄准不能重叠")
	check(not aim.intersects(action), "瞄准和搜索不能重叠")
	check(not bag.intersects(pause), "背包和暂停不能重叠")
	check(attack.size.x >= 150 and attack.size.y >= 150, "攻击键至少 150×150")
	check(jump.size.y >= 80, "跳键至少 80 高")
	check(aim.get_center().y < attack.get_center().y, "瞄准在攻击上方")
	check(action.get_center().x < aim.get_center().x, "搜索在瞄准左侧")

	# 吃鸡手游布局：跳在开火右上，开镜在开火左上，弹药数字在底部中间
	var half_w := hud.get_viewport().get_visible_rect().size.x * 0.5
	check(jump.get_center().x > attack.get_center().x and jump.get_center().y < attack.get_center().y, "跳在开火右上")
	check(aim.get_center().x < attack.get_center().x and aim.get_center().y < attack.get_center().y, "开镜在开火左上")
	check(bag.get_center().x < half_w and bag.get_center().y > attack.get_center().y, "背包在底部偏左")
	var all_btns := {"开火": attack, "开镜": aim, "跳": jump, "搜索": action,
		"背包": bag, "设置": pause, "摇杆": hud._joy_base.get_global_rect(),
		"蹲": hud._crouch_btn.get_global_rect()}
	var names := all_btns.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			check(not all_btns[names[i]].intersects(all_btns[names[j]]), "%s和%s不能重叠" % [names[i], names[j]])
	for n in names:
		var r: Rect2 = all_btns[n]
		check(r.size.x >= 80 and r.size.y >= 80, "%s至少 80 像素（44pt）" % n)

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
	hud._touch_down(3, ammo.get_center())
	check_eq(reloads[0], 1, "点弹药数字应换弹")
	hud._touch_up(3)
	hud.set_ammo_data(2, "10", "9mm 普通", false, 15)
	check_eq(hud._ammo_mag.text, "2", "显示弹匣数")
	check_eq(hud._ammo_reserve.text, "/ 10", "显示备弹")
	check_eq(hud._ammo_type.text, "9mm 普通", "显示弹种")
	check(hud.crosshair_color().g < 0.8, "低弹量准星变色")
	hud.set_ammo_data(0, "10", "9mm 普通", false, 15)
	check(hud._ammo_type.text.contains("点这里换弹"), "空弹提示换弹")
	check(hud.crosshair_color().g < 0.4, "空弹准星变红")
	hud.set_ammo_data(2, "10", "9mm 普通", true, 15)
	check(hud._ammo_type.text.contains("换弹中"), "换弹中提示")
	hud.set_ammo("")
	check(not hud._ammo_panel.visible, "切到空手应隐藏弹药面板")
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

	# 背包能打开；格子点击/滑动由 test_bag 覆盖
	hud.open_bag()
	await get_tree().process_frame
	check(hud._bag_panel.visible, "背包应打开")
	hud._bag_panel.visible = false

	# 安全区：刘海和底部横条让出来，按钮整体往里收
	var attack_before := hud._attack_btn.get_global_rect()
	var stats_before: Vector2 = hud._status.get_global_rect().position
	hud.apply_safe_insets(Vector4(90, 0, 90, 40))
	await get_tree().process_frame
	var vp := hud.get_viewport().get_visible_rect().size
	check(hud._attack_btn.get_global_rect().end.x <= vp.x - 90, "攻击键应避开右边刘海")
	check(is_equal_approx(hud._attack_btn.get_global_rect().position.x, attack_before.position.x - 90), "攻击键应左移 90")
	check(absf(hud._attack_btn.get_global_rect().end.y - (attack_before.end.y - 40)) <= 1.0, "攻击键应避开底部横条")
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

	# 标题页/暂停页共用设置面板
	hud.show_start(true)
	check(hud._start_settings_btn.visible, "标题页应有设置按钮")
	hud._start_settings_btn.pressed.emit()
	await get_tree().process_frame
	check(hud._settings_panel.visible, "标题页设置应打开")
	var settings_box: Control = hud._settings_panel.get_child(0).get_child(0)
	check(settings_box.size.y <= vp.y, "设置面板不应超出屏幕高度")
	hud._settings_back_btn.pressed.emit()
	check(not hud._settings_panel.visible and hud._start_panel.visible, "设置返回标题页")
	var volume_slider: HSlider = hud._setting_sliders["volume"]
	volume_slider.value = 0.5
	check(absf(hud.settings.volume - 0.5) < 0.001, "拖动音量应更新设置")
	check_eq(hud._setting_values["volume"].text, "50%", "音量应显示百分比")
	hud._settings_reset_btn.pressed.emit()
	check(absf(hud.settings.volume - 1.0) < 0.001, "恢复默认音量")
	check_eq(hud._setting_values["volume"].text, "100%", "恢复默认后显示 100%")
	hud.set_paused(true)
	hud._pause_settings_btn.pressed.emit()
	check(hud._settings_panel.visible and not hud._pause_panel.visible, "暂停页设置应打开")
	hud._settings_back_btn.pressed.emit()
	check(hud._pause_panel.visible and get_tree().paused, "设置返回暂停页")
	hud.set_paused(false)

	# 快捷栏：格子缩小、显示装备名
	Assets.ensure_item("testUiItem", "测试物品")
	hud.set_inventory([{"id": "testUiItem", "count": 3, "equipped": true, "quality": 0}], ["testUiItem"])
	await get_tree().process_frame
	var slot: Control = hud._hotbar.get_child(0)
	check_eq(slot.custom_minimum_size, Vector2(76, 76), "快捷栏格子 76")
	check_eq(hud._hotbar_name.text, "测试物品", "切换时显示装备名")

	# 结算页回标题
	var backs := [0]
	hud.back_to_title.connect(func(): backs[0] += 1)
	hud.show_end("测试")
	hud._end_back_btn.pressed.emit()
	check_eq(backs[0], 1, "结算回标题应发信号")

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
