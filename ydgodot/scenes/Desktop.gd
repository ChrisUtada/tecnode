extends Control
## 桌面外壳 + 画布 + P0 垂直切片链路
##
## 切片（计划 §三 P0）：花园展开 → 手电筒拖到黑影 → 尸体场景 → TEC 分析计时 → 结局演出。
## 数据直读 `data/case-a001.json`（P0 允许），逻辑全在 core/ 里，本文件只管「搭界面 + 接线」。

const HEADER_H := 52.0
const SLICE_SCENE := "SCENES_garden"
const CARD_PAD := 8.0
const MEM_CARD_MIN_X := 132.0

var case_def: CaseLoader
var graph: GraphState
var combos: ComboSystem

var _desk: Control
var _stage: Control
var _card_layer: Control
var _crumb: Label
var _toast: PanelContainer
var _toast_label: Label
var _toast_timer: SceneTreeTimer
var _case_win: SysWindow
var _tec: TecWindow
var _tec_chip: TecChip
var _tec_btn: Button
var _tec_min := false
var _tec_dot := false
var _tec_before: Dictionary = {}
var _narr: NarrCard
var _ending: EndingOverlay
var _cards: Dictionary = {}          # key -> NodeCard
var _selected: String = ""
var _cmds: CommandSystem
var _pw_pop: PasswordPop = null
var _pw_ctx: Dictionary = {}
var _bag_win: StorageWin = null
var _ledger_win: StorageWin = null
var _matrix_win: MatrixWin = null
var _archive_win: ArchiveWin = null
var _mem_card: MemCard = null
var _chat_win: ChatWindow = null
var dialogues: DialogueSystem = null
var _archive_btn: Button = null
var _archive_badge: PanelContainer = null
var _archive_new := false
var _suppress_archive_new := false
var _last_ending_id := ""
var _flash_supply_note := false
var _save: SaveSystem = null
var _save_enabled := true
var _storage_before: Dictionary = {}
var _investigator: Dictionary = {}
var _inv_path := Investigator.PATH
var _intro: IntroWin = null
var _inv_chip: Button = null
var _cert_win: SysWindow = null
var _catalog: CaseCatalog = null
var _active_case := CaseCatalog.DEFAULT_ID
var _progress_path := CaseCatalog.PROGRESS_PATH
var _progress_read_only := false
var _case_open := true
var _case_held := false
var _case_docked := false
var _map_win: CaseMapWin = null
var _map_btn: Button = null
var _map_badge: PanelContainer = null
var _dock_card: Button = null
var _dock_code: Label = null
var _dock_title: Label = null
var _dock_sub: Label = null
var _music_btn: Button = null
var _music_win: MusicWin = null
var _music_dock: MusicDock = null
var _garden_btn: Button = null
var _garden_badge: PanelContainer = null
var _garden_win: GardenWin = null
var _garden_drop_before: Dictionary = {}


func _ready() -> void:
	theme = TecTheme.build()
	_progress_path = "user://shot_progress.json" if _shot_mode() else CaseCatalog.PROGRESS_PATH
	_progress_read_only = DisplayServer.get_name() == "headless" and not _shot_mode()
	_catalog = CaseCatalog.new(_progress_path)
	case_def = CaseLoader.new(CaseCatalog.path_of(_active_case))
	if not case_def.load_case():
		push_error("案件数据装载失败：" + case_def.load_error)
		return
	_save_enabled = not _shot_mode() and DisplayServer.get_name() != "headless"
	_investigator = Investigator.load_from(_inv_path)
	graph = GraphState.new(case_def)
	combos = ComboSystem.new(case_def, graph)
	_cmds = CommandSystem.new(case_def, graph)
	_build_ui()
	_update_case_chrome()
	_update_case_park_ui()
	_refresh_chip()
	if _resume_allowed() and _resume_from_save():
		_show_toast("已继续上次进度")
	else:
		_start_slice()
	if _intro_allowed() and _investigator.is_empty():
		_open_intro()
	if _has_arg("--shot-p2"):
		_shot_p2_flow.call_deferred()
	elif _has_arg("--shot"):
		if _has_arg("--shot-intro"):
			_shot_intro_flow.call_deferred()
		else:
			_shot_flow.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave()
		get_tree().quit()


## 命令行参数（`--` 之后的用户参数）
func _has_arg(flag: String) -> bool:
	return OS.get_cmdline_user_args().has(flag) or OS.get_cmdline_args().has(flag)


func _shot_mode() -> bool:
	return _has_arg("--shot") or _has_arg("--shot-p2")


# ── 界面搭建 ────────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.name = "desk_bg"
	var bg_mat := ShaderMaterial.new()
	bg_mat.shader = load("res://ui/shaders/paper.gdshader")
	bg_mat.set_shader_parameter("area", Vector2(1280, 800))
	bg.material = bg_mat
	bg.color = Color.WHITE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_build_header()

	_desk = Control.new()
	_desk.name = "desk"
	_desk.position = Vector2(0, HEADER_H)
	_desk.size = Vector2(1280, 800 - HEADER_H)
	_desk.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_desk)

	_build_case_window()
	_build_icons()
	_build_case_park()
	_build_tec_chip()

	_tec = TecWindow.new()
	_tec.name = "tec_win"
	_tec.setup_tec()
	_tec.position = Vector2(906, 264)
	_tec.visible = false
	_tec.closed.connect(_close_tec)
	_tec.minimized.connect(_minimize_tec)
	_tec.analysis_started.connect(_on_tec_analysis_started)
	_tec.analysis_progress.connect(_on_tec_analysis_progress)
	_tec.analysis_done.connect(_on_tec_analysis_done)
	_tec.talk_requested.connect(_tec_talk)
	_desk.add_child(_tec)

	_narr = NarrCard.new()
	_narr.name = "narr_card"
	_narr.visible = false
	_desk.add_child(_narr)

	_ending = EndingOverlay.new()
	_ending.name = "ending"
	setup_ending()

	_build_toast()


func setup_ending() -> void:
	add_child(_ending)
	_ending.setup_overlay()
	if not _ending.finished.is_connected(_on_ending_finished):
		_ending.finished.connect(_on_ending_finished)


