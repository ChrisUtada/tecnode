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
## 证据族用「墨色反白字牌」：实心圆 + 纸白单字。`glyph_override` 承载 tier 的 物/词/证。
var filled := false
var text_col := TecTheme.CARD
var glyph_override := ""


func _draw() -> void:
	var c := size * 0.5
	var r := radius
	var sw := maxf(1.0, 1.1 / maxf(zoom, 0.1))
	if filled:
		draw_circle(c, maxf(r - sw * 0.5, 0.5), col, true, -1.0, true)
	else:
		draw_arc(c, maxf(r - sw * 0.5, 0.5), 0.0, TAU, 40, col, sw, true)
	var glyph := glyph_override if glyph_override != "" else String(GLYPH_TEXT.get(kind, "?"))
	var font := TecTheme.font()
	## 字要明显小于圈：占圈内径的 ~2/3，四边留出呼吸缝，笔画才不会顶到弧线上。
	## （旧版文字档直接画 12px、缩略档画 24px，圈内径只有 13/30，一放大就糊成一团�?
	var px := glyph_font_px(r, zoom)
	var w := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, px).x
	var asc := font.get_ascent(px)
	var desc := font.get_descent(px)
	var baseline := c.y + (asc - desc) * 0.5
	draw_string(font, Vector2(c.x - w * 0.5, baseline), glyph,
		HORIZONTAL_ALIGNMENT_CENTER, -1, px, text_col if filled else col)


## 圈内字号：U1 只允许 **12 / 24** 两档（点阵字原生格 12 的整数倍）。
## 文字档圈径 20（内径 17.8）放 12px 仍有留缝；缩略档圈径 40+ 才跳到 24。
## 旧版的 9/10/22px 是重采样发糊的根因，不再按内径连续取值。
## 抽成静态函数是为了测试能直接断言「笔画 < 内径」，不依赖渲染截图。
static func glyph_font_px(radius: float, zoom: float) -> int:
	var sw := maxf(1.0, 1.1 / maxf(zoom, 0.1))
	var inner_d := maxf((radius - sw) * 2.0, 1.0)
	return 24 if inner_d >= 30.0 else 12


func set_kind(k: String) -> void:
	kind = k
	queue_redraw()


func set_evidence_tier(tier: String) -> void:
	glyph_override = {"wu": "物", "ci": "词", "zheng": "证"}.get(tier, "?")
	filled = true
	queue_redraw()


func set_color(c: Color) -> void:
	col = c
	queue_redraw()
