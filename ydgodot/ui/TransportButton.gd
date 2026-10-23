class_name TecTransportButton
extends Button
## 18×18 键线播放键。图标用线画，不走字体：▶/❚❚ 在 1x 下会缺字或上下不齐。
## 三态与全站按钮一致——常态 1px、悬停 2px、按下反白。

const BOX := 18.0

var _mode := "play"


func setup_transport(mode: String, tip: String) -> void:
	_mode = mode
	text = ""
	tooltip_text = tip
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(BOX, BOX)
	size = Vector2(BOX, BOX)
	add_theme_stylebox_override("normal", _key_style(TecTheme.NONE, 1))
	add_theme_stylebox_override("hover", _key_style(TecTheme.NONE, 2))
	add_theme_stylebox_override("pressed", _key_style(TecTheme.INK, 1))
	add_theme_stylebox_override("hover_pressed", _key_style(TecTheme.INK, 2))
	add_theme_stylebox_override("disabled", _key_style(TecTheme.NONE, 1, TecTheme.INK_FAINT))
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	queue_redraw()


func set_mode(mode: String) -> void:
	if _mode == mode:
		return
	_mode = mode
	queue_redraw()


func _key_style(fill: Color, width: int, line: Color = TecTheme.INK) -> StyleBoxFlat:
	var sb := TecTheme.flat(fill, 2, line, width)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb


func _draw() -> void:
	var c := _icon_color()
	var center := size * 0.5
	match _mode:
		"pause":
			draw_line(center + Vector2(-2.5, -5.0), center + Vector2(-2.5, 5.0), c, 1.6, true)
			draw_line(center + Vector2(2.5, -5.0), center + Vector2(2.5, 5.0), c, 1.6, true)
		"stop":
			draw_rect(Rect2(center - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), c, false, 1.2, true)
		_:
			draw_polyline(PackedVector2Array([
				center + Vector2(-3.5, -5.0),
				center + Vector2(4.5, 0.0),
				center + Vector2(-3.5, 5.0),
				center + Vector2(-3.5, -5.0),
			]), c, 1.2, true)


func _icon_color() -> Color:
	if disabled:
		return TecTheme.INK_FAINT
	var m := get_draw_mode()
	if m == Button.DRAW_PRESSED or m == Button.DRAW_HOVER_PRESSED:
		return TecTheme.CARD
	return TecTheme.TEXT
