class_name TutorialFlow
extends Node
## 由 Desktop 挂载的子系统控制器。
## 过渡期直接通过注入的 `desk` 访问宿主成员；搬出的函数名保持不变。

var desk: Desktop


## 按当前可见图标数重排（Web `resetIconPositions()`）—— 图标增减时才调，
## 平时不碰，免得把玩家拖过的位置收走。
## 教学期图标栏是分阶段解锁的：第 3 幕只出证据 / 物品 / 推演，
## 第 6 幕再出案件。其余 app 一律不露头，避免玩家提前点进未接好的系统。
func _refresh_tutorial_icons() -> void:
	var allowed := {}
	if desk._tutorial_apps_unlocked:
		allowed = {"clue": true, "bag": true, "infer": true}
		if desk._tutorial_map_unlocked:
			allowed["map"] = true
	## TEC 是普通 app：应用栏解锁后它一直有图标；应用栏还没解锁时，
	## 只在 TEC 被关掉 / 最小化后露出来，保证玩家能把它叫回来。
	if desk._tutorial_tec_icon_visible or desk._tutorial_apps_unlocked:
		allowed["tec"] = true
	for app in ["infer", "goto", "clue", "people", "bag", "tec", "log", "map", "music", "garden"]:
		var b: Button = desk.launcher._icon_by_app(app)
		if b != null:
			b.visible = allowed.has(app)
	var layer: Control = desk.launcher._icon_layer()
	if layer != null and layer != desk._desk:
		layer.visible = not allowed.is_empty()
	if not allowed.is_empty():
		desk.launcher._reset_icon_positions()
	desk.launcher._refresh_count_badges()


func _tutorial_unlock_apps() -> void:
	desk._tutorial_apps_unlocked = true
	var layer: Control = desk.launcher._icon_layer()
	if layer != null:
		layer.visible = true
	_refresh_tutorial_icons()
	_animate_tutorial_icons(["infer", "clue", "bag"])


func _tutorial_unlock_map() -> void:
	desk._tutorial_map_unlocked = true
	var layer: Control = desk.launcher._icon_layer()
	if layer != null:
		layer.visible = true
	_refresh_tutorial_icons()
	_animate_tutorial_icons(["map"])


## 图标从左侧滑入：只动教学刚解锁的几枚，不碰运行中的拖拽 / 落点计算。
func _animate_tutorial_icons(apps: Array) -> void:
	for app in apps:
		var b: Button = desk.launcher._icon_by_app(String(app))
		if b == null:
			continue
		var target := b.position
		b.position = target - Vector2(18.0, 0.0)
		b.modulate.a = 0.0
		var tw := b.create_tween()
		tw.set_parallel(true)
		tw.tween_property(b, "position", target, 0.24)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "modulate:a", 1.0, 0.22)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## 第 1–2 幕：空白桌面 + 常驻 TEC + 三步登记教学。
## 不启动正式案件、不出图标栏、不放诊断入口；教学用自己的迷你案件数据。
func _begin_tutorial() -> void:
	desk._tutorial_active = true
	desk._tutorial_step = Desktop.TutorialStep.DOUBLE_CLICK_OFFICE
	desk._tutorial_apps_unlocked = false
	desk._tutorial_map_unlocked = false
	desk._tutorial_cert_win = null
	desk._tutorial_tec_placed = false
	desk._tutorial_tec_icon_visible = false
	desk._tutorial_map_arranged = false
	## 新调查从领证开始：不要把上一次的调查员证带进来。
	Investigator.clear(desk._inv_path)
	desk._investigator = {}
	var tutorial := CaseLoader.new(Desktop.TUTORIAL_CASE_PATH)
	if tutorial.load_case():
		desk.case_def = tutorial
	else:
		push_error("教学案件装载失败：" + tutorial.load_error)
	## 教学期不写盘：第 5 幕完成领证后才写第一份档。
	desk._save_enabled = false
	desk.session._new_runtime()
	desk._case_open = true
	desk._case_win.visible = true
	desk.windows._place_z(desk._case_win, Desktop.ZR_CASE)
	desk._case_win.set_title("T.E.C-OS // 调查员登记")
	_hide_tutorial_chrome()

	desk._tec.visible = true
	desk.windows._place_z(desk._tec, Desktop.ZR_TEC)
	## TEC 和普通 app 窗一样：可拖、可关、可最小化；关掉后左侧会出现 TEC 图标。
	desk._tec.set_drag_enabled(true)
	desk._tec.reset_tec()
	desk._tec.append_line("欢迎来到 TEC，你将开始领取你的调查员证，以便展开工作。\n"
		+ "桌面上是你的办公室——双击「TEC办公室」，把调查员证调出来。")
	_tutorial_set_hint()

	desk._view_k = 1.0
	desk._view_pos = Vector2.ZERO
	desk._view_user = true
	desk.canvas._apply_view()
	desk.windows._place_floating_windows()
	_spawn_tutorial_office()
	## 开场白落定后只做一次居中：之后 TEC 就是普通可拖窗，不再被重排拉回。
	await get_tree().process_frame
	await get_tree().process_frame
	if desk._tutorial_active and desk._tec != null and desk._tec.visible:
		desk._tutorial_tec_placed = false
		desk.windows._place_floating_windows()


