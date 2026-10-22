class_name KindGlyph
extends Control
## 节点类型符号：■ 场景 / □ 物品 / ● 人物 / ▲ 线索 / ◆ 时刻。
##
## **为什么用 `_draw` 画而不是用字体的 ■□●▲**：
##   1. 字库不一定有这几个字符（缺字就是豆腐块）；
##   2. 低倍率下字形会被重采样糊成一团，几何图形不会 —— 一个 8px 方块缩到 5px 仍是方块。
##
## **符号是整张卡上唯一承载「类型色」的地方**（`TecTheme.kind_color()`）。卡面与边框
## 一律不上类型色：那里已经被状态占满了（实线=已探索 / 虚线=未探索 / 双线=枢纽 /
## 金框=点亮 / 深色反白=已捕获 / 墨环=选中），再叠一层就分不清是谁在说话。
##
## 两个使用方：画布卡片（`NodeCard`，高倍率左侧小符号、低倍率铺满居中）与
## 回忆卡标题条（`MemCard`，深色面上用提亮版色）。

var kind := "item"
var col := Color(0.169, 0.169, 0.149)
## 当前相机倍率：描边按 1/k 反向补偿。不补偿的话 1.7px 的空心方框缩到 0.62x
## 只剩 1.05px，某一条边会被像素采样直接吞掉（实测缺右边线，看成「⊐」）。
var zoom := 1.0
## 半边长。5 = 10px 见方；0.62x 下落到 6px 仍能分辨方/圆/三角，再小就只剩一个点。
var radius := 5.0


func _draw() -> void:
	var c := size * 0.5
	var r := radius
	var box := Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
	var sw := maxf(1.0, 1.7 / maxf(zoom, 0.1))
	match kind:
		"loc":
			draw_rect(box, col, true)
		"char":
			draw_circle(c, r, col)
		"clue":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, -r), c + Vector2(r, r * 0.85),
				c + Vector2(-r, r * 0.85)]), col)
		"time":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, -r), c + Vector2(r, 0.0),
				c + Vector2(0.0, r), c + Vector2(-r, 0.0)]), col)
		_:
			draw_rect(box, col, false, sw)


## 换类型（回忆卡按场景/人物复用同一个实例时用）。
func set_kind(k: String) -> void:
	kind = k
	queue_redraw()


func set_color(c: Color) -> void:
	col = c
	queue_redraw()
