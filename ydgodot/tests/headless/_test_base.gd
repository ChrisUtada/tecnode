extends SceneTree
## 无头测试基类：统一 `check()` / 计数 / 清理 / 退出。
##
## 用法：
##   extends "res://tests/headless/_test_base.gd"
##   func _initialize() -> void: ... ; _finish()
##
## 约定：
##   · 子类只实现 `_initialize()` 与用例函数，结束时调一次 `_finish()`；
##   · 需要删临时档时覆盖 `_cleanup()`，不要自己写 `quit()`；
##   · `_finish()` 在失败时返回退出码 1，CI 才能拦住。

var fails := 0
var total := 0


func check(name: String, cond: bool, detail: String = "") -> void:
	total += 1
	if cond:
		print("  PASS  ", name)
	else:
		fails += 1
		print("  FAIL  ", name, ("  [" + detail + "]") if detail != "" else "")


## 子类覆盖：删除测试期间创建的临时档。
func _cleanup() -> void:
	pass


## 汇总并退出。失败返回 1。
func _finish() -> void:
	_cleanup()
	print("=== %d 项，失败 %d ===" % [total, fails])
	quit(0 if fails == 0 else 1)
