class_name ChatWindow
extends SysWindow
## 多人对话窗（对齐 Web `.chat-win` / `11-dialog.js`）：
## 390 宽、右上角、逐行打字；有台词的人不在场时停下等，拖人物进来续播。

const CHAR_MS := 45.0
const AVATAR_ART := {
	"CHARS_TEC": "res://assets/raw/tec-avatar.png",
	"CHARS_EXEC": "res://assets/raw/executor-avatar.png",
}

var session: DialogueSession
var case_def: CaseLoader

var _scroll: ScrollContainer
var _line_box: VBoxContainer
var _hint_rule: ColorRect
var _hint_box: MarginContainer
var _hint: Label
var _cur: Label = null
var _cur_text := ""
var _shown := 0.0
var _typing := false
var _lines_shown := 0


func setup_chat(p_entry: DialogueDef, initial_ids: Array, p_case: CaseLoader) -> void:
	case_def = p_case
	session = DialogueSession.new(p_entry, initial_ids)
	setup(_chat_title(p_entry, initial_ids), 390, 200)
	body.clip_contents = true

	var col := VBoxContainer.new()
	col.name = "chat_col"
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(col)

	_scroll = ScrollContainer.new()
	_scroll.name = "chat_scroll"
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.gui_input.connect(_on_click)
	col.add_child(_scroll)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 4)
	pad.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(pad)

	_line_box = VBoxContainer.new()
	_line_box.name = "chat_lines"
	_line_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line_box.add_theme_constant_override("separation", 0)
	_line_box.mouse_filter = Control.MOUSE_FILTER_PASS
	pad.add_child(_line_box)

	_hint_rule = ColorRect.new()
	_hint_rule.name = "chat_hint_rule"
	_hint_rule.color = TecTheme.EDGE_SOFT
	_hint_rule.custom_minimum_size = Vector2(0, 1)
	_hint_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_rule.visible = false
	col.add_child(_hint_rule)

	_hint_box = MarginContainer.new()
	_hint_box.name = "chat_hint_box"
	_hint_box.add_theme_constant_override("margin_left", 12)
	_hint_box.add_theme_constant_override("margin_right", 12)
	_hint_box.add_theme_constant_override("margin_top", 5)
	_hint_box.add_theme_constant_override("margin_bottom", 6)
	_hint_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_box.visible = false
	col.add_child(_hint_box)

	_hint = TecTheme.label("", 11, TecTheme.FAINT)
	_hint.name = "chat_hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_box.add_child(_hint)

	body.gui_input.connect(_on_click)
	col.gui_input.connect(_on_click)
	_advance()
	call_deferred("_fit_height")


func _chat_title(entry: DialogueDef, ids: Array) -> String:
	var names: Array = []
	for id in ids:
		names.append(case_def.label_of("char", String(id)))
	var solo := entry != null and entry.participants.size() == 1
	var when := entry.context_when.id if entry != null and entry.context_when != null else ""
	var head := "独白 // " if solo else "DIALOGUE // "
	if when != "":
		head += case_def.time_label_of(when) + " · "
	return head + " × ".join(names)


func _on_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		advance()


func advance() -> bool:
	if _typing:
		finish_line()
		return true
	if session == null or session.done or session.waiting_for != "":
		return false
	return _advance() > 0


func _advance() -> int:
	if session == null:
		return 0
	var res := session.step()
	var status := String(res.get("status", "done"))
	if status == "line":
		_append_line(res["line"] as DialogueLineDef)
		return 1
	if status == "wait":
		set_hint("把「" + case_def.label_of("char", String(res["who"])) + "」拖进对话框")
		return 0
	set_hint("")
	return 0


func _append_line(line: DialogueLineDef) -> void:
	if _line_box.get_child_count() > 0:
		var sep := ColorRect.new()
		sep.color = TecTheme.LINE2
		sep.custom_minimum_size = Vector2(0, 1)
		sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_line_box.add_child(sep)
	var raw := String(line.text)
	var text := case_def.strip_tags(raw).strip_edges()
	if String(line.kind) == "say" and line.who != null:
		_line_box.add_child(_wrap_line(_say_row(line.who.id, line.who.name, text)))
	else:
		var label := _new_text_label(TecTheme.MUTED)
		label.name = "chat_narr"
		label.text = text
		_line_box.add_child(_wrap_line(label))
		_start_typing(label, text)
	_lines_shown += 1
	call_deferred("_fit_height")


