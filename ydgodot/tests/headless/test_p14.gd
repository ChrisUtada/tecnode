extends "res://tests/headless/_test_base.gd"
## P1.4 回归：五感槽位 / 推演桌布 / 结局判定与真名遮罩
##
## 覆盖：
##   1) 五感槽位初始为空，归位 / 取回 / 跨窗搬运（物品 / 证据 → 桌布、桌布 → 证据）
##   2) 推演判定：配方必须**恰好**相等（多一条、少一条都不算）
##   3) TEC 解读捕获 hiddenClue（尸体场景 → 植物学家陆珩松）
##   4) 桌布窗口：归位后芯片出现、画布上的节点收起、取回后回到画布
##   5) 长按推演失败 → 心碎表情；成功后 → 结局分幕 + 真名遮罩
##
## 运行：godot --headless --path ydgodot --script res://tests/headless/test_p14.gd

var c: CaseLoader

func _initialize() -> void:
	print("=== P1.4 推演桌布 / 结局判定 ===")
	c = CaseLoader.new()
	check("装载案件", c.load_case(), c.load_error)

	_test_blank_slots()
	_test_assign_take()
	_test_cross_window()
	_test_capture()
	_test_recipe_exact()
	await _test_desktop_flow()

	_finish()


# ── 1. 初始五个空槽 ────────────────────────────────────────────────────
func _test_blank_slots() -> void:
	var g := GraphState.new(c)
	check("五感词表 5 项且中文名齐全",
		MatrixState.SENSES.size() == 5 and MatrixState.SENSE_NAMES.size() == 5)
	check("五感槽位共 5 个", g.matrix.size() == 5, str(g.matrix.keys()))
	var all_empty := true
	for sense in MatrixState.SENSES:
		if not (g.matrix.get(sense, []) as Array).is_empty():
			all_empty = false
	check("开局槽位全空", all_empty)
	check("空阵列不命中任何结局", g.match_ending() == null)


# ── 2. 归位 / 取回 ─────────────────────────────────────────────────────
func _test_assign_take() -> void:
	var g := GraphState.new(c)
	var nm := String(g.add_node("clue", "CLUES_nm")["key"])
	check("感官不符：归位失败", not g.matrix_assign(nm, "taste"))
	check("感官不符：未记去向", not g.stored.has(nm))
	check("感官正确：归位成功", g.matrix_assign(nm, "hearing"))
	check("归位：记去向 MATRIX", String(g.stored.get(nm, "")) == GraphState.MATRIX)
	check("归位：画布上不可见", not g.is_visible(nm))
	check("归位：落进听觉槽", g.matrix_slot_of("CLUES_nm") == "hearing")
	check("归位：槽位里有这条证", (g.matrix["hearing"] as Array).has("CLUES_nm"))
	check("重复归位：拒绝", not g.matrix_assign(nm, "hearing"))
	check("归位：matrix_ids 摊平", g.matrix_ids() == ["CLUES_nm"], str(g.matrix_ids()))
	check("取回：成功", g.matrix_take(nm))
	check("取回：槽位清空", g.matrix_slot_of("CLUES_nm") == "" and g.matrix_count() == 0)
	check("取回：画布上重新可见", g.is_visible(nm))


# ── 3. 跨窗搬运（证据 ↔ 桌布）────────────────────────────────────────
func _test_cross_window() -> void:
	var g := GraphState.new(c)
	var mc := String(g.add_node("evidence", "CLUES_mc")["key"])
	check("证不进物品", not g.bag_store(mc))
	check("证卡进证据", g.ledger_store(mc))
	check("证据 → 桌布：直接归位", g.matrix_assign(mc))
	check("证据 → 桌布：去向改成 MATRIX", String(g.stored.get(mc, "")) == GraphState.MATRIX)
	check("证据 → 桌布：落进触觉槽", g.matrix_slot_of("CLUES_mc") == "touch")
	check("桌布 → 证据：restash 成功", g.restash(mc, GraphState.MATRIX, GraphState.LEDGER))
	check("桌布 → 证据：槽位已摘掉", g.matrix_slot_of("CLUES_mc") == "")
	check("桌布 → 证据：去向改成 LEDGER", String(g.stored.get(mc, "")) == GraphState.LEDGER)
	check("证不能再搬回物品", not g.restash(mc, GraphState.LEDGER, GraphState.BAG))


