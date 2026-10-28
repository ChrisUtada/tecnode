extends Node
## 测试 / 截图专用 API。
##
## 只在 OS.is_debug_build() 或 --shot 下由 Desktop 实例化；产品代码不得依赖它。
## `desk` 由 Desktop 注入，函数名保持 `dbg_*` 不变，测试走 `scene.debug.dbg_*`。

var desk: Desktop


func dbg_undo() -> bool:
	return desk.session._undo()


func dbg_history_size() -> int:
	return desk._save.history.size() if desk._save != null else 0


func dbg_last_rebuild_stats() -> Dictionary:
	return desk.canvas._last_rebuild_stats.duplicate(true)


func dbg_save() -> bool:
	return desk._save.save_to_disk() if desk._save != null else false


func dbg_load() -> bool:
	if desk._save == null or not desk._save.load_from_disk():
		return false
	desk.canvas._rebuild_from_graph(true)
	return true


func dbg_clear_save() -> void:
	if desk._save != null:
		desk._save.clear_save()


func dbg_save_path() -> String:
	return desk._save.path if desk._save != null else ""


func dbg_use_temp_save(p_path: String) -> void:
	desk._save = SaveSystem.new(desk.graph, desk.session._case_id(), p_path)
	desk._save.clear_save()
	desk._save.clear_history()


## 供测试钩子 / 后续接线用：把当前选中的节点收进某个收纳处
## 无头钩子：模拟「把收纳窗里的一行拖到 at_global」（跳过 _process 的指针轮询）
func dbg_storage_drag(key: String, at_global: Vector2) -> void:
	if not desk.graph.stored.has(key):
		return
	desk.drag._on_row_pressed(key, String(desk.graph.stored.get(key, "")), at_global)
	desk._sdrag_started = true
	desk.drag._finish_sdrag(at_global)


## 探针：当前落点表的 id 列表（保持顺序）。
## 单一入口的意义就在这里 —— 以后加落点只改 `_drop_targets()` 与 `_apply_drop()`，
## 悬停高亮、松手分派共用同一份，不可能出现"高亮了但不生效"。
func dbg_drop_target_ids() -> Array:
	var out: Array = []
	for t in desk.drag._drop_targets():
		out.append(String(t["id"]))
	return out


func dbg_store(kind: String) -> bool:
	if desk._selected == "":
		return false
	if kind == GraphState.MATRIX:
		return desk.matrix._assign_to_matrix(desk._selected)
	var before: Dictionary = desk._save.snapshot()
	var ok := false
	if kind == GraphState.BAG:
		ok = desk.graph.bag_store(desk._selected)
	elif kind == GraphState.LEDGER:
		ok = desk.graph.ledger_store(desk._selected)
	if not ok:
		return false
	desk.card_ui._apply_hidden()
	desk.matrix._refresh_matrix_views()
	desk.session._commit(before)
	return true


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
		var n: Dictionary = desk.graph.nodes[k]
		if n["kind"] == "item" and not (n.get("installed", {}) as Dictionary).is_empty():
			out[k] = (n["installed"] as Dictionary).keys()
	return out


func _lit_map() -> Dictionary:
	var out := {}
	for k in desk.graph.nodes.keys():
		var n: Dictionary = desk.graph.nodes[k]
		if n["kind"] == "item":
			out[String(n["id"])] = bool(n.get("lit", false))
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
	var n: Dictionary = desk.graph.add_node(kind, id)
	desk.canvas._spawn_card(String(n["key"]))
	desk.canvas._relayout()
	return String(n["key"])


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
		var n: Dictionary = desk.graph.node(String(key))
		if String(n.get("id", "")) == id and String(n.get("kind", "")) != "time":
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


## 图标栏：位置 / 顺序 / 角标文字（都是玩家可见的状态，不碰内部缓存）
func dbg_icon_pos(app: String) -> Vector2:
	var b: Button = desk.launcher._icon_by_app(app)
	return b.position if b != null else Vector2(-1, -1)


func dbg_icon_visible(app: String) -> bool:
	var b: Button = desk.launcher._icon_by_app(app)
	return b != null and b.visible


