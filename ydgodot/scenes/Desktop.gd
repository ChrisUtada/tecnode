extends Control
## 桌面外壳 + 画布 + P0 垂直切片链路
##
## 切片（计划 §三 P0）：花园展开 → 手电筒拖到黑影 → 尸体场景 → TEC 分析计时 → 结局演出。
## 数据直读 `data/case-a001.json`（P0 允许），逻辑全在 core/ 里，本文件只管「搭界面 + 接线」。

const HEADER_H := 52.0
const SLICE_SCENE := "SCENES_garden"
const CARD_PAD := 8.0

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


func _ready() -> void:
	theme = TecTheme.build()
	case_def = CaseLoader.new()
	if not case_def.load_case():
		push_error("案件数据装载失败：" + case_def.load_error)
		return
	_save_enabled = not _has_arg("--shot") and DisplayServer.get_name() != "headless"
	_investigator = Investigator.load_from(_inv_path)
	graph = GraphState.new(case_def)
	combos = ComboSystem.new(case_def, graph)
	_cmds = CommandSystem.new(case_def, graph)
	_build_ui()
	_refresh_chip()
	if _resume_allowed() and _resume_from_save():
		_show_toast("已继续上次进度")
	else:
		_start_slice()
	if _intro_allowed() and _investigator.is_empty():
		_open_intro()
	if _has_arg("--shot"):
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

	_tec = TecWindow.new()
	_tec.name = "tec_win"
	_tec.setup_tec()
	_tec.position = Vector2(845, HEADER_H + 146)
	_tec.visible = false
	_tec.analysis_done.connect(_on_tec_analysis_done)
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

	_crumb = TecTheme.label("案件 A-001", TecTheme.FS_BODY, TecTheme.LINE2)
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
	_case_win.setup("案件 A-001 // 植物学家的花园", 900, 596)
	_case_win.position = Vector2(150, 24)
	_case_win.body.clip_contents = true
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
	for pair in [["TEC", "tec"], ["证物袋", "bag"], ["线索册", "clue"], ["推演桌布", "infer"], ["档案袋", "goto"]]:
		var b := TecTheme.button(String(pair[0]))
		b.custom_minimum_size = Vector2(96, 40)
		b.name = "icon_" + String(pair[1])
		if String(pair[1]) == "tec":
			b.pressed.connect(_toggle_tec)
		elif String(pair[1]) == "bag":
			b.pressed.connect(func(): _toggle_storage(GraphState.BAG))
		elif String(pair[1]) == "clue":
			b.pressed.connect(func(): _toggle_storage(GraphState.LEDGER))
		elif String(pair[1]) == "infer":
			b.pressed.connect(_toggle_matrix)
		else:
			b.pressed.connect(func(): _show_toast("这个东西还没搬过来（P1 再做）"))
		col.add_child(b)


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
	_selected = ""
	graph.selected = ""
	_last_ending_id = ""
	_storage_before = {}
	if _ending != null:
		_ending.visible = false
	if _tec != null:
		_tec.cancel_analysis()
		_tec.visible = false
	if _pw_pop != null and is_instance_valid(_pw_pop):
		_pw_pop.queue_free()
	_pw_pop = null
	_pw_ctx = {}
	if _narr != null and is_instance_valid(_narr):
		_narr.queue_free()
	_narr = null
	if _matrix_win != null and is_instance_valid(_matrix_win):
		_matrix_win.queue_free()
	_matrix_win = null
	if _bag_win != null and is_instance_valid(_bag_win):
		_bag_win.queue_free()
	_bag_win = null
	if _ledger_win != null and is_instance_valid(_ledger_win):
		_ledger_win.queue_free()
	_ledger_win = null


func _reset_case() -> void:
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
	return true


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

	_set_crumb("案件 A-001 // " + case_def.scene_title(sid))
	_show_toast("把「%s」拖到「手电筒」上试试" % case_def.scene_title(sid))
	_relayout()


func _set_crumb(text: String) -> void:
	if _crumb != null:
		_crumb.text = text
	if _case_win != null:
		_case_win.set_title(text)


# ── 调查员 / 开场适性测试 ───────────────────────────────────────────────

func _intro_allowed() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return not _has_arg("--shot") and not _has_arg("--no-intro")


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
	if _pw_pop != null and is_instance_valid(_pw_pop):
		_pw_pop.queue_free()
	_pw_pop = null
	_pw_ctx = {}
	if _narr != null and is_instance_valid(_narr):
		_narr.queue_free()
	_narr = null
	_ending.visible = false
	if _tec != null:
		_tec.cancel_analysis()
		_tec.set_meta("selected_scene", "")
	for key in graph.nodes.keys():
		_spawn_card(String(key))
	_apply_hidden()
	_refresh_matrix_views()
	_last_ending_id = String(graph.endings.keys()[0]) if not graph.endings.is_empty() else ""
	var sid := graph.last_scene
	_set_crumb("案件 A-001 // " + case_def.scene_title(sid) if sid != "" else "案件 A-001")


# ── 卡片 ────────────────────────────────────────────────────────────────

func _spawn_card(key: String) -> NodeCard:
	if _cards.has(key):
		return _cards[key]
	var n := graph.node(key)
	if n.is_empty():
		return null
	var w := GraphState.SCENE_W if n["kind"] == "loc" else GraphState.ENT_W
	var h := GraphState.SCENE_H if n["kind"] == "loc" else GraphState.ENT_H
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
	if _tec != null:
		var n := graph.node(key)
		if n.get("kind", "") == "loc":
			_tec.set_meta("selected_scene", String(n["id"]))


