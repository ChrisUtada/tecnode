extends SceneTree
## EVIDENCE_SYSTEM_PLAN §8：证据数据 / 配方 / 字牌 / 词卡掉落 / 落点规则 /
## 档案主张与 TEC 批量核对 / 快照与盖章。全部走真实 Desktop 入口。

const TEMP_PROGRESS := "user://test_evidence_progress.json"
const TEMP_SAVE := "user://test_evidence_case.save"

var fails := 0
var total := 0
var c: CaseLoader
var scene: Control


func check(name: String, cond: bool, detail: String = "") -> void:
	total += 1
	if cond:
		print("  PASS  ", name)
	else:
		fails += 1
		print("  FAIL  ", name, ("  [" + detail + "]") if detail != "" else "")


func _initialize() -> void:
	print("=== 证据系统（EVIDENCE_SYSTEM_PLAN）===")
	c = CaseLoader.new(CaseCatalog.path_of("A001"))
	check("案件装载", c.load_case(), c.load_error)
	if c.case_def == null:
		_finish()
		return
	_test_data()
	_test_recipes()
	_test_claim_snapshot()
	await _test_ui()
	_finish()


func _finish() -> void:
	for p in [TEMP_PROGRESS, TEMP_SAVE]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("=== %d 项，失败 %d ===" % [total, fails])
	quit(0 if fails == 0 else 1)


func _test_data() -> void:
	check("证据定义 ≥ 10", c.evidences.size() >= 10, str(c.evidences.size()))
	check("证据配方 ≥ 4", c.evidence_recipes.size() >= 4, str(c.evidence_recipes.size()))
	check("证据链可达性检查通过", c.evidence_issues.is_empty(), str(c.evidence_issues))
	var tiers := {"wu": 0, "ci": 0, "zheng": 0}
	for ev in c.evidences.values():
		tiers[String(ev.tier)] = int(tiers.get(String(ev.tier), 0)) + 1
	check("三层证据都有（物/词/证）",
		int(tiers["wu"]) > 0 and int(tiers["ci"]) > 0 and int(tiers["zheng"]) > 0,
		str(tiers))
	var ch := c.char_of("CHARS_luhengs")
	check("陆珩松有关键字段", ch != null and ch.evidence_fields.size() >= 1)
	var has_wu_ci := false
	var has_zheng_wu := false
	for r in c.evidence_recipes:
		if r.a == null or r.b == null or r.evidence == null:
			continue
		var ts := [String(r.a.tier), String(r.b.tier)]
		if ts.has("wu") and ts.has("ci") and String(r.evidence.tier) == "zheng":
			has_wu_ci = true
		if ts.has("zheng") and ts.has("wu") and String(r.evidence.tier) == "zheng":
			has_zheng_wu = true
	check("签名配方 物×词→证", has_wu_ci)
	check("链式配方 证×物→证", has_zheng_wu)


