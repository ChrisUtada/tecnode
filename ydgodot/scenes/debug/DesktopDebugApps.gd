extends "res://scenes/debug/DesktopDebugWindows.gd"
## 图标 / 推演 / 结局 / 音乐 / 花园 / 案件 / 证件动作。

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
