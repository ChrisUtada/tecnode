class_name PersonCard
extends Control
## 人物档案卡（PEOPLE_CARD_PLAN）：名册点行打开的竖长查看器，不是窗口管理器里的窗。
## 单张替换、固定 260×360、2px 框 + 偏移影；照片 / 姓名 / 身份 / 状态 / 首次记录 / 关联 /
## 备注（玩家知识，按 id 存 graph.notes）/ 底部次级动作。

signal closed
signal action_requested(id: String)
signal note_changed(id: String, text: String)
signal note_committed(id: String, text: String)
## 证据字段：选词 / 请求 TEC 批量核对。真正改图由 Desktop 统一做（快照 / 日志 / 刷新）。
signal field_word_selected(person_id: String, field_id: String, value: String)
signal field_check_requested(person_id: String)

const W := 260.0
const H := 360.0
const SHADOW := 3.0
const AvatarFrameScript = preload("res://ui/AvatarFrame.gd")

var person_id := ""
var _payload: Dictionary = {}
var _card_h := H
var _content: VBoxContainer
var _fields_box: VBoxContainer
var _field_boxes: Dictionary = {}
var _name_label: Label
var _role_label: Label
var _state_label: Label
var _meta_box: VBoxContainer
var _note: TextEdit
var _action_btn: Button
var _close_btn: Button
var _note_dirty := false
var _loading := false


## 待核对态：墨色虚线框。PanelContainer 的 StyleBox 画不出虚线，单独叠一层。
class FieldDashed extends Control:
	func _draw() -> void:
		var r := Rect2(Vector2(0.5, 0.5), size - Vector2(1.0, 1.0))
		var c := TecTheme.INK
		var dash := 2.4
		draw_dashed_line(Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), c, 1.0, dash, true, false)
		draw_dashed_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), c, 1.0, dash, true, false)
		draw_dashed_line(Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y), c, 1.0, dash, true, false)
		draw_dashed_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y), c, 1.0, dash, true, false)


