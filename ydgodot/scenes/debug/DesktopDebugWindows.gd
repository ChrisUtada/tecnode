extends "res://scenes/debug/DesktopDebugAction.gd"
## 窗口与领域动作：状态、TEC、对话、人物、日志。

func dbg_state() -> Dictionary:
	return {
		"nodes": desk._cards.keys(),
		"explored": desk.graph.explored.keys(),
		"captured": desk.graph.captured.keys(),
		"tec_prog": desk.graph.tec_prog.duplicate(),
		"lit": _lit_map(),
		"selected": desk._selected,
		"cards": desk._cards.size(),
		"collapsed": desk.graph.collapsed.keys(),
		"stored": desk.graph.stored.keys(),
		"hidden": desk.graph.hidden.keys(),
		"installed": _installed_map(),
		"matrix": desk.graph.matrix.duplicate(true),
		"matrix_ids": desk.graph.matrix_ids(),
		"endings": desk.graph.endings.keys(),
		"ending_visible": desk._ending.visible if desk._ending != null else false,
		"ending_id": desk._last_ending_id,
		"can_undo": desk._save.can_undo() if desk._save != null else false,
		"history": desk._save.history.size() if desk._save != null else 0,
	}


func _installed_map() -> Dictionary:
	var out := {}
	for k in desk.graph.nodes.keys():
		var n := desk.graph.node(String(k))
		if n.kind == "item" and not n.installed.is_empty():
			out[k] = n.installed.keys()
	return out


func _lit_map() -> Dictionary:
	var out := {}
	for k in desk.graph.nodes.keys():
		var n := desk.graph.node(String(k))
		if n.kind == "item":
			out[String(n.id)] = n.lit
	return out


func dbg_expand(sid: String) -> void:
	desk.card_ui._expand_scene(sid, false)


func dbg_combo(tool_id: String, target_id: String) -> Dictionary:
	var tkind := CaseLoader.kind_of_ref(tool_id)
	var okind := CaseLoader.kind_of_ref(target_id)
	return desk.combos.use_item(desk.graph.key_of(tkind, tool_id), desk.graph.key_of(okind, target_id))


## 双击某张卡（跑第一条命令 / 展开容器，与真实双击同一条路）
func dbg_activate(key: String) -> void:
	desk.card_ui._on_card_activated(key)


## 建节点并上卡片（等价 Web 的 __ensure）
func dbg_ensure(kind: String, id: String) -> String:
	var n := desk.graph.add_node(kind, id)
	desk.canvas._spawn_card(n.key)
	desk.canvas._relayout()
	return n.key


func dbg_pw_open(node_key: String) -> void:
	desk.card_ui._open_password(node_key)


func dbg_password(node_key: String, value: String) -> void:
	# 已经为这个节点开着窗就直接提交（模拟「在同一个弹窗里改输入再点确定」）
	if desk._pw_pop == null or not is_instance_valid(desk._pw_pop) or String(desk._pw_ctx.get("node_key", "")) != node_key:
		desk.card_ui._open_password(node_key)
	desk.card_ui._submit_password(value)


func dbg_toggle_light(id: String) -> Dictionary:
	return desk.combos.toggle_light(desk.graph.key_of("item", id))


## 选中某个节点（等价点一下卡）
func dbg_select(key: String) -> void:
	desk._selected = key
	desk.graph.selected = key


## 打开某个收纳窗
func dbg_open_storage(kind: String) -> void:
	desk.drag._toggle_storage(kind)


func dbg_tec_analyze(sid: String) -> void:
	desk.tec._start_tec_analysis(desk.tec._tec_key(sid))


func dbg_reset_case(force: bool = false) -> void:
	desk.session._reset_case(force)


func dbg_commit(before: Dictionary) -> void:
	desk.session._commit(before)


func dbg_open_start_screen() -> void:
	desk.session._open_start_screen()


func dbg_start_continue() -> void:
	desk.session._on_start_continue()


func dbg_tec_finish() -> int:
	return desk._tec.done_count() if desk._tec != null else 0


func dbg_tec_complete() -> void:
	if desk._tec != null:
		desk._tec.finish_now()


func dbg_tec_open() -> void:
	desk.tec._open_tec()


func dbg_tec_close() -> void:
	desk.tec._close_tec()


func dbg_tec_minimize() -> void:
	desk.tec._minimize_tec()


func dbg_tec_hide() -> void:
	desk.tec._hide_tec()


func dbg_tec_hint(text: String) -> void:
	desk.tec._tec_hint(text, false)


