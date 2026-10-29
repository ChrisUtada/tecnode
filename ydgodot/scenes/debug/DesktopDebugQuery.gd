extends "res://scenes/debug/DesktopDebugBase.gd"
## 查询与视图接缝：桌面状态、相机、卡片、窗口句柄、toast。
## 有生命周期的窗口统一 is_instance_valid 守卫，已释放返回 null。

# ── 查询接缝：外壳 / 相机 / 卡片 ────────────────────────────────────────
## 测试不再直接读 Desktop 的私有字段；只读查询统一走这里。
## 有生命周期的窗口用 `is_instance_valid` 守卫，已释放时返回 null。

func dbg_desk() -> Control:
	return desk._desk


func dbg_stage() -> Control:
	return desk._stage


func dbg_card_layer() -> Control:
	return desk._card_layer


func dbg_edge_layer() -> EdgeLayer:
	return desk._edge_layer


func dbg_drag_line() -> EdgeLayer:
	return desk._drag_line


func dbg_cards() -> Dictionary:
	return desk._cards


func dbg_card(key: String) -> NodeCard:
	return desk._cards.get(key, null) as NodeCard


func dbg_selected() -> String:
	return desk._selected


func dbg_drag_key() -> String:
	return desk._drag_key


func dbg_inv_path() -> String:
	return desk._inv_path


func dbg_active_case() -> String:
	return desk._active_case


func dbg_vw() -> float:
	return desk._vw()


func dbg_vh() -> float:
	return desk._vh()


func dbg_view_k() -> float:
	return desk._view_k


func dbg_view_pos() -> Vector2:
	return desk._view_pos


func dbg_view_user() -> bool:
	return desk._view_user


func dbg_set_view_k(k: float) -> void:
	desk._view_k = k


func dbg_set_view_pos(p: Vector2) -> void:
	desk._view_pos = p


func dbg_set_view_user(on: bool) -> void:
	desk._view_user = on


func dbg_apply_view() -> void:
	desk.canvas._apply_view()


func dbg_clamp_view_pos(p: Vector2) -> Vector2:
	return desk.canvas._clamp_view_pos(p)


func dbg_fit_cards(keep_titles := true) -> void:
	desk.canvas._fit_cards(keep_titles)


func dbg_center_on(card: NodeCard) -> void:
	desk.canvas._center_on(card)


func dbg_relayout(animated := false, force := false) -> void:
	desk.canvas._relayout(animated, force)


func dbg_repaint_edges() -> void:
	desk.canvas._repaint_edges()


func dbg_clear_selection() -> void:
	desk.canvas._clear_selection()


func dbg_card_key_at(p: Vector2) -> String:
	return desk.canvas._card_key_at(p)


func dbg_floating_window_at(p: Vector2) -> SysWindow:
	return desk.canvas._floating_window_at(p)


func dbg_stage_input(event: InputEvent) -> void:
	desk.canvas._on_stage_input(event)


func dbg_refresh_or_spawn_card(key: String) -> void:
	desk.canvas._refresh_or_spawn_card(key)


func dbg_move_twens() -> Dictionary:
	return desk.canvas._move_twens.duplicate()


func dbg_follow_frames() -> int:
	return desk.canvas._follow_frames


func dbg_fit_view() -> void:
	desk._fit_view()


func dbg_show_toast(text: String, warn := false) -> void:
	desk._show_toast(text, warn)


func dbg_hide_toast() -> void:
	desk._hide_toast()


func dbg_toggle_log() -> void:
	desk._toggle_log()


func dbg_has_true_name_clue(keys: Array) -> bool:
	return desk._has_true_name_clue(keys)


func dbg_unhandled_input(event: InputEvent) -> void:
	desk._unhandled_input(event)


# ── 查询接缝：窗口 / 页眉 / 提示条 ──────────────────────────────────────

func dbg_case_win() -> SysWindow:
	return desk._case_win if desk._case_win != null and is_instance_valid(desk._case_win) else null


func dbg_bag_win() -> StorageWin:
	return desk._bag_win if desk._bag_win != null and is_instance_valid(desk._bag_win) else null


func dbg_ledger_win() -> StorageWin:
	return desk._ledger_win if desk._ledger_win != null and is_instance_valid(desk._ledger_win) else null


func dbg_detail_win() -> DetailWin:
	return desk._detail_win if desk._detail_win != null and is_instance_valid(desk._detail_win) else null


func dbg_map_win() -> CaseMapWin:
	return desk._map_win if desk._map_win != null and is_instance_valid(desk._map_win) else null


func dbg_narr() -> NarrCard:
	return desk._narr if desk._narr != null and is_instance_valid(desk._narr) else null


func dbg_start_screen() -> Control:
	return desk._start_screen if desk._start_screen != null and is_instance_valid(desk._start_screen) else null


func dbg_confirm_win() -> Control:
	return desk._confirm_win if desk._confirm_win != null and is_instance_valid(desk._confirm_win) else null


func dbg_photo_win() -> SysWindow:
	return desk._photo_win if desk._photo_win != null and is_instance_valid(desk._photo_win) else null


func dbg_cert_win() -> SysWindow:
	return desk._cert_win if desk._cert_win != null and is_instance_valid(desk._cert_win) else null


func dbg_tutorial_cert_win() -> SysWindow:
	return desk._tutorial_cert_win if desk._tutorial_cert_win != null and is_instance_valid(desk._tutorial_cert_win) else null


func dbg_inv_chip() -> Button:
	return desk._inv_chip if desk._inv_chip != null and is_instance_valid(desk._inv_chip) else null


func dbg_dock_card() -> PanelContainer:
	return desk._dock_card if desk._dock_card != null and is_instance_valid(desk._dock_card) else null


func dbg_dock_title() -> Label:
	return desk._dock_title if desk._dock_title != null and is_instance_valid(desk._dock_title) else null


func dbg_dock_sub() -> Label:
	return desk._dock_sub if desk._dock_sub != null and is_instance_valid(desk._dock_sub) else null


func dbg_goal() -> Label:
	return desk._goal


func dbg_toast() -> PanelContainer:
	return desk._toast


func dbg_toast_label() -> Label:
	return desk._toast_label


func dbg_toast_active() -> bool:
	return desk._toast_active


func dbg_toast_queue() -> Array:
	return desk._toast_queue


func dbg_drop_outline() -> DropOutline:
	return desk._drop_outline if desk._drop_outline != null and is_instance_valid(desk._drop_outline) else null


func dbg_card_mirror() -> NodeCard:
	return desk._card_mirror if desk._card_mirror != null and is_instance_valid(desk._card_mirror) else null


func dbg_card_ctx() -> PanelContainer:
	return desk._card_ctx if desk._card_ctx != null and is_instance_valid(desk._card_ctx) else null


func dbg_pending_detail() -> bool:
	return desk._pending_detail


func dbg_tutorial_step() -> int:
	return desk._tutorial_step


func dbg_tutorial_active() -> bool:
	return desk._tutorial_active


func dbg_save_enabled() -> bool:
	return desk._save_enabled


func dbg_save_system() -> SaveSystem:
	return desk._save


func dbg_last_ending_id() -> String:
	return desk._last_ending_id


