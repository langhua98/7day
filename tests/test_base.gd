extends SceneTree
## 无头测试的小工具：收集断言，最后统一退出。

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s：期望 %s，实际 %s" % [message, expected, actual])


func check_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s：期望 %.4f，实际 %.4f" % [message, expected, actual])


func finish(name: String) -> void:
	if failures.is_empty():
		print("PASS ", name)
		quit(0)
		return
	for f in failures:
		push_error("%s: %s" % [name, f])
	print("FAIL %s（%d 项）" % [name, failures.size()])
	quit(1)
