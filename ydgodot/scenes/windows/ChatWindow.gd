class_name ChatWindow
extends SysWindow
## 多人对话窗（对齐 Web `.chat-win` / `11-dialog.js`）：
## 390 宽、右上角、逐行打字；有台词的人不在场时停下等，拖人物进来续播。

const CHAR_MS := 45.0
const BODY_PAD_X := 12.0
const BODY_PAD_Y := 4.0
const AvatarFrameScript = preload("res://ui/AvatarFrame.gd")

var session: DialogueSession
var case_def: CaseLoader

var _line_box: VBoxContainer
var _scroll: ScrollContainer
var _area: Control
var _rows: Array = []
var _hint_rule: ColorRect
var _hint_box: MarginContainer
var _hint: Label
var _cur: TypewriterLabel = null
var _cur_text := ""
var _lines_shown := 0
## 独白 / 反应独白：一次把全部行贴出，不要求玩家逐句点击。
var _reveal_all := false


## `p_reveal_all`：独白整段直接可见；标题可用 `p_title` 覆盖，
## 反应独白据此带上「对『某物』的反应」，而普通对话仍走逐行推进。
func setup_chat(p_entry: DialogueDef, initial_ids: Array, p_case: CaseLoader,
		p_reveal_all := false, p_title := "") -> void:
	case_def = p_case
	session = DialogueSession.new(p_entry, initial_ids)
	_reveal_all = p_reveal_all
	var head := p_title if p_title != "" else _chat_title(p_entry, initial_ids)
	setup(head, 390, 200)
	content.add_theme_constant_override("separation", 0)

	## W9：对话越长越不能把窗撑出桌布。正文放进滚动区，窗高封顶；
	## 结构照抄 TEC 的 area + ScrollContainer，滚轮 / 拖动滚动条都能回看旧台词。
	_area = Control.new()
	_area.name = "chat_area"
	_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_area.custom_minimum_size = Vector2(0, 96)
	_area.clip_contents = true
	_area.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(_area)

	_scroll = ScrollContainer.new()
	_scroll.name = "chat_scroll"
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_area.add_child(_scroll)

	var pad := MarginContainer.new()
	pad.name = "chat_pad"
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", int(BODY_PAD_X))
	pad.add_theme_constant_override("margin_right", int(BODY_PAD_X))
	pad.add_theme_constant_override("margin_top", int(BODY_PAD_Y))
	pad.add_theme_constant_override("margin_bottom", int(BODY_PAD_Y))
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
	content.add_child(_hint_rule)

	_hint_box = MarginContainer.new()
	_hint_box.name = "chat_hint_box"
	_hint_box.add_theme_constant_override("margin_left", 12)
	_hint_box.add_theme_constant_override("margin_right", 12)
	_hint_box.add_theme_constant_override("margin_top", 5)
	_hint_box.add_theme_constant_override("margin_bottom", 6)
	_hint_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_box.visible = false
	content.add_child(_hint_box)

	_hint = TecTheme.label("", TecTheme.FS_BODY, TecTheme.MUTED)
	_hint.name = "chat_hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_box.add_child(_hint)

	body.gui_input.connect(_on_click)
	content.gui_input.connect(_on_click)
	_build_rows()
	if _reveal_all:
		_reveal_all_rows()
	else:
		_advance()
	call_deferred("_fit_height")


func _chat_title(entry: DialogueDef, ids: Array) -> String:
	var names: Array = []
	for id in ids:
		names.append(case_def.label_of("char", String(id)))
	var solo := entry != null and entry.participants.size() == 1
	var when := entry.context_when.id if entry != null and entry.context_when != null else ""
	var head := "独白 · " if solo else "对话 · "
	if when != "":
		head += case_def.time_label_of(when) + " · "
	return head + " × ".join(names)


func _on_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		advance()


func advance() -> bool:
	if is_typing():
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


func _build_rows() -> void:
	if session == null or session.entry == null:
		return
	var first := true
	for line in session.entry.script_lines:
		var raw := String(line.text)
		var text := raw.strip_edges()
		var built: Array
		if String(line.kind) == "say" and line.who != null:
			built = _say_row(line.who.id, line.who.name, text)
		else:
			var label := _new_text_label(TecTheme.MUTED)
			label.name = "chat_narr"
			label.text = text
			built = [_wrap_line(label), label]
		var root := VBoxContainer.new()
		root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root.add_theme_constant_override("separation", 0)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not first:
			## 分割线不能贴着下一行头像：上下各留 6px，和旁白行的呼吸一致。
			var rule := MarginContainer.new()
			rule.name = "chat_rule"
			rule.add_theme_constant_override("margin_top", 6)
			rule.add_theme_constant_override("margin_bottom", 6)
			rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var sep := ColorRect.new()
			sep.name = "chat_sep"
			sep.color = TecTheme.LINE2
			sep.custom_minimum_size = Vector2(0, 1)
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rule.add_child(sep)
			root.add_child(rule)
		root.add_child(built[0] as Control)
		root.modulate.a = 0.0
		_line_box.add_child(root)
		_rows.append({"root": root, "label": built[1] as TypewriterLabel, "text": text})
		first = false