## 图标栏（只列当前可见的 —— 播放器 / 花园解锁前不算占位）
func dbg_icon_apps() -> Array:
	var out: Array = []
	for c in desk.launcher._icon_layer().get_children():
		if c is DeskIcon and (c as DeskIcon).visible:
			out.append(String(c.name).trim_prefix("icon_"))
	return out


## 模拟一次图标拖动（不吃输入事件，直接走同一段位移逻辑）
func dbg_drag_icon(app: String, at: Vector2) -> void:
	var b: Button = desk.launcher._icon_by_app(app)
	if b != null:
		b.position = Vector2(clampf(at.x, 0.0, desk._desk.size.x - b.size.x),
			clampf(at.y, 0.0, desk._desk.size.y - b.size.y))


func dbg_badge_text(app: String) -> String:
	var pair := {"infer": desk._infer_badge, "bag": desk._bag_badge, "clue": desk._clue_badge,
		"log": desk._log_badge, "garden": desk._garden_badge}
	var badge: PanelContainer = pair.get(app, null)
	if badge == null or not is_instance_valid(badge) or not badge.visible:
		return ""
	var lab: Label = badge.get_node_or_null("Label")
	return lab.text if lab != null else ""


func dbg_log_unread() -> int:
	return desk._log_unread


## 模拟双击图标（两次点击必须落在 300ms 判决窗内，见 _on_icon_pressed）
func dbg_double_click_icon(app: String) -> void:
	var b: Button = desk.launcher._icon_by_app(app)
	if b == null:
		return
	desk.launcher._on_icon_pressed(app, b)
	desk.launcher._on_icon_pressed(app, b)


func dbg_open_matrix() -> MatrixWin:
	if desk._matrix_win == null or not is_instance_valid(desk._matrix_win):
		desk.matrix._toggle_matrix()
	return desk._matrix_win


func dbg_matrix_assign(key: String) -> bool:
	return desk.matrix._assign_to_matrix(key)


func dbg_matrix_toggle() -> void:
	desk.matrix._toggle_matrix()


func dbg_matrix_refresh() -> void:
	desk.matrix._refresh_matrix_views()


func dbg_matrix_sync_occlusion() -> void:
	desk.matrix._sync_matrix_occlusion()


func dbg_ledger_to_matrix(key: String) -> void:
	desk.matrix._on_ledger_to_matrix(key)


func dbg_matrix_win() -> MatrixWin:
	return desk._matrix_win if desk._matrix_win != null and is_instance_valid(desk._matrix_win) else null


func dbg_matrix_charge() -> void:
	if desk._matrix_win != null and is_instance_valid(desk._matrix_win):
		desk._matrix_win.finish_charge()


func dbg_matrix_take(key: String) -> void:
	desk.matrix._on_matrix_took(key)


func dbg_ending() -> EndingOverlay:
	return desk._ending


func dbg_ending_id() -> String:
	return desk._last_ending_id


func dbg_ending_finish() -> void:
	if desk._ending != null:
		desk._ending.finish_now()


func dbg_confirm_ending() -> void:
	if desk._ending == null or not desk._ending.visible:
		return
	desk._ending.visible = false
	desk._ending.finished.emit()


func dbg_music_icon_visible() -> bool:
	return desk._music_btn != null and desk._music_btn.visible


func dbg_garden_icon_visible() -> bool:
	return desk._garden_btn != null and desk._garden_btn.visible


func dbg_garden_badge_text() -> String:
	if desk._garden_badge == null or not desk._garden_badge.visible:
		return ""
	var l: Label = desk._garden_badge.get_node_or_null("Label")
	return l.text if l != null else ""


func dbg_music_win() -> MusicWin:
	return desk._music_win if desk._music_win != null and is_instance_valid(desk._music_win) else null


func dbg_music_dock() -> MusicDock:
	return desk._music_dock if desk._music_dock != null and is_instance_valid(desk._music_dock) else null


func dbg_click_music_icon() -> void:
	if desk._music_btn != null and is_instance_valid(desk._music_btn):
		desk.launcher._on_icon_pressed("music", desk._music_btn)