func dbg_tec_win() -> TecWindow:
	return desk._tec


func dbg_tec_chip() -> TecChip:
	return desk._tec_chip


func dbg_tec_talk() -> void:
	desk.tec._tec_talk()


func dbg_tec_analyze_key(key: String) -> bool:
	return desk.tec._start_tec_analysis(key)


func dbg_tec_drop_hit(at_global: Vector2) -> bool:
	return desk.tec._tec_drop_hit(at_global)


func dbg_tec_drop(key: String, at_global: Vector2) -> void:
	desk.drag._on_card_drag_released(key, at_global)


func dbg_tec_icon_rect() -> Rect2:
	return desk._tec_btn.get_global_rect() if desk._tec_btn != null else Rect2()


func dbg_tec_info() -> Dictionary:
	var win := {}
	if desk._tec != null:
		win = desk._tec.dbg_status()
	var chip := {}
	if desk._tec_chip != null:
		chip = desk._tec_chip.dbg_state()
	return {
		"visible": desk._tec.visible if desk._tec != null else false,
		"min": desk._tec_min,
		"dot": desk._tec_dot,
		"chip_visible": desk._tec_chip.visible if desk._tec_chip != null else false,
		"win": win,
		"chip": chip,
	}


func dbg_open_archive() -> ArchiveWin:
	if desk._archive_win == null or not is_instance_valid(desk._archive_win):
		desk.narrative._toggle_archive()
	return desk._archive_win


func dbg_archive_press(tid: String) -> bool:
	if desk._archive_win == null or not is_instance_valid(desk._archive_win):
		return false
	return desk._archive_win.press_time(tid)


func dbg_archive_new() -> bool:
	return desk._archive_new


func dbg_chat() -> ChatWindow:
	if desk._chat_win != null and is_instance_valid(desk._chat_win):
		return desk._chat_win
	return null


func dbg_chat_state() -> Dictionary:
	var chat := dbg_chat()
	if chat == null:
		return {"open": false, "id": "", "participants": [], "joined": [], "idx": 0,
			"total": 0, "waitingFor": "", "typing": false, "done": false, "lines": 0}
	return chat.state()


func dbg_chat_advance() -> bool:
	var chat := dbg_chat()
	return chat.advance() if chat != null else false


func dbg_chat_finish() -> void:
	var chat := dbg_chat()
	if chat != null:
		chat.finish_line()


func dbg_chat_drop(kind: String, id: String) -> bool:
	var chat := dbg_chat()
	return chat.drop_node(kind, id) if chat != null else false


func dbg_chat_drop_key(key: String) -> bool:
	return desk.narrative._chat_drop(key)


func dbg_chat_hint() -> String:
	var chat := dbg_chat()
	return chat.hint_text() if chat != null else ""


func dbg_chat_title() -> String:
	var chat := dbg_chat()
	return chat.title if chat != null else ""


func dbg_chat_rect() -> Rect2:
	var chat := dbg_chat()
	return chat.get_global_rect() if chat != null else Rect2()


func dbg_chat_close() -> void:
	desk.narrative._close_chat()


func dbg_open_dialogue(id: String, ids: Array) -> bool:
	if desk.dialogues == null:
		return false
	return desk.narrative._open_chat(desk.dialogues.by_id(id), ids)


func dbg_open_monologue(char_id: String) -> bool:
	return desk.narrative._open_monologue(char_id)


func dbg_dialogues() -> DialogueSystem:
	return desk.dialogues


func dbg_time() -> String:
	return desk.graph.time if desk.graph != null else ""


func dbg_time_label() -> String:
	return desk.graph.time_label_of() if desk.graph != null else ""


func dbg_time_known() -> Array:
	return desk.graph.timeline_known() if desk.graph != null else []


func dbg_set_time(tid: String) -> bool:
	return desk.narrative._select_time(tid)


func dbg_mem_card() -> MemCard:
	return desk._mem_card


func dbg_mem_advance() -> bool:
	return desk._mem_card.advance() if desk._mem_card != null and is_instance_valid(desk._mem_card) else false


func dbg_close_mem() -> void:
	desk.narrative._close_mem_card()


func dbg_card_visible(key: String) -> bool:
	var card: NodeCard = desk._cards.get(key, null)
	return card != null and card.visible


func dbg_card_pos(key: String) -> Vector2:
	var card: NodeCard = desk._cards.get(key, null)
	return card.position if card != null else Vector2.ZERO


