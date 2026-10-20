class_name NarrCard
extends SysWindow
## 场景叙事卡：展开场景时浮在画布上，正文可滚。
## Web 版是锚在节点上方的卡片；P0 先用窗口承载，P1 补锚定与打字机。

var _text: RichTextLabel


func setup_narr(scene_title: String, text: String, w: float = 470.0, h: float = 330.0) -> void:
	setup("叙事 // " + scene_title, w, h, TecTheme.R_SM)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = false
	_text.fit_content = true
	_text.scroll_active = false
	_text.add_theme_font_override("normal_font", TecTheme.font())
	_text.add_theme_font_size_override("normal_font_size", 13)
	_text.add_theme_color_override("default_color", TecTheme.TEXT)
	_text.add_theme_constant_override("line_separation", 6)
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size = Vector2(w - 60.0, 0)
	_text.text = text
	scroll.add_child(_text)


func text_of() -> String:
	return _text.text if _text != null else ""