func dbg_open_music() -> MusicWin:
	desk.garden_music._open_music()
	return dbg_music_win()


func dbg_minimize_music() -> void:
	desk.garden_music._minimize_music()


func dbg_restore_music() -> void:
	desk.garden_music._restore_music()


func dbg_close_music() -> void:
	desk.garden_music._on_music_closed()


func dbg_music_play(id: String) -> bool:
	var w := dbg_music_win()
	if w == null:
		w = dbg_open_music()
	return w.play_track(id) if w != null else false


func dbg_music_toggle() -> bool:
	return desk._music_win.toggle_current() if dbg_music_win() != null else false


func dbg_music_stop() -> void:
	desk.garden_music._stop_music()


func dbg_music_state() -> Dictionary:
	var w := dbg_music_win()
	if w == null:
		return {}
	var s := w.state()
	s["win_visible"] = w.visible
	s["dock_visible"] = desk._music_dock != null and is_instance_valid(desk._music_dock) and desk._music_dock.visible
	return s


func dbg_layout_music_windows() -> void:
	desk.garden_music._place_music_windows()


func dbg_garden_win() -> GardenWin:
	return desk._garden_win if desk._garden_win != null and is_instance_valid(desk._garden_win) else null


func dbg_open_garden() -> GardenWin:
	if desk._garden_win == null or not is_instance_valid(desk._garden_win):
		desk.garden_music._open_garden()
	return dbg_garden_win()


func dbg_close_garden() -> void:
	if desk._garden_win != null and is_instance_valid(desk._garden_win):
		desk._garden_win.queue_free()
	desk._garden_win = null


func dbg_garden_state() -> Dictionary:
	var w := dbg_garden_win()
	if w != null:
		return w.dbg_state()
	return {}


func dbg_garden_icon_rect() -> Rect2:
	return desk._garden_btn.get_global_rect() if desk._garden_btn != null else Rect2()


func dbg_drop_seed(at_global: Vector2) -> bool:
	return desk.garden_music._drop_seed(at_global)


func dbg_play_true_ending() -> void:
	if desk._ending == null:
		return
	desk._last_ending_id = "TRUE_E"
	desk._ending.play(desk.case_def.ending_by_id("TRUE_E"))


func dbg_touch_garden_plot(idx: int, at_ms: int) -> bool:
	if desk.graph == null or not (desk.graph.garden is Dictionary):
		return false
	var plots: Array = desk.graph.garden.get("plots", [])
	if idx < 0 or idx >= plots.size():
		return false
	plots[idx]["at"] = at_ms
	plots[idx]["hit"] = false
	if desk._garden_win != null and is_instance_valid(desk._garden_win):
		desk._garden_win.refresh()
	return true


func dbg_use_temp_progress(path: String) -> void:
	desk._progress_path = path
	desk._progress_read_only = false
	desk._catalog.clear_progress(path)
	desk._catalog = CaseCatalog.new(path)
	desk.session._update_case_park_ui()


func dbg_case_info() -> Dictionary:
	return {
		"id": desk._active_case,
		"open": desk._case_open,
		"held": desk._case_held,
		"dock": desk._case_docked,
		"dock_visible": desk._dock_card != null and desk._dock_card.visible,
		"badge_visible": desk._map_badge != null and desk._map_badge.visible,
		"map_open": desk._map_win != null and is_instance_valid(desk._map_win),
		"title": desk._case_win.title if desk._case_win != null else "",
		"unlocked": desk._catalog.unlocked.duplicate(),
		"completed": desk._catalog.completed.duplicate(),
		"last": desk._catalog.last,
		"progress_path": desk._progress_path,
	}


func dbg_park_case(where: String) -> bool:
	return desk.session._park_case(where)


func dbg_reopen_case() -> void:
	desk.session._reopen_case()


func dbg_open_case_map() -> CaseMapWin:
	if desk._map_win == null or not is_instance_valid(desk._map_win):
		desk.session._toggle_case_map()
	return desk._map_win


func dbg_case_map_win() -> CaseMapWin:
	return desk._map_win if desk._map_win != null and is_instance_valid(desk._map_win) else null