func _hide_tutorial_chrome() -> void:
	_refresh_tutorial_icons()
	for n in ["btn_撤销", "btn_调试"]:
		var b := desk._head.get_node_or_null(n) as Control
		if b != null:
			b.visible = false
	if desk._brand_sub != null:
		desk._brand_sub.visible = false
	if desk._crumb != null:
		desk._crumb.visible = false
	if desk._goal != null:
		desk._goal.visible = false
	if desk._inv_chip != null:
		desk._inv_chip.visible = false
	for n in ["bar/close", "bar/min"]:
		var c := desk._case_win.get_node_or_null(n) as Control
		if c != null:
			c.visible = false


func _spawn_tutorial_office() -> void:
	var n := desk.graph.add_node("loc", Desktop.TUT_OFFICE_ID)
	n.label = "TEC办公室"
	n.always_visible = true
	var pos := _tutorial_card_pos(0)
	n.x = pos.x
	n.y = pos.y
	desk._tutorial_office_key = n.key
	var card: NodeCard = desk.canvas._spawn_card(desk._tutorial_office_key)
	if card != null:
		card.visible = true
		card.position = pos
		card.set_home_silent(pos)
		desk.canvas._sync_card_shell(card)


## 教学卡片沿左下角向上斜排：调查员 → 线索 → 证件 → 证件线索。
func _tutorial_card_pos(layer: int) -> Vector2:
	var y0 := maxf(40.0, desk._stage.size.y - 144.0)
	## 阶梯在宽屏上向右展开；窄窗里 TEC 会占掉中间，必须把横向步长收窄到
	## 卡片仍落在 TEC 左缘之外，否则最后一张线索会钻到 TEC 窗体底下。
	var step_x := Desktop.TUT_CARD_STEP_X
	if desk._tec != null and desk._card_layer != null and desk._tec.visible:
		var inv := desk._card_layer.get_global_transform().affine_inverse()
		var tec_left := (inv * desk._tec.global_position).x
		var max_x := tec_left - (GraphState.ENT_W + Desktop.CARD_PAD * 2.0) - 12.0
		step_x = minf(step_x, maxf(0.0, (max_x - Desktop.TUT_CARD_X) / 3.0))
	var x := Desktop.TUT_CARD_X + step_x * float(layer)
	var y := y0 - Desktop.TUT_CARD_STEP_Y * float(layer)
	x = minf(x, maxf(20.0, desk._stage.size.x - 160.0))
	y = maxf(20.0, y)
	return Vector2(x, y)


func _tutorial_spawn_node(kind: String, id: String, layer: int) -> String:
	var n := desk.graph.add_node(kind, id)
	var pos := _tutorial_card_pos(layer)
	n.x = pos.x
	n.y = pos.y
	var key := n.key
	desk.graph.mark_fresh(key)
	desk.canvas._refresh_or_spawn_card(key)
	desk.canvas._relayout()
	return key