# ── 4. 捕获线索 ────────────────────────────────────────────────────────
func _test_capture() -> void:
	var g := GraphState.new(c)
	var key := g.capture_clue("CLUES_nm")
	check("捕获：记入 captured", g.captured.has("CLUES_nm"))
	check("捕获：建出证节点", g.has("clue", "CLUES_nm"))
	check("捕获：节点带 captured 标记", bool(g.node(key).get("captured", false)))
	var from_refs := g.capture_clue_refs([c.clue_of("CLUES_xds")])
	check("§7-2 结构化证据引用捕获", from_refs.size() == 1 and g.captured.has("CLUES_xds"))


# ── 5. 配方必须恰好相等 ────────────────────────────────────────────────
func _test_recipe_exact() -> void:
	var true_e := c.ending_by_id("TRUE_E")
	check("TRUE_E 配方 5 条", true_e != null and true_e.recipe.size() == 5)

	var g := GraphState.new(c)
	for clue in true_e.recipe:
		g.add_node("clue", clue.id)
		g.matrix_assign(g.key_of("clue", clue.id))
	check("五感各一：命中 TRUE_E", _ending_id(g.match_ending()) == "TRUE_E")
	check("五感各一：matrix_count = 5", g.matrix_count() == 5)

	var extra := String(g.add_node("clue", "CLUES_JS")["key"])
	g.matrix_assign(extra)
	check("多一条证：不命中", g.match_ending() == null)
	g.matrix_take(extra)
	check("拿掉多余证：重新命中", _ending_id(g.match_ending()) == "TRUE_E")

	var g2 := GraphState.new(c)
	var normal := c.ending_by_id("END_NORMAL")
	for clue in normal.recipe:
		g2.add_node("clue", clue.id)
		g2.matrix_assign(g2.key_of("clue", clue.id))
	check("另一套配方：命中 END_NORMAL", _ending_id(g2.match_ending()) == "END_NORMAL")


func _ending_id(e: EndingDef) -> String:
	return e.id if e != null else ""


