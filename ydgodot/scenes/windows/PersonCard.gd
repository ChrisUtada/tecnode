class_name PersonCard
extends Control
## 人物档案卡（PEOPLE_CARD_PLAN）：名册点行打开的竖长查看器，不是窗口管理器里的窗。
## 单张替换、固定 260×360、2px 框 + 偏移影；照片 / 姓名 / 身份 / 状态 / 首次记录 / 关联 /
## 备注（玩家知识，按 id 存 graph.notes）/ 底部次级动作。

signal closed
signal action_requested(id: String)
signal note_changed(id: String, text: String)
signal note_committed(id: String, text: String)

const W := 260.0
const H := 360.0
const SHADOW := 3.0
const AvatarFrameScript = preload("res://ui/AvatarFrame.gd")

var person_id := ""
var _payload: Dictionary = {}
var _content: VBoxContainer
var _name_label: Label
var _role_label: Label
var _state_label: Label
var _meta_box: VBoxContainer
var _note: TextEdit
var _action_btn: Button
var _close_btn: Button
var _note_dirty := false
var _loading := false


func setup_card(p: Dictionary) -> void:
	_payload = p.duplicate(true)
	person_id = String(_payload.get("id", ""))
	name = "person_card_" + person_id
	size = Vector2(W + SHADOW, H + SHADOW)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var shadow := ColorRect.new()
	shadow.name = "card_shadow"
	shadow.position = Vector2(SHADOW, SHADOW)
	shadow.size = Vector2(W, H)
	shadow.color = TecTheme.shadow(1.0)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shadow)

	var bg := Panel.new()
	bg.name = "card_bg"
	bg.position = Vector2.ZERO
	bg.size = Vector2(W, H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", TecTheme.flat(TecTheme.CARD, 0, TecTheme.LINE, 2))
	add_child(bg)

	_content = VBoxContainer.new()
	_content.name = "card_content"
	_content.position = Vector2(14.0, 10.0)
	_content.size = Vector2(W - 28.0, H - 20.0)
	_content.add_theme_constant_override("separation", 4)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)

	var photo_box := CenterContainer.new()
	photo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(photo_box)
	var photo := AvatarFrameScript.new()
	photo.name = "card_photo"
	photo.setup(String(_payload.get("photo", "")), 72.0, String(_payload.get("initial", "?")))
	photo_box.add_child(photo)

	_name_label = TecTheme.brand_label(String(_payload.get("name", "")), TecTheme.FS_DISPLAY, TecTheme.TEXT)
	_name_label.name = "card_name"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.tooltip_text = _name_label.text
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_name_label)

	_role_label = TecTheme.label(String(_payload.get("role", "")), TecTheme.FS_BODY, TecTheme.MUTED)
	_role_label.name = "card_role"
	_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_role_label.clip_text = true
	_role_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_role_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_role_label)

	_content.add_child(_rule())

	_state_label = TecTheme.label("状态 · " + String(_payload.get("state", "")),
		TecTheme.FS_BODY, TecTheme.TEXT)
	_state_label.name = "card_state"
	_state_label.clip_text = true
	_state_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_state_label)

	_meta_box = VBoxContainer.new()
	_meta_box.name = "card_meta"
	_meta_box.add_theme_constant_override("separation", 1)
	_meta_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_meta_box)
	for raw in _payload.get("meta_lines", []):
		var line := String(raw)
		if line == "":
			continue
		var lab := TecTheme.label(line, TecTheme.FS_BODY, TecTheme.MUTED)
		lab.clip_text = true
		lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lab.tooltip_text = line
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_meta_box.add_child(lab)

	_content.add_child(_rule())

	var notes_cap := TecTheme.label("备注", TecTheme.FS_BODY, TecTheme.MUTED)
	notes_cap.name = "card_notes_cap"
	notes_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(notes_cap)

	_note = TextEdit.new()
	_note.name = "card_note"
	_note.custom_minimum_size = Vector2(0, 80)
	_note.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_note.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_note.placeholder_text = "写点笔记…"
	_note.scroll_fit_content_height = false
	_note.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	_note.add_theme_font_override("font", TecTheme.font())
	_note.add_theme_font_size_override("font_size", TecTheme.FS_BODY)
	_note.add_theme_color_override("font_color", TecTheme.TEXT)
	_note.add_theme_color_override("font_placeholder_color", TecTheme.INK_FAINT)
	_note.add_theme_color_override("caret_color", TecTheme.INK)
	_note.add_theme_color_override("selection_color", Color(TecTheme.INK, 0.16))
	_note.add_theme_color_override("background_color", TecTheme.BG)
	var note_sb := TecTheme.flat(TecTheme.BG, 0, TecTheme.EDGE, 1)
	note_sb.content_margin_left = 5
	note_sb.content_margin_right = 5
	note_sb.content_margin_top = 4
	note_sb.content_margin_bottom = 4
	_note.add_theme_stylebox_override("normal", note_sb)
	var note_focus := TecTheme.flat(TecTheme.BG, 0, TecTheme.INK, 1)
	note_focus.content_margin_left = 5
	note_focus.content_margin_right = 5
	note_focus.content_margin_top = 4
	note_focus.content_margin_bottom = 4
	_note.add_theme_stylebox_override("focus", note_focus)
	_note.text_changed.connect(_on_note_changed)
	_note.focus_exited.connect(_commit_note)
	_note.gui_input.connect(_on_note_gui_input)
	_content.add_child(_note)
	_loading = true
	_note.text = String(_payload.get("note", ""))
	_loading = false

	_action_btn = TecTheme.button(String(_payload.get("action", "前往此人")))
	_action_btn.name = "card_action"
	_action_btn.custom_minimum_size = Vector2(0, 24)
	_action_btn.add_theme_font_size_override("font_size", TecTheme.FS_BODY)
	_action_btn.pressed.connect(func(): action_requested.emit(person_id))
	_content.add_child(_action_btn)

	_close_btn = TecTheme.button("×")
	_close_btn.name = "card_close"
	_close_btn.tooltip_text = "关闭档案卡"
	_close_btn.position = Vector2(W - 26.0, 6.0)
	_close_btn.custom_minimum_size = Vector2(18, 18)
	_close_btn.size = Vector2(18, 18)
	_close_btn.z_index = 2
	var close_sb := TecTheme.button_style()
	close_sb.content_margin_left = 0
	close_sb.content_margin_right = 0
	close_sb.content_margin_top = 0
	close_sb.content_margin_bottom = 0
	_close_btn.add_theme_stylebox_override("normal", close_sb)
	_close_btn.pressed.connect(close)
	add_child(_close_btn)


func _rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = TecTheme.EDGE_SOFT
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


func payload() -> Dictionary:
	return _payload.duplicate(true)


func note_text() -> String:
	return _note.text if _note != null else ""


func set_note_text(text: String) -> void:
	if _note == null:
		return
	_loading = true
	_note.text = text
	_loading = false
	_note_dirty = false


func state_text() -> String:
	return _state_label.text if _state_label != null else ""


func action_text() -> String:
	return _action_btn.text if _action_btn != null else ""


func name_text() -> String:
	return _name_label.text if _name_label != null else ""


func _on_note_changed() -> void:
	if _loading:
		return
	_note_dirty = true
	note_changed.emit(person_id, _note.text)


func _commit_note() -> void:
	if _note == null or not _note_dirty:
		return
	_note_dirty = false
	note_committed.emit(person_id, _note.text)


func commit_note() -> void:
	_commit_note()


func _on_note_gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			_commit_note()
			_note.release_focus()
			accept_event()


func close() -> void:
	_commit_note()
	closed.emit()
