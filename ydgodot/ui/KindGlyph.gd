class_name KindGlyph
extends Control
## 节点类型符号：圆形字牌（地 / 物 / 人 / 线 / 时）。

const GLYPH_TEXT := {
	"loc": "地",
	"item": "物",
	"char": "人",
	"clue": "线",
	"time": "时",
}

var kind := "item"
var col := TecTheme.INK
var zoom := 1.0
var radius := 8.0


func _draw() -> void:
	var c := size * 0.5
	var r := radius
	var sw := maxf(1.0, 1.7 / maxf(zoom, 0.1))
	draw_arc(c, maxf(r - sw * 0.5, 0.5), 0.0, TAU, 40, col, sw, true)
	var glyph := String(GLYPH_TEXT.get(kind, "?"))
	var font := TecTheme.font()
	var px := TecTheme.FS_BODY if minf(size.x, size.y) < 30.0 else TecTheme.FS_DISPLAY
	var w := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, px).x
	var asc := font.get_ascent(px)
	var desc := font.get_descent(px)
	var baseline := c.y + (asc - desc) * 0.5
	draw_string(font, Vector2(c.x - w * 0.5, baseline), glyph,
		HORIZONTAL_ALIGNMENT_CENTER, -1, px, col)


func set_kind(k: String) -> void:
	kind = k
	queue_redraw()


func set_color(c: Color) -> void:
	col = c
	queue_redraw()
