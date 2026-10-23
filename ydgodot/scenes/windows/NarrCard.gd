class_name NarrCard
extends SysWindow
## 场景叙事卡：展开场景时浮在画布上，正文一次性预留高度并逐字打出。

var _text: TypewriterLabel
var _width := 470.0


func setup_narr(scene_title: String, text: String, w: float = 470.0, h: float = 330.0) -> void:
	_width = w
	setup("叙事 · " + scene_title, w, h, TecTheme.R_SM)
	_text = TecTheme.narrative_label(text, TecTheme.TEXT)
	_text.name = "narr_text"
	_text.custom_minimum_size = Vector2(w - 72.0, 0)
	content.add_child(_text)
	_text.start_typing()
	call_deferred("_fit_height")


func _fit_height() -> void:
	if _text == null:
		return
	if not is_inside_tree():
		await tree_entered
	await get_tree().process_frame
	var target := SysWindow.BAR_H + 20.0 + _text.get_combined_minimum_size().y
	if absf(size.y - (target + SysWindow.PAD * 2.0)) > 0.5:
		set_inner_height(target)


func text_of() -> String:
	return _text.text if _text != null else ""