func _tutorial_spawn_clue(id: String, from_key: String, layer: int) -> String:
	var key := desk.graph.capture_evidence(id, from_key, -1.0, -1.0, "deduce")
	var n := desk.graph.node(key)
	var pos := _tutorial_card_pos(layer)
	n.x = pos.x
	n.y = pos.y
	desk.graph.mark_fresh(key)
	desk.canvas._refresh_or_spawn_card(key)
	desk.canvas._relayout()
	return key


func _tutorial_say(text: String) -> void:
	if desk._tec == null or not is_instance_valid(desk._tec):
		return
	desk._tec.append_line(text)


func _tutorial_set_hint() -> void:
	if desk._tec == null:
		return
	match desk._tutorial_step:
		Desktop.TutorialStep.DOUBLE_CLICK_OFFICE:
			desk._tec.set_guidance("待命 · 等办公室档案", "双击「TEC办公室」调出调查员证")
		Desktop.TutorialStep.DRAG_CERT:
			desk._tec.set_guidance("待命 · 等你交证件", "把「调查员证」拖到我身上")
		Desktop.TutorialStep.STORE_SUPPLIES:
			desk._tec.set_guidance("待命 · 整理可选", "收纳可选 · 双击「推演」继续")
		Desktop.TutorialStep.INFER:
			desk._tec.set_guidance("待命 · 等推演", "桌布放入调查员证 · 长按执行者")
		Desktop.TutorialStep.CERT_FORM:
			desk._tec.set_guidance("待命 · 等你领证", "填写调查员证")
		Desktop.TutorialStep.CHOOSE_CASE:
			desk._tec.set_guidance("待命 · 等你选案", "在「案件」里选 A-001")
		_:
			desk._tec.set_guidance("待命 · 登记完成", "证件信息已核对")


## 拖到 TEC 前的教学门：只放行当前步骤该交的节点；其余由 TEC 亲口纠正。
func _tutorial_talk_line() -> String:
	match desk._tutorial_step:
		Desktop.TutorialStep.DOUBLE_CLICK_OFFICE:
			return "双击桌上的「TEC办公室」，把调查员证调出来；拖给我只能看到它的提示。"
		Desktop.TutorialStep.DRAG_CERT:
			return "把「调查员证」拖给我，我核对一下。"
		Desktop.TutorialStep.STORE_SUPPLIES:
			return "桌面可以整理：物与词放「物品」，证放「证据」。不想收也行，直接双击「推演」。"
		Desktop.TutorialStep.INFER:
			return "双击「推演」开桌布，把「调查员证」拖上去，再长按执行者。挡住我的话拖开或点「–」收起。"
		Desktop.TutorialStep.CERT_FORM:
			return "先把调查员证填完。"
		Desktop.TutorialStep.CHOOSE_CASE:
			return "在「案件」里选 A-001。"
		_:
			return "登记已经完成了。证件信息都齐了。"


func _tutorial_tec_guard(key: String) -> bool:
	match desk._tutorial_step:
		Desktop.TutorialStep.DOUBLE_CLICK_OFFICE:
			if key == Desktop.TUT_OFFICE_KEY:
				return true
			_tutorial_say("先把「TEC办公室」拖给我，我给你它的提示。")
		Desktop.TutorialStep.DRAG_CERT:
			if key == Desktop.TUT_CERT_ITEM_KEY:
				return true
			_tutorial_say("把「调查员证」拖给我。")
		Desktop.TutorialStep.STORE_SUPPLIES:
			_tutorial_say("桌面可以整理，但不是必须。收拾好就双击「推演」；不想收也可以直接去。")
		Desktop.TutorialStep.INFER:
			_tutorial_say("证不要交给我——双击「推演」打开桌布，把「调查员证」拖上去。")
		Desktop.TutorialStep.CERT_FORM:
			_tutorial_say("先把调查员证填完。")
		Desktop.TutorialStep.CHOOSE_CASE:
			_tutorial_say("在「案件」里选 A-001。")
		_:
			_tutorial_say("证件已经核对完了。")
	return false


