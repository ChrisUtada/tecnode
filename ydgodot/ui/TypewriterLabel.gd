class_name TypewriterLabel
extends Label

signal typing_finished

const CHAR_MS := 45.0

var _typing := false
var _shown := 0.0
var _reserve_h := 0.0


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
	_update_reserve()


func start_typing(p_text: String = "") -> void:
	if p_text != "":
		text = p_text
	if text.is_empty():
		finish_typing()
		return
	_update_reserve()
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
	_update_reserve()


func is_typing() -> bool:
	return _typing


func typed_text() -> String:
	if visible_characters < 0:
		return text
	return text.substr(0, visible_characters)


## 逐字期间 `visible_characters` 会参与 Label 自身的最小尺寸计算：只剩两三个字时
## 高度被算成「一行」，窗体按这个值增高就会把正文压在框外。Label 不允许改
## `_get_minimum_size`，所以这里把**全文高度**写进 `custom_minimum_size.y`：
## `get_combined_minimum_size()` 会取它和 Label 自身最小值的较大者 —— 布局永远为
## 整段文字留位，打字只改变揭示进度，窗口只增高一次。
func _update_reserve() -> void:
	var font := get_theme_font("font")
	var fs := get_theme_font_size("font_size")
	if font == null or text.is_empty():
		_reserve_h = 0.0
		custom_minimum_size.y = 0.0
		return
	var wrap_w := size.x
	if wrap_w <= 0.0:
		wrap_w = custom_minimum_size.x
	if wrap_w <= 0.0:
		return
	var full := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, wrap_w, fs)
	var line_h := maxf(font.get_height(fs), 1.0)
	var lines := maxi(1, int(round(full.y / line_h)))
	var h := full.y + maxf(lines - 1, 0) * float(get_theme_constant("line_spacing"))
	if absf(_reserve_h - h) < 0.5:
		return
	_reserve_h = h
	custom_minimum_size.y = h


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_reserve()


func _process(delta: float) -> void:
	if not _typing:
		return
	_shown += delta * (1000.0 / CHAR_MS)
	var n := int(_shown)
	if n >= text.length():
		finish_typing()
	else:
		visible_characters = n