# ── 6. 桌面级：TEC 捕获 + 桌布窗口 + 推演演出 ─────────────────────────
func _test_desktop_flow() -> void:
	var scene: Control = load("res://scenes/Desktop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	# TEC 解读尸体 → hiddenClue 上画布
	scene.debug.dbg_expand("SCENES_body")
	await process_frame
	scene.debug.dbg_tec_analyze("SCENES_body")
	scene.debug.dbg_tec_complete()
	await process_frame
	await process_frame
	var st: Dictionary = scene.debug.dbg_state()
	check("TEC 解读：捕获尸体隐藏证据", (st["captured"] as Array).has("CLUES_V_luheng"), str(st["captured"]))
	check("TEC 解读：证卡上画布", _cards(scene).has("evidence:CLUES_V_luheng"))

	# 桌布窗口：归位 / 取回
	scene.debug.dbg_ensure("clue", "CLUES_nm")
	await process_frame
	var mw: MatrixWin = scene.debug.dbg_open_matrix()
	await process_frame
	check("桌布窗口能打开", mw != null)
	check("K10 推演窗标题统一", mw != null and mw.title == "推演", mw.title if mw != null else "null")
	check("桌布五感芯片初始为空", mw != null and mw.chip_count() == 0)
	check("普通物品不能归位", not scene.debug.dbg_matrix_assign("item:ITEMS_bd"))
	_drag_card_to(_cards(scene)["evidence:CLUES_nm"], mw.board_global_rect().get_center())
	await process_frame
	check("把证卡拖到桌布上：归位成功", mw != null and mw.has_chip("CLUES_nm"))
	check("归位后桌布出现芯片", mw != null and mw.has_chip("CLUES_nm"))
	check("归位后听觉槽有 1 条", mw != null and mw.chip_count("hearing") == 1)
	check("归位后画布上的卡片收起", not (_cards(scene)["evidence:CLUES_nm"] as NodeCard).visible)
	check("归位后状态里有 MATRIX", (scene.debug.dbg_state()["matrix_ids"] as Array).has("CLUES_nm"))

	scene.debug.dbg_matrix_take("evidence:CLUES_nm")
	await process_frame
	check("取回后芯片消失", mw != null and not mw.has_chip("CLUES_nm"))
	check("取回后卡片重新可见", (_cards(scene)["evidence:CLUES_nm"] as NodeCard).visible)

	# 配方不全就推演：失败 + 心碎表情
	scene.debug.dbg_matrix_assign("evidence:CLUES_nm")
	await process_frame
	scene.debug.dbg_matrix_charge()
	await process_frame
	check("配方不全：不触发结局", not bool(scene.debug.dbg_state()["ending_visible"]))
	check("配方不全：执行者弹出心碎", mw != null and mw.emote_visible())
	check("配方不全：失败提示指向检查配方",
		mw != null and mw.dbg_hint().contains("检查配方"),
		mw.dbg_hint() if mw != null else "null")

	# 补齐 TRUE_E 配方 → 长按推演 → 真名遮罩
	var true_e := c.ending_by_id("TRUE_E")
	for clue in true_e.recipe:
		if clue.id == "CLUES_nm":
			continue
		scene.debug.dbg_ensure("clue", clue.id)
		scene.debug.dbg_matrix_assign("evidence:" + clue.id)
	await process_frame
	check("五感归位完成：matrix_count = 5",
		(scene.debug.dbg_state()["matrix_ids"] as Array).size() == 5, str(scene.debug.dbg_state()["matrix_ids"]))

	scene.debug.dbg_matrix_charge()
	await process_frame
	var st2: Dictionary = scene.debug.dbg_state()
	check("推演命中：结局开演", bool(st2["ending_visible"]))
	check("推演命中：记录结局 TRUE_E", st2["ending_id"] == "TRUE_E" and (st2["endings"] as Array).has("TRUE_E"))
	check("推演命中：真名镜头先震动", mw != null)
	# S5：种子在结局触发时就要进图与快照，不能等收幕按钮。
	check("S5 结局触发即发种子", bool(scene.graph.garden.get("seed", false)),
		str(scene.graph.garden))
	check("S5 种子的真名旁白同时写好",
		String(scene.graph.garden.get("narr", "")) == GardenSystem.true_ending_message(c),
		String(scene.graph.garden.get("narr", "")))
	check("S5 快照里已带种子（遮罩期退出不丢）",
		bool((scene.debug.dbg_save_system().snapshot()["garden"] as Dictionary).get("seed", false)),
		str(scene.debug.dbg_save_system().snapshot()["garden"]))

	var ending: EndingOverlay = scene.debug.dbg_ending()
	check("结局分幕共 4 幕", ending.total_lines() == 4, str(ending.total_lines()))
	scene.debug.dbg_ending_finish()
	check("真名遮罩出现", ending.truename_shown())
	check("真名文字是「花魄」", ending.truename() == "花魄")
	check("末帧按钮 = 确认捕获", ending.final_text() == "确认捕获")
	check("真名结局不在遮罩上放大段说明", ending.shown_message() == "")


func _cards(scene: Control) -> Dictionary:
	var out := {}
	var layer: Node = scene.get_node("desk/case_win/body/stage/cards")
	for child in layer.get_children():
		if child is NodeCard:
			out[(child as NodeCard).card_key] = child
	return out


func _drag_card_to(card: NodeCard, to_global: Vector2) -> void:
	var from := card.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = from
	card._gui_input(press)

	var move := InputEventMouseMotion.new()
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	move.global_position = from + Vector2(12, 8)
	card._gui_input(move)
	move = InputEventMouseMotion.new()
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	move.global_position = to_global
	card._gui_input(move)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.global_position = to_global
	card._gui_input(release)
