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
var _flash_supply_note := false


func _ready() -> void:
	theme = TecTheme.build()
	case_def = CaseLoader.new()
	if not case_def.load_case():
		push_error("案件数据装载失败：" + case_def.load_error)
		return
	graph = GraphState.new(case_def)
	combos = ComboSystem.new(case_def, graph)
	_cmds = CommandSystem.new(case_def, graph)
	_build_ui()
	_start_slice()
	if _has_arg("--shot"):
		_shot_flow.call_deferred()


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
	_crumb.size = Vector2(560, 28)
	head.add_child(_crumb)

	var reset_btn := TecTheme.button("重来")
	reset_btn.name = "btn_reset"
	reset_btn.position = Vector2(1040, 11)
	reset_btn.size = Vector2(80, 30)
	reset_btn.pressed.connect(_start_slice)
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
	for pair in [["TEC", "tec"], ["证物袋", "bag"], ["线索册", "clue"], ["档案袋", "goto"]]:
		var b := TecTheme.button(String(pair[0]))
		b.custom_minimum_size = Vector2(96, 40)
		b.name = "icon_" + String(pair[1])
		if String(pair[1]) == "tec":
			b.pressed.connect(_toggle_tec)
		elif String(pair[1]) == "bag":
			b.pressed.connect(func(): _toggle_storage(GraphState.BAG))
		elif String(pair[1]) == "clue":
			b.pressed.connect(func(): _toggle_storage(GraphState.LEDGER))
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

func _start_slice() -> void:
	for c in _card_layer.get_children():
		if c is NodeCard:
			c.queue_free()
	_cards.clear()
	graph = GraphState.new(case_def)
	combos = ComboSystem.new(case_def, graph)
	_cmds = CommandSystem.new(case_def, graph)
	_selected = ""

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
	var res := combos.activate(key)
	if res.is_empty():
		return
	_apply_outcome(res, key)


## 容器双重身份：第一次双击展开，已展开再双击收起（对齐 Web 的展开 / 折叠）
func _toggle_container(kind: String, id: String) -> void:
	if graph.explored.has(id) and not graph.is_collapsed(id):
		graph.collapse(id)
		_apply_hidden()
		_show_toast("收起了「%s」" % case_def.label_of(kind, id))
		_relayout()
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
	_ledger_win.took.connect(_on_storage_took)
	_ledger_win.closed.connect(func(): _ledger_win = null)
	_desk.add_child(_ledger_win)
	_ledger_win.move_to_front()


## 从收纳窗取回：节点回到画布，并刷新两个清单窗
func _on_storage_took(key: String) -> void:
	if _cards.has(key):
		(_cards[key] as NodeCard).visible = true
	_relayout()
	if _bag_win != null and is_instance_valid(_bag_win):
		_bag_win.refresh_store()
	if _ledger_win != null and is_instance_valid(_ledger_win):
		_ledger_win.refresh_store()


## 供测试钩子 / 后续接线用：把当前选中的节点收进某个收纳处
func dbg_store(kind: String) -> bool:
	if _selected == "":
		return false
	var ok := false
	if kind == GraphState.BAG:
		ok = graph.bag_store(_selected)
	elif kind == GraphState.LEDGER:
		ok = graph.ledger_store(_selected)
	elif kind == GraphState.MATRIX:
		var n := graph.node(_selected)
		if not n.is_empty() and n.get("kind", "") == "clue":
			var cl := case_def.clue_of(String(n["id"]))
			ok = graph.matrix_assign(_selected, cl.sense if cl != null else "")
	if not ok:
		return false
	_apply_hidden()
	if _bag_win != null and is_instance_valid(_bag_win):
		_bag_win.refresh_store()
	if _ledger_win != null and is_instance_valid(_ledger_win):
		_ledger_win.refresh_store()
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


func _on_card_combo(tool_key: String, target_key: String) -> void:
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
		_relayout()
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
	graph.tec_prog[scene_id] = int(graph.tec_prog.get(scene_id, 0)) + 1
	if scene_id == "SCENES_body":
		var e := case_def.ending_by_id("TRUE_E")
		_ending.play(e)


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
		"ending_visible": _ending.visible if _ending != null else false,
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
	await _shot("res://docs/p0_5_ending.png")
	await _wait(1.6)
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
	quit_app()


func _ensure_card(kind: String, id: String) -> void:
	var n := graph.add_node(kind, id)
	_spawn_card(String(n["key"]))
	_relayout()


func quit_app() -> void:
	get_tree().quit()
