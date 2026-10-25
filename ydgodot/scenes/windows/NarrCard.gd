class_name NarrCard
extends SysWindow
## 场景叙事卡：展开场景时浮在画布上，正文一次性预留高度并逐字打出。

signal typing_finished

var _text: TypewriterLabel
var _width := 470.0


## A2：叙事卡是内容卡，不参与系统窗的激活态竞争。
func participates_in_activation() -> bool:
	return false


func setup_narr(scene_title: String, text: String, w: float = 470.0, h: float = 330.0) -> void:
	_width = w
	setup("叙事 · " + scene_title, w, h, TecTheme.R_SM)
	_text = TecTheme.narrative_label(text, TecTheme.TEXT)
	_text.name = "narr_text"
	_text.custom_minimum_size = Vector2(w - 72.0, 0)
	content.add_child(_text)
	_text.typing_finished.connect(func(): typing_finished.emit())
	_text.start_typing()
	call_deferred("_fit_height")


func is_typing() -> bool:
	return _text != null and _text.is_typing()


## U2/W17：单击补全整段（与 MemCard 的单击补全同口径）。
func finish_typing() -> void:
	if _text != null:
		_text.finish_typing()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if is_typing():
			finish_typing()
		accept_event()


func _fit_height() -> void:
	if _text == null:
		return
	if not is_inside_tree():
		await tree_entered
	await get_tree().process_frame
	var target := SysWindow.BAR_H + 20.0 + _text.get_combined_minimum_size().y
	if absf(size.y - (target + SysWindow.PAD * 2.0)) > 0.5:
		set_inner_height(target)
	## W22：长旁白把窗口撑出视口时把顶边提上来，按真实视口而不是写死 740。
	var vh := 720.0
	if is_inside_tree():
		var raw := get_viewport_rect().size.y
		if raw >= 320.0:
			vh = raw
	if position.y + size.y > vh - 8.0:
		position.y = maxf(8.0, vh - 8.0 - size.y)


func text_of() -> String:
	return _text.text if _text != null else ""