func setup_card(p: Dictionary) -> void:
	_payload = p.duplicate(true)
	person_id = String(_payload.get("id", ""))
	name = "person_card_" + person_id
	var field_count := (_payload.get("evidence_fields", []) as Array).size()
	## 每个字段块含标题 / 提示 / 证据行 / 词库按钮，5 个词条常折两行；
	## 118px 才够把底部动作键也留在框内。
	_card_h = minf(620.0, H + float(field_count) * 118.0 + (8.0 if field_count > 0 else 0.0))
	size = Vector2(W + SHADOW, _card_h + SHADOW)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var shadow := ColorRect.new()
	shadow.name = "card_shadow"
	shadow.position = Vector2(SHADOW, SHADOW)
	shadow.size = Vector2(W, _card_h)
	shadow.color = TecTheme.shadow(1.0)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shadow)

	var bg := Panel.new()
	bg.name = "card_bg"
	bg.position = Vector2.ZERO
	bg.size = Vector2(W, _card_h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", TecTheme.flat(TecTheme.CARD, 0, TecTheme.LINE, 2))
	add_child(bg)

	_content = VBoxContainer.new()
	_content.name = "card_content"
	_content.position = Vector2(14.0, 10.0)
	_content.size = Vector2(W - 28.0, _card_h - 28.0)
	_content.add_theme_constant_override("separation", 3)
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

	var fields: Array = _payload.get("evidence_fields", [])
	if not fields.is_empty():
		var cap := TecTheme.label("证据 · 关键字段", TecTheme.FS_BODY, TecTheme.MUTED)
		cap.name = "card_fields_cap"
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(cap)
		_fields_box = VBoxContainer.new()
		_fields_box.name = "card_fields"
		_fields_box.add_theme_constant_override("separation", 4)
		_fields_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(_fields_box)
		_build_fields(fields)
		_content.add_child(_rule())

	var notes_cap := TecTheme.label("备注", TecTheme.FS_BODY, TecTheme.MUTED)
	notes_cap.name = "card_notes_cap"
	notes_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(notes_cap)

	_note = TextEdit.new()
	_note.name = "card_note"
	_note.custom_minimum_size = Vector2(0, 72)
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

	_close_btn = TecTheme.mini_button("×", "关闭档案卡")
	_close_btn.name = "card_close"
	_close_btn.position = Vector2(W - 26.0, 6.0)
	_close_btn.z_index = 2
	_close_btn.pressed.connect(close)
	add_child(_close_btn)


func _build_fields(fields: Array) -> void:
	if _fields_box == null:
		return
	for c in _fields_box.get_children():
		_fields_box.remove_child(c)
		c.queue_free()
	_field_boxes.clear()
	for raw in fields:
		if raw is Dictionary:
			_add_field(raw as Dictionary)


func _add_field(f: Dictionary) -> void:
	var fid := String(f.get("id", ""))
	if fid == "":
		return
	var state := String(f.get("state", "empty"))
	var box := PanelContainer.new()
	box.name = "field_" + fid
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.tooltip_text = "「%s」还缺证据：把一张「证」级结论拖到这一行。" % String(f.get("label", fid))
	var edge := TecTheme.EDGE
	var bw := 1
	if state == "stamped":
		edge = TecTheme.SPOT_DANGER
		bw = 2
	elif state == "pending":
		edge = TecTheme.NONE
		bw = 0
	var sb := TecTheme.flat(TecTheme.CARD, TecTheme.R_BTN, edge, bw)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	box.add_theme_stylebox_override("panel", sb)
	_fields_box.add_child(box)
	_field_boxes[fid] = box

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(col)
	if state == "pending":
		var dashed := FieldDashed.new()
		dashed.name = "field_pending_dash"
		dashed.set_anchors_preset(Control.PRESET_FULL_RECT)
		dashed.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(dashed)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var lab := TecTheme.label(String(f.get("label", fid)), TecTheme.FS_BODY, TecTheme.TEXT)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.clip_text = true
	lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(lab)
	var state_text := "缺证据"
	var state_col := TecTheme.MUTED
	match state:
		"stamped":
			state_text = "已核准"
			state_col = TecTheme.SPOT_DANGER
		"pending":
			state_text = "待核对"
			state_col = TecTheme.TEXT
		"draft":
			state_text = "待附证据"
			state_col = TecTheme.MUTED
	var tag := TecTheme.label(state_text, TecTheme.FS_BODY, state_col)
	tag.name = "field_state"
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(tag)
	if state == "pending":
		## 核对键压在标题行，别在字段底部再长一行：档案卡在 960×560 下必须完整落在桌面内。
		var check := TecTheme.button("核对")
		check.name = "field_check"
		check.custom_minimum_size = Vector2(40, 18)
		check.add_theme_font_size_override("font_size", TecTheme.FS_BODY)
		check.tooltip_text = "请 TEC 核对这批主张"
		check.pressed.connect(func(): field_check_requested.emit(person_id))
		top.add_child(check)

	var prompt := String(f.get("prompt", ""))
	if prompt != "":
		var p := TecTheme.label(prompt, TecTheme.FS_BODY, TecTheme.MUTED)
		p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(p)

	var ev_text := "证据 · " + String(f.get("evidence_label", "")) \
		if String(f.get("evidence_id", "")) != "" else "证据 · 未附"
	var ev := TecTheme.label(ev_text, TecTheme.FS_BODY, TecTheme.MUTED)
	ev.clip_text = true
	ev.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(ev)

	var opts := HFlowContainer.new()
	opts.name = "field_options"
	opts.add_theme_constant_override("h_separation", 3)
	opts.add_theme_constant_override("v_separation", 3)
	opts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(opts)
	var chosen := String(f.get("value", ""))
	for raw_opt in f.get("options", []):
		var opt := String(raw_opt)
		var b := TecTheme.button(opt)
		b.name = "field_opt_" + opt
		b.custom_minimum_size = Vector2(0, 20)
		b.add_theme_font_size_override("font_size", TecTheme.FS_BODY)
		b.disabled = state == "stamped"
		if opt == chosen:
			var on_sb := TecTheme.flat(TecTheme.INK, TecTheme.R_BTN, TecTheme.INK, 1)
			b.add_theme_stylebox_override("normal", on_sb)
			b.add_theme_stylebox_override("hover", on_sb)
			b.add_theme_stylebox_override("pressed", on_sb)
			b.add_theme_color_override("font_color", TecTheme.CARD)
			b.add_theme_color_override("font_hover_color", TecTheme.CARD)
			b.add_theme_color_override("font_pressed_color", TecTheme.CARD)
		b.pressed.connect(_on_field_option_pressed.bind(fid, opt))
		opts.add_child(b)




func _on_field_option_pressed(field_id: String, value: String) -> void:
	field_word_selected.emit(person_id, field_id, value)


func refresh_evidence(fields: Array) -> void:
	_payload["evidence_fields"] = fields.duplicate(true)
	_build_fields(fields)


func evidence_drop_targets() -> Array:
	var out: Array = []
	for fid in _field_boxes.keys():
		var box := _field_boxes[fid] as Control
		if box == null or not is_instance_valid(box) or not box.visible:
			continue
		out.append({"id": String(fid), "rect": box.get_global_rect()})
	return out


func field_state(field_id: String) -> String:
	var fields: Array = _payload.get("evidence_fields", [])
	for raw in fields:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == field_id:
			return String((raw as Dictionary).get("state", ""))
	return ""


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