func _test_recipes() -> void:
	var g := GraphState.new(c)
	var comb := ComboSystem.new(c, g)
	var note := g.add_node("evidence", "EVID_WU_note")
	note["x"] = 100.0
	note["y"] = 100.0
	var lamp := g.add_node("evidence", "EVID_WU_lamp")
	lamp["x"] = 200.0
	lamp["y"] = 100.0
	var res := comb.use_item("evidence:EVID_WU_note", "evidence:EVID_WU_lamp")
	check("物×物配方命中", bool(res.get("ok", false)) and String(res.get("produced_evidence", "")) == "EVID_Z_lamp_notes",
		str(res))
	var k := g.key_of("evidence", "EVID_Z_lamp_notes")
	var n := g.node(k)
	check("产物是「证」级新卡", String(n.get("tier", "")) == "zheng"
		and bool(n.get("fresh", false)) and bool(n.get("unread", false)), str(n))
	check("产物落在目标右下 60/60", Vector2(float(n["x"]), float(n["y"])) == Vector2(260.0, 160.0),
		str(Vector2(float(n["x"]), float(n["y"]))))

	var g2 := GraphState.new(c)
	var comb2 := ComboSystem.new(c, g2)
	g2.add_node("evidence", "EVID_WU_note")
	g2.add_node("evidence", "EVID_WU_lamp")
	var rev := comb2.use_item("evidence:EVID_WU_lamp", "evidence:EVID_WU_note")
	check("配方无序对反向命中", bool(rev.get("ok", false))
		and String(rev.get("produced_evidence", "")) == "EVID_Z_lamp_notes", str(rev))

	var g3 := GraphState.new(c)
	var comb3 := ComboSystem.new(c, g3)
	g3.add_node("evidence", "EVID_WU_note")
	g3.add_node("evidence", "EVID_WU_rope")
	var miss := comb3.use_item("evidence:EVID_WU_note", "evidence:EVID_WU_rope")
	check("未命中记 tried", not bool(miss.get("ok", true))
		and bool(g3.tried.get("evidence:EVID_WU_note>evidence:EVID_WU_rope", false)), str(miss))

	var g4 := GraphState.new(c)
	var comb4 := ComboSystem.new(c, g4)
	g4.add_node("evidence", "EVID_WU_note")
	g4.add_node("evidence", "EVID_CI_lhs_word")
	var sig := comb4.use_item("evidence:EVID_WU_note", "evidence:EVID_CI_lhs_word")
	check("物×词签名配方命中", bool(sig.get("ok", false))
		and String(sig.get("produced_evidence", "")) == "EVID_Z_note_voice", str(sig))


func _test_claim_snapshot() -> void:
	var g := GraphState.new(c)
	g.set_claim("CHARS_luhengs", "FIELD_lhs_cause", "缢死", "EVID_Z_strangled")
	var ss := SaveSystem.new(g, "a001")
	var snap := ss.snapshot()
	check("快照含主张 / 已盖章字段", snap.has("claims") and snap.has("confirmedFields"))
	var g2 := GraphState.new(c)
	var ss2 := SaveSystem.new(g2, "a001")
	check("恢复快照成功", ss2.restore(snap))
	check("主张按快照恢复",
		String(g2.claim_of("CHARS_luhengs", "FIELD_lhs_cause").get("value", "")) == "缢死")
	g.confirm_field("CHARS_luhengs", "FIELD_lhs_cause", "缢死", "EVID_Z_strangled")
	ss.push_history_snapshot(snap)
	check("撤销成功", ss.undo())
	check("撤销不回滚已盖章字段",
		g.is_field_confirmed("CHARS_luhengs", "FIELD_lhs_cause")
			and String(g.confirmed_field_of("CHARS_luhengs", "FIELD_lhs_cause").get("value", "")) == "缢死",
		str(g.confirmed_field_of("CHARS_luhengs", "FIELD_lhs_cause")))