func _say_row(who_id: String, who_name: String, text: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "chat_say"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_say_avatar(who_id, who_name))

	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 2)
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name := TecTheme.label(who_name, 12, TecTheme.MUTED)
	name.name = "chat_who"
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(name)
	var label := _new_text_label(TecTheme.TEXT)
	label.name = "chat_text"
	label.text = text
	main.add_child(label)
	row.add_child(main)
	_start_typing(label, text)
	return row


func _say_avatar(who_id: String, who_name: String) -> Control:
	var frame := PanelContainer.new()
	frame.name = "chat_av"
	frame.custom_minimum_size = Vector2(30, 30)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", TecTheme.flat(TecTheme.BG, 6, TecTheme.EDGE))
	var art := String(AVATAR_ART.get(who_id, ""))
	if art != "" and ResourceLoader.exists(art):
		var tex := TextureRect.new()
		tex.texture = load(art)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(tex)
	else:
		var ini := TecTheme.label(who_name.substr(0, 1) if who_name != "" else "?", 15, TecTheme.MUTED)
		ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ini.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(ini)
	return frame


func _new_text_label(color: Color) -> Label:
	var label := TecTheme.label("", 13, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible_characters = 0
	return label


func _wrap_line(row: Control) -> Control:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 6)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)
	return pad


func _start_typing(label: Label, text: String) -> void:
	_cur = label
	_cur_text = text
	_shown = 0.0
	_typing = true
	label.visible_characters = 0
	set_process(true)
	_scroll_bottom()


func _process(delta: float) -> void:
	if not _typing or _cur == null:
		return
	_shown += delta * (1000.0 / CHAR_MS)
	var n := int(_shown)
	if n >= _cur_text.length():
		finish_line()
	else:
		_cur.visible_characters = n


func finish_line() -> void:
	if _cur != null:
		_cur.visible_characters = -1
	_typing = false
	set_process(false)
	_scroll_bottom()


func _scroll_bottom() -> void:
	if _scroll == null:
		return
	_scroll.scroll_vertical = 1000000
	call_deferred("_scroll_bottom_now")


func _scroll_bottom_now() -> void:
	if _scroll != null and is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func set_hint(text: String) -> void:
	if _hint == null:
		return
	var on := text != ""
	_hint.text = text
	_hint_box.visible = on
	_hint_rule.visible = on
	call_deferred("_fit_height")


## Web 的 `.chat-win` 高度随内容长；Godot 里同样只改内高，宽度和顶边保持贴右上。
func _fit_height() -> void:
	if _line_box == null or body == null:
		return
	var lines_h := _line_box.get_combined_minimum_size().y + 8.0
	var hint_h := 30.0 if _hint_box != null and _hint_box.visible else 0.0
	var need := 56.0 + lines_h + hint_h + 8.0
	var target := clampf(need, 150.0, 368.0)
	if absf(size.y - (target + SysWindow.PAD * 2.0)) > 0.5:
		set_inner_height(target)
		call_deferred("_fit_height")
	_scroll_bottom()


func hint_text() -> String:
	return _hint.text if _hint != null else ""


func drop_node(kind: String, id: String) -> bool:
	if kind != "char":
		set_hint("只有人物能加入这段对话")
		return false
	return drop_character(id)


func drop_character(id: String) -> bool:
	if session == null:
		return false
	var res := session.join(id)
	if bool(res.get("ok", false)):
		set_hint("")
		_advance()
		return true
	if String(res.get("reason", "")) != "joined":
		set_hint("插不上话")
	return false


func line_count() -> int:
	return _lines_shown


func is_typing() -> bool:
	return _typing


func typed_text() -> String:
	if _cur == null:
		return ""
	if _cur.visible_characters < 0:
		return _cur.text
	return _cur.text.substr(0, _cur.visible_characters)


func current_text() -> String:
	return _cur_text


func waiting_for() -> String:
	return session.waiting_for if session != null else ""


func state() -> Dictionary:
	var out := session.state() if session != null else {}
	out["open"] = true
	out["typing"] = _typing
	out["lines"] = _lines_shown
	return out