func dbg_case_map_click(id: String) -> bool:
	var w := dbg_case_map_win()
	return w.dbg_click(id) if w != null else false


func dbg_case_map_state(id: String) -> String:
	var w := dbg_case_map_win()
	return w.dbg_row_state(id) if w != null else ""


func dbg_enter_case(id: String) -> bool:
	return desk.session._enter_case(id)


func dbg_catalog_unlock(id: String) -> bool:
	var ok: bool = desk._catalog.unlock(id)
	desk.session._update_case_park_ui()
	return ok


func dbg_catalog() -> CaseCatalog:
	return desk._catalog


func dbg_catalog_unlock_next(id: String) -> bool:
	var ok: bool = desk._catalog.unlock_next(id)
	desk.session._update_case_park_ui()
	return ok


func dbg_use_temp_investigator(path: String) -> void:
	desk._inv_path = path
	desk._investigator = Investigator.load_from(path)
	desk.session._refresh_chip()


func dbg_clear_investigator() -> void:
	Investigator.clear(desk._inv_path)
	desk._investigator = {}
	desk.session._refresh_chip()


func dbg_investigator() -> Dictionary:
	return desk._investigator.duplicate(true)


func dbg_open_intro() -> IntroWin:
	return desk.session._open_intro()


func dbg_intro_open() -> bool:
	return desk._intro != null and is_instance_valid(desk._intro)


func dbg_open_cert() -> void:
	desk.session._open_cert_review()


func dbg_cert_open() -> bool:
	return desk._cert_win != null and is_instance_valid(desk._cert_win)


func _wait(sec: float) -> void:
	await desk.get_tree().create_timer(sec).timeout


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = desk.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[shot] ", path, " ", img.get_width(), "x", img.get_height())