func _test_ui() -> void:
	scene = load("res://scenes/Desktop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.dbg_use_temp_progress(TEMP_PROGRESS)
	scene._save.path = TEMP_SAVE
	scene._save_enabled = false

	await _test_glyph()
	await _test_tec_hidden_evidence()
	await _test_word_drops()
	await _test_drop_rules()
	await _test_field_flow()
	scene.queue_free()
	await process_frame
	await process_frame


func _cards() -> Dictionary:
	return scene._cards


func _last_log() -> String:
	if scene.graph.logs.is_empty():
		return ""
	return String((scene.graph.logs[scene.graph.logs.size() - 1] as Dictionary).get("text", ""))


func _test_glyph() -> void:
	var wu: String = scene.dbg_ensure("evidence", "EVID_WU_note")
	var lamp: String = scene.dbg_ensure("evidence", "EVID_WU_lamp")
	var ci: String = scene.dbg_ensure("evidence", "EVID_CI_lhs_word")
	var zheng: String = scene.dbg_ensure("evidence", "EVID_Z_strangled")
	await process_frame
	for pair in [[wu, "物"], [ci, "词"], [zheng, "证"]]:
		var card: NodeCard = _cards().get(String(pair[0]), null)
		check("证据卡字牌 = " + String(pair[1]),
			card != null and card._glyph.glyph_override == String(pair[1])
				and card._glyph.filled,
			"null" if card == null else card._glyph.glyph_override)
	var wcard: NodeCard = _cards().get(wu, null)
	if wcard != null:
		check("1x 字牌字号 12", KindGlyph.glyph_font_px(wcard._glyph.radius, 1.0) == 12,
			str(KindGlyph.glyph_font_px(wcard._glyph.radius, 1.0)))
		wcard.set_lod(0.8)
		check("缩略档文字退场、字牌放大",
			not wcard._title.visible and wcard._glyph.visible and wcard._glyph.size.x > 60.0,
			"%.0f" % wcard._glyph.size.x)
		wcard.set_lod(1.0)
	# 画布合成：Desktop 入口也要把产物上画布、记案卷、弹 toast。
	var logs_before: int = int(scene.graph.logs.size())
	scene.dbg_combo_ui("EVID_WU_note", "EVID_WU_lamp")
	await process_frame
	var made: String = scene.graph.key_of("evidence", "EVID_Z_lamp_notes")
	var made_card: NodeCard = _cards().get(made, null)
	check("画布合成产物上卡", made_card != null and scene.graph.has("evidence", "EVID_Z_lamp_notes"))
	check("画布合成进案卷", scene.graph.logs.size() > logs_before and _last_log().contains("获得"),
		_last_log())
	check("画布合成有 toast", scene.dbg_toast_text().contains("获得证据"),
		scene.dbg_toast_text())
	if made_card != null:
		made_card.set_lod(1.0)
	check("画布合成「新」角标", made_card != null and made_card._badge.visible)


func _test_tec_hidden_evidence() -> void:
	## 用绳索：手写笔记 / 台灯在字牌与配方测试里已经人为铺到画布上，
	## 这里要验证的是「分析真的会新掉一张证据卡」。
	var rope_item: String = scene.dbg_ensure("item", "ITEMS_ccss")
	await process_frame
	check("TEC 开始分析粗糙的绳索", scene.dbg_tec_analyze_key(rope_item))
	scene.dbg_tec_complete()
	await process_frame
	await process_frame
	check("TEC 分析掉落「物」证据", scene.graph.has("evidence", "EVID_WU_rope"))
	var card: NodeCard = _cards().get(scene.graph.key_of("evidence", "EVID_WU_rope"), null)
	if card != null:
		card.set_lod(1.0)
	check("TEC 证据卡带「新」角标", card != null and card._badge.visible
		and scene.graph.has_unread(card.card_key), "null" if card == null else str(card._badge.visible))


func _test_word_drops() -> void:
	# 独白：整段一次贴出 = 完整播放。
	scene.dbg_open_monologue("CHARS_luhengs")
	await process_frame
	check("独白完整播放掉落「词」证据", scene.graph.has("evidence", "EVID_CI_lhs_word"))
	var logs: int = int(scene.graph.logs.size())
	scene.dbg_chat_close()
	scene.dbg_open_monologue("CHARS_luhengs")
	await process_frame
	check("重播不重复掉落", scene.graph.logs.size() == logs,
		"%d -> %d" % [logs, scene.graph.logs.size()])
	scene.dbg_chat_close()

	# 对话：补全跳过不算完整播放。
	scene.dbg_open_dialogue("DLG_0704_zs_lhs", ["CHARS_zs", "CHARS_luhengs"])
	await process_frame
	var chat: ChatWindow = scene.dbg_chat()
	for i in 40:
		scene.dbg_chat_finish()
		if not scene.dbg_chat_advance():
			break
	check("对话补全跳过不掉「词」", not scene.graph.has("evidence", "EVID_CI_zs_word"))
	scene.dbg_chat_close()

	# 对话：自然打完才掉。
	scene.dbg_open_dialogue("DLG_0704_zs_lhs", ["CHARS_zs", "CHARS_luhengs"])
	await process_frame
	chat = scene.dbg_chat()
	chat.dbg_set_char_ms(0.1)
	var guard := 0
	while guard < 300 and not scene.graph.has("evidence", "EVID_CI_zs_word"):
		guard += 1
		if chat.is_typing():
			await create_timer(0.02).timeout
		elif not scene.dbg_chat_advance():
			break
	check("对话首次完整播放掉落「词」", scene.graph.has("evidence", "EVID_CI_zs_word"),
		"guard=%d" % guard)
	var logs2: int = int(scene.graph.logs.size())
	scene.dbg_chat_close()
	scene.dbg_open_dialogue("DLG_0704_zs_lhs", ["CHARS_zs", "CHARS_luhengs"])
	await process_frame
	chat = scene.dbg_chat()
	chat.dbg_set_char_ms(0.1)
	guard = 0
	while guard < 300 and not chat.state().get("done", false):
		guard += 1
		if chat.is_typing():
			await create_timer(0.02).timeout
		elif not scene.dbg_chat_advance():
			break
	check("对话重播不重复掉落", scene.graph.logs.size() == logs2,
		"%d -> %d" % [logs2, scene.graph.logs.size()])
	scene.dbg_chat_close()

	# 回忆：同口径。
	var mem := c.memory_for("SCENES_0602", "CHARS_luhengs", "SCENES_garden")
	scene._open_memory_play(mem, scene.graph.scene_key("SCENES_garden"))
	await process_frame
	var mem_card: MemCard = scene.dbg_mem_card()
	check("回忆小剧场打开", mem_card != null)
	if mem_card != null:
		mem_card.dbg_set_char_ms(0.1)
		guard = 0
		while guard < 300 and not scene.graph.has("evidence", "EVID_CI_lhs_mem"):
			guard += 1
			if mem_card.is_typing():
				await create_timer(0.02).timeout
			elif not mem_card.advance():
				break
		check("回忆首次完整播放掉落「词」", scene.graph.has("evidence", "EVID_CI_lhs_mem"),
			"guard=%d" % guard)
		scene.dbg_close_mem()


func _test_drop_rules() -> void:
	var key: String = scene.dbg_ensure("evidence", "EVID_Z_zs_knife")
	await process_frame
	scene._apply_drop("bag-dock", key)
	check("证物袋收证据", String(scene.graph.stored.get(key, "")) == GraphState.BAG,
		String(scene.graph.stored.get(key, "")))
	scene.graph.take_back(key)
	scene._apply_drop("clue-icon", key)
	check("线索册拒证据", String(scene.graph.stored.get(key, "")) != GraphState.LEDGER)
	check("线索册拒收话术", _last_log().contains("不归线索册"), _last_log())
	scene._apply_drop("infer-icon", key)
	check("推演桌布拒证据", not scene.graph.matrix_has("EVID_Z_zs_knife"))
	check("推演桌布拒收话术", _last_log().contains("五感线索"), _last_log())
	scene._apply_drop("tec-dock", key)
	check("TEC 拒收证据", not scene._tec.is_analyzing())
	check("TEC 拒收话术", _last_log().contains("已经是结论") or _last_log().contains("不用再分析"),
		_last_log())


func _test_field_flow() -> void:
	var ch: CharDef = scene.case_def.char_of("CHARS_luhengs")
	# 注入第二个关键字段，验证「2–3 条一批」的核对节奏与全字段完成。
	var extra := EvidenceFieldDef.new()
	extra.id = "FIELD_lhs_probe"
	extra.label = "致死方式"
	extra.prompt = "伤口和绳索，哪个才是真正致命的一步？"
	extra.options = PackedStringArray(["刀伤", "绳痕"])
	extra.correct = "绳痕"
	var support: Array[EvidenceDef] = [scene.case_def.evidence_of("EVID_Z_strangled")]
	extra.support = support
	extra.drop_clue = scene.case_def.clue_of("CLUES_mc")
	ch.evidence_fields.append(extra)

	scene.dbg_people_row("CHARS_luhengs")
	await process_frame
	await process_frame
	var card = scene.dbg_person_card()
	check("档案卡含两个关键字段", card != null
		and scene.dbg_person_fields("CHARS_luhengs").size() == 2)
	check("有字段时档案卡自动增高", card != null and card.size.y > 360.0,
		str(card.size) if card != null else "null")

	var note: String = scene.graph.key_of("evidence", "EVID_WU_note")
	var word: String = scene.graph.key_of("evidence", "EVID_CI_lhs_word")
	var zheng: String = scene.graph.key_of("evidence", "EVID_Z_strangled")
	check("物级证据→字段退回", not scene.dbg_person_field_drop("CHARS_luhengs", "FIELD_lhs_cause", note))
	check("词级证据→字段退回", not scene.dbg_person_field_drop("CHARS_luhengs", "FIELD_lhs_cause", word))
	check("原料退回话术", _last_log().contains("拼出「证」"), _last_log())
	check("证级证据→字段待核对",
		scene.dbg_person_field_drop("CHARS_luhengs", "FIELD_lhs_cause", zheng))
	await process_frame
	check("待核对态", scene.dbg_person_field_state("FIELD_lhs_cause") == "pending",
		scene.dbg_person_field_state("FIELD_lhs_cause"))
	check("待核对虚线框",
		card != null and card.find_child("field_pending_dash", true, false) != null)
	check("词库按钮存在",
		card != null and card.find_child("field_opt_缢死", true, false) != null)
	scene.dbg_person_field_word("CHARS_luhengs", "FIELD_lhs_cause", "刺伤")
	check("错误词条核对退回", scene.dbg_person_check("CHARS_luhengs"))
	await process_frame
	check("错误主张不盖章", scene.dbg_person_field_state("FIELD_lhs_cause") == "empty",
		scene.dbg_person_field_state("FIELD_lhs_cause"))
	check("错误词条不剧透", " ".join(scene.dbg_tec_win().dbg_lines()).contains("站不住"),
		" ".join(scene.dbg_tec_win().dbg_lines().slice(-3)))

	# 两条待核对一起交批：正确词条 + 正确证据。
	check("重新附上结论", scene.dbg_person_field_drop("CHARS_luhengs", "FIELD_lhs_cause", zheng))
	scene.dbg_person_field_word("CHARS_luhengs", "FIELD_lhs_cause", "缢死")
	check("第二字段附上结论",
		scene.dbg_person_field_drop("CHARS_luhengs", "FIELD_lhs_probe", zheng))
	scene.dbg_person_field_word("CHARS_luhengs", "FIELD_lhs_probe", "绳痕")
	check("批量核对 2 条", scene.dbg_person_check("CHARS_luhengs"))
	await process_frame
	check("死因盖章", scene.dbg_person_field_state("FIELD_lhs_cause") == "stamped",
		scene.dbg_person_field_state("FIELD_lhs_cause"))
	check("致死方式盖章", scene.dbg_person_field_state("FIELD_lhs_probe") == "stamped",
		scene.dbg_person_field_state("FIELD_lhs_probe"))
	check("核准进图状态", scene.graph.is_field_confirmed("CHARS_luhengs", "FIELD_lhs_cause")
		and scene.graph.is_field_confirmed("CHARS_luhengs", "FIELD_lhs_probe"))
	var stamped_box := card.find_child("field_FIELD_lhs_cause", true, false) as PanelContainer
	var stamped_sb := stamped_box.get_theme_stylebox("panel") as StyleBoxFlat if stamped_box != null else null
	check("盖章警示朱 2px 框",
		stamped_sb != null and stamped_sb.border_width_top == 2
			and stamped_sb.border_color.is_equal_approx(TecTheme.SPOT_DANGER),
		str(stamped_sb))
	check("字段集齐掉落人物线索", scene.graph.captured.has("CLUES_mc")
		and scene.graph.has("clue", "CLUES_mc"))
	check("人物线索卡在画布", _cards().has(scene.graph.key_of("clue", "CLUES_mc")))
	var tec_win = scene.dbg_tec_win()
	var true_line := false
	if tec_win != null:
		for row in tec_win._lines.get_children():
			if row is TypewriterLabel and row.find_child("true_clue_mark", true, false) != null:
				true_line = true
				break
	check("真名级线索触发 G14 反白行", true_line)
	# 把注入字段摘掉，避免影响后续测试 / 自动存档。
	ch.evidence_fields.erase(extra)
