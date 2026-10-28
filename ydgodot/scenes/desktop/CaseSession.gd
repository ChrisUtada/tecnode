class_name CaseSession
extends Node
## 由 Desktop 挂载的子系统控制器。
## 过渡期直接通过注入的 `desk` 访问宿主成员；搬出的函数名保持不变。

var desk: Desktop


func _place_case_dock() -> void:
	if desk._dock_card == null or not is_instance_valid(desk._dock_card):
		return
	var desk_w := desk._desk.size.x if desk._desk != null and is_instance_valid(desk._desk) else desk._vw()
	var desk_h := desk._desk.size.y if desk._desk != null and is_instance_valid(desk._desk) else desk._vh() - Desktop.HEADER_H
	if desk._dock_user_placed:
		desk._dock_card.position = _clamp_dock_pos(desk._dock_card.position, desk_w, desk_h)
		return
	desk._dock_card.position = Vector2(
		maxf(14.0, desk_w - 16.0 - desk._dock_card.size.x),
		maxf(14.0, desk_h - 16.0 - desk._dock_card.size.y))


func _clamp_dock_pos(p: Vector2, desk_w: float, desk_h: float) -> Vector2:
	return Vector2(
		clampf(p.x, 0.0, maxf(0.0, desk_w - desk._dock_card.size.x)),
		clampf(p.y, 0.0, maxf(0.0, desk_h - desk._dock_card.size.y)))


func _on_case_dock_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			desk._dock_down = true
			desk._dock_dragged = false
			desk._dock_press_global = event.global_position
			desk._dock_grab = desk._dock_card.position
			desk._dock_card.accept_event()
		elif desk._dock_down:
			var was_dragged := desk._dock_dragged
			desk._dock_down = false
			desk._dock_dragged = false
			if not was_dragged:
				_reopen_case()
			desk._dock_card.accept_event()
		return
	if event is InputEventMouseMotion and desk._dock_down:
		var at := (event as InputEventMouseMotion).global_position
		var d := at - desk._dock_press_global
		if not desk._dock_dragged and absf(d.x) + absf(d.y) < 5.0:
			return
		if not desk._dock_dragged:
			desk._dock_dragged = true
			desk._dock_card.move_to_front()
		var desk_w := desk._desk.size.x if desk._desk != null and is_instance_valid(desk._desk) else desk._vw()
		var desk_h := desk._desk.size.y if desk._desk != null and is_instance_valid(desk._desk) else desk._vh() - Desktop.HEADER_H
		desk._dock_card.position = _clamp_dock_pos(desk._dock_grab + d, desk_w, desk_h)
		desk._dock_user_placed = true
		desk._place_toast_anchor()
		desk._dock_card.accept_event()