func _shot_flow() -> void:
	await _wait(0.6)
	await _shot("res://docs/p0_1_desktop.png")

	desk.card_ui._expand_scene("SCENES_garden", true)
	await _wait(0.5)
	await _shot("res://docs/p0_2_garden.png")

	# 开局不再直接给手电筒（对齐 Web）：截图流程走真实链路 书桌 → 抽屉 → 左侧抽屉
	desk.card_ui._on_card_activated("item:ITEM_shuzhuo")
	await _wait(0.25)
	desk.card_ui._on_card_activated("item:ITEM_chouti")
	await _wait(0.25)
	desk.card_ui._on_card_activated("loc:SCENES_choutiyi")
	await _wait(0.25)

	desk.combos.toggle_light("item:ITEM_shoudiantong")
	if desk._cards.has("item:ITEM_shoudiantong"):
		desk._cards["item:ITEM_shoudiantong"].refresh()
		desk.canvas._sync_card_shell(desk._cards["item:ITEM_shoudiantong"])
	desk.card_ui._on_card_combo("item:ITEM_shoudiantong", "item:ITEM_something")
	await _wait(0.5)
	await _shot("res://docs/p0_3_body.png")

	desk.tec._toggle_tec()
	desk.tec._start_tec_analysis("loc:SCENES_body")
	await _wait(1.1)                      # 分析进行中（真实 5–8 秒，这里取中段）
	await _shot("res://docs/p0_4_tec.png")
	desk._tec.finish_now()
	await _wait(0.25)
	# P1.4 起 TEC 分析不再直接触发结局：这里仍按 P0 基线直接放 TRUE_E，只为保留对拍图
	desk._ending.play(desk.case_def.ending_by_id("TRUE_E"))
	await _wait(0.25)
	await _shot("res://docs/p0_5_ending.png")
	desk._ending.finish_now()
	await _wait(0.25)
	await _shot("res://docs/p0_6_ending_full.png")

	# ── P1 新特性：容器展开 / 选项节点 / 密码弹窗 / 折叠 ──
	desk._ending.visible = false
	desk.session._start_slice()
	await _wait(0.3)
	desk.card_ui._expand_scene("SCENES_garden", false)
	await _wait(0.2)
	_ensure_card("item", "ITEM_shuzhuo")
	desk.card_ui._toggle_container("item", "ITEM_shuzhuo")
	await _wait(0.35)
	await _shot("res://docs/p1_1_container.png")

	desk.card_ui._toggle_container("item", "ITEM_chouti")    # choice：两个抽屉一起上画布
	await _wait(0.35)
	await _shot("res://docs/p1_2_choice.png")

	_ensure_card("item", "ITEMS_jzmh")
	desk.card_ui._open_password(desk.graph.key_of("item", "ITEMS_jzmh"))
	await _wait(0.35)
	await _shot("res://docs/p1_3_password.png")
	desk.card_ui._submit_password("0321")
	await _wait(0.35)
	await _shot("res://docs/p1_4_unlocked.png")

	desk.card_ui._toggle_container("item", "ITEM_shuzhuo")   # 再双击 = 收起
	await _wait(0.35)
	await _shot("res://docs/p1_5_collapsed.png")

	# ── 收纳三态（P1.2）：物品 / 证据两扇窗 ──
	desk.session._start_slice()
	await _wait(0.3)
	desk.card_ui._expand_scene("SCENES_garden", false)
	await _wait(0.2)
	_ensure_card("item", "ITEM_taideng")
	dbg_select("item:ITEM_taideng")
	dbg_store("BAG")
	_ensure_card("clue", "CLUES_nm")
	dbg_select("clue:CLUES_nm")
	dbg_store("LEDGER")
	desk.drag._toggle_storage(GraphState.BAG)
	await _wait(0.35)
	await _shot("res://docs/p1_6_bag.png")

	desk.drag._toggle_storage(GraphState.LEDGER)
	await _wait(0.35)
	await _shot("res://docs/p1_7_ledger.png")

	# ── 推演桌布（P1.4）：五感归位 → 长按 → 真名遮罩 ──
	var true_e: EndingDef = desk.case_def.ending_by_id("TRUE_E")
	for clue in true_e.recipe:
		_ensure_card("clue", clue.id)
		desk.matrix._assign_to_matrix(desk.graph.key_of("clue", clue.id))
	dbg_open_matrix()
	await _wait(0.4)
	await _shot("res://docs/p1_8_matrix.png")

	dbg_matrix_charge()
	await _wait(0.3)
	dbg_ending_finish()
	await _wait(0.3)
	await _shot("res://docs/p1_9_truename.png")
	desk.quit_app()


func _shot_intro_flow() -> void:
	await _wait(0.4)
	desk._inv_path = "user://shot_investigator.json"
	Investigator.clear(desk._inv_path)
	desk._investigator = {}
	desk.session._refresh_chip()
	var w: IntroWin = desk.session._open_intro()
	await _wait(0.4)
	await _shot("res://docs/p1_10_intro_name.png")
	w.dbg_set_name("林雾")
	w.dbg_begin()
	await _wait(0.3)
	await _shot("res://docs/p1_11_intro_quiz.png")
	w.dbg_answer(0)
	w.dbg_answer(0)
	w.dbg_answer(2)
	await _wait(0.3)
	await _shot("res://docs/p1_12_intro_avatar.png")
	w.dbg_confirm_pick()
	await _wait(0.3)
	await _shot("res://docs/p1_13_intro_card.png")
	w.dbg_confirm()
	await _wait(0.5)
	await _shot("res://docs/p1_14_investigator.png")
	desk.session._open_cert_review()
	await _wait(0.3)
	await _shot("res://docs/p1_15_cert.png")
	Investigator.clear(desk._inv_path)
	desk.quit_app()