## 证件由 TEC办公室本身产出；TEC 分析只给提示，不产出证件。
func _tutorial_on_activate(key: String) -> bool:
	if desk._tutorial_step == Desktop.TutorialStep.DOUBLE_CLICK_OFFICE and key == Desktop.TUT_OFFICE_KEY:
		var cert_key := _tutorial_spawn_node("item", Desktop.TUT_CERT_ITEM_ID, 1)
		desk.graph.link(Desktop.TUT_OFFICE_KEY, cert_key, "entity")
		desk.canvas._repaint_edges()
		desk._tutorial_step = Desktop.TutorialStep.DRAG_CERT
		_tutorial_set_hint()
		_tutorial_say("这是你的调查员证。把它拖给我，我核对一下。")
		return true
	if desk._tutorial_step == Desktop.TutorialStep.DRAG_CERT and (key == Desktop.TUT_CERT_ITEM_KEY or key == Desktop.TUT_OFFICE_KEY):
		_tutorial_say("证件已经调出来了。把「调查员证」拖给我。")
		return true
	return false


## TEC 分析只产生节点相关提示 / 证；TEC办公室分析不会产出调查员证。
func _tutorial_on_tec_done(key: String) -> bool:
	if desk._tutorial_step == Desktop.TutorialStep.DOUBLE_CLICK_OFFICE and key == Desktop.TUT_OFFICE_KEY:
		_tutorial_say("TEC办公室：档案柜里有你的调查员证。双击办公室把它调出来，而不是拖给我。")
		return true
	if desk._tutorial_step == Desktop.TutorialStep.DRAG_CERT and key == Desktop.TUT_CERT_ITEM_KEY:
		_tutorial_spawn_clue(Desktop.TUT_CERT_CLUE_ID, key, 2)
		desk._tutorial_step = Desktop.TutorialStep.STORE_SUPPLIES
		_tutorial_unlock_apps()
		_tutorial_set_hint()
		_tutorial_say("核对完成。桌面可以整理：物与词放「物品」，证放「证据」，但不整理也能继续。")
		return true
	return false


func _tutorial_begin_infer() -> void:
	desk._tutorial_step = Desktop.TutorialStep.INFER
	_tutorial_set_hint()
	## 不替玩家打开任何 app：双击「推演」图标打开桌布，和正式案件完全同一条路径。
	var opened := desk._matrix_win != null and is_instance_valid(desk._matrix_win)
	if opened:
		_tutorial_say("桌布已经打开了。把「调查员证」拖上去，长按执行者开始推演。")
	else:
		_tutorial_say("双击左边「推演」打开桌布；如果 TEC 挡住，把我拖开或点「–」收起。"
			+ "把「调查员证」放到推演桌布，长按执行者开始推演。")


func _tutorial_on_matrix_changed() -> void:
	if not desk._tutorial_active or desk._tutorial_step != Desktop.TutorialStep.INFER:
		return
	if desk._matrix_win == null or not is_instance_valid(desk._matrix_win):
		return
	var got := 1 if desk.graph.matrix_has(Desktop.TUT_CERT_CLUE_ID) else 0
	if got >= 1:
		desk._matrix_win.set_hint("TEC：证齐了。长按执行者，开始推演。")
	else:
		desk._matrix_win.set_hint("TEC：还需要「调查员证」——把它放到推演桌布，然后长按执行者。")


func _tutorial_on_inference_success(hit: EndingDef) -> void:
	desk.graph.mark_ending(hit.id)
	## 教学桌布用完即收：清空配方，避免领证/选案期间重开推演误触正式结局。
	desk.graph.clear_matrix()
	desk._tutorial_step = Desktop.TutorialStep.CERT_FORM
	_tutorial_set_hint()
	_tutorial_say("推演成立。调查员证已经生成——把姓名、编号、日期和照片补齐。")
	## 桌布和收纳窗到此完成使命：收掉，把注意力交给证件。
	if desk._matrix_win != null and is_instance_valid(desk._matrix_win):
		desk.matrix._restore_matrix_occlusion()
		desk._matrix_win.queue_free()
		desk._matrix_win = null
	if desk._ledger_win != null and is_instance_valid(desk._ledger_win):
		desk._ledger_win.queue_free()
		desk._ledger_win = null
	if desk._bag_win != null and is_instance_valid(desk._bag_win):
		desk._bag_win.queue_free()
		desk._bag_win = null
	desk.windows._place_floating_windows()
	_open_cert_form()