func _build_case_park() -> void:
	## U7：案件卡片改成自管手势的 PanelContainer；按下可拖，松手未拖才展开案件。
	desk._dock_card = PanelContainer.new()
	desk._dock_card.name = "case_dock"
	desk._dock_card.size = Vector2(170, 56)
	desk._dock_card.custom_minimum_size = Vector2(170, 56)
	desk._dock_card.position = Vector2(1094, 678)
	desk._dock_card.mouse_filter = Control.MOUSE_FILTER_STOP
	desk._dock_card.tooltip_text = "案件已收起 · 拖动可挪位置 · 单击展开"
	desk._normal_style = TecTheme.flat(TecTheme.CARD, TecTheme.R_WIN, TecTheme.INK, 1)
	desk._hover_style = TecTheme.flat(TecTheme.CARD, TecTheme.R_WIN, TecTheme.INK, 2)
	## PanelContainer 会把子节点排进 style 的内容区；边框内留 10/8px，图标才不会贴边。
	for sb in [desk._normal_style, desk._hover_style]:
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
	desk._dock_card.add_theme_stylebox_override("panel", desk._normal_style)
	desk._dock_card.mouse_entered.connect(func():
		desk._dock_card.add_theme_stylebox_override("panel", desk._hover_style))
	desk._dock_card.mouse_exited.connect(func():
		desk._dock_card.add_theme_stylebox_override("panel", desk._normal_style))
	desk._dock_card.gui_input.connect(_on_case_dock_input)
	desk._dock_card.visible = false
	desk._desk.add_child(desk._dock_card)
	desk.windows._place_z(desk._dock_card, Desktop.ZR_DOCK)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	## 内边距由 PanelContainer 的 StyleBox content_margin 负责；这里填满内容区即可。
	row.offset_left = 0
	row.offset_top = 0
	row.offset_right = 0
	row.offset_bottom = 0
	row.add_theme_constant_override("separation", 9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desk._dock_card.add_child(row)

	## 案卷标记和节点类型符号同语法：一个汉字 + 一圈外框，不再用「▣」这个看不出含义的小方块。
	var glyph_box := PanelContainer.new()
	glyph_box.name = "case_glyph_box"
	glyph_box.custom_minimum_size = Vector2(32, 32)
	glyph_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph_box.add_theme_stylebox_override("panel",
		TecTheme.flat(TecTheme.CARD, TecTheme.R_BTN, TecTheme.INK, 1))
	row.add_child(glyph_box)
	var glyph_center := CenterContainer.new()
	glyph_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph_box.add_child(glyph_center)
	var glyph := TecTheme.label("案", TecTheme.FS_BODY, TecTheme.TEXT)
	glyph.name = "case_glyph"
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph_center.add_child(glyph)

	var meta := VBoxContainer.new()
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.alignment = BoxContainer.ALIGNMENT_CENTER
	meta.add_theme_constant_override("separation", 1)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(meta)

	desk._dock_code = TecTheme.label("", TecTheme.FS_BODY, TecTheme.MUTED)
	desk._dock_code.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(desk._dock_code)
	desk._dock_title = TecTheme.label("", TecTheme.FS_BODY, TecTheme.TEXT)
	desk._dock_title.clip_text = true
	desk._dock_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desk._dock_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(desk._dock_title)
	desk._dock_sub = TecTheme.label("进度已保存 · 点此展开", TecTheme.FS_BODY, TecTheme.MUTED)
	desk._dock_sub.clip_text = true
	desk._dock_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desk._dock_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(desk._dock_sub)


func _case_id() -> String:
	return desk.case_def.case_def.id if desk.case_def != null and desk.case_def.case_def != null else ""


func _case_label() -> String:
	return "案件 " + CaseCatalog.code_of(desk._active_case).trim_prefix("CASE ")


func _case_title() -> String:
	if desk.case_def != null and desk.case_def.case_def != null and desk.case_def.case_def.title != "":
		return desk.case_def.case_def.title
	return CaseCatalog.title_of(desk._active_case)


func _case_window_title() -> String:
	return "案件 " + CaseCatalog.code_of(desk._active_case).trim_prefix("CASE ") + " · " + _case_title()


func _update_case_chrome() -> void:
	if desk._case_win != null:
		desk._case_win.set_title(_case_window_title())
	desk.chrome._refresh_crumbs()


func _require_case() -> bool:
	if desk._case_open:
		return true
	desk._show_toast("当前不在案件中，请先展开案件图标或右下角案件卡片", true)
	return false


func _toggle_case_map() -> void:
	if desk._map_win != null and is_instance_valid(desk._map_win):
		desk._map_win.queue_free()
		desk._map_win = null
		desk.windows._place_floating_windows()
		return
	var w := CaseMapWin.new()
	w.name = "case_map"
	## 教学第 6 幕：还没有「当前案件」，A-001 必须保持可点击。
	var cur := "" if desk._tutorial_active else desk._active_case
	var opened := false if desk._tutorial_active else desk._case_open
	w.setup_map(desk._catalog, cur, opened,
		CaseCatalog.DEFAULT_ID if desk._tutorial_active else "")
	w.position = Vector2(420, 72)
	w.enter_requested.connect(_on_case_map_enter)
	w.closed.connect(func():
		desk._map_win = null
		desk.windows._place_floating_windows())
	desk._desk.add_child(w)
	desk.windows._place_z(w, Desktop.ZR_WIN)
	desk._map_win = w
	desk.windows._place_floating_windows()


func _on_case_map_enter(id: String) -> void:
	if desk._map_win != null and is_instance_valid(desk._map_win):
		desk._map_win.queue_free()
		desk._map_win = null
	if desk._tutorial_active:
		desk.tutorial._finish_tutorial_to_case(id)
		return
	_enter_case(id)


func _enter_case(id: String) -> bool:
	if not CaseCatalog.exists(id):
		desk._show_toast("没有这个案件地址", true)
		return false
	if not desk._catalog.is_unlocked(id):
		desk._show_toast("该案件地址尚未解锁", true)
		return false
	if id == desk._active_case:
		if not desk._case_open:
			_reopen_case()
		return true
	if not CaseCatalog.data_ready(id):
		desk._show_toast("案件 " + CaseCatalog.code_of(id) + " 的数据尚未装载", true)
		return false
	_autosave()
	var loader := CaseLoader.new(CaseCatalog.path_of(id))
	if not loader.load_case():
		desk._show_toast("案件装载失败：" + loader.load_error, true)
		return false
	desk._active_case = id
	desk.case_def = loader
	desk._catalog.last = id
	if not desk._progress_read_only:
		desk._catalog.save_progress()
	desk._case_open = true
	desk._case_held = false
	desk._case_docked = false
	desk._case_win.visible = true
	if _resume_allowed() and _resume_from_save():
		desk._show_toast("已加载上次进度")
	else:
		_start_slice()
	_update_case_chrome()
	_update_case_park_ui()
	desk._log("已进入案件 %s // %s" % [CaseCatalog.code_of(id), CaseCatalog.title_of(id)], "sys")
	return true


## 解锁提示里要写的「下一案编号」（A001 → CASE A-002）
func _next_case_code(from_id: String) -> String:
	var list: Array = CaseCatalog.all()
	for i in list.size():
		if String((list[i] as Dictionary)["id"]) != from_id:
			continue
		if i + 1 < list.size():
			return String((list[i + 1] as Dictionary).get("code", ""))
		break
	return ""


func _park_case(where: String) -> bool:
	if not desk._case_open:
		return false
	_autosave()
	_close_case_transients()
	desk._case_open = false
	desk._case_win.visible = false
	desk._case_held = where != "dock"
	desk._case_docked = where == "dock"
	_update_case_park_ui()
	return true


func _reopen_case() -> void:
	if desk._case_win == null:
		return
	desk._case_open = true
	desk._case_held = false
	desk._case_docked = false
	desk._case_win.visible = true
	desk._case_win.clamp_into_parent()
	desk.windows._place_z(desk._case_win, Desktop.ZR_CASE)
	if desk._tec != null and desk._tec.visible:
		desk.windows._place_z(desk._tec, Desktop.ZR_TEC)
	_update_case_park_ui()


func _close_case_transients() -> void:
	desk.card_ui._close_card_context()
	if desk._pw_pop != null and is_instance_valid(desk._pw_pop):
		desk._pw_pop.queue_free()
	desk._pw_pop = null
	desk._pw_ctx = {}
	if desk._narr != null and is_instance_valid(desk._narr):
		desk._narr.queue_free()
	desk._narr = null
	desk.narrative._close_mem_card()
	desk.narrative._close_chat()
	desk.people._close_person_card()
	if desk._archive_win != null and is_instance_valid(desk._archive_win):
		desk._archive_win.queue_free()
	desk._archive_win = null
	desk.tec._hide_tec()
	desk._selected = ""
	if desk.graph != null:
		desk.graph.selected = ""
	## S11：案件收起后详情窗也收起，避免留下上一案的陈旧内容。
	if desk._detail_win != null and is_instance_valid(desk._detail_win):
		desk._detail_win.hide()


func _update_case_park_ui() -> void:
	if desk._dock_card != null:
		desk._dock_code.text = CaseCatalog.code_of(desk._active_case)
		desk._dock_title.text = _case_title()
		desk._dock_sub.text = "进度已保存 · 点此展开"
		desk._dock_card.visible = desk._case_docked
		if desk._case_docked:
			_place_case_dock()
			desk.windows._place_z(desk._dock_card, Desktop.ZR_DOCK)
	if desk._map_badge != null:
		desk._map_badge.visible = desk._case_held
		desk.launcher._set_badge(desk._map_badge, "进行中" if desk._case_held else "")
	if desk._map_win != null and is_instance_valid(desk._map_win):
		desk._map_win.set_case_state(desk._active_case, desk._case_open)
	## S11：案件收起后，仍开着的收纳窗 / 花园不能继续写进度。
	if desk._bag_win != null and is_instance_valid(desk._bag_win):
		desk._bag_win.set_writes_enabled(desk._case_open)
	if desk._ledger_win != null and is_instance_valid(desk._ledger_win):
		desk._ledger_win.set_writes_enabled(desk._case_open)
	if desk._garden_win != null and is_instance_valid(desk._garden_win):
		desk._garden_win.set_writes_enabled(desk._case_open)


func _resume_allowed() -> bool:
	if not desk._save_enabled or desk._has_arg("--fresh"):
		return false
	return DisplayServer.get_name() != "headless"


## 重建一套运行时对象（图 / 命令系统 / 存档），并清掉旧卡片与会话窗
func _new_runtime() -> void:
	for c in desk._card_layer.get_children():
		if c is NodeCard:
			desk._card_layer.remove_child(c)
			c.queue_free()
	desk._cards.clear()
	desk.canvas._fresh_spawns.clear()
	desk.canvas._layout_sig = ""            # 换案子 / 重开一局：卡片表清空，下次 `_relayout()` 必须真跑一次
	desk.graph = GraphState.new(desk.case_def)
	desk.combos = ComboSystem.new(desk.case_def, desk.graph)
	desk._cmds = CommandSystem.new(desk.case_def, desk.graph)
	desk._save = SaveSystem.new(desk.graph, _case_id())
	desk.dialogues = DialogueSystem.new(desk.case_def, desk.graph)
	desk.canvas._layout_job = null
	desk.card_ui._close_card_context()
	desk._selected = ""
	desk.graph.selected = ""
	desk._last_ending_id = ""
	desk._storage_before = {}
	if desk._ending != null:
		desk._ending.visible = false
	desk.tec._hide_tec(true)
	if desk._pw_pop != null and is_instance_valid(desk._pw_pop):
		desk._pw_pop.queue_free()
	desk._pw_pop = null
	desk._pw_ctx = {}
	desk._pw_wrong.clear()
	if desk._narr != null and is_instance_valid(desk._narr):
		desk._narr.queue_free()
	desk._narr = null
	desk.narrative._close_mem_card()
	desk.narrative._close_chat()
	if desk._archive_win != null and is_instance_valid(desk._archive_win):
		desk._archive_win.queue_free()
	desk._archive_win = null
	desk.narrative._clear_archive_new()
	if desk._matrix_win != null and is_instance_valid(desk._matrix_win):
		desk.matrix._restore_matrix_occlusion()
		desk._matrix_win.queue_free()
	desk._matrix_win = null
	if desk._bag_win != null and is_instance_valid(desk._bag_win):
		desk._bag_win.queue_free()
	desk._bag_win = null
	if desk._ledger_win != null and is_instance_valid(desk._ledger_win):
		desk._ledger_win.queue_free()
	desk._ledger_win = null
	if desk._map_win != null and is_instance_valid(desk._map_win):
		desk._map_win.queue_free()
	desk._map_win = null
	if desk._music_win != null and is_instance_valid(desk._music_win):
		desk._music_win.queue_free()
	desk._music_win = null
	if desk._music_dock != null and is_instance_valid(desk._music_dock):
		desk._music_dock.queue_free()
	desk._music_dock = null
	## U7：换案 / 重置恢复默认贴边位（同一局内的玩家摆位仍保留）。
	desk._dock_user_placed = false
	if desk._tec_chip != null and is_instance_valid(desk._tec_chip):
		desk._tec_chip.reset_place()
	if desk._garden_win != null and is_instance_valid(desk._garden_win):
		desk._garden_win.queue_free()
	desk._garden_win = null
	desk.people._close_person_card()
	if desk._people_win != null and is_instance_valid(desk._people_win):
		desk._people_win.queue_free()
	desk._people_win = null
	if desk._log_win != null and is_instance_valid(desk._log_win):
		desk._log_win.queue_free()
	desk._log_win = null
	## 换案 / 教学 ↔ 正式案件会换整个 graph。详情窗持有旧 graph 引用，
	## 不销毁的话下一次选中新节点会查到空节点并 hide()，看起来就是「节点详情消失」。
	if desk._detail_win != null and is_instance_valid(desk._detail_win):
		desk._detail_win.queue_free()
		desk._detail_win = null
	# 日志是「本次调查的案卷」：重来 / 换案才清（Web 17-boot.js:20），撤销不回滚
	desk._log_unread = 0
	desk.launcher._set_badge(desk._log_badge, "")
	desk.launcher._refresh_app_icons()
	desk.chrome._refresh_crumbs()
	_refresh_undo_btn()


## 不可逆操作：默认先弹确认；测试 / 调试可传 force=true 直接重置。
func _reset_case(force := false) -> void:
	if not _require_case():
		return
	if force:
		_reset_case_now()
		return
	if desk._confirm_win != null and is_instance_valid(desk._confirm_win):
		return
	var w := Desktop.ConfirmWinScript.new()
	w.name = "confirm_reset"
	w.setup("重置本案？", "当前案件的进度、节点和日志都会被清除，且无法撤销。", "重置", "取消")
	w.confirmed.connect(_reset_case_now)
	w.cancelled.connect(func(): desk._confirm_win = null)
	w.tree_exited.connect(func(): desk._confirm_win = null)
	w.z_index = 90
	add_child(w)
	desk._confirm_win = w


func _reset_case_now() -> void:
	if desk._confirm_win != null and is_instance_valid(desk._confirm_win):
		desk._confirm_win.queue_free()
		desk._confirm_win = null
	if desk._save != null:
		desk._save.clear_save()
	_start_slice()
	desk._log("已重置为初始状态", "sys")
	desk._show_toast("已重置为初始状态")


func _resume_from_save() -> bool:
	_new_runtime()
	if not desk._save.load_from_disk():
		desk._save.clear_history()
		return false
	desk.canvas._rebuild_from_graph(true)
	_sync_case_progress_from_graph()
	return true


func _sync_case_progress_from_graph() -> void:
	if desk.graph == null or desk.case_def == null or desk._progress_read_only:
		return
	for e in desk.case_def.endings:
		if e == null or not e.is_true_capture or not desk.graph.endings.has(e.id):
			continue
		desk._catalog.mark_completed(desk._active_case)
		var newly := desk._catalog.unlock_next(desk._active_case)
		_update_case_park_ui()
		if newly:
			desk._log("新案件地址已解锁：%s" % _next_case_code(desk._active_case), "cap")
		return


func _start_slice() -> void:
	## 重置 / 换案后镜头必须回到自动档，否则玩家之前拖过的镜头会对着空画布。
	desk.canvas._reset_camera()
	_new_runtime()

	# 开局状态**照 Web `17-boot.js:42` 一模一样的口径**：画布上只放一张「未探索」的起始场景节点，
	# 位置也用 Web 的 (1000, 620)。手电筒不在这里给 —— 它在「花园 → 书桌 → 抽屉 → 左侧抽屉」
	# 这条真实链路的末端（旧版图省事直接摆一把在桌上，等于跳掉了整个开场探索）。
	var sid := Desktop.SLICE_SCENE
	var loc := desk.graph.add_node("loc", sid)
	loc["x"] = 1000.0
	loc["y"] = 620.0
	desk.graph.mark_fresh(String(loc["key"]))
	desk.canvas._spawn_card(loc["key"])

	_set_crumb(_case_label() + " // " + desk.case_def.scene_title(sid))
	desk._log("已载入%s：双击「场景节点」展开里面的东西，把节点拖到另一个节点上组合使用。" % _case_label())
	desk._log("提示：先双击「%s」展开场景，再双击「书桌」等继续展开，拖动手电筒到黑影上试试。"
		% desk.case_def.scene_title(sid))
	desk.canvas._relayout()


## 面包屑不再显示「案件 + 场景名」——那是**案件窗标题栏**的职责（Web 也是这样分工）。
## 仍保留这个函数名，是因为各处收尾（展开 / 换时刻 / 重置）都调它；现在统一刷计数。
func _set_crumb(_text: String) -> void:
	desk.chrome._refresh_crumbs()


func _intro_allowed() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return not desk._shot_mode() and not desk._has_arg("--no-intro")


## 第 0 幕：正常启动（非无头 / 非截图 / 未显式 --no-start）先停在开始界面。
func _start_screen_allowed() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return not desk._shot_mode() and not desk._has_arg("--no-start")


func _open_start_screen() -> void:
	if desk._start_screen != null and is_instance_valid(desk._start_screen):
		return
	var has_save := desk._save_enabled and desk._catalog != null and desk._catalog.has_save(desk._active_case)
	desk._start_screen = Desktop.StartScreenScript.new()
	desk._start_screen.name = "start_screen"
	desk._start_screen.z_index = 100
	desk._start_screen.setup(has_save)
	desk._start_screen.start_requested.connect(_on_start_new)
	desk._start_screen.continue_requested.connect(_on_start_continue)
	desk._start_screen.quit_requested.connect(func(): get_tree().quit())
	add_child(desk._start_screen)


func _close_start_screen() -> void:
	if desk._start_screen != null and is_instance_valid(desk._start_screen):
		desk._start_screen.queue_free()
	desk._start_screen = null


func _boot_session() -> void:
	var resumed := _resume_allowed() and _resume_from_save()
	if resumed:
		desk._show_toast("已继续上次进度")
	else:
		_start_slice()
	if not resumed and _intro_allowed() and desk._investigator.is_empty():
		desk.tutorial._begin_tutorial()


func _on_start_new(overwrite: bool) -> void:
	_close_start_screen()
	if overwrite:
		_clear_case_save()
	desk.tutorial._begin_tutorial()


func _on_start_continue() -> void:
	if _resume_allowed() and _resume_from_save():
		_close_start_screen()
		desk._show_toast("已继续上次进度")
		return
	## 读档失败：留在开始界面报错，不动调查员证；清证只由「开始新调查」的确认路径负责。
	if desk._start_screen != null and is_instance_valid(desk._start_screen):
		desk._start_screen.show_notice("读档失败",
			"存档无法读取。你的调查员证不会被清除；请重试，或从「开始」进入新调查。")
		return
	_start_slice()
	desk._show_toast("存档不可用，已回到桌面", true)


func _clear_case_save() -> void:
	if desk._save != null:
		desk._save.clear_save()
	var path := SaveSystem.save_path_for(_case_id())
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _refresh_chip() -> void:
	if desk._people_win != null and is_instance_valid(desk._people_win):
		desk._people_win.set_investigator(desk._investigator)
	if desk._inv_chip == null:
		return
	if desk._investigator.is_empty():
		desk._inv_chip.visible = false
		desk._inv_chip.text = ""
		desk._inv_chip.tooltip_text = ""
		return
	desk._inv_chip.text = "▣ %s · %s" % [String(desk._investigator.get("name", "")), String(desk._investigator.get("id", ""))]
	desk._inv_chip.tooltip_text = desk._inv_chip.text
	desk._inv_chip.visible = true


func _avatar_pool() -> Array:
	var out: Array = Investigator.AVATAR_INITIAL.duplicate()
	for key in desk.graph.nodes.keys():
		if not String(key).begins_with("char:"):
			continue
		var id := String(key).substr(5)
		if id != "CHARS_TEC" and not out.has(id):
			out.append(id)
	return out


func _avatar_names() -> Dictionary:
	var out := {"CHARS_EXEC": "执行者", "CHARS_TEC": "TEC"}
	if desk.case_def == null:
		return out
	for id in _avatar_pool():
		var ch := desk.case_def.char_of(String(id))
		if ch != null and ch.name != "":
			out[String(id)] = ch.name
	return out


func _locked_avatar_count() -> int:
	if desk.case_def == null:
		return 0
	var pool := _avatar_pool()
	var n := 0
	for id in desk.case_def.chars.keys():
		if not pool.has(String(id)):
			n += 1
	return n


func _open_intro() -> IntroWin:
	if desk._intro != null and is_instance_valid(desk._intro):
		return desk._intro
	var w := IntroWin.new()
	w.name = "intro"
	w.store_path = desk._inv_path
	w.setup(_avatar_pool(), _avatar_names(), _locked_avatar_count())
	w.finished.connect(_on_intro_finished)
	w.tree_exited.connect(_on_intro_closed)
	add_child(w)
	desk._intro = w
	return w


func _on_intro_closed() -> void:
	desk._intro = null


func _on_intro_finished(card: Dictionary) -> void:
	desk._investigator = card.duplicate(true)
	_refresh_chip()
	desk._show_toast("调查员 %s 已接入 T.E.C-OS" % String(desk._investigator.get("name", "")))
	desk._log("调查员 %s（%s）已接入 T.E.C-OS" % [String(desk._investigator.get("name", "")),
		String(desk._investigator.get("id", ""))], "sys")


func _open_cert_review() -> void:
	if desk._investigator.is_empty():
		return
	## 复核窗比较高，底部按钮不要被「已进入案件」toast 压住。
	desk._hide_toast()
	if desk._cert_win != null and is_instance_valid(desk._cert_win):
		desk._cert_win.queue_free()
		desk._cert_win = null
	var w := SysWindow.new()
	w.name = "cert_win"
	w.setup("调查员证", 340, 470)
	w.position = Vector2(
		clampf((desk._vw() - w.size.x) * 0.5, 8.0, maxf(8.0, desk._vw() - w.size.x - 8.0)),
		8.0)
	desk._desk.add_child(w)
	desk.windows._place_z(w, Desktop.ZR_WIN)
	w.content.add_child(IntroWin.build_cert(desk._investigator))
	var change := TecTheme.button("[ 更换头像 ]")
	change.name = "cert_change_photo"
	change.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	change.pressed.connect(_open_photo_picker)
	w.content.add_child(change)
	w.tree_exited.connect(func(): desk._cert_win = null)
	desk._cert_win = w


func _open_photo_picker() -> void:
	if desk._investigator.is_empty():
		return
	if desk._photo_win != null and is_instance_valid(desk._photo_win):
		desk._photo_win.queue_free()
		desk._photo_win = null
	var w := Desktop.PhotoWinScript.new()
	w.name = "photo_win"
	w.setup_photo(String(desk._investigator.get("avatarId", "CHARS_EXEC")))
	w.picked.connect(_on_photo_picked)
	w.closed.connect(func(): desk._photo_win = null)
	desk._desk.add_child(w)
	desk.windows._place_z(w, Desktop.ZR_CERT)
	w.place_center(desk._vw(), desk._desk.size.y)
	desk._photo_win = w


func _on_photo_picked(avatar_id: String) -> void:
	desk._investigator["avatarId"] = avatar_id
	if not Investigator.save_to(desk._investigator, desk._inv_path):
		push_warning("调查员证照片写入失败：" + desk._inv_path)
	desk._photo_win = null
	_refresh_chip()
	_open_cert_review()


func _autosave() -> void:
	desk._autosave_pending = false
	if desk._save == null or not desk._save_enabled:
		return
	if not desk._save.flush_pending():
		push_warning("自动存档失败：" + desk._save.last_error)


func _queue_autosave() -> void:
	if desk._save == null or not desk._save_enabled:
		return
	desk._autosave_pending = true
	desk._autosave_due_msec = Time.get_ticks_msec() + Desktop.AUTOSAVE_DELAY_MSEC


## 动作开始前拍一张；动作结束后状态真的变了才入撤销栈并写盘
func _commit(before: Dictionary) -> void:
	if before.is_empty() or desk._save == null:
		return
	## F4：只序列化当前快照一次。`last_json` 是上一次入账后的基准；
	## 没变化就不压栈，也不再像旧版那样把 before/current 各 stringify 一遍。
	var current_json := desk._save.snapshot_json()
	if current_json == desk._save.last_json:
		return
	desk._save.last_json = current_json
	desk._save.pending_json = current_json
	desk._save.push_history_snapshot(before)
	desk.canvas._sync_canvas()
	_queue_autosave()
	desk.launcher._refresh_app_icons()
	desk.card_ui._refresh_detail()
	desk.chrome._refresh_crumbs()
	desk.people._refresh_people_win()
	desk.people._refresh_person_card_fields()
	desk._refresh_log_win()


## K8：撤销按钮必须反映空栈；所有会改变历史的路径在提交后统一刷这里。
func _refresh_undo_btn() -> void:
	if desk._undo_btn == null or not is_instance_valid(desk._undo_btn):
		return
	var can := desk._save != null and desk._save.can_undo()
	desk._undo_btn.disabled = not can
	desk._undo_btn.tooltip_text = "撤销上一步" if can else "没有可撤销的操作"


func _undo() -> bool:
	if not _require_case():
		return false
	if desk._save == null or not desk._save.can_undo():
		desk._log("没有可撤销的操作", "warn")
		desk._show_toast("没有可撤销的操作", true)
		_refresh_undo_btn()
		return false
	if not desk._save.undo():
		desk._show_toast("撤销失败：" + desk._save.last_error, true)
		return false
	desk.canvas._rebuild_from_graph()
	_autosave()
	desk._show_toast("已撤销上一步")
	_refresh_undo_btn()
	return true
