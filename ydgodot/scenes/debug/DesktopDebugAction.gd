extends "res://scenes/debug/DesktopDebugQuery.gd"
## 设置场景前提 + 画布 / 卡片 / 拖放动作接缝。

# ── 设置接缝：测试只改这些「场景前提」，不直接写私有字段 ────────────────

func dbg_set_save_enabled(on: bool) -> void:
	desk._save_enabled = on


func dbg_set_icon_last(app: String, ms: int) -> void:
	desk._icon_last_app = app
	desk._icon_last_ms = ms


func dbg_set_investigator(d: Dictionary) -> void:
	desk._investigator = d.duplicate(true)


func dbg_set_inv_path(path: String) -> void:
	desk._inv_path = path


func dbg_set_drag_key(key: String) -> void:
	desk._drag_key = key


func dbg_set_tutorial_step(step: int) -> void:
	desk._tutorial_step = step


func dbg_set_pending_detail(on: bool) -> void:
	desk._pending_detail = on


func dbg_set_ending_id(id: String) -> void:
	desk._last_ending_id = id


func dbg_clear_narr() -> void:
	if desk._narr != null and is_instance_valid(desk._narr):
		desk._narr.queue_free()
	desk._narr = null


# ── 动作接缝：控制器的私有入口 ──────────────────────────────────────────

func dbg_refresh_crumbs() -> void:
	desk.chrome._refresh_crumbs()


func dbg_open_debug_panel() -> void:
	desk.chrome._open_debug_panel()


func dbg_close_debug_panel() -> void:
	desk.chrome._close_debug_panel()


func dbg_close_top_window() -> bool:
	return desk.windows._close_top_window()


func dbg_place_floating_windows() -> void:
	desk.windows._place_floating_windows()


func dbg_raise_to_front(w: Control, refresh := true) -> void:
	desk.windows._raise_to_front(w, refresh)


func dbg_raise_window_at(p: Vector2) -> bool:
	return desk.windows._raise_window_at(p)


func dbg_card_selected(key: String) -> void:
	desk.card_ui._on_card_selected(key)


## 直接走 UI 组合（参数是节点 key；id 版本见 `dbg_combo_ui`）。
func dbg_card_combo(tool_key: String, target_key: String) -> void:
	desk.card_ui._on_card_combo(tool_key, target_key)


func dbg_card_pin_toggled(key: String) -> void:
	desk.card_ui._on_card_pin_toggled(key)


func dbg_ensure_detail() -> DetailWin:
	return desk.card_ui._ensure_detail()


func dbg_refresh_detail(force := false) -> void:
	desk.card_ui._refresh_detail(force)


func dbg_show_narr(sid: String) -> void:
	desk.card_ui._show_narr(sid)


func dbg_toggle_container(kind: String, id: String) -> void:
	desk.card_ui._toggle_container(kind, id)


func dbg_apply_hidden() -> void:
	desk.card_ui._apply_hidden()


func dbg_apply_drop(id: String, key: String) -> void:
	desk.drag._apply_drop(id, key)


func dbg_clear_drop_over() -> void:
	desk.drag._clear_drop_over()


func dbg_drop_card_mirror(card: NodeCard) -> void:
	desk.drag._drop_card_mirror(card)


func dbg_drop_target_at(p: Vector2) -> Dictionary:
	return desk.drag._drop_target_at(p)


func dbg_drop_targets() -> Array:
	return desk.drag._drop_targets()


func dbg_handle_card_drop(key: String, p: Vector2) -> bool:
	return desk.drag._handle_card_drop(key, p)


func dbg_card_drag_released(key: String, p: Vector2) -> void:
	desk.drag._on_card_drag_released(key, p)


func dbg_card_dragged(key: String) -> void:
	desk.drag._on_card_dragged(key)


func dbg_sdrag_ghost_position(p: Vector2) -> Vector2:
	return desk.drag._sdrag_ghost_position(p)


func dbg_store_into(where: String, key: String) -> void:
	desk.drag._store_into(where, key)


func dbg_update_drop_over(p: Vector2) -> void:
	desk.drag._update_drop_over(p)


func dbg_icon_by_app(app: String) -> Button:
	return desk.launcher._icon_by_app(app)


func dbg_icon_layer() -> Control:
	return desk.launcher._icon_layer()


func dbg_open_icon_app(app: String) -> void:
	desk.launcher._open_icon_app(app)


func dbg_sync_icon_bounds() -> void:
	desk.launcher._sync_icon_bounds()


func dbg_open_memory_play(mem: MemoryDef, where_key: String) -> void:
	desk.narrative._open_memory_play(mem, where_key)


func dbg_place_case_dock() -> void:
	desk.session._place_case_dock()


func dbg_sync_case_progress() -> void:
	desk.session._sync_case_progress_from_graph()


func dbg_toggle_case_map() -> void:
	desk.session._toggle_case_map()


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