func _shot_p2_flow() -> void:
	await _wait(0.5)
	desk._catalog.clear_progress(desk._progress_path)
	desk._catalog = CaseCatalog.new(desk._progress_path)
	desk.session._update_case_park_ui()

	# ── P4.2：桌面图标的按下态（只反白标签条，图标本体不垫底板）──
	# 必须**在流程开头**拍：跑到结尾时图标栏已经切紧凑模式、标签被收掉了。
	var pressed_icon: Button = desk.launcher._icon_by_app("bag")
	if pressed_icon != null:
		pressed_icon.set_selected(true)
		desk._hide_toast()
		await _wait(0.3)
		await _shot("res://docs/p2_23_icon_press.png")
		pressed_icon.set_selected(false)

	dbg_open_case_map()
	await _wait(0.35)
	await _shot("res://docs/p2_1_case_map.png")
	if desk._map_win != null and is_instance_valid(desk._map_win):
		desk._map_win.queue_free()
	desk._map_win = null

	dbg_park_case("dock")
	await _wait(0.35)
	await _shot("res://docs/p2_2_case_dock.png")

	dbg_reopen_case()
	await _wait(0.25)
	dbg_park_case("icon")
	await _wait(0.35)
	await _shot("res://docs/p2_3_case_closed.png")

	dbg_catalog_unlock("A002")
	dbg_open_case_map()
	await _wait(0.35)
	await _shot("res://docs/p2_4_case_unlocked.png")
	if desk._map_win != null and is_instance_valid(desk._map_win):
		desk._map_win.queue_free()
	desk._map_win = null

	desk.session._reopen_case()
	desk.session._start_slice()
	await _wait(0.3)
	desk.card_ui._expand_scene("SCENES_body", false)
	desk.tec._open_tec()
	desk.tec._tec_talk()
	desk.tec._tec_talk()
	desk._tec.finish_typing()
	desk._hide_toast()
	await _wait(0.35)
	await _shot("res://docs/p2_5_tec_chat.png")

	desk.tec._start_tec_analysis("loc:SCENES_body")
	await _wait(2.5)
	await _shot("res://docs/p2_6_tec_analysis.png")

	desk.tec._minimize_tec()
	await _wait(0.35)
	await _shot("res://docs/p2_7_tec_chip.png")

	desk._tec.finish_now()
	await _wait(0.3)
	desk._hide_toast()
	await _wait(0.2)
	await _shot("res://docs/p2_8_tec_chip_done.png")

	desk.tec._open_tec()
	await _wait(0.35)
	await _shot("res://docs/p2_9_tec_archive.png")

	desk.tec._hide_tec()
	desk.card_ui._expand_scene("SCENES_fkjl", false)
	await _wait(0.35)
	desk.narrative._toggle_archive()
	await _wait(0.35)
	await _shot("res://docs/p2_10_archive.png")
	desk.narrative._toggle_archive()
	await _wait(0.15)

	desk.card_ui._expand_scene("SCENES_lhsdst", false)
	await _wait(0.2)
	desk.narrative._select_time("SCENES_0602")
	await _wait(0.5)
	_show_mem_lines(3)
	await _wait(0.3)
	await _shot("res://docs/p2_11_memory_card.png")

	desk.narrative._close_mem_card()
	desk.card_ui._on_card_combo("char:NPC_FB", "loc:SCENES_garden")
	await _wait(0.3)
	_show_mem_lines(4)
	await _wait(0.35)
	await _shot("res://docs/p2_12_memory_play.png")

	desk.narrative._close_mem_card()
	desk.narrative._select_time("SCENES_0704")
	await _wait(0.5)
	desk.narrative._close_mem_card()
	desk._hide_toast()
	desk.card_ui._on_card_combo("char:CHARS_zs", "char:CHARS_luhengs")
	await _wait(0.35)
	_show_chat_lines(5)
	desk._hide_toast()
	await _wait(0.35)
	await _shot("res://docs/p2_13_dialogue.png")
	desk.narrative._close_chat()

	var garden: DialogueDef = desk.dialogues.by_id("DLG_garden_review") if desk.dialogues != null else null
	desk.narrative._open_chat(garden, ["CHARS_zs", "NPC_FB"])
	await _wait(0.3)
	desk._chat_win.finish_line()
	desk._chat_win.advance()
	desk._chat_win.finish_line()
	desk._chat_win.advance()
	desk._hide_toast()
	await _wait(0.35)
	await _shot("res://docs/p2_14_dialogue_join.png")
	desk.narrative._close_chat()

	desk.narrative._open_monologue("CHARS_luhengs")
	await _wait(0.3)
	_show_chat_lines(4)
	desk._hide_toast()
	await _wait(0.35)
	await _shot("res://docs/p2_15_monologue.png")
	desk.narrative._close_chat()

	# ── P2.5 音乐播放器 / 花园彩蛋 ──
	_ensure_card("item", "ITEMS_changji")
	_ensure_card("item", "ITEMS_cz")
	dbg_combo_ui("ITEMS_cz", "ITEMS_changji")
	desk._hide_toast()
	var music := dbg_open_music()
	if music != null:
		music.play_track("Air_Bach")
		await _wait(0.2)
		music.seek_ratio(0.25)
	await _wait(0.8)
	await _shot("res://docs/p2_16_music.png")
	desk.garden_music._minimize_music()
	await _wait(0.45)
	await _shot("res://docs/p2_17_music_dock.png")
	desk.garden_music._restore_music()
	desk.garden_music._stop_music()
	desk.garden_music._on_music_closed()

	dbg_play_true_ending()
	dbg_confirm_ending()
	await _wait(0.25)
	dbg_open_matrix()
	desk._hide_toast()
	await _wait(0.4)
	await _shot("res://docs/p2_18_matrix_seed.png")
	if desk._matrix_win != null and is_instance_valid(desk._matrix_win):
		desk._matrix_win.queue_free()
	desk._matrix_win = null
	var gwin := dbg_open_garden()
	desk._hide_toast()
	await _wait(0.45)
	await _shot("res://docs/p2_19_garden_seed.png")
	if gwin != null:
		desk.garden_music._drop_seed(gwin.field_global_rect().get_center())
		dbg_touch_garden_plot(0, GardenSystem.now_ms_now() - 181000)
		gwin._process(1.1)
		await _wait(0.2)
		gwin.dbg_open_narr(0)
		gwin.dbg_advance_narr()
		desk._hide_toast()
		await _wait(0.45)
		await _shot("res://docs/p2_20_garden_narr.png")

	# ── 批 1：人物名册 / 因果追踪 ──
	dbg_close_garden()
	await _wait(0.3)
	var people := dbg_open_people()
	desk._hide_toast()
	await _wait(0.45)
	await _shot("res://docs/p2_21_people.png")
	dbg_close_people()
	await _wait(0.25)
	dbg_open_log()
	desk._hide_toast()
	await _wait(0.45)
	await _shot("res://docs/p2_22_log.png")
	dbg_close_log()
	desk.quit_app()