func _open_cert_form() -> void:
	if desk._tutorial_cert_win != null and is_instance_valid(desk._tutorial_cert_win):
		return
	var w := Desktop.CertWinScript.new()
	w.name = "tutorial_cert"
	w.store_path = desk._inv_path
	w.setup_cert(String(desk._investigator.get("name", "")))
	w.completed.connect(_on_tutorial_cert_completed)
	desk._desk.add_child(w)
	desk.windows._place_z(w, Desktop.ZR_CERT)
	w.place_center(desk._vw(), desk._desk.size.y)
	desk._tutorial_cert_win = w


func _on_tutorial_cert_completed(card: Dictionary) -> void:
	desk._investigator = card.duplicate(true)
	desk.session._refresh_chip()
	if desk._tutorial_cert_win != null and is_instance_valid(desk._tutorial_cert_win):
		desk._tutorial_cert_win.queue_free()
	desk._tutorial_cert_win = null
	desk._tutorial_step = Desktop.TutorialStep.CHOOSE_CASE
	_tutorial_unlock_map()
	_tutorial_set_hint()
	## 第 5 幕完成即写一份「进入案件」的档：玩家此时退出，下一次「继续」
	## 也能跳过整段开场。第 6 幕真正选案后会被实际案件进度覆盖。
	_write_tutorial_entry_save()
	if desk._tec != null and desk._tec.visible:
		desk._tec.append_line("证件已签发。现在选择一个案件。")
	elif desk._tec != null:
		desk._tutorial_tec_icon_visible = true
		desk.launcher._refresh_app_icons()
	desk.launcher._open_case_map()
	_arrange_tutorial_map_once()


## 地图是 TEC 主动弹的：第一次打开时把地图和 TEC 并排摆一次，免得 TEC 正好压住
## 唯一可点的 A-001 行。摆完就是普通窗口，玩家拖到哪都算数，不再自动归位。
func _arrange_tutorial_map_once() -> void:
	if desk._tutorial_map_arranged:
		return
	if desk._map_win == null or not is_instance_valid(desk._map_win):
		return
	desk._tutorial_map_arranged = true
	var vw := desk._vw()
	var desk_h := desk._desk.size.y
	if desk._tec != null and desk._tec.visible:
		var gap := 16.0
		var total_w := desk._map_win.size.x + desk._tec.size.x + gap
		var left := maxf(96.0, (vw - total_w) * 0.5)
		desk._map_win.position = Vector2(left,
			maxf(14.0, minf(72.0, desk_h - 14.0 - desk._map_win.size.y)))
		desk._tec.position = Vector2(left + desk._map_win.size.x + gap,
			maxf(14.0, (desk_h - desk._tec.size.y) * 0.5 - 24.0))
	else:
		desk._map_win.position = Vector2(maxf(96.0, (vw - desk._map_win.size.x) * 0.5),
			maxf(14.0, minf(72.0, desk_h - 14.0 - desk._map_win.size.y)))


func _write_tutorial_entry_save() -> void:
	if desk._shot_mode() or DisplayServer.get_name() == "headless" or desk._has_arg("--fresh"):
		return
	var path := CaseCatalog.path_of(CaseCatalog.DEFAULT_ID)
	if path == "" or not ResourceLoader.exists(path):
		return
	var loader := CaseLoader.new(path)
	if not loader.load_case():
		return
	var g := GraphState.new(loader)
	var loc := g.add_node("loc", Desktop.SLICE_SCENE)
	loc["x"] = 1000.0
	loc["y"] = 620.0
	g.last_scene = Desktop.SLICE_SCENE
	g.mark_fresh(String(loc["key"]))
	var s := SaveSystem.new(g, loader.case_def.id)
	if not s.save_to_disk():
		push_warning("开场完成后写档失败：" + s.last_error)