func _build_header() -> void:
	var head := Panel.new()
	head.name = "header"
	head.position = Vector2.ZERO
	head.size = Vector2(1280, HEADER_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = TecTheme.LINE
	sb.border_width_bottom = 2
	sb.border_color = TecTheme.LINE
	head.add_theme_stylebox_override("panel", sb)
	add_child(head)

	var brand := TecTheme.label("T.E.C-OS", 14, TecTheme.CARD)
	brand.position = Vector2(14, 12)
	brand.size = Vector2(110, 28)
	head.add_child(brand)

	var sub := TecTheme.label("CASE FILE SYSTEM", 10, TecTheme.LINE2)
	sub.position = Vector2(112, 12)
	sub.size = Vector2(140, 28)
	head.add_child(sub)

	_crumb = TecTheme.label(_case_label(), TecTheme.FS_BODY, TecTheme.LINE2)
	_crumb.name = "crumb"
	_crumb.position = Vector2(258, 12)
	_crumb.size = Vector2(430, 28)
	head.add_child(_crumb)

	_inv_chip = TecTheme.button("")
	_inv_chip.name = "inv_chip"
	_inv_chip.position = Vector2(700, 11)
	_inv_chip.size = Vector2(214, 30)
	_inv_chip.clip_text = true
	_inv_chip.add_theme_font_size_override("font_size", 11)
	_inv_chip.add_theme_color_override("font_color", TecTheme.CARD)
	_inv_chip.add_theme_color_override("font_hover_color", TecTheme.TEXT)
	_inv_chip.add_theme_color_override("font_pressed_color", TecTheme.TEXT)
	var chip_normal := TecTheme.flat(Color(0, 0, 0, 0), TecTheme.R_BTN, TecTheme.CARD)
	var chip_hover := TecTheme.flat(TecTheme.CARD, TecTheme.R_BTN, TecTheme.CARD)
	chip_normal.content_margin_left = 8
	chip_normal.content_margin_right = 8
	chip_hover.content_margin_left = 8
	chip_hover.content_margin_right = 8
	_inv_chip.add_theme_stylebox_override("normal", chip_normal)
	_inv_chip.add_theme_stylebox_override("hover", chip_hover)
	_inv_chip.add_theme_stylebox_override("pressed", chip_hover)
	_inv_chip.visible = false
	_inv_chip.pressed.connect(_open_cert_review)
	head.add_child(_inv_chip)

	var undo_btn := TecTheme.button("撤销")
	undo_btn.name = "btn_undo"
	undo_btn.position = Vector2(930, 11)
	undo_btn.size = Vector2(84, 30)
	undo_btn.pressed.connect(_undo)
	head.add_child(undo_btn)

	var reset_btn := TecTheme.button("重来")
	reset_btn.name = "btn_reset"
	reset_btn.position = Vector2(1022, 11)
	reset_btn.size = Vector2(90, 30)
	reset_btn.pressed.connect(_reset_case)
	head.add_child(reset_btn)

	var tec_btn := TecTheme.button("TEC")
	tec_btn.name = "btn_tec"
	tec_btn.position = Vector2(1130, 11)
	tec_btn.size = Vector2(80, 30)
	tec_btn.pressed.connect(_toggle_tec)
	head.add_child(tec_btn)


func _build_case_window() -> void:
	_case_win = SysWindow.new()
	_case_win.name = "case_win"
	_case_win.setup(_case_window_title(), 900, 596)
	_case_win.position = Vector2(150, 24)
	_case_win.body.clip_contents = true
	_case_win.enable_case_controls()
	_case_win.closed.connect(func(): _park_case("icon"))
	_case_win.minimized.connect(func(): _park_case("dock"))
	_desk.add_child(_case_win)

	_stage = Control.new()
	_stage.name = "stage"
	_stage.size = _case_win.body.size
	_stage.clip_contents = true
	_stage.mouse_filter = Control.MOUSE_FILTER_PASS
	_case_win.body.add_child(_stage)

	var stage_bg := ColorRect.new()
	stage_bg.name = "stage_bg"
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/shaders/paper.gdshader")
	mat.set_shader_parameter("area", _stage.size)
	mat.set_shader_parameter("blotch", 0.06)
	stage_bg.material = mat
	stage_bg.color = Color.WHITE
	stage_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(stage_bg)

	_card_layer = Control.new()
	_card_layer.name = "cards"
	_card_layer.size = _stage.size
	_card_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	_stage.add_child(_card_layer)


func _build_icons() -> void:
	var col := VBoxContainer.new()
	col.name = "icons"
	col.position = Vector2(22, 30)
	col.add_theme_constant_override("separation", 10)
	_desk.add_child(col)
	for pair in [["TEC", "tec"], ["证物袋", "bag"], ["线索册", "clue"], ["推演桌布", "infer"],
			["档案袋", "goto"], ["案件地图", "map"]]:
		var b := TecTheme.button(String(pair[0]))
		b.custom_minimum_size = Vector2(96, 40)
		b.name = "icon_" + String(pair[1])
		if String(pair[1]) == "tec":
			_tec_btn = b
			b.pressed.connect(_toggle_tec)
		elif String(pair[1]) == "bag":
			b.pressed.connect(func(): _toggle_storage(GraphState.BAG))
		elif String(pair[1]) == "clue":
			b.pressed.connect(func(): _toggle_storage(GraphState.LEDGER))
		elif String(pair[1]) == "infer":
			b.pressed.connect(_toggle_matrix)
		elif String(pair[1]) == "map":
			_map_btn = b
			b.pressed.connect(_toggle_case_map)
		else:
			_archive_btn = b
			b.pressed.connect(_toggle_archive)
		col.add_child(b)
	_build_map_badge()
	_build_archive_badge()

	_music_btn = TecTheme.button("播放器")
	_music_btn.name = "icon_music"
	_music_btn.custom_minimum_size = Vector2(96, 40)
	_music_btn.tooltip_text = "打开音乐播放器（唱针已装上唱机）"
	_music_btn.visible = false
	_music_btn.pressed.connect(_toggle_music_win)
	col.add_child(_music_btn)

	_garden_btn = TecTheme.button("花园")
	_garden_btn.name = "icon_garden"
	_garden_btn.custom_minimum_size = Vector2(96, 40)
	_garden_btn.tooltip_text = "去花园看看真名留下的种子"
	_garden_btn.visible = false
	_garden_btn.pressed.connect(_open_garden)
	col.add_child(_garden_btn)

	_garden_badge = PanelContainer.new()
	_garden_badge.name = "garden_badge"
	_garden_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gsb := TecTheme.flat(TecTheme.LINE, 6, TecTheme.LINE)
	gsb.content_margin_left = 5
	gsb.content_margin_right = 5
	gsb.content_margin_top = 1
	gsb.content_margin_bottom = 1
	_garden_badge.add_theme_stylebox_override("panel", gsb)
	var gl := TecTheme.label("", 9, TecTheme.CARD)
	gl.name = "Label"
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_garden_badge.add_child(gl)
	_garden_badge.position = Vector2(50, -5)
	_garden_badge.visible = false
	_garden_btn.add_child(_garden_badge)


func _build_map_badge() -> void:
	if _map_btn == null:
		return
	_map_badge = PanelContainer.new()
	_map_badge.name = "map_badge"
	_map_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := TecTheme.flat(TecTheme.LINE, 6, TecTheme.LINE)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	_map_badge.add_theme_stylebox_override("panel", sb)
	var l := TecTheme.label("已关闭", 9, TecTheme.CARD)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_badge.add_child(l)
	_map_badge.position = Vector2(58, -5)
	_map_badge.visible = false
	_map_btn.add_child(_map_badge)


func _build_archive_badge() -> void:
	if _archive_btn == null:
		return
	_archive_badge = PanelContainer.new()
	_archive_badge.name = "archive_badge"
	_archive_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := TecTheme.flat(TecTheme.LINE, 6, TecTheme.LINE)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	_archive_badge.add_theme_stylebox_override("panel", sb)
	var l := TecTheme.label("新", 9, TecTheme.CARD)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_archive_badge.add_child(l)
	_archive_badge.position = Vector2(58, -5)
	_archive_badge.visible = false
	_archive_btn.add_child(_archive_badge)


# ── 音乐播放器 / 花园彩蛋（P2.5）────────────────────────────────────────

func _music_unlocked() -> bool:
	if graph == null:
		return false
	for n in graph.nodes.values():
		var ins = n.get("installed", {})
		if ins is Dictionary and bool(ins.get("ITEMS_cz", false)):
			return true
	return false


func _refresh_app_icons() -> void:
	if graph == null:
		return
	var music := _music_unlocked()
	if _music_btn != null:
		_music_btn.visible = music
	if not music:
		if _music_win != null and is_instance_valid(_music_win):
			_music_win.queue_free()
		_music_win = null
		if _music_dock != null and is_instance_valid(_music_dock):
			_music_dock.queue_free()
		_music_dock = null

	var garden := GardenSystem.has_garden(graph)
	if _garden_btn != null:
		_garden_btn.visible = garden
	if not garden:
		if _garden_win != null and is_instance_valid(_garden_win):
			_garden_win.queue_free()
		_garden_win = null
		if _garden_badge != null:
			_garden_badge.visible = false
		return
	GardenSystem.normalize(graph, case_def)
	var plots: Array = graph.garden.get("plots", [])
	var seed := bool(graph.garden.get("seed", false))
	if _garden_badge != null:
		if not plots.is_empty():
			_garden_badge.visible = true
			var lab: Label = _garden_badge.get_node_or_null("Label")
			if lab != null:
				lab.text = "%d 株" % plots.size()
		elif seed:
			_garden_badge.visible = true
			var lab: Label = _garden_badge.get_node_or_null("Label")
			if lab != null:
				lab.text = "种子"
		else:
			_garden_badge.visible = false


func _toggle_music_win() -> void:
	if _music_win == null or not is_instance_valid(_music_win):
		_open_music()
		return
	if _music_win.visible:
		_on_music_closed()
		return
	if _music_dock != null and is_instance_valid(_music_dock) and _music_dock.visible:
		_restore_music()
		return
	_open_music()


func _open_music() -> void:
	if not _music_unlocked():
		return
	if _music_win == null or not is_instance_valid(_music_win):
		_music_win = MusicWin.new()
		_music_win.name = "music_win"
		_music_win.setup_music()
		_music_win.position = Vector2(906, 414)
		_music_win.closed.connect(_on_music_closed)
		_music_win.minimized.connect(_minimize_music)
		_music_win.progress_changed.connect(_on_music_progress)
		_desk.add_child(_music_win)
	_music_win.visible = true
	_music_win.move_to_front()
	if _music_dock != null:
		_music_dock.visible = false


func _ensure_music_dock() -> MusicDock:
	if _music_dock != null and is_instance_valid(_music_dock):
		return _music_dock
	_music_dock = MusicDock.new()
	_music_dock.name = "music_dock"
	_music_dock.setup_dock()
	_music_dock.position = Vector2(1026, 532)
	_music_dock.restore_requested.connect(_restore_music)
	_music_dock.toggle_requested.connect(_toggle_music)
	_music_dock.stop_requested.connect(_stop_music)
	_desk.add_child(_music_dock)
	_music_dock.visible = false
	return _music_dock


func _minimize_music() -> void:
	if _music_win == null:
		return
	_music_win.visible = false
	var dock := _ensure_music_dock()
	dock.update_state(_music_win.state())
	dock.visible = true
	dock.move_to_front()


func _restore_music() -> void:
	if _music_win == null or not is_instance_valid(_music_win):
		_open_music()
		if _music_dock != null:
			_music_dock.visible = false
		return
	_music_win.visible = true
	_music_win.move_to_front()
	if _music_dock != null:
		_music_dock.visible = false


func _on_music_closed() -> void:
	if _music_win != null:
		_music_win.visible = false
	if _music_dock != null:
		_music_dock.visible = false
	if _music_win != null and _music_win.is_playing():
		_show_toast("播放器已收起，音乐继续")


func _on_music_progress(_cur: float, _dur: float) -> void:
	if _music_dock != null and _music_dock.visible and _music_win != null:
		_music_dock.update_state(_music_win.state())


func _toggle_music() -> void:
	if _music_win == null:
		return
	_music_win.toggle_current()
	if _music_dock != null and _music_dock.visible:
		_music_dock.update_state(_music_win.state())


func _stop_music() -> void:
	if _music_win == null:
		return
	_music_win.stop()
	if _music_dock != null:
		_music_dock.visible = false


func _open_garden() -> void:
	if not GardenSystem.has_garden(graph):
		return
	if _garden_win != null and is_instance_valid(_garden_win):
		_garden_win.queue_free()
		_garden_win = null
		return
	GardenSystem.normalize(graph, case_def)
	_garden_win = GardenWin.new()
	_garden_win.name = "garden_win"
	_garden_win.setup_garden(graph, case_def)
	_garden_win.position = Vector2(380, 58)
	_garden_win.closed.connect(func(): _garden_win = null)
	_garden_win.plant_moved.connect(func(_idx): _autosave())
	_garden_win.garden_changed.connect(_on_garden_changed)
	_garden_win.plot_bloomed.connect(_on_garden_bloomed)
	_desk.add_child(_garden_win)
	_garden_win.move_to_front()


func _on_garden_changed() -> void:
	_autosave()
	_refresh_app_icons()


func _on_garden_bloomed(_idx: int, fresh: bool) -> void:
	if fresh:
		_show_toast("花园里的种子开花了")


## 种子从桌布拖到花园窗 / 花园图标；成功返回 true，MatrixWin 据此决定是否弹回。
func _drop_seed(at_global: Vector2) -> bool:
	if graph == null or not GardenSystem.has_garden(graph):
		return false
	if not bool(graph.garden.get("seed", false)):
		return false
	var spot := {}
	var over_win := _garden_win != null and is_instance_valid(_garden_win) \
		and _garden_win.get_global_rect().has_point(at_global)
	var over_icon := _garden_btn != null and _garden_btn.visible \
		and _garden_btn.get_global_rect().has_point(at_global)
	if over_win:
		spot = _garden_win.spot_of_global(at_global)
	elif over_icon:
		spot = GardenSystem.spot_of(GardenSystem.DEFAULT_X, GardenSystem.DEFAULT_Y)
	else:
		return false
	var before := _save.snapshot() if _save != null else {}
	if not GardenSystem.plant(graph, float(spot["x"]), float(spot["y"])):
		return false
	GardenSystem.normalize(graph, case_def)
	_commit(before)
	if _matrix_win != null and is_instance_valid(_matrix_win):
		_matrix_win.refresh_seed()
	if _garden_win != null and is_instance_valid(_garden_win):
		_garden_win.refresh()
		if over_icon:
			_garden_win.move_to_front()
	else:
		_open_garden()
	_refresh_app_icons()
	_show_toast("种下了「真名」")
	return true


func _on_seed_dropped(at_global: Vector2) -> void:
	_drop_seed(at_global)


func _on_ending_finished() -> void:
	if _last_ending_id == "":
		return
	var e := case_def.ending_by_id(_last_ending_id)
	if e == null or not e.is_true_capture:
		return
	GardenSystem.normalize(graph, case_def)
	if not GardenSystem.grant_seed(graph, e.message, case_def):
		return
	_autosave()
	if _matrix_win != null and is_instance_valid(_matrix_win):
		_matrix_win.refresh_seed()
	_refresh_app_icons()
	_show_toast("花盆里多了一枚种子。去花园种下它。")


func _build_case_park() -> void:
	_dock_card = Button.new()
	_dock_card.name = "case_dock"
	_dock_card.size = Vector2(170, 56)
	_dock_card.position = Vector2(1094, 678)
	_dock_card.focus_mode = Control.FOCUS_NONE
	var normal := TecTheme.flat(TecTheme.CARD, TecTheme.R_WIN)
	normal.shadow_color = Color(0.306, 0.282, 0.212, 0.24)
	normal.shadow_size = 8
	normal.shadow_offset = Vector2(3, 5)
	_dock_card.add_theme_stylebox_override("normal", normal)
	_dock_card.add_theme_stylebox_override("hover", TecTheme.flat(TecTheme.BG, TecTheme.R_WIN))
	_dock_card.add_theme_stylebox_override("pressed", TecTheme.flat(TecTheme.FACE_LO, TecTheme.R_WIN))
	_dock_card.pressed.connect(_reopen_case)
	_dock_card.visible = false
	_desk.add_child(_dock_card)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_top = 8
	row.offset_right = -9
	row.offset_bottom = -8
	row.add_theme_constant_override("separation", 9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock_card.add_child(row)

	var glyph_box := PanelContainer.new()
	glyph_box.custom_minimum_size = Vector2(32, 32)
	glyph_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph_box.add_theme_stylebox_override("panel",
		TecTheme.flat(TecTheme.BG, TecTheme.R_BTN, TecTheme.EDGE))
	row.add_child(glyph_box)
	var glyph := TecTheme.label("▣", 15, TecTheme.MUTED)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph_box.add_child(glyph)

	var meta := VBoxContainer.new()
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.alignment = BoxContainer.ALIGNMENT_CENTER
	meta.add_theme_constant_override("separation", 1)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(meta)

	_dock_code = TecTheme.label("", 9, TecTheme.MUTED)
	_dock_code.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(_dock_code)
	_dock_title = TecTheme.label("", 11, TecTheme.TEXT)
	_dock_title.clip_text = true
	_dock_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_dock_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(_dock_title)
	_dock_sub = TecTheme.label("进度已保存 · 点此展开", 9, TecTheme.FAINT)
	_dock_sub.clip_text = true
	_dock_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_dock_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(_dock_sub)


func _build_tec_chip() -> void:
	_tec_chip = TecChip.new()
	_tec_chip.setup_chip()
	_tec_chip.position = Vector2(1068, 608)
	_tec_chip.visible = false
	_tec_chip.pressed.connect(_open_tec)
	_desk.add_child(_tec_chip)


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.name = "toast"
	var sb := StyleBoxFlat.new()
	sb.bg_color = TecTheme.LINE
	sb.set_corner_radius_all(TecTheme.R_BTN)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	sb.shadow_color = Color(0.306, 0.282, 0.212, 0.30)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(4, 6)
	_toast.add_theme_stylebox_override("panel", sb)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_toast_label = TecTheme.label("", TecTheme.FS_BODY, TecTheme.CARD)
	_toast.add_child(_toast_label)
	_desk.add_child(_toast)


# ── 切片 ────────────────────────────────────────────────────────────────

func _case_id() -> String:
	return case_def.case_def.id if case_def != null and case_def.case_def != null else ""


func _case_label() -> String:
	return "案件 " + CaseCatalog.code_of(_active_case).trim_prefix("CASE ")


func _case_title() -> String:
	if case_def != null and case_def.case_def != null and case_def.case_def.title != "":
		return case_def.case_def.title
	return CaseCatalog.title_of(_active_case)


func _case_window_title() -> String:
	return CaseCatalog.code_of(_active_case) + " // " + _case_title()


func _update_case_chrome() -> void:
	if _case_win != null:
		_case_win.set_title(_case_window_title())
	if _crumb != null and (graph == null or graph.last_scene == ""):
		_crumb.text = _case_label()


func _require_case() -> bool:
	if _case_open:
		return true
	_show_toast("当前不在案件中，请先展开案件地图图标或右下角案件卡片", true)
	return false


func _toggle_case_map() -> void:
	if _map_win != null and is_instance_valid(_map_win):
		_map_win.queue_free()
		_map_win = null
		return
	var w := CaseMapWin.new()
	w.name = "case_map"
	w.setup_map(_catalog, _active_case, _case_open)
	w.position = Vector2(420, 72)
	w.enter_requested.connect(_on_case_map_enter)
	w.closed.connect(func(): _map_win = null)
	_desk.add_child(w)
	w.move_to_front()
	_map_win = w


func _on_case_map_enter(id: String) -> void:
	if _map_win != null and is_instance_valid(_map_win):
		_map_win.queue_free()
		_map_win = null
	_enter_case(id)


func _enter_case(id: String) -> bool:
	if not CaseCatalog.exists(id):
		_show_toast("没有这个案件地址", true)
		return false
	if not _catalog.is_unlocked(id):
		_show_toast("该案件地址尚未解密", true)
		return false
	if id == _active_case:
		if not _case_open:
			_reopen_case()
		return true
	if not CaseCatalog.data_ready(id):
		_show_toast("案件 " + CaseCatalog.code_of(id) + " 的数据尚未装载", true)
		return false
	_autosave()
	var loader := CaseLoader.new(CaseCatalog.path_of(id))
	if not loader.load_case():
		_show_toast("案件装载失败：" + loader.load_error, true)
		return false
	_active_case = id
	case_def = loader
	_catalog.last = id
	if not _progress_read_only:
		_catalog.save_progress()
	_case_open = true
	_case_held = false
	_case_docked = false
	_case_win.visible = true
	if _resume_allowed() and _resume_from_save():
		_show_toast("已加载上次进度")
	else:
		_start_slice()
	_update_case_chrome()
	_update_case_park_ui()
	return true


func _park_case(where: String) -> bool:
	if not _case_open:
		return false
	_autosave()
	_close_case_transients()
	_case_open = false
	_case_win.visible = false
	_case_held = where != "dock"
	_case_docked = where == "dock"
	_update_case_park_ui()
	return true


func _reopen_case() -> void:
	if _case_win == null:
		return
	_case_open = true
	_case_held = false
	_case_docked = false
	_case_win.visible = true
	_case_win.move_to_front()
	if _tec != null and _tec.visible:
		_tec.move_to_front()
	_update_case_park_ui()


func _close_case_transients() -> void:
	if _pw_pop != null and is_instance_valid(_pw_pop):
		_pw_pop.queue_free()
	_pw_pop = null
	_pw_ctx = {}
	if _narr != null and is_instance_valid(_narr):
		_narr.queue_free()
	_narr = null
	_close_mem_card()
	_close_chat()
	if _archive_win != null and is_instance_valid(_archive_win):
		_archive_win.queue_free()
	_archive_win = null
	_hide_tec()
	_selected = ""
	if graph != null:
		graph.selected = ""


func _update_case_park_ui() -> void:
	if _dock_card != null:
		_dock_code.text = CaseCatalog.code_of(_active_case)
		_dock_title.text = _case_title()
		_dock_sub.text = "进度已保存 · 点此展开"
		_dock_card.visible = _case_docked
		if _case_docked:
			_dock_card.move_to_front()
	if _map_badge != null:
		_map_badge.visible = _case_held
	if _map_win != null and is_instance_valid(_map_win):
		_map_win.set_case_state(_active_case, _case_open)


func _resume_allowed() -> bool:
	if not _save_enabled or _has_arg("--fresh"):
		return false
	return DisplayServer.get_name() != "headless"


## 重建一套运行时对象（图 / 命令系统 / 存档），并清掉旧卡片与会话窗
func _new_runtime() -> void:
	for c in _card_layer.get_children():
		if c is NodeCard:
			_card_layer.remove_child(c)
			c.queue_free()
	_cards.clear()
	graph = GraphState.new(case_def)
	combos = ComboSystem.new(case_def, graph)
	_cmds = CommandSystem.new(case_def, graph)
	_save = SaveSystem.new(graph, _case_id())
	dialogues = DialogueSystem.new(case_def, graph)
	_selected = ""
	graph.selected = ""
	_last_ending_id = ""
	_storage_before = {}
	if _ending != null:
		_ending.visible = false
	_hide_tec(true)
	if _pw_pop != null and is_instance_valid(_pw_pop):
		_pw_pop.queue_free()
	_pw_pop = null
	_pw_ctx = {}
	if _narr != null and is_instance_valid(_narr):
		_narr.queue_free()
	_narr = null
	_close_mem_card()
	_close_chat()
	if _archive_win != null and is_instance_valid(_archive_win):
		_archive_win.queue_free()
	_archive_win = null
	_clear_archive_new()
	if _matrix_win != null and is_instance_valid(_matrix_win):
		_matrix_win.queue_free()
	_matrix_win = null
	if _bag_win != null and is_instance_valid(_bag_win):
		_bag_win.queue_free()
	_bag_win = null
	if _ledger_win != null and is_instance_valid(_ledger_win):
		_ledger_win.queue_free()
	_ledger_win = null
	if _map_win != null and is_instance_valid(_map_win):
		_map_win.queue_free()
	_map_win = null
	if _music_win != null and is_instance_valid(_music_win):
		_music_win.queue_free()
	_music_win = null
	if _music_dock != null and is_instance_valid(_music_dock):
		_music_dock.queue_free()
	_music_dock = null
	if _garden_win != null and is_instance_valid(_garden_win):
		_garden_win.queue_free()
	_garden_win = null
	_refresh_app_icons()


func _reset_case() -> void:
	if not _require_case():
		return
	if _save != null:
		_save.clear_save()
	_start_slice()
	_show_toast("已重置为初始状态")


func _resume_from_save() -> bool:
	_new_runtime()
	if not _save.load_from_disk():
		_save.clear_history()
		return false
	_rebuild_from_graph()
	_sync_case_progress_from_graph()
	return true


func _sync_case_progress_from_graph() -> void:
	if graph == null or case_def == null or _progress_read_only:
		return
	for e in case_def.endings:
		if e == null or not e.is_true_capture or not graph.endings.has(e.id):
			continue
		_catalog.mark_completed(_active_case)
		_catalog.unlock_next(_active_case)
		_update_case_park_ui()
		return


func _start_slice() -> void:
	_new_runtime()

	# 切片固定从花园开始：config.startScene 是封面标题页（SCENE_START），不是调查起点
	var sid := SLICE_SCENE
	var loc := graph.add_node("loc", sid)
	loc["x"] = 40.0
	loc["y"] = 30.0
	_spawn_card(loc["key"])

	# P0：抽屉链路（书桌 → 左侧抽屉 → 手电筒）不在切片内，直接把点亮的工具放到桌上
	var torch := graph.add_node("item", "ITEM_shoudiantong")
	torch["x"] = 40.0
	torch["y"] = 40.0 + 100.0
	graph.link(loc["key"], torch["key"], "entity")
	_spawn_card(torch["key"])
	_flash_supply_note = false

	_set_crumb(_case_label() + " // " + case_def.scene_title(sid))
	_show_toast("把「%s」拖到「手电筒」上试试" % case_def.scene_title(sid))
	_relayout()


func _set_crumb(text: String) -> void:
	if _crumb != null:
		_crumb.text = text


# ── 调查员 / 开场适性测试 ───────────────────────────────────────────────

func _intro_allowed() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return not _shot_mode() and not _has_arg("--no-intro")


func _refresh_chip() -> void:
	if _inv_chip == null:
		return
	if _investigator.is_empty():
		_inv_chip.visible = false
		_inv_chip.text = ""
		_inv_chip.tooltip_text = ""
		return
	_inv_chip.text = "▣ %s · %s" % [String(_investigator.get("name", "")), String(_investigator.get("id", ""))]
	_inv_chip.tooltip_text = _inv_chip.text
	_inv_chip.visible = true


func _avatar_pool() -> Array:
	var out: Array = Investigator.AVATAR_INITIAL.duplicate()
	for key in graph.nodes.keys():
		if not String(key).begins_with("char:"):
			continue
		var id := String(key).substr(5)
		if id != "CHARS_TEC" and not out.has(id):
			out.append(id)
	return out


func _avatar_names() -> Dictionary:
	var out := {"CHARS_EXEC": "执行者", "CHARS_TEC": "TEC"}
	if case_def == null:
		return out
	for id in _avatar_pool():
		var ch := case_def.char_of(String(id))
		if ch != null and ch.name != "":
			out[String(id)] = ch.name
	return out


func _locked_avatar_count() -> int:
	if case_def == null:
		return 0
	var pool := _avatar_pool()
	var n := 0
	for id in case_def.chars.keys():
		if not pool.has(String(id)):
			n += 1
	return n


func _open_intro() -> IntroWin:
	if _intro != null and is_instance_valid(_intro):
		return _intro
	var w := IntroWin.new()
	w.name = "intro"
	w.store_path = _inv_path
	w.setup(_avatar_pool(), _avatar_names(), _locked_avatar_count())
	w.finished.connect(_on_intro_finished)
	w.tree_exited.connect(_on_intro_closed)
	add_child(w)
	_intro = w
	return w


func _on_intro_closed() -> void:
	_intro = null


func _on_intro_finished(card: Dictionary) -> void:
	_investigator = card.duplicate(true)
	_refresh_chip()
	_show_toast("调查员 %s 已接入 T.E.C-OS" % String(_investigator.get("name", "")))


func _open_cert_review() -> void:
	if _investigator.is_empty():
		return
	if _cert_win != null and is_instance_valid(_cert_win):
		_cert_win.queue_free()
		_cert_win = null
	var w := SysWindow.new()
	w.name = "cert_win"
	w.setup("INVESTIGATOR // 调查员证", 340, 540)
	w.position = Vector2(470, 40)
	_desk.add_child(w)
	w.content.add_child(IntroWin.build_cert(_investigator))
	w.tree_exited.connect(func(): _cert_win = null)
	_cert_win = w


func _show_toast(text: String, warn: bool = false) -> void:
	_toast_label.text = text
	_toast.add_theme_stylebox_override("panel", _toast_style(warn))
	_toast.visible = true
	_toast.reset_size()
	_toast.position = Vector2((1280.0 - _toast.size.x) * 0.5, 800.0 - HEADER_H - 60.0)
	if _toast_timer != null:
		_toast_timer.timeout.disconnect(_hide_toast)
	_toast_timer = get_tree().create_timer(2.2)
	_toast_timer.timeout.connect(_hide_toast)


func _toast_style(warn: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TecTheme.LINE
	sb.set_corner_radius_all(TecTheme.R_BTN)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	if warn:
		sb.border_width_left = 4
		sb.border_color = TecTheme.LINE2
	sb.shadow_color = Color(0.306, 0.282, 0.212, 0.30)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(4, 6)
	return sb


func _hide_toast() -> void:
	_toast.visible = false


# ── 撤销 / 存档 ─────────────────────────────────────────────────────────

func _autosave() -> void:
	if _save == null or not _save_enabled:
		return
	if not _save.save_to_disk():
		push_warning("自动存档失败：" + _save.last_error)


## 动作开始前拍一张；动作结束后状态真的变了才入撤销栈并写盘
func _commit(before: Dictionary) -> void:
	if before.is_empty() or _save == null:
		return
	if JSON.stringify(before) == JSON.stringify(_save.snapshot()):
		return
	_save.push_history(before)
	_autosave()
	_refresh_app_icons()


func dbg_undo() -> bool:
	return _undo()


func dbg_history_size() -> int:
	return _save.history.size() if _save != null else 0


func dbg_save() -> bool:
	return _save.save_to_disk() if _save != null else false


func dbg_load() -> bool:
	if _save == null or not _save.load_from_disk():
		return false
	_rebuild_from_graph()
	return true


func dbg_clear_save() -> void:
	if _save != null:
		_save.clear_save()


func dbg_save_path() -> String:
	return _save.path if _save != null else ""


func dbg_use_temp_save(p_path: String) -> void:
	_save = SaveSystem.new(graph, _case_id(), p_path)
	_save.clear_save()
	_save.clear_history()


func _undo() -> bool:
	if not _require_case():
		return false
	if _save == null or not _save.can_undo():
		_show_toast("没有可撤销的操作", true)
		return false
	if not _save.undo():
		_show_toast("撤销失败：" + _save.last_error, true)
		return false
	_rebuild_from_graph()
	_autosave()
	_show_toast("已撤销上一步")
	return true


## 按当前图状态重建所有卡片（撤销 / 续档共用）
func _rebuild_from_graph() -> void:
	for c in _card_layer.get_children():
		if c is NodeCard:
			_card_layer.remove_child(c)
			c.queue_free()
	_cards.clear()
	_selected = ""
	graph.selected = ""
	_storage_before = {}
	GardenSystem.normalize(graph, case_def)
	if _music_win != null and is_instance_valid(_music_win):
		_music_win.queue_free()
	_music_win = null
	if _music_dock != null and is_instance_valid(_music_dock):
		_music_dock.queue_free()
	_music_dock = null
	if _garden_win != null and is_instance_valid(_garden_win):
		_garden_win.queue_free()
	_garden_win = null
	if _pw_pop != null and is_instance_valid(_pw_pop):
		_pw_pop.queue_free()
	_pw_pop = null
	_pw_ctx = {}
	if _narr != null and is_instance_valid(_narr):
		_narr.queue_free()
	_narr = null
	_close_mem_card()
	_close_chat()
	if _archive_win != null and is_instance_valid(_archive_win):
		_archive_win.queue_free()
	_archive_win = null
	_clear_archive_new()
	_ending.visible = false
	if _tec != null:
		_tec.cancel_analysis()
		_sync_tec_chip()
	_suppress_archive_new = true
	for key in graph.nodes.keys():
		_spawn_card(String(key))
	_suppress_archive_new = false
	_apply_hidden()
	_refresh_matrix_views()
	_last_ending_id = String(graph.endings.keys()[0]) if not graph.endings.is_empty() else ""
	var sid := graph.last_scene
	_set_crumb(_case_label() + " // " + case_def.scene_title(sid) if sid != "" else _case_label())
	_update_case_chrome()
	_refresh_app_icons()


# ── 卡片 ────────────────────────────────────────────────────────────────

func _spawn_card(key: String) -> NodeCard:
	if _cards.has(key):
		return _cards[key]
	var n := graph.node(key)
	if n.is_empty():
		return null
	if String(n["kind"]) == "time":
		if not _suppress_archive_new and graph.has_unread(key):
			_mark_archive_new()
		return null                       # 时间节点不上画布（入口在档案窗）
	var w := GraphState.SCENE_W if GraphState.is_scene_kind(String(n["kind"])) else GraphState.ENT_W
	var h := GraphState.SCENE_H if GraphState.is_scene_kind(String(n["kind"])) else GraphState.ENT_H
	var card := NodeCard.new()
	card.name = "card_" + key.replace(":", "_")
	card.setup(key, String(n["kind"]), n, w, h)
	card.position = Vector2(float(n.get("x", 0.0)), float(n.get("y", 0.0)))
	card.selected.connect(_on_card_selected)
	card.activated.connect(_on_card_activated)
	card.dragged.connect(_on_card_dragged)
	card.drag_released.connect(_on_card_drag_released)
	card.combo_requested.connect(_on_card_combo)
	_card_layer.add_child(card)
	_cards[key] = card
	return card


func _on_card_selected(key: String) -> void:
	_selected = key
	graph.selected = key


func _on_card_dragged(key: String) -> void:
	_selected = key
	graph.selected = key


## 拖到推演桌布窗口上 = 归位（Web 版 overMatrixDrop 的画布侧入口）
func _on_card_drag_released(key: String, at_global: Vector2) -> void:
	if _chat_drop_hit(at_global):
		_chat_drop(key)
		_relayout()
		return
	if _matrix_win != null and is_instance_valid(_matrix_win) \
		and _matrix_win.board_global_rect().has_point(at_global):
		_assign_to_matrix(key)
		return
	if _tec_drop_hit(at_global):
		_start_tec_analysis(key)


func _on_card_activated(key: String) -> void:
	var n := graph.node(key)
	if n.is_empty():
		return
	var id := String(n["id"])
	if n["kind"] == "loc":
		_toggle_container("loc", id)
		return
	if graph.is_container("item", id):
		_toggle_container("item", id)
		return
	# 其余：跑第一条命令（text / password / choice / conditional / reveal 都从这儿进）
	var before := _save.snapshot()
	var res := combos.activate(key)
	if res.is_empty():
		if String(n["kind"]) == "char" and _open_monologue(id):
			return
		return
	_apply_outcome(res, key)
	_commit(before)


## 容器双重身份：第一次双击展开，已展开再双击收起（对齐 Web 的展开 / 折叠）
func _toggle_container(kind: String, id: String) -> void:
	var before := _save.snapshot()
	if graph.explored.has(id) and not graph.is_collapsed(id):
		graph.collapse(id)
		_apply_hidden()
		_show_toast("收起了「%s」" % case_def.label_of(kind, id))
		_relayout()
		_commit(before)
		return
	var fresh := graph.reveal_container(kind, id)
	graph.uncollapse(id)
	_apply_hidden()
	for k in fresh:
		_spawn_card(String(k))
	if _cards.has(graph.key_of(kind, id)):
		_cards[graph.key_of(kind, id)].refresh()
	_relayout()
	if kind == "loc":
		_show_narr(id)
		_set_crumb(_case_label() + " // " + case_def.scene_title(id))
	else:
		_show_toast("展开了「%s」" % case_def.label_of(kind, id))
	_commit(before)


## 把图状态的隐藏结论落到卡片上（对齐 Web 的 recomputeHidden：钉住的、跟场外有连线的都不藏）
func _apply_hidden() -> void:
	graph.recompute_hidden()
	for key in _cards.keys():
		(_cards[key] as NodeCard).visible = graph.visible_node(graph.node(String(key)))


## 统一落地一次命令结果：提示 / 长卡片 / 刷新 / 重排
func _apply_outcome(res: Dictionary, node_key: String) -> void:
	if res.get("needs_password", false):
		_open_password(node_key)
		return
	var blocked := bool(res.get("blocked", false))
	var msg := String(res.get("message", ""))
	if msg != "":
		_show_toast(msg, blocked)
	for m in res.get("messages", []):
		if String(m) != "":
			_show_toast(String(m))
	for k in res.get("spawn", []):
		_spawn_card(String(k))
	for k in res.get("reveal", []):
		_spawn_card(String(k))
	for k in res.get("captured", []):
		_refresh_or_spawn_card(String(k))
	if bool(res.get("lit_changed", false)):
		if _cards.has(node_key):
			_cards[node_key].refresh()
		var flavor := String(res.get("flavor", ""))
		if flavor != "":
			_show_toast(flavor)
	if res.has("next_scene") and String(res.get("next_scene", "")) != "":
		_set_crumb(_case_label() + " // " + case_def.scene_title(String(res["next_scene"])))
	_relayout()


# ── 收纳窗（证物袋 / 线索册）────────────────────────────────────────────

func _toggle_storage(kind: String) -> void:
	if not _require_case():
		return
	if kind == GraphState.BAG:
		if _bag_win != null and is_instance_valid(_bag_win):
			_bag_win.queue_free()
			_bag_win = null
			return
		_bag_win = StorageWin.new()
		_bag_win.name = "bag_win"
		_bag_win.setup_store("EVIDENCE BAG // 证物袋", GraphState.BAG, graph, case_def)
		_bag_win.position = Vector2(150, 300)
		_bag_win.will_take.connect(_on_storage_will_take)
		_bag_win.took.connect(_on_storage_took)
		_bag_win.closed.connect(func(): _bag_win = null)
		_desk.add_child(_bag_win)
		_bag_win.move_to_front()
		return
	if _ledger_win != null and is_instance_valid(_ledger_win):
		_ledger_win.queue_free()
		_ledger_win = null
		return
	_ledger_win = StorageWin.new()
	_ledger_win.name = "clue_win"
	_ledger_win.setup_store("CLUE LEDGER // 线索册", GraphState.LEDGER, graph, case_def)
	_ledger_win.position = Vector2(410, 300)
	_ledger_win.will_take.connect(_on_storage_will_take)
	_ledger_win.took.connect(_on_storage_took)
	_ledger_win.to_matrix.connect(_on_ledger_to_matrix)
	_ledger_win.closed.connect(func(): _ledger_win = null)
	_desk.add_child(_ledger_win)
	_ledger_win.move_to_front()


## 收纳窗取出前先拍快照（StorageWin 自己改图，Desktop 只能从信号里抢在它前面）
func _on_storage_will_take(_key: String) -> void:
	_storage_before = _save.snapshot()


## 从收纳窗取回：节点回到画布，并刷新两个清单窗
func _on_storage_took(key: String) -> void:
	if _cards.has(key):
		(_cards[key] as NodeCard).visible = graph.visible_node(graph.node(key))
	_relayout()
	if _bag_win != null and is_instance_valid(_bag_win):
		_bag_win.refresh_store()
	if _ledger_win != null and is_instance_valid(_ledger_win):
		_ledger_win.refresh_store()
	_commit(_storage_before)
	_storage_before = {}


# ── 推演桌布（五感槽位 / 归位 / 长按推演）──────────────────────────────

func _toggle_matrix() -> void:
	if not _require_case():
		return
	if _matrix_win != null and is_instance_valid(_matrix_win):
		_matrix_win.queue_free()
		_matrix_win = null
		return
	_matrix_win = MatrixWin.new()
	_matrix_win.name = "matrix_win"
	_matrix_win.setup_matrix(graph, case_def)
	_matrix_win.position = Vector2(336, 40)
	_matrix_win.clue_taken.connect(_on_matrix_took)
	_matrix_win.clue_dropped.connect(_on_matrix_dropped)
	_matrix_win.inference_requested.connect(_run_inference)
	_matrix_win.seed_dropped.connect(_on_seed_dropped)
	_desk.add_child(_matrix_win)
	_matrix_win.move_to_front()


## 画布 / 册子 → 桌布。感官自动取线索自身的 sense（与 Web 的 assignClue 一致）。
func _assign_to_matrix(key: String) -> bool:
	var n := graph.node(key)
	if n.is_empty():
		return false
	if String(n["kind"]) != "clue":
		_show_toast("只有线索能归位到推演桌布", true)
		return false
	var cl := case_def.clue_of(String(n["id"]))
	if cl == null:
		return false
	var before := _save.snapshot()
	if not graph.matrix_assign(key):
		_show_toast("「%s」的感官类型是%s，归位失败" % [n.get("label", ""), GraphState.SENSE_NAMES.get(cl.sense, cl.sense)], true)
		return false
	_apply_hidden()
	_refresh_or_spawn_card(key)
	_refresh_matrix_views()
	_commit(before)
	return true


func _on_matrix_took(key: String) -> void:
	var before := _save.snapshot()
	if not graph.matrix_take(key):
		return
	_apply_hidden()
	_refresh_or_spawn_card(key)
	_refresh_matrix_views()
	_commit(before)


## 桌布上的线索拖到线索册 = 改归册子；拖出桌布到别处 = 取回画布
func _on_matrix_dropped(key: String, at_global: Vector2) -> void:
	if _ledger_win != null and is_instance_valid(_ledger_win) \
		and _ledger_win.get_global_rect().has_point(at_global):
		var before := _save.snapshot()
		if graph.restash(key, GraphState.MATRIX, GraphState.LEDGER):
			_apply_hidden()
			_refresh_matrix_views()
			_commit(before)
			return
	_on_matrix_took(key)


func _on_ledger_to_matrix(key: String) -> void:
	var before := _save.snapshot()
	if graph.matrix_assign(key):
		_apply_hidden()
		_refresh_matrix_views()
		_commit(before)
	else:
		_show_toast("这条线索没有可用的感官槽位", true)


func _refresh_matrix_views() -> void:
	if _matrix_win != null and is_instance_valid(_matrix_win):
		_matrix_win.refresh_matrix()
		_matrix_win.refresh_seed()
	if _bag_win != null and is_instance_valid(_bag_win):
		_bag_win.refresh_store()
	if _ledger_win != null and is_instance_valid(_ledger_win):
		_ledger_win.refresh_store()


## 长按蓄力完成 → 配方判定（Web 的 executeInference）：恰好命中才算，多余线索也失败
func _run_inference() -> void:
	var hit := graph.match_ending()
	if hit == null:
		if _matrix_win != null and is_instance_valid(_matrix_win):
			_matrix_win.show_heartbroken()
		_show_toast("推演失败：当前阵列不匹配任何结局配方", true)
		return
	var before := _save.snapshot()
	graph.mark_ending(hit.id)
	_last_ending_id = hit.id
	if hit.is_true_capture and not _progress_read_only:
		_catalog.mark_completed(_active_case)
		_catalog.unlock_next(_active_case)
		_update_case_park_ui()
	if _matrix_win != null and is_instance_valid(_matrix_win):
		_matrix_win.play_shock()
	_ending.play(hit)
	_commit(before)


func _refresh_or_spawn_card(key: String) -> void:
	var card: NodeCard = _cards.get(key, null)
	if card == null:
		card = _spawn_card(key)
	if card != null:
		card.visible = graph.visible_node(graph.node(key))
		card.refresh()


## 供测试钩子 / 后续接线用：把当前选中的节点收进某个收纳处
func dbg_store(kind: String) -> bool:
	if _selected == "":
		return false
	if kind == GraphState.MATRIX:
		return _assign_to_matrix(_selected)
	var before := _save.snapshot()
	var ok := false
	if kind == GraphState.BAG:
		ok = graph.bag_store(_selected)
	elif kind == GraphState.LEDGER:
		ok = graph.ledger_store(_selected)
	if not ok:
		return false
	_apply_hidden()
	_refresh_matrix_views()
	_commit(before)
	return true


# ── 密码弹窗 ────────────────────────────────────────────────────────────

func _open_password(node_key: String) -> void:
	var n := graph.node(node_key)
	var it := case_def.item_of(String(n.get("id", "")))
	if it == null:
		return
	var cmd: PasswordCommandDef = null
	for c in it.commands:
		if c is PasswordCommandDef:
			cmd = c
			break
	if cmd == null:
		return
	if _pw_pop != null and is_instance_valid(_pw_pop):
		if _pw_pop.get_parent() != null:
			_pw_pop.get_parent().remove_child(_pw_pop)
		_pw_pop.queue_free()
	var card: NodeCard = _cards.get(node_key, null)
	_pw_pop = PasswordPop.new()
	_pw_pop.name = "pw_pop"
	_pw_pop.setup_password(it.label, cmd.label)
	var base := Vector2(300, 300)
	if card != null:
		base = card.position + _stage.get_global_rect().position - _desk.get_global_rect().position + Vector2(0, 80)
	_pw_pop.position = base
	_pw_pop.submitted.connect(_submit_password)
	_desk.add_child(_pw_pop)
	_pw_pop.move_to_front()
	_pw_ctx = {"node_key": node_key, "cmd": cmd}


func _submit_password(text: String) -> void:
	if _pw_ctx.is_empty():
		return
	var before := _save.snapshot()
	var res := _cmds.submit_password(String(_pw_ctx["node_key"]), _pw_ctx["cmd"], text)
	if bool(res.get("wrong_password", false)):
		if _pw_pop != null and is_instance_valid(_pw_pop):
			_pw_pop.reject_wrong()
		_show_toast(String(res.get("message", "")), true)
		return
	if _pw_pop != null and is_instance_valid(_pw_pop):
		_pw_pop.queue_free()
	_pw_pop = null
	_apply_outcome(res, String(_pw_ctx["node_key"]))
	_pw_ctx = {}
	_commit(before)


func _on_card_combo(tool_key: String, target_key: String) -> void:
	var before := _save.snapshot()
	if _try_memory_combo(tool_key, target_key, before):
		return
	if _try_dialogue_combo(tool_key, target_key):
		return
	var res := combos.use_item(tool_key, target_key)
	if res.has("blocked") and res["blocked"]:
		_show_toast(String(res.get("message", "")), true)     # 发光门：不记 tried、不进撤销
		_relayout()
		return
	if res.get("ok", false):
		_show_toast(String(res.get("message", "")))
		var next_scene := String(res.get("next_scene", ""))
		if next_scene != "":
			_expand_scene(next_scene, true)
		for k in res.get("reveal", []):
			_spawn_card(String(k))
		for k in res.get("captured", []):
			_refresh_or_spawn_card(String(k))
		_relayout()
		_commit(before)
	else:
		var msg := String(res.get("message", ""))
		if msg != "":
			_show_toast(msg, true)
		_relayout()


func _expand_scene(sid: String, show_narr: bool) -> void:
	var fresh := graph.reveal_scene(sid)
	var key := graph.scene_key(sid)
	var had := _cards.has(key)
	for k in fresh:
		_spawn_card(String(k))
	if not had:
		_spawn_card(key)
	if _cards.has(key):
		_cards[key].refresh()
	_relayout()
	if show_narr:
		_show_narr(sid)
	_set_crumb(_case_label() + " // " + case_def.scene_title(sid))


func _show_narr(sid: String) -> void:
	var n := graph.node(graph.scene_key(sid))
	if n.is_empty():
		return
	var body := case_def.text_of(graph.normalize_kind("loc", sid), sid)
	if _narr != null and is_instance_valid(_narr):
		_narr.queue_free()
	_narr = NarrCard.new()
	_narr.name = "narr_card"
	_narr.setup_narr(case_def.scene_title(sid), body, 340, 300)
	_narr.position = Vector2(700, 290)
	_narr.closed.connect(_on_narr_closed)
	_desk.add_child(_narr)
	_narr.move_to_front()


func _on_narr_closed() -> void:
	_narr = null


# ── 档案 / 时间图层 / 回忆放映 ─────────────────────────────────────────

func _toggle_archive() -> void:
	if not _require_case():
		return
	if _archive_win != null and is_instance_valid(_archive_win):
		_archive_win.queue_free()
		_archive_win = null
		return
	_archive_win = ArchiveWin.new()
	_archive_win.name = "archive_win"
	_archive_win.setup_archive(graph, case_def)
	_archive_win.position = Vector2(458, 84)
	_archive_win.time_selected.connect(_on_archive_time)
	_archive_win.closed.connect(func(): _archive_win = null)
	_desk.add_child(_archive_win)
	_archive_win.move_to_front()
	_clear_archive_new()
	for sid in graph.timeline_known():
		graph.clear_fresh(graph.scene_key(String(sid)))


func _on_archive_time(tid: String) -> void:
	_select_time(tid)


func _try_memory_combo(tool_key: String, target_key: String, before: Dictionary) -> bool:
	if graph == null or case_def == null or graph.time == GraphState.PRESENT_TIME:
		return false
	var tool := graph.node(tool_key)
	var target := graph.node(target_key)
	if tool.is_empty() or target.is_empty():
		return false
	var who: Dictionary = {}
	var where: Dictionary = {}
	var where_key := ""
	if String(tool["kind"]) == "char":
		who = tool
	elif String(target["kind"]) == "char":
		who = target
	if String(tool["kind"]) == "loc":
		where = tool
		where_key = tool_key
	elif String(target["kind"]) == "loc":
		where = target
		where_key = target_key
	if who.is_empty() or where.is_empty():
		return false
	var mem := case_def.memory_for(graph.time, String(who["id"]), String(where["id"]))
	graph.tried[tool_key + ">" + target_key] = true
	if mem != null:
		_open_memory_play(mem, where_key)
		var title := mem.title if mem.title != "" else mem.id
		_show_toast("想起了一段回忆：" + title)
	else:
		_show_toast("「%s」里没有「%s」的回忆" % [String(where["label"]), String(who["label"])], true)
	_commit(before)
	_relayout()
	return true


## 换档 = 改 graph.time → 收掉锚在画布上的浮层 → 带出那天的登场人物 → 重算可见性。
func _select_time(tid: String) -> bool:
	if graph == null or case_def == null:
		return false
	if tid != GraphState.PRESENT_TIME and not case_def.is_time_id(tid):
		return false
	if graph.time == tid:
		if tid != GraphState.PRESENT_TIME:
			_open_time_card(tid)
		return true
	_close_time_transients()
	graph.time = tid
	_selected = ""
	graph.selected = ""
	if tid != GraphState.PRESENT_TIME:
		graph.spawn_mem_cast(tid)
	_sync_cards_for_time()
	_apply_hidden()
	_sync_time_crumb()
	_open_time_card_once(tid)
	_autosave()
	return true


func _close_time_transients() -> void:
	if _pw_pop != null and is_instance_valid(_pw_pop):
		_pw_pop.queue_free()
	_pw_pop = null
	_pw_ctx = {}
	if _narr != null and is_instance_valid(_narr):
		_narr.queue_free()
	_narr = null
	_close_mem_card()
	_close_chat()


## 把图上已有、但还没上过画布的实体补成卡片；已存在的只刷新（时刻切换不重排）。
func _sync_cards_for_time() -> void:
	for key in graph.nodes.keys():
		var n := graph.node(String(key))
		if n.is_empty() or String(n["kind"]) == "time":
			continue
		if _cards.has(String(key)):
			(_cards[String(key)] as NodeCard).refresh()
		else:
			_spawn_card(String(key))


func _sync_time_crumb() -> void:
	if graph.time != GraphState.PRESENT_TIME:
		_set_crumb(_case_label() + " // " + graph.time_label_of())
		return
	var sid := graph.last_scene
	if sid != "":
		_set_crumb(_case_label() + " // " + case_def.scene_title(sid))
	else:
		_set_crumb(_case_label() + " // " + graph.time_label_of())


## 每档回忆的放映卡只自动放一遍；重放走档案里点当前档。
func _open_time_card_once(tid: String) -> void:
	if tid == GraphState.PRESENT_TIME or not case_def.is_time_id(tid):
		return
	if bool(graph.card_seen.get(tid, false)):
		return
	graph.card_seen[tid] = true
	_open_time_card(tid)
	_autosave()


func _open_time_card(tid: String) -> void:
	if tid == GraphState.PRESENT_TIME or not case_def.is_time_id(tid):
		return
	_close_mem_card()
	_mem_card = MemCard.new()
	_mem_card.name = "mem_card"
	_mem_card.setup_memory("MEMORY // " + case_def.time_label_of(tid), _memory_lines(tid))
	_mem_card.closed.connect(_on_mem_closed)
	_desk.add_child(_mem_card)
	_anchor_memory_card(_mem_card, tid)
	_mem_card.move_to_front()


## 放映卡正文 = 日期场景正文（按行拆）+ 该场景里各角色当天的 sceneTalks。
func _memory_lines(tid: String) -> Array:
	var out: Array = []
	var s := case_def.scene_of(tid)
	if s == null:
		return out
	var body := s.content if s.content.strip_edges() != "" else s.desc
	for raw in case_def.strip_tags(body).split("\n"):
		var line := String(raw).strip_edges()
		if line != "":
			out.append(line)
	for tag in case_def.tags_of(s.content):
		if String(tag["kind"]) != "char":
			continue
		var cid := String(tag["id"])
		if cid == "CHARS_TEC":
			continue
		var ch := case_def.char_of(cid)
		if ch == null:
			continue
		for st in ch.scene_talks:
			if st == null or st.scene == null or st.scene.id != tid:
				continue
			for raw in st.lines:
				var talk_line := case_def.strip_tags(String(raw)).strip_edges()
				if talk_line != "":
					out.append("——%s：%s" % [ch.name, talk_line])
	return out


func _memory_play_lines(mem: MemoryDef) -> Array:
	var out: Array = []
	for line in mem.script_lines:
		if line == null:
			continue
		var text := case_def.strip_tags(line.text).strip_edges()
		if text == "":
			continue
		var kind := "say" if line.kind == "say" else "narr"
		var who_id := line.who.id if line.who != null else ""
		var who_name := line.who.name if line.who != null else ""
		out.append({"t": kind, "text": text, "who": who_id, "name": who_name})
	return out


func _open_memory_play(mem: MemoryDef, where_key: String) -> void:
	if mem == null:
		return
	_close_mem_card()
	_mem_card = MemCard.new()
	_mem_card.name = "mem_card"
	var title := mem.title if mem.title != "" else mem.id
	_mem_card.setup_play("MEMORY // " + title, _memory_play_lines(mem), 420, 300)
	_mem_card.closed.connect(_on_mem_closed)
	_desk.add_child(_mem_card)
	_anchor_card_to(_mem_card, where_key)
	_mem_card.move_to_front()


## 锚在该时刻的发生地点上方；上方放不下就放下面，再整体钳进桌面。
func _anchor_memory_card(card: MemCard, tid: String) -> void:
	var place := case_def.mem_place_of(tid)
	_anchor_card_to(card, graph.scene_key(place.id) if place != null else "")


func _anchor_card_to(card: MemCard, node_key: String) -> void:
	if card == null:
		return
	var area := Vector2(1280.0, 800.0 - HEADER_H)
	var pos := Vector2(700.0, 290.0)
	var nc := _cards.get(node_key) as NodeCard
	if nc != null and is_instance_valid(nc) and nc.visible:
		var target := nc.get_global_rect()
		var origin := _desk.get_global_rect().position
		pos.x = target.position.x - origin.x + (target.size.x - card.size.x) * 0.5
		var above := target.position.y - origin.y - card.size.y - 14.0
		if above >= 8.0:
			pos.y = above
		else:
			pos.y = target.position.y - origin.y + target.size.y + 14.0
	pos.x = clampf(pos.x, MEM_CARD_MIN_X, area.x - card.size.x - 8.0)
	pos.y = clampf(pos.y, 8.0, area.y - card.size.y - 8.0)
	card.position = pos


func _close_mem_card() -> void:
	if _mem_card != null and is_instance_valid(_mem_card):
		_mem_card.queue_free()
	_mem_card = null


func _on_mem_closed() -> void:
	_mem_card = null


func _close_chat() -> void:
	if _chat_win != null and is_instance_valid(_chat_win):
		_chat_win.queue_free()
	_chat_win = null


func _on_chat_closed() -> void:
	_chat_win = null


## 对话窗固定贴右上（Web `.chat-win`：right 18 / top 72；desk 已让出 header，再减 PAD 14）。
func _open_chat(entry: DialogueDef, ids: Array) -> bool:
	if entry == null or case_def == null:
		return false
	_close_chat()
	_chat_win = ChatWindow.new()
	_chat_win.name = "chat_win"
	_chat_win.setup_chat(entry, ids, case_def)
	_chat_win.closed.connect(_on_chat_closed)
	_desk.add_child(_chat_win)
	_chat_win.position = Vector2(858, 58)
	_chat_win.z_index = 30
	_chat_win.move_to_front()
	return true


func _open_monologue(char_id: String) -> bool:
	if dialogues == null:
		return false
	var entry := dialogues.monologue_of(char_id)
	if entry == null:
		return false
	return _open_chat(entry, [char_id])


func _try_dialogue_combo(tool_key: String, target_key: String) -> bool:
	if dialogues == null:
		return false
	var a := graph.node(tool_key)
	var b := graph.node(target_key)
	if a.is_empty() or b.is_empty():
		return false
	if String(a["kind"]) != "char" or String(b["kind"]) != "char":
		return false
	var ids := [String(a["id"]), String(b["id"])]
	var entry := dialogues.lookup(ids)
	if entry == null:
		entry = dialogues.fallback(ids)
	return _open_chat(entry, ids)


func _chat_drop_hit(at_global: Vector2) -> bool:
	var chat := dbg_chat()
	return chat != null and chat.get_global_rect().has_point(at_global)


func _chat_drop(key: String) -> bool:
	var chat := dbg_chat()
	if chat == null or graph == null:
		return false
	var n := graph.node(key)
	if n.is_empty():
		return false
	return chat.drop_node(String(n["kind"]), String(n["id"]))


func _mark_archive_new() -> void:
	_archive_new = true
	if _archive_badge != null:
		_archive_badge.visible = true


func _clear_archive_new() -> void:
	_archive_new = false
	if _archive_badge != null:
		_archive_badge.visible = false


## 极简布局：场景卡在前，实体随后，四列网格（P1 换成真正的分层排布 + 连线）
func _relayout() -> void:
	var order: Array = []
	# 1) 当前切片场景的 loc 卡最先
	var first_loc := graph.scene_key(SLICE_SCENE)
	if _cards.has(first_loc):
		order.append(first_loc)
	# 2) 其余 loc 卡
	for key in _cards.keys():
		var n := graph.node(key)
		if n.get("kind", "") == "loc" and key != first_loc:
			order.append(key)
	# 3) 实体（物品 / 人物 / 线索），按 key 稳定排序
	var ents: Array = []
	for key in _cards.keys():
		if not order.has(key):
			ents.append(key)
	ents.sort()
	order.append_array(ents)

	for i in order.size():
		var card: NodeCard = _cards[order[i]]
		var col := i % 4
		var row := int(i / 4)
		card.position = Vector2(26.0 + col * 178.0, 20.0 + row * 78.0)


# ── TEC ─────────────────────────────────────────────────────────────────

func _tec_key(target: String) -> String:
	if target.contains(":"):
		var parts := target.split(":", true, 1)
		if parts.size() == 2:
			return graph.key_of(parts[0], parts[1])
		return target
	return graph.scene_key(target)


func _open_tec() -> void:
	if not _require_case():
		return
	if _tec == null:
		return
	_tec.visible = true
	_tec.move_to_front()
	_tec_min = false
	_tec_dot = false
	if _tec_chip != null:
		_tec_chip.visible = false


func _close_tec() -> void:
	if _tec == null:
		return
	_tec.visible = false
	_tec_min = false
	if _tec_chip != null:
		_tec_chip.visible = false


func _minimize_tec() -> void:
	if _tec == null or not _tec.visible:
		return
	_tec.visible = false
	_tec_min = true
	_sync_tec_chip()


func _hide_tec(reset: bool = false) -> void:
	if _tec == null:
		return
	_tec.cancel_analysis()
	_tec.visible = false
	if reset:
		_tec.reset_tec()
	_tec_min = false
	_tec_dot = false
	_tec_before = {}
	if _tec_chip != null:
		_tec_chip.visible = false


func _toggle_tec() -> void:
	if not _require_case():
		return
	if _tec.visible:
		_close_tec()
	else:
		_open_tec()


func _sync_tec_chip() -> void:
	if _tec_chip == null:
		return
	if not _tec_min:
		_tec_chip.visible = false
		return
	_tec_chip.visible = true
	_tec_chip.move_to_front()
	if _tec.is_analyzing():
		_tec_chip.set_analyzing(_tec.target_label(), _tec.progress())
	else:
		_tec_chip.set_idle(_tec_dot)


func _tec_drop_hit(at_global: Vector2) -> bool:
	if _tec_btn != null and _tec_btn.get_global_rect().has_point(at_global):
		return true
	if _tec.visible and _tec.avatar_global_rect().has_point(at_global):
		return true
	if _tec_chip != null and _tec_chip.visible and _tec_chip.get_global_rect().has_point(at_global):
		return true
	return false


func _start_tec_analysis(key: String) -> bool:
	if not _require_case() or _tec == null:
		return false
	key = _tec_key(key)
	var n := graph.node(key)
	if n.is_empty():
		return false
	if String(n["kind"]) == "clue":
		_show_toast("线索节点不需要再让 TEC 分析", true)
		return false
	if _tec.is_analyzing():
		_show_toast("TEC 正在分析中，请稍候…", true)
		return false
	if not _tec.visible and not _tec_min:
		_open_tec()
	return _tec.analyze(key, String(n.get("label", key)))


func _on_tec_analysis_started(_target: String, _label: String) -> void:
	_tec_before = _save.snapshot() if _save != null else {}
	_tec_dot = false
	if _tec_min:
		_sync_tec_chip()


func _on_tec_analysis_progress(ratio: float) -> void:
	if _tec_min and _tec_chip != null:
		_tec_chip.set_analyzing(_tec.target_label(), ratio)


func _capture_text_clues(text: String, from_key: String = "") -> Array:
	var got: Array = []
	for tag in case_def.tags_of(text):
		if tag["kind"] != "clue":
			continue
		var cid := String(tag["id"])
		if graph.captured.has(cid):
			continue
		got.append(graph.capture_clue(cid, from_key))
	return got


func _refresh_clue_keys(keys: Array) -> void:
	if keys.is_empty():
		return
	for key in keys:
		_refresh_or_spawn_card(String(key))
	_relayout()


func _hidden_clue_of(kind: String, id: String) -> HiddenClueDef:
	match kind:
		"loc", "time":
			var s := case_def.scene_of(id)
			return s.hidden_clue if s != null else null
		"item":
			var it := case_def.item_of(id)
			return it.hidden_clue if it != null else null
		"char":
			var ch := case_def.char_of(id)
			return ch.hidden_clue if ch != null else null
	return null


func _capture_node_hidden_clues(kind: String, id: String, host_key: String) -> Dictionary:
	var hc := _hidden_clue_of(kind, id)
	if hc == null:
		return {"keys": [], "names": [], "text": ""}
	var got: Array = []
	var names: Array = []
	var seen := {}
	for clue in hc.clues:
		if clue == null or graph.captured.has(clue.id) or seen.has(clue.id):
			continue
		seen[clue.id] = true
		got.append(graph.capture_clue(clue.id, host_key))
		names.append(clue.label)
	for tag in case_def.tags_of(hc.text):
		var cid := String(tag["id"])
		if tag["kind"] != "clue" or graph.captured.has(cid) or seen.has(cid):
			continue
		seen[cid] = true
		got.append(graph.capture_clue(cid, host_key))
		names.append(case_def.label_of("clue", cid))
	_refresh_clue_keys(got)
	return {"keys": got, "names": names, "text": case_def.strip_tags(hc.text)}


## TEC 解读完成后捕获 hiddenClue（场景 / 物品同一套字段；当前先接场景分析链路）
func _capture_hidden_clue(scene_id: String) -> void:
	var kind := graph.normalize_kind("loc", scene_id)
	var host := graph.key_of(kind, scene_id)
	var res := _capture_node_hidden_clues(kind, scene_id, host)
	if res["keys"].is_empty():
		return
	_show_toast("捕获线索：" + "、".join(res["names"]))


func _tec_talk_lines(sid: String) -> Array:
	var tec := case_def.char_of("CHARS_TEC")
	if tec == null:
		return []
	for st in tec.scene_talks:
		if st != null and st.scene != null and st.scene.id == sid:
			return st.lines
	return []


func _tec_reaction(key: String) -> bool:
	var n := graph.node(key)
	if n.is_empty() or _tec == null:
		return false
	var tec := case_def.char_of("CHARS_TEC")
	if tec == null:
		return false
	var id := String(n["id"])
	var raw := ""
	for r in tec.item_reactions:
		if r != null and ((r.item != null and r.item.id == id) or r.trigger_id == id):
			raw = r.text
			break
	if raw == "":
		for r in tec.clue_reactions:
			if r != null and ((r.clue != null and r.clue.id == id) or r.trigger_id == id):
				raw = r.text
				break
	if raw == "":
		_tec.append_line("关于「%s」，我暂时没有更多线索。试试把它和别的节点组合。" % String(n["label"]))
		graph.tried[key + ">tec-dock"] = true
		return false
	_tec.append_line("（分析 %s）%s" % [String(n["label"]), case_def.strip_tags(raw)])
	var got := _capture_text_clues(raw)
	_refresh_clue_keys(got)
	return true


func _tec_talk() -> void:
	if not _require_case() or _tec == null:
		return
	if not _tec.visible:
		_open_tec()
	var tec := case_def.char_of("CHARS_TEC")
	var queue: Array = tec.talk_queue if tec != null else []
	if queue.is_empty():
		_tec.append_line("（把节点拖到我身上，我来分析）", TecTheme.MUTED)
		return
	var idx := int(graph.tec_prog.get("_def", 0))
	if idx >= queue.size():
		return
	graph.tec_prog["_def"] = idx + 1
	_tec.append_line(case_def.strip_tags(String(queue[idx])))
	_autosave()


func _on_tec_analysis_done(target: String) -> void:
	var key := _tec_key(target)
	var n := graph.node(key)
	if n.is_empty():
		_tec_before = {}
		return
	var kind := String(n["kind"])
	var id := String(n["id"])
	var label := String(n.get("label", id))
	if GraphState.is_scene_kind(kind):
		var talks := _tec_talk_lines(id)
		var prog := int(graph.tec_prog.get(id, 0))
		var unread := talks.size() - prog
		var hidden := _capture_node_hidden_clues(kind, id, key)
		if not (hidden["keys"] as Array).is_empty():
			_tec.append_line("分析完成：「%s」中提取到线索 —— %s。（已落到画布上，可自由拖动）"
				% [label, "、".join(hidden["names"])])
			if String(hidden["text"]) != "":
				_tec.append_line(String(hidden["text"]))
			_show_toast("捕获线索：" + "、".join(hidden["names"]))
		elif unread <= 0:
			_tec.append_line("分析完成：「%s」中没有可以捕获的线索。" % label)
		if not talks.is_empty() and unread > 0:
			var line := String(talks[prog])
			graph.tec_prog[id] = prog + 1
			_tec.append_line(case_def.strip_tags(line))
			_refresh_clue_keys(_capture_text_clues(line))
		elif not talks.is_empty():
			_tec.append_line("「%s」的档案已经全部解读完毕。" % label)
	else:
		_tec_reaction(key)
		var ent_hidden := _capture_node_hidden_clues(kind, id, key)
		if not (ent_hidden["keys"] as Array).is_empty():
			_tec.append_line("分析完成：「%s」中提取到线索 —— %s。（已落到画布上，可自由拖动）"
				% [label, "、".join(ent_hidden["names"])])
			if String(ent_hidden["text"]) != "":
				_tec.append_line(String(ent_hidden["text"]))
			_show_toast("捕获线索：" + "、".join(ent_hidden["names"]))
	if _tec_min:
		_tec_dot = true
		_sync_tec_chip()
	_commit(_tec_before)
	_tec_before = {}


# ── 测试钩子（与 Web 版 window.__* 同名，便于把操作脚本逐行翻译）──────────

func dbg_state() -> Dictionary:
	return {
		"nodes": _cards.keys(),
		"explored": graph.explored.keys(),
		"captured": graph.captured.keys(),
		"tec_prog": graph.tec_prog.duplicate(),
		"lit": _lit_map(),
		"selected": _selected,
		"cards": _cards.size(),
		"collapsed": graph.collapsed.keys(),
		"stored": graph.stored.keys(),
		"hidden": graph.hidden.keys(),
		"installed": _installed_map(),
		"matrix": graph.matrix.duplicate(true),
		"matrix_ids": graph.matrix_ids(),
		"endings": graph.endings.keys(),
		"ending_visible": _ending.visible if _ending != null else false,
		"ending_id": _last_ending_id,
		"can_undo": _save.can_undo() if _save != null else false,
		"history": _save.history.size() if _save != null else 0,
	}


func _installed_map() -> Dictionary:
	var out := {}
	for k in graph.nodes.keys():
		var n: Dictionary = graph.nodes[k]
		if n["kind"] == "item" and not (n.get("installed", {}) as Dictionary).is_empty():
			out[k] = (n["installed"] as Dictionary).keys()
	return out


func _lit_map() -> Dictionary:
	var out := {}
	for k in graph.nodes.keys():
		var n: Dictionary = graph.nodes[k]
		if n["kind"] == "item":
			out[String(n["id"])] = bool(n.get("lit", false))
	return out


func dbg_expand(sid: String) -> void:
	_expand_scene(sid, false)


func dbg_combo(tool_id: String, target_id: String) -> Dictionary:
	var tkind := CaseLoader.kind_of_ref(tool_id)
	var okind := CaseLoader.kind_of_ref(target_id)
	return combos.use_item(graph.key_of(tkind, tool_id), graph.key_of(okind, target_id))


## 双击某张卡（跑第一条命令 / 展开容器，与真实双击同一条路）
func dbg_activate(key: String) -> void:
	_on_card_activated(key)


## 建节点并上卡片（等价 Web 的 __ensure）
func dbg_ensure(kind: String, id: String) -> String:
	var n := graph.add_node(kind, id)
	_spawn_card(String(n["key"]))
	_relayout()
	return String(n["key"])


func dbg_pw_open(node_key: String) -> void:
	_open_password(node_key)


func dbg_password(node_key: String, value: String) -> void:
	# 已经为这个节点开着窗就直接提交（模拟「在同一个弹窗里改输入再点确定」）
	if _pw_pop == null or not is_instance_valid(_pw_pop) or String(_pw_ctx.get("node_key", "")) != node_key:
		_open_password(node_key)
	_submit_password(value)


func dbg_toggle_light(id: String) -> Dictionary:
	return combos.toggle_light(graph.key_of("item", id))


## 选中某个节点（等价点一下卡）
func dbg_select(key: String) -> void:
	_selected = key
	graph.selected = key


## 打开某个收纳窗
func dbg_open_storage(kind: String) -> void:
	_toggle_storage(kind)


func dbg_tec_analyze(sid: String) -> void:
	_start_tec_analysis(_tec_key(sid))


func dbg_tec_finish() -> int:
	return _tec.done_count() if _tec != null else 0


func dbg_tec_complete() -> void:
	if _tec != null:
		_tec.finish_now()


func dbg_tec_open() -> void:
	_open_tec()


func dbg_tec_close() -> void:
	_close_tec()


func dbg_tec_minimize() -> void:
	_minimize_tec()


func dbg_tec_win() -> TecWindow:
	return _tec


func dbg_tec_chip() -> TecChip:
	return _tec_chip


func dbg_tec_talk() -> void:
	_tec_talk()


func dbg_tec_analyze_key(key: String) -> bool:
	return _start_tec_analysis(key)


func dbg_tec_drop_hit(at_global: Vector2) -> bool:
	return _tec_drop_hit(at_global)


func dbg_tec_drop(key: String, at_global: Vector2) -> void:
	_on_card_drag_released(key, at_global)


func dbg_tec_icon_rect() -> Rect2:
	return _tec_btn.get_global_rect() if _tec_btn != null else Rect2()


func dbg_tec_info() -> Dictionary:
	var win := {}
	if _tec != null:
		win = _tec.dbg_status()
	var chip := {}
	if _tec_chip != null:
		chip = _tec_chip.dbg_state()
	return {
		"visible": _tec.visible if _tec != null else false,
		"min": _tec_min,
		"dot": _tec_dot,
		"chip_visible": _tec_chip.visible if _tec_chip != null else false,
		"win": win,
		"chip": chip,
	}


# ── 档案 / 放映卡测试钩子（P2.3）──────────────────────────────────────

func dbg_open_archive() -> ArchiveWin:
	if _archive_win == null or not is_instance_valid(_archive_win):
		_toggle_archive()
	return _archive_win


func dbg_archive_press(tid: String) -> bool:
	if _archive_win == null or not is_instance_valid(_archive_win):
		return false
	return _archive_win.press_time(tid)


func dbg_archive_new() -> bool:
	return _archive_new


# ── 多人对话 / 独白测试钩子（P2.4）────────────────────────────────────

func dbg_chat() -> ChatWindow:
	if _chat_win != null and is_instance_valid(_chat_win):
		return _chat_win
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
	return _chat_drop(key)


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
	_close_chat()


func dbg_open_dialogue(id: String, ids: Array) -> bool:
	if dialogues == null:
		return false
	return _open_chat(dialogues.by_id(id), ids)


func dbg_open_monologue(char_id: String) -> bool:
	return _open_monologue(char_id)


func dbg_dialogues() -> DialogueSystem:
	return dialogues


func dbg_time() -> String:
	return graph.time if graph != null else ""


func dbg_time_label() -> String:
	return graph.time_label_of() if graph != null else ""


func dbg_time_known() -> Array:
	return graph.timeline_known() if graph != null else []


func dbg_set_time(tid: String) -> bool:
	return _select_time(tid)


func dbg_mem_card() -> MemCard:
	return _mem_card


func dbg_mem_advance() -> bool:
	return _mem_card.advance() if _mem_card != null and is_instance_valid(_mem_card) else false


func dbg_close_mem() -> void:
	_close_mem_card()


func dbg_card_visible(key: String) -> bool:
	var card: NodeCard = _cards.get(key, null)
	return card != null and card.visible


func dbg_card_pos(key: String) -> Vector2:
	var card: NodeCard = _cards.get(key, null)
	return card.position if card != null else Vector2.ZERO


func dbg_mem_pos() -> Vector2:
	return _mem_card.position if _mem_card != null and is_instance_valid(_mem_card) else Vector2.ZERO


func dbg_combo_ui(tool_id: String, target_id: String) -> void:
	if graph == null:
		return
	_on_card_combo(_dbg_node_key(tool_id), _dbg_node_key(target_id))


func _dbg_node_key(id: String) -> String:
	for key in graph.nodes.keys():
		var n := graph.node(String(key))
		if String(n.get("id", "")) == id and String(n.get("kind", "")) != "time":
			return String(key)
	return graph.key_of(CaseLoader.kind_of_ref(id), id)


func dbg_toast_text() -> String:
	return _toast_label.text if _toast_label != null else ""


# ── 推演桌布测试钩子（P1.4）────────────────────────────────────────────

func dbg_open_matrix() -> MatrixWin:
	if _matrix_win == null or not is_instance_valid(_matrix_win):
		_toggle_matrix()
	return _matrix_win


func dbg_matrix_assign(key: String) -> bool:
	return _assign_to_matrix(key)


func dbg_matrix_win() -> MatrixWin:
	return _matrix_win if _matrix_win != null and is_instance_valid(_matrix_win) else null


func dbg_matrix_charge() -> void:
	if _matrix_win != null and is_instance_valid(_matrix_win):
		_matrix_win.finish_charge()


func dbg_matrix_take(key: String) -> void:
	_on_matrix_took(key)


func dbg_ending() -> EndingOverlay:
	return _ending


func dbg_ending_id() -> String:
	return _last_ending_id


func dbg_ending_finish() -> void:
	if _ending != null:
		_ending.finish_now()


func dbg_confirm_ending() -> void:
	if _ending == null or not _ending.visible:
		return
	_ending.visible = false
	_ending.finished.emit()


# ── 音乐播放器 / 花园测试钩子（P2.5）──────────────────────────────────

func dbg_music_icon_visible() -> bool:
	return _music_btn != null and _music_btn.visible


func dbg_garden_icon_visible() -> bool:
	return _garden_btn != null and _garden_btn.visible


func dbg_garden_badge_text() -> String:
	if _garden_badge == null or not _garden_badge.visible:
		return ""
	var l: Label = _garden_badge.get_node_or_null("Label")
	return l.text if l != null else ""


func dbg_music_win() -> MusicWin:
	return _music_win if _music_win != null and is_instance_valid(_music_win) else null


func dbg_music_dock() -> MusicDock:
	return _music_dock if _music_dock != null and is_instance_valid(_music_dock) else null


func dbg_click_music_icon() -> void:
	_toggle_music_win()


func dbg_open_music() -> MusicWin:
	_open_music()
	return dbg_music_win()


func dbg_minimize_music() -> void:
	_minimize_music()


func dbg_restore_music() -> void:
	_restore_music()


func dbg_close_music() -> void:
	_on_music_closed()


func dbg_music_play(id: String) -> bool:
	var w := dbg_music_win()
	if w == null:
		w = dbg_open_music()
	return w.play_track(id) if w != null else false


func dbg_music_toggle() -> bool:
	return _music_win.toggle_current() if dbg_music_win() != null else false


func dbg_music_stop() -> void:
	_stop_music()


func dbg_music_state() -> Dictionary:
	var w := dbg_music_win()
	if w == null:
		return {}
	var s := w.state()
	s["win_visible"] = w.visible
	s["dock_visible"] = _music_dock != null and is_instance_valid(_music_dock) and _music_dock.visible
	return s


func dbg_garden_win() -> GardenWin:
	return _garden_win if _garden_win != null and is_instance_valid(_garden_win) else null


func dbg_open_garden() -> GardenWin:
	if _garden_win == null or not is_instance_valid(_garden_win):
		_open_garden()
	return dbg_garden_win()


func dbg_close_garden() -> void:
	if _garden_win != null and is_instance_valid(_garden_win):
		_garden_win.queue_free()
	_garden_win = null


func dbg_garden_state() -> Dictionary:
	var w := dbg_garden_win()
	if w != null:
		return w.dbg_state()
	return {}


func dbg_garden_icon_rect() -> Rect2:
	return _garden_btn.get_global_rect() if _garden_btn != null else Rect2()


func dbg_drop_seed(at_global: Vector2) -> bool:
	return _drop_seed(at_global)


func dbg_play_true_ending() -> void:
	if _ending == null:
		return
	_last_ending_id = "TRUE_E"
	_ending.play(case_def.ending_by_id("TRUE_E"))


func dbg_touch_garden_plot(idx: int, at_ms: int) -> bool:
	if graph == null or not (graph.garden is Dictionary):
		return false
	var plots: Array = graph.garden.get("plots", [])
	if idx < 0 or idx >= plots.size():
		return false
	plots[idx]["at"] = at_ms
	plots[idx]["hit"] = false
	if _garden_win != null and is_instance_valid(_garden_win):
		_garden_win.refresh()
	return true


# ── 案件系统测试钩子（P2.1）────────────────────────────────────────────

func dbg_use_temp_progress(path: String) -> void:
	_progress_path = path
	_progress_read_only = false
	_catalog.clear_progress(path)
	_catalog = CaseCatalog.new(path)
	_update_case_park_ui()


func dbg_case_info() -> Dictionary:
	return {
		"id": _active_case,
		"open": _case_open,
		"held": _case_held,
		"dock": _case_docked,
		"dock_visible": _dock_card != null and _dock_card.visible,
		"badge_visible": _map_badge != null and _map_badge.visible,
		"map_open": _map_win != null and is_instance_valid(_map_win),
		"title": _case_win.title if _case_win != null else "",
		"unlocked": _catalog.unlocked.duplicate(),
		"completed": _catalog.completed.duplicate(),
		"last": _catalog.last,
		"progress_path": _progress_path,
	}


func dbg_park_case(where: String) -> bool:
	return _park_case(where)


func dbg_reopen_case() -> void:
	_reopen_case()


func dbg_open_case_map() -> CaseMapWin:
	if _map_win == null or not is_instance_valid(_map_win):
		_toggle_case_map()
	return _map_win


func dbg_case_map_win() -> CaseMapWin:
	return _map_win if _map_win != null and is_instance_valid(_map_win) else null


func dbg_case_map_click(id: String) -> bool:
	var w := dbg_case_map_win()
	return w.dbg_click(id) if w != null else false


func dbg_case_map_state(id: String) -> String:
	var w := dbg_case_map_win()
	return w.dbg_row_state(id) if w != null else ""


func dbg_enter_case(id: String) -> bool:
	return _enter_case(id)


func dbg_catalog_unlock(id: String) -> bool:
	var ok := _catalog.unlock(id)
	_update_case_park_ui()
	return ok


func dbg_catalog() -> CaseCatalog:
	return _catalog


func dbg_catalog_unlock_next(id: String) -> bool:
	var ok := _catalog.unlock_next(id)
	_update_case_park_ui()
	return ok


# ── 调查员测试钩子（P1.6）──────────────────────────────────────────────

func dbg_use_temp_investigator(path: String) -> void:
	_inv_path = path
	_investigator = Investigator.load_from(path)
	_refresh_chip()


func dbg_clear_investigator() -> void:
	Investigator.clear(_inv_path)
	_investigator = {}
	_refresh_chip()


func dbg_investigator() -> Dictionary:
	return _investigator.duplicate(true)


func dbg_open_intro() -> IntroWin:
	return _open_intro()


func dbg_intro_open() -> bool:
	return _intro != null and is_instance_valid(_intro)


func dbg_open_cert() -> void:
	_open_cert_review()


func dbg_cert_open() -> bool:
	return _cert_win != null and is_instance_valid(_cert_win)


# ── 截图采样（P0 视觉自查：跑一遍切片，按阶段存 PNG 到 docs/）──────────

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[shot] ", path, " ", img.get_width(), "x", img.get_height())


func _shot_flow() -> void:
	await _wait(0.6)
	await _shot("res://docs/p0_1_desktop.png")

	_expand_scene("SCENES_garden", true)
	await _wait(0.5)
	await _shot("res://docs/p0_2_garden.png")

	combos.toggle_light("item:ITEM_shoudiantong")
	if _cards.has("item:ITEM_shoudiantong"):
		_cards["item:ITEM_shoudiantong"].refresh()
	_on_card_combo("item:ITEM_shoudiantong", "item:ITEM_something")
	await _wait(0.5)
	await _shot("res://docs/p0_3_body.png")

	_toggle_tec()
	_start_tec_analysis("loc:SCENES_body")
	await _wait(1.1)                      # 分析进行中（真实 5–8 秒，这里取中段）
	await _shot("res://docs/p0_4_tec.png")
	_tec.finish_now()
	await _wait(0.25)
	# P1.4 起 TEC 分析不再直接触发结局：这里仍按 P0 基线直接放 TRUE_E，只为保留对拍图
	_ending.play(case_def.ending_by_id("TRUE_E"))
	await _wait(0.25)
	await _shot("res://docs/p0_5_ending.png")
	_ending.finish_now()
	await _wait(0.25)
	await _shot("res://docs/p0_6_ending_full.png")

	# ── P1 新特性：容器展开 / 选项节点 / 密码弹窗 / 折叠 ──
	_ending.visible = false
	_start_slice()
	await _wait(0.3)
	_expand_scene("SCENES_garden", false)
	await _wait(0.2)
	_ensure_card("item", "ITEM_shuzhuo")
	_toggle_container("item", "ITEM_shuzhuo")
	await _wait(0.35)
	await _shot("res://docs/p1_1_container.png")

	_toggle_container("item", "ITEM_chouti")    # choice：两个抽屉一起上画布
	await _wait(0.35)
	await _shot("res://docs/p1_2_choice.png")

	_ensure_card("item", "ITEMS_jzmh")
	_open_password(graph.key_of("item", "ITEMS_jzmh"))
	await _wait(0.35)
	await _shot("res://docs/p1_3_password.png")
	_submit_password("0321")
	await _wait(0.35)
	await _shot("res://docs/p1_4_unlocked.png")

	_toggle_container("item", "ITEM_shuzhuo")   # 再双击 = 收起
	await _wait(0.35)
	await _shot("res://docs/p1_5_collapsed.png")

	# ── 收纳三态（P1.2）：证物袋 / 线索册两扇窗 ──
	_start_slice()
	await _wait(0.3)
	_expand_scene("SCENES_garden", false)
	await _wait(0.2)
	_ensure_card("item", "ITEM_taideng")
	dbg_select("item:ITEM_taideng")
	dbg_store("BAG")
	_ensure_card("clue", "CLUES_nm")
	dbg_select("clue:CLUES_nm")
	dbg_store("LEDGER")
	_toggle_storage(GraphState.BAG)
	await _wait(0.35)
	await _shot("res://docs/p1_6_bag.png")

	_toggle_storage(GraphState.LEDGER)
	await _wait(0.35)
	await _shot("res://docs/p1_7_ledger.png")

	# ── 推演桌布（P1.4）：五感归位 → 长按 → 真名遮罩 ──
	var true_e := case_def.ending_by_id("TRUE_E")
	for clue in true_e.recipe:
		_ensure_card("clue", clue.id)
		_assign_to_matrix(graph.key_of("clue", clue.id))
	dbg_open_matrix()
	await _wait(0.4)
	await _shot("res://docs/p1_8_matrix.png")

	dbg_matrix_charge()
	await _wait(0.3)
	dbg_ending_finish()
	await _wait(0.3)
	await _shot("res://docs/p1_9_truename.png")
	quit_app()


func _shot_intro_flow() -> void:
	await _wait(0.4)
	_inv_path = "user://shot_investigator.json"
	Investigator.clear(_inv_path)
	_investigator = {}
	_refresh_chip()
	var w := _open_intro()
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
	_open_cert_review()
	await _wait(0.3)
	await _shot("res://docs/p1_15_cert.png")
	Investigator.clear(_inv_path)
	quit_app()


func _shot_p2_flow() -> void:
	await _wait(0.5)
	_catalog.clear_progress(_progress_path)
	_catalog = CaseCatalog.new(_progress_path)
	_update_case_park_ui()

	dbg_open_case_map()
	await _wait(0.35)
	await _shot("res://docs/p2_1_case_map.png")
	if _map_win != null and is_instance_valid(_map_win):
		_map_win.queue_free()
	_map_win = null

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
	if _map_win != null and is_instance_valid(_map_win):
		_map_win.queue_free()
	_map_win = null

	_reopen_case()
	_start_slice()
	await _wait(0.3)
	_expand_scene("SCENES_body", false)
	_open_tec()
	_tec_talk()
	_tec_talk()
	_hide_toast()
	await _wait(0.35)
	await _shot("res://docs/p2_5_tec_chat.png")

	_start_tec_analysis("loc:SCENES_body")
	await _wait(2.5)
	await _shot("res://docs/p2_6_tec_analysis.png")

	_minimize_tec()
	await _wait(0.35)
	await _shot("res://docs/p2_7_tec_chip.png")

	_tec.finish_now()
	await _wait(0.3)
	_hide_toast()
	await _wait(0.2)
	await _shot("res://docs/p2_8_tec_chip_done.png")

	_open_tec()
	await _wait(0.35)
	await _shot("res://docs/p2_9_tec_archive.png")

	_hide_tec()
	_expand_scene("SCENES_fkjl", false)
	await _wait(0.35)
	_toggle_archive()
	await _wait(0.35)
	await _shot("res://docs/p2_10_archive.png")
	_toggle_archive()
	await _wait(0.15)

	_expand_scene("SCENES_lhsdst", false)
	await _wait(0.2)
	_select_time("SCENES_0602")
	await _wait(0.5)
	_show_mem_lines(3)
	await _wait(0.3)
	await _shot("res://docs/p2_11_memory_card.png")

	_close_mem_card()
	_on_card_combo("char:NPC_FB", "loc:SCENES_garden")
	await _wait(0.3)
	_show_mem_lines(4)
	await _wait(0.35)
	await _shot("res://docs/p2_12_memory_play.png")

	_close_mem_card()
	_select_time("SCENES_0704")
	await _wait(0.5)
	_close_mem_card()
	_hide_toast()
	_on_card_combo("char:CHARS_zs", "char:CHARS_luhengs")
	await _wait(0.35)
	_show_chat_lines(5)
	_hide_toast()
	await _wait(0.35)
	await _shot("res://docs/p2_13_dialogue.png")
	_close_chat()

	var garden := dialogues.by_id("DLG_garden_review") if dialogues != null else null
	_open_chat(garden, ["CHARS_zs", "NPC_FB"])
	await _wait(0.3)
	_chat_win.finish_line()
	_chat_win.advance()
	_chat_win.finish_line()
	_chat_win.advance()
	_hide_toast()
	await _wait(0.35)
	await _shot("res://docs/p2_14_dialogue_join.png")
	_close_chat()

	_open_monologue("CHARS_luhengs")
	await _wait(0.3)
	_show_chat_lines(4)
	_hide_toast()
	await _wait(0.35)
	await _shot("res://docs/p2_15_monologue.png")
	_close_chat()

	# ── P2.5 音乐播放器 / 花园彩蛋 ──
	_ensure_card("item", "ITEMS_changji")
	_ensure_card("item", "ITEMS_cz")
	dbg_combo_ui("ITEMS_cz", "ITEMS_changji")
	_hide_toast()
	var music := dbg_open_music()
	if music != null:
		music.play_track("Air_Bach")
		await _wait(0.2)
		music.seek_ratio(0.25)
	await _wait(0.8)
	await _shot("res://docs/p2_16_music.png")
	_minimize_music()
	await _wait(0.45)
	await _shot("res://docs/p2_17_music_dock.png")
	_restore_music()
	_stop_music()
	_on_music_closed()

	dbg_play_true_ending()
	dbg_confirm_ending()
	await _wait(0.25)
	dbg_open_matrix()
	_hide_toast()
	await _wait(0.4)
	await _shot("res://docs/p2_18_matrix_seed.png")
	if _matrix_win != null and is_instance_valid(_matrix_win):
		_matrix_win.queue_free()
	_matrix_win = null
	var gwin := dbg_open_garden()
	_hide_toast()
	await _wait(0.45)
	await _shot("res://docs/p2_19_garden_seed.png")
	if gwin != null:
		_drop_seed(gwin.field_global_rect().get_center())
		dbg_touch_garden_plot(0, GardenSystem.now_ms_now() - 181000)
		gwin._process(1.1)
		await _wait(0.2)
		gwin.dbg_open_narr(0)
		gwin.dbg_advance_narr()
		_hide_toast()
		await _wait(0.45)
		await _shot("res://docs/p2_20_garden_narr.png")
	quit_app()


func _show_chat_lines(n: int) -> void:
	if _chat_win == null or not is_instance_valid(_chat_win):
		return
	_chat_win.finish_line()
	for i in maxi(0, n - 1):
		if not _chat_win.advance():
			break
		_chat_win.finish_line()


func _show_mem_lines(n: int) -> void:
	if _mem_card == null or not is_instance_valid(_mem_card):
		return
	_mem_card.finish_line()
	for i in maxi(0, n - 1):
		if not _mem_card.advance():
			break
		_mem_card.finish_line()


func _ensure_card(kind: String, id: String) -> void:
	var n := graph.add_node(kind, id)
	_spawn_card(String(n["key"]))
	_relayout()


func quit_app() -> void:
	if _shot_mode() and FileAccess.file_exists(_progress_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_progress_path))
	get_tree().quit()