func _shot_p3_flow() -> void:
	await _wait(0.5)
	desk.session._new_runtime()
	## 与 Web 侧对拍脚本对齐：那边走完开场适性测试（姓名「陈调整」），页眉才有证章。
	## 证号写死成 TEC-GD-2160，两边的证章文字才逐字相同。
	desk._investigator = {"name": "陈调整", "id": "TEC-GD-2160", "sense": ["vision"], "avatarId": "CHARS_EXEC"}
	desk.session._refresh_chip()
	var loc: Dictionary = desk.graph.add_node("loc", desk.SLICE_SCENE)
	loc["x"] = 40.0
	loc["y"] = 30.0
	desk.graph.mark_fresh(String(loc["key"]))
	desk.canvas._spawn_card(loc["key"])
	desk.canvas._relayout()
	desk._hide_toast()
	await _wait(0.5)
	await _shot("res://docs/p3/godot/start.png")
	desk.quit_app()


func _show_chat_lines(n: int) -> void:
	if desk._chat_win == null or not is_instance_valid(desk._chat_win):
		return
	desk._chat_win.finish_line()
	for i in maxi(0, n - 1):
		if not desk._chat_win.advance():
			break
		desk._chat_win.finish_line()


func _show_mem_lines(n: int) -> void:
	if desk._mem_card == null or not is_instance_valid(desk._mem_card):
		return
	desk._mem_card.finish_line()
	for i in maxi(0, n - 1):
		if not desk._mem_card.advance():
			break
		desk._mem_card.finish_line()


func _ensure_card(kind: String, id: String) -> void:
	var n: Dictionary = desk.graph.add_node(kind, id)
	desk.canvas._spawn_card(String(n["key"]))
	desk.canvas._relayout()