func _finish_tutorial_to_case(id: String) -> bool:
	if id != CaseCatalog.DEFAULT_ID:
		desk._show_toast("教学期只开放 A-001", true)
		return false
	if not CaseCatalog.exists(id):
		desk._show_toast("没有这个案件地址", true)
		return false
	if not desk._catalog.is_unlocked(id):
		desk._show_toast("该案件地址尚未解锁", true)
		return false
	if not CaseCatalog.data_ready(id):
		desk._show_toast("案件 " + CaseCatalog.code_of(id) + " 的数据尚未装机", true)
		return false
	var loader := CaseLoader.new(CaseCatalog.path_of(id))
	if not loader.load_case():
		desk._show_toast("案件装载失败：" + loader.load_error, true)
		return false
	desk._tutorial_active = false
	desk._tutorial_step = Desktop.TutorialStep.DONE
	desk._tutorial_apps_unlocked = false
	desk._tutorial_map_unlocked = false
	desk._tutorial_cert_win = null
	desk._active_case = id
	desk.case_def = loader
	desk._catalog.last = id
	var saves := not desk._shot_mode() and DisplayServer.get_name() != "headless"
	desk._save_enabled = saves
	if saves and not desk._progress_read_only:
		desk._catalog.save_progress()
	desk._case_open = true
	desk._case_held = false
	desk._case_docked = false
	desk._case_win.visible = true
	## 教学桌面把镜头固定在 1x；进入正式案件要交还给「适应窗口」。
	desk._view_k = 1.0
	desk._view_pos = Vector2.ZERO
	desk._view_user = false
	desk.canvas._apply_view()
	desk.session._start_slice()
	_restore_full_chrome()
	desk.session._update_case_chrome()
	desk.session._update_case_park_ui()
	desk.session._refresh_chip()
	desk.launcher._refresh_app_icons()
	desk.launcher._reset_icon_positions()
	desk.windows._place_floating_windows()
	desk.session._autosave()
	desk._show_toast("已进入案件 " + CaseCatalog.code_of(id))
	desk._log("已进入案件 %s // %s" % [CaseCatalog.code_of(id), CaseCatalog.title_of(id)], "sys")
	return true


func _restore_full_chrome() -> void:
	var layer: Control = desk.launcher._icon_layer()
	if layer != null:
		layer.visible = true
	for n in ["btn_撤销", "btn_调试"]:
		var b := desk._head.get_node_or_null(n) as Control
		if b != null:
			b.visible = true
	if desk._brand_sub != null:
		desk._brand_sub.visible = true
	if desk._crumb != null:
		desk._crumb.visible = true
	if desk._goal != null:
		desk._goal.visible = true
	if desk._inv_chip != null:
		desk._inv_chip.visible = not desk._investigator.is_empty()
	for n in ["bar/close", "bar/min"]:
		var c := desk._case_win.get_node_or_null(n) as Control
		if c != null:
			c.visible = true
	if desk._tec != null:
		desk._tec.set_drag_enabled(true)
		for n in ["bar/close", "bar/min"]:
			var c := desk._tec.get_node_or_null(n) as Control
			if c != null:
				c.visible = true
	desk._layout_header_left(desk._vw())


## C5：教学期错误统一由 TEC 口头纠正，不落系统 toast。
func _tutorial_correct(text: String) -> bool:
	if desk._tutorial_active and desk._tutorial_step != Desktop.TutorialStep.DONE:
		_tutorial_say(text)
		return true
	return false


## 教学桌面不做力导向：三张卡是 TEC 亲手摆的教学道具，位置必须稳定可预期，
## 否则刚生成的线索会被弹簧/斥力推到画布边上，玩家根本找不到。
func _layout_tutorial() -> void:
	for key in desk._cards.keys():
		var card: NodeCard = desk._cards[key]
		if card == null or not card.visible:
			continue
		desk.canvas._kill_move(String(key))
		var n := desk.graph.node(String(key))
		var p := Vector2(n.x, n.y)
		card.set_home_silent(p)
		card.position = p