func _on_card_dragged(key: String) -> void:
	_selected = key
	graph.selected = key


## 拖到推演桌布窗口上 = 归位（Web 版 overMatrixDrop 的画布侧入口）
func _on_card_drag_released(key: String, at_global: Vector2) -> void:
	if _matrix_win == null or not is_instance_valid(_matrix_win):
		return
	if _matrix_win.board_global_rect().has_point(at_global):
		_assign_to_matrix(key)


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
		_set_crumb("案件 A-001 // " + case_def.scene_title(id))
	else:
		_show_toast("展开了「%s」" % case_def.label_of(kind, id))
	_commit(before)


## 把图状态的隐藏结论落到卡片上（对齐 Web 的 recomputeHidden：钉住的、跟场外有连线的都不藏）
func _apply_hidden() -> void:
	graph.recompute_hidden()
	for key in _cards.keys():
		(_cards[key] as NodeCard).visible = graph.is_visible(String(key))


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
		_set_crumb("案件 A-001 // " + case_def.scene_title(String(res["next_scene"])))
	_relayout()


# ── 收纳窗（证物袋 / 线索册）────────────────────────────────────────────

func _toggle_storage(kind: String) -> void:
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
		(_cards[key] as NodeCard).visible = true
	_relayout()
	if _bag_win != null and is_instance_valid(_bag_win):
		_bag_win.refresh_store()
	if _ledger_win != null and is_instance_valid(_ledger_win):
		_ledger_win.refresh_store()
	_commit(_storage_before)
	_storage_before = {}


# ── 推演桌布（五感槽位 / 归位 / 长按推演）──────────────────────────────

func _toggle_matrix() -> void:
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
	if _matrix_win != null and is_instance_valid(_matrix_win):
		_matrix_win.play_shock()
	_ending.play(hit)
	_commit(before)


func _refresh_or_spawn_card(key: String) -> void:
	var card: NodeCard = _cards.get(key, null)
	if card == null:
		card = _spawn_card(key)
	if card != null:
		card.visible = graph.is_visible(key)
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
	var had := _cards.has(graph.key_of("loc", sid))
	for k in fresh:
		_spawn_card(String(k))
	if not had:
		_spawn_card(graph.key_of("loc", sid))
	if _cards.has(graph.key_of("loc", sid)):
		_cards[graph.key_of("loc", sid)].refresh()
	_relayout()
	if show_narr:
		_show_narr(sid)
	_set_crumb("案件 A-001 // " + case_def.scene_title(sid))


func _show_narr(sid: String) -> void:
	var n := graph.node(graph.key_of("loc", sid))
	if n.is_empty():
		return
	var body := case_def.text_of("loc", sid)
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


## 极简布局：场景卡在前，实体随后，四列网格（P1 换成真正的分层排布 + 连线）
func _relayout() -> void:
	var order: Array = []
	# 1) 当前切片场景的 loc 卡最先
	var first_loc := graph.key_of("loc", SLICE_SCENE)
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

func _toggle_tec() -> void:
	_tec.visible = not _tec.visible
	if _tec.visible:
		_tec.move_to_front()
		var n := graph.node(_selected)
		if n.get("kind", "") == "loc":
			_tec.set_meta("selected_scene", String(n["id"]))


func _on_tec_analysis_done(scene_id: String) -> void:
	var before := _save.snapshot()
	graph.tec_prog[scene_id] = int(graph.tec_prog.get(scene_id, 0)) + 1
	_capture_hidden_clue(scene_id)
	_commit(before)


## TEC 解读完成后捕获 hiddenClue（场景 / 物品同一套字段；当前先接场景分析链路）
func _capture_hidden_clue(scene_id: String) -> void:
	var s := case_def.scene_of(scene_id)
	if s == null or s.hidden_clue == null:
		return
	var host := graph.key_of("loc", scene_id)
	var got: Array = []
	var seen := {}
	for clue in s.hidden_clue.clues:
		if clue == null or graph.captured.has(clue.id) or seen.has(clue.id):
			continue
		seen[clue.id] = true
		got.append(graph.capture_clue(clue.id, host))
	for tag in case_def.tags_of(s.hidden_clue.text):
		var cid := String(tag["id"])
		if tag["kind"] != "clue" or graph.captured.has(cid) or seen.has(cid):
			continue
		seen[cid] = true
		got.append(graph.capture_clue(cid, host))
	if got.is_empty():
		return
	for key in got:
		_refresh_or_spawn_card(String(key))
	_relayout()
	var names: Array = []
	for key in got:
		var n := graph.node(String(key))
		if not n.is_empty() and not names.has(String(n.get("label", ""))):
			names.append(String(n.get("label", "")))
	_show_toast("捕获线索：" + "、".join(names))


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
	_tec.visible = true
	_tec.analyze(sid)


func dbg_tec_finish() -> int:
	return _tec.done_count() if _tec != null else 0


func dbg_tec_complete() -> void:
	if _tec != null:
		_tec.finish_now()


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
	_tec.analyze("SCENES_body")
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


func _ensure_card(kind: String, id: String) -> void:
	var n := graph.add_node(kind, id)
	_spawn_card(String(n["key"]))
	_relayout()


func quit_app() -> void:
	get_tree().quit()
