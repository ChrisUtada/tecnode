extends Control
## 系统窗标题栏的三道 1px 横纹（System 6 / Control Panel 语汇）。
##
## 由 `SysWindow` 用 `preload()` 实例化；刻意不设 `class_name`，避免新增
## 全局脚本类缓存依赖。横纹在标题文字处断开，断口由 `gap_left/gap_right`
## 控制，整条 Control 参与激活 / 非激活切换。

var line_left := 10.0
var line_right := 10.0
var gap_left := 0.0
var gap_right := 0.0
var col := TecTheme.SPOT_ACCENT


func _draw() -> void:
	var mid := size.y * 0.5
	for i in 3:
		var y := mid - 4.5 + float(i) * 4.0
		if gap_left > line_left:
			draw_line(Vector2(line_left, y), Vector2(gap_left, y), col, 1.0)
		if line_right > gap_right:
			draw_line(Vector2(gap_right, y), Vector2(line_right, y), col, 1.0)