func dbg_mem_pos() -> Vector2:
	return desk._mem_card.position if desk._mem_card != null and is_instance_valid(desk._mem_card) else Vector2.ZERO


## 屏幕坐标里的视觉矩形 —— 画布有缩放 / 平移之后，「谁压住谁」只能在同一个空间里比，
## 拿 world 坐标去和桌面坐标比必然误判（2026-10-21 世界层上线的副产物）。
func dbg_card_global(key: String) -> Rect2:
	var card: NodeCard = desk._cards.get(key, null)
	if card == null or not is_instance_valid(card) or not card.visible:
		return Rect2()
	return card.get_global_rect()


func dbg_mem_global() -> Rect2:
	if desk._mem_card == null or not is_instance_valid(desk._mem_card):
		return Rect2()
	return desk._mem_card.get_global_rect()


func dbg_combo_ui(tool_id: String, target_id: String) -> void:
	if desk.graph == null:
		return
	desk.card_ui._on_card_combo(_dbg_node_key(tool_id), _dbg_node_key(target_id))


func _dbg_node_key(id: String) -> String:
	for key in desk.graph.nodes.keys():
		var n := desk.graph.node(String(key))
		if n.id == id and n.kind != "time":
			return String(key)
	return desk.graph.key_of(CaseLoader.kind_of_ref(id), id)


func dbg_toast_text() -> String:
	return desk._toast_label.text if desk._toast_label != null else ""


func dbg_open_people() -> PeopleWin:
	if desk._people_win == null or not is_instance_valid(desk._people_win):
		desk.people._toggle_people()
	return desk._people_win


func dbg_people_win() -> PeopleWin:
	return desk._people_win if desk._people_win != null and is_instance_valid(desk._people_win) else null


func dbg_close_people() -> void:
	desk.people._close_person_card()
	if desk._people_win != null and is_instance_valid(desk._people_win):
		desk._people_win.queue_free()
	desk._people_win = null


func dbg_people_row(id: String) -> void:
	desk.people._on_people_row(id)


func dbg_person_card() -> Control:
	return desk._people_card if desk._people_card != null and is_instance_valid(desk._people_card) else null


func dbg_person_payload(id: String) -> Dictionary:
	return desk.people._person_payload(id)


func dbg_person_id() -> String:
	return String(desk._people_card.person_id) if desk._people_card != null and is_instance_valid(desk._people_card) else ""


func dbg_person_action(id: String = "") -> void:
	var target := id
	if target == "" and desk._people_card != null and is_instance_valid(desk._people_card):
		target = desk._people_card.person_id
	if target != "":
		desk.people._on_person_action(target)


func dbg_person_note(id: String, text: String) -> void:
	desk.people._on_person_note_committed(id, text)
	if desk._people_card != null and is_instance_valid(desk._people_card) and desk._people_card.person_id == id:
		desk._people_card.set_note_text(text)


func dbg_person_fields(person_id: String) -> Array:
	return desk.people._person_field_payload(person_id)


func dbg_person_field_word(person_id: String, field_id: String, value: String) -> void:
	desk.people._on_person_field_word(person_id, field_id, value)


func dbg_person_field_drop(person_id: String, field_id: String, key: String) -> bool:
	return desk.people._assign_evidence_to_field(person_id, field_id, key, "canvas")


func dbg_person_check(person_id: String) -> bool:
	return desk.people._check_person_claims(person_id)


func dbg_person_field_state(field_id: String) -> String:
	return desk._people_card.field_state(field_id) if desk._people_card != null and is_instance_valid(desk._people_card) else ""


func dbg_close_person_card() -> void:
	desk.people._close_person_card()


func dbg_place_person_card() -> void:
	desk.people._place_person_card()


func dbg_open_log() -> LogWin:
	if desk._log_win == null or not is_instance_valid(desk._log_win):
		desk._toggle_log()
	return desk._log_win


func dbg_log_win() -> LogWin:
	return desk._log_win if desk._log_win != null and is_instance_valid(desk._log_win) else null


func dbg_close_log() -> void:
	if desk._log_win != null and is_instance_valid(desk._log_win):
		desk._log_win.queue_free()
	desk._log_win = null


func dbg_log_kinds() -> Array:
	return desk.graph.logs.map(func(e): return String((e as Dictionary).get("kind", "")))


func dbg_log_texts() -> Array:
	return desk.graph.logs.map(func(e): return String((e as Dictionary).get("text", "")))


func dbg_add_log(text: String, kind: String = "") -> void:
	desk._log(text, kind)


