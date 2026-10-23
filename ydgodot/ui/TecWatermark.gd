class_name TecWatermark
extends Control
## 桌面画布的 T.E.C 水印：3–5% 墨色，压在卡片层下面，只看得到、点不到。
## 画在 `_stage` 而不是 `_desk`：主窗覆盖桌面中央，只有画布这块大面积灰面需要焦点。


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var font := TecTheme.brand_font()
	var px := TecTheme.FS_INITIAL
	var text := "T.E.C"
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var center := Vector2(size.x * 0.5, size.y * 0.36)
	draw_string(font, Vector2(center.x - tw * 0.5, center.y + font.get_ascent(px) * 0.5),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, TecTheme.scrim(0.045))