func _append_line(_line: DialogueLineDef) -> void:
	var row := _rows[_lines_shown] as Dictionary
	_cur = row["label"] as TypewriterLabel
	_cur_text = String(row["text"])
	(row["root"] as Control).modulate.a = 1.0
	_cur.start_typing()
	_lines_shown += 1
	call_deferred("_fit_height")
	_scroll_to_end()


## 独白不是“点一下出一句”的对话：构建完就把所有行完整贴出。
## 同时把 session 推到 done，避免之后点击再走 step 把已显示的行重复追加。
func _reveal_all_rows() -> void:
	if session != null:
		session.index = session.total()
		session.waiting_for = ""
		session.done = true
	for raw in _rows:
		var row := raw as Dictionary
		(row["root"] as Control).modulate.a = 1.0
		var label := row["label"] as TypewriterLabel
		label.finish_typing()
	_lines_shown = _rows.size()
	if not _rows.is_empty():
		var last := _rows[_rows.size() - 1] as Dictionary
		_cur = last["label"] as TypewriterLabel
		_cur_text = String(last["text"])


func _say_row(who_id: String, who_name: String, text: String) -> Array:
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
	var name := TecTheme.label(who_name, TecTheme.FS_BODY, TecTheme.MUTED)
	name.name = "chat_who"
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(name)
	var label := _new_text_label(TecTheme.TEXT)
	label.name = "chat_text"
	label.text = text
	main.add_child(label)
	row.add_child(main)
	return [row, label]


func _say_avatar(who_id: String, who_name: String) -> Control:
	var frame := AvatarFrameScript.new()
	frame.name = "chat_av"
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.setup(case_def.avatar_path_of(who_id) if case_def != null else "", 30.0,
		who_name.substr(0, 1) if who_name != "" else "?")
	return frame


func _new_text_label(color: Color) -> TypewriterLabel:
	return TecTheme.narrative_label("", color)


func _wrap_line(row: Control) -> Control:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 6)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)
	return pad


func finish_line() -> void:
	if _cur != null:
		_cur.finish_typing()


func set_hint(text: String) -> void:
	if _hint == null:
		return
	var on := text != ""
	_hint.text = text
	_hint_box.visible = on
	_hint_rule.visible = on
	call_deferred("_fit_height")


## Web 的 `.chat-win` 高度随内容长；W9 起封顶 380，超出部分进滚动区。
func _fit_height() -> void:
	if content == null or body == null or _line_box == null:
		return
	if not is_inside_tree():
		await tree_entered
	await get_tree().process_frame
	var lines_h := _line_box.get_combined_minimum_size().y
	var hint_h := 0.0
	if _hint_box != null and _hint_box.visible:
		hint_h = _hint_box.get_combined_minimum_size().y + 1.0
	## 正文区还有 `chat_pad` 的上下 4px；只按 line_box 算会把最后一行切掉。
	var lo := 120.0 if _reveal_all else 200.0
	var target := clampf(SysWindow.BAR_H + 20.0 + lines_h + BODY_PAD_Y * 2.0 + hint_h,
		lo, 380.0)
	if absf(size.y - (target + SysWindow.PAD * 2.0)) > 0.5:
		set_inner_height(target)


func _scroll_to_end() -> void:
	if _scroll == null or not is_instance_valid(_scroll) or not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree() or _scroll == null or not is_instance_valid(_scroll):
		return
	_scroll.set_deferred("scroll_vertical", 1 << 20)


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


func is_monologue() -> bool:
	return _reveal_all


func is_typing() -> bool:
	return _cur != null and _cur.is_typing()


func typed_text() -> String:
	return _cur.typed_text() if _cur != null else ""


func current_text() -> String:
	return _cur_text


func waiting_for() -> String:
	return session.waiting_for if session != null else ""


func state() -> Dictionary:
	var out := session.state() if session != null else {}
	out["open"] = true
	out["typing"] = is_typing()
	out["lines"] = _lines_shown
	return out
