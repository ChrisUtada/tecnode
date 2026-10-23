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
	var sw := maxf(1.0, 1.1 / maxf(zoom, 0.1))
	draw_arc(c, maxf(r - sw * 0.5, 0.5), 0.0, TAU, 40, col, sw, true)
	var glyph := String(GLYPH_TEXT.get(kind, "?"))
	var font := TecTheme.font()
	## 字要明显小于圈：占圈内径的 ~2/3，四边留出呼吸缝，笔画才不会顶到弧线上。
	## （旧版文字档直接画 12px、缩略档画 24px，圈内径只有 13/30，一放大就糊成一团�?
	var px := glyph_font_px(r, zoom)
	var w := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, px).x
	var asc := font.get_ascent(px)
	var desc := font.get_descent(px)
	var baseline := c.y + (asc - desc) * 0.5
	draw_string(font, Vector2(c.x - w * 0.5, baseline), glyph,
		HORIZONTAL_ALIGNMENT_CENTER, -1, px, col)


## 圈内字号：P2 把文字档从 9px 提到 10px（字牌同时从 16 放到 18，内径 15.8）；
## 0.64 让 18px 圈落在 10，而 16px 圈仍夹回 10，不会因为半径多 1px 跳到 11。
## 缩略档没有标题可读，只靠形状，因此跟着圈径放大到 22px。
## 抽成静态函数是为了测试能直接断言「笔画 < 内径」，不依赖渲染截图。
static func glyph_font_px(radius: float, zoom: float) -> int:
	var sw := maxf(1.0, 1.1 / maxf(zoom, 0.1))
	var inner_d := maxf((radius - sw) * 2.0, 1.0)
	return clampi(int(round(inner_d * 0.64)), 10, 22)


func set_kind(k: String) -> void:
	kind = k
	queue_redraw()


func set_color(c: Color) -> void:
	col = c
	queue_redraw()
