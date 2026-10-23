class_name TypewriterLabel
extends Label

signal typing_finished

const CHAR_MS := 45.0

var _typing := false
var _shown := 0.0


func configure(p_text: String, p_size: int = 12, p_color: Color = Color.BLACK) -> void:
	text = p_text
	add_theme_font_override("font", TecTheme.font())
	add_theme_font_size_override("font_size", p_size)
	add_theme_color_override("font_color", p_color)
	add_theme_constant_override("line_spacing", TecTheme.NARR_LINE_SPACING)
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible_characters = -1
	_typing = false
	_shown = 0.0
	set_process(false)


func start_typing(p_text: String = "") -> void:
	if p_text != "":
		text = p_text
	if text.is_empty():
		finish_typing()
		return
	_shown = 0.0
	visible_characters = 0
	_typing = true
	set_process(true)


func finish_typing() -> void:
	visible_characters = -1
	if not _typing:
		return
	_typing = false
	set_process(false)
	typing_finished.emit()


func reset_text(p_text: String) -> void:
	text = p_text
	finish_typing()


func is_typing() -> bool:
	return _typing


func typed_text() -> String:
	if visible_characters < 0:
		return text
	return text.substr(0, visible_characters)


func _process(delta: float) -> void:
	if not _typing:
		return
	_shown += delta * (1000.0 / CHAR_MS)
	var n := int(_shown)
	if n >= text.length():
		finish_typing()
	else:
		visible_characters = n
