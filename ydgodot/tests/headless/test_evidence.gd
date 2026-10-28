extends "res://tests/headless/_test_base.gd"
## ZHENG_MODEL_PLAN §8：物 / 词 / 证 数据、合成、字牌、词卡掉落、落点规则、
## 档案主张与 TEC 批量核对、快照与盖章。全部走真实 Desktop 入口。

const TEMP_PROGRESS := "user://test_evidence_progress.json"
const TEMP_SAVE := "user://test_evidence_case.save"

var c: CaseLoader
var scene: Control

func _initialize() -> void:
	print("=== 证据模型（物 / 词 / 证）===")
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


func _cleanup() -> void:
	for p in [TEMP_PROGRESS, TEMP_SAVE]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _test_data() -> void:
	check("证据定义 28 张", c.evidences.size() == 28, str(c.evidences.size()))
	check("证据配方 6 条", c.evidence_recipes.size() == 6, str(c.evidence_recipes.size()))
	check("证据链可达性检查通过", c.evidence_issues.is_empty(), str(c.evidence_issues))
	var tiers := {"wu": 0, "ci": 0, "zheng": 0}
	var origins := {"tec": 0, "synth": 0, "deduce": 0}
	var senses := {}
	for ev in c.evidences.values():
		tiers[String(ev.tier)] = int(tiers.get(String(ev.tier), 0)) + 1
		origins[String(ev.origin)] = int(origins.get(String(ev.origin), 0)) + 1
		senses[String(ev.sense)] = true
	check("物卡通道已退役（没有 wu）", int(tiers["wu"]) == 0, str(tiers))
	check("词 / 证两层都在", int(tiers["ci"]) == 3 and int(tiers["zheng"]) == 25, str(tiers))
	check("三种来源都有（tec / synth / deduce）",
		int(origins["tec"]) > 0 and int(origins["synth"]) > 0 and int(origins["deduce"]) > 0,
		str(origins))
	check("五感覆盖视觉 / 听觉 / 触觉",
		senses.has("vision") and senses.has("hearing") and senses.has("touch"), str(senses))
	var ch := c.char_of("CHARS_luhengs")
	check("陆珩松有关键字段", ch != null and ch.evidence_fields.size() >= 1)
	var has_item_item := false
	var has_item_word := false
	var has_evidence_item := false
	for r in c.evidence_recipes:
		if r.a == null or r.b == null or r.evidence == null:
			continue
		var sides := [r.a, r.b]
		if sides[0] is ItemDef and sides[1] is ItemDef:
			has_item_item = true
		if (sides[0] is ItemDef and sides[1] is EvidenceDef) \
				or (sides[0] is EvidenceDef and sides[1] is ItemDef):
			has_evidence_item = true
			for side in sides:
				if side is EvidenceDef and String((side as EvidenceDef).tier) == "ci":
					has_item_word = true
		check("配方 %s 产物是证" % r.id, String(r.evidence.tier) == "zheng", r.evidence.tier)
		check("配方 %s 带合法五感" % r.id, GraphState.SENSES.has(String(r.sense)), String(r.sense))
	check("物×物配方存在", has_item_item)
	check("物×词配方存在", has_item_word)
	check("证×物配方存在", has_evidence_item)
	check("被配方引用的物品标记为原料", c.item_used_in_recipe("ITEM_sxbj")
		and c.item_used_in_recipe("ITEMS_ccss"))
	check("未被引用的物品不标原料", not c.item_used_in_recipe("ITEMS_a4paper"))


func _test_recipes() -> void:
	var g := GraphState.new(c)
	var comb := ComboSystem.new(c, g)
	var note := g.add_node("item", "ITEM_sxbj")
	note["x"] = 100.0
	note["y"] = 100.0
	var lamp := g.add_node("item", "ITEM_taideng")
	lamp["x"] = 200.0
	lamp["y"] = 100.0
	var res := comb.use_item("item:ITEM_sxbj", "item:ITEM_taideng")
	check("物×物配方命中", bool(res.get("ok", false))
		and String(res.get("produced_evidence", "")) == "EVID_Z_lamp_notes", str(res))
	var k := g.key_of("evidence", "EVID_Z_lamp_notes")
	var n := g.node(k)
	check("产物是「证」", String(n.get("tier", "")) == "zheng"
		and bool(n.get("captured", false)), str(n))
	check("产物 origin=synth / sense=vision",
		String(n.get("origin", "")) == "synth" and String(n.get("sense", "")) == "vision", str(n))
	check("产物带「新」标记", bool(n.get("fresh", false)) and bool(n.get("unread", false)), str(n))
	check("产物落在目标右下 60/60", Vector2(float(n["x"]), float(n["y"])) == Vector2(260.0, 160.0),
		str(Vector2(float(n["x"]), float(n["y"]))))
	check("原料不消耗：笔记还在", g.has("item", "ITEM_sxbj"))
	check("原料不消耗：台灯还在", g.has("item", "ITEM_taideng"))
	check("原料不会被塞进物品 / 证据", not g.stored.has("item:ITEM_sxbj")
		and not g.stored.has("item:ITEM_taideng"))

	var g2 := GraphState.new(c)
	var comb2 := ComboSystem.new(c, g2)
	g2.add_node("item", "ITEM_sxbj")
	g2.add_node("item", "ITEM_taideng")
	var rev := comb2.use_item("item:ITEM_taideng", "item:ITEM_sxbj")
	check("配方无序对反向命中", bool(rev.get("ok", false))
		and String(rev.get("produced_evidence", "")) == "EVID_Z_lamp_notes", str(rev))

	var g3 := GraphState.new(c)
	var comb3 := ComboSystem.new(c, g3)
	g3.add_node("item", "ITEM_taideng")
	g3.add_node("item", "ITEMS_rxbs")
	var miss := comb3.use_item("item:ITEM_taideng", "item:ITEMS_rxbs")
	check("未命中记 tried", not bool(miss.get("ok", true))
		and bool(g3.tried.get("item:ITEM_taideng>item:ITEMS_rxbs", false)), str(miss))

	var g4 := GraphState.new(c)
	var comb4 := ComboSystem.new(c, g4)
	var word := g4.add_node("evidence", "EVID_CI_lhs_word")
	word["x"] = 200.0
	word["y"] = 100.0
	g4.add_node("item", "ITEM_sxbj")
	var sig := comb4.use_item("item:ITEM_sxbj", "evidence:EVID_CI_lhs_word")
	check("物×词签名配方命中", bool(sig.get("ok", false))
		and String(sig.get("produced_evidence", "")) == "EVID_Z_note_voice", str(sig))
	var sig_n := g4.node(g4.key_of("evidence", "EVID_Z_note_voice"))
	check("物×词产物带配方五感", String(sig_n.get("sense", "")) == "hearing", str(sig_n))
	check("词本身不被消耗、不变成已捕获",
		g4.has("evidence", "EVID_CI_lhs_word")
			and not bool(g4.node("evidence:EVID_CI_lhs_word").get("captured", false)))

	# 链式：台灯笔记 × 独白 → 伪造时间；再 × 绳索 → 缢死。
	var g5 := GraphState.new(c)
	var comb5 := ComboSystem.new(c, g5)
	g5.add_node("item", "ITEM_sxbj")
	g5.add_node("evidence", "EVID_Z_lamp_notes")
	g5.add_node("evidence", "EVID_CI_lhs_word")
	g5.add_node("item", "ITEMS_ccss")
	var step1 := comb5.use_item("evidence:EVID_Z_lamp_notes", "evidence:EVID_CI_lhs_word")
	check("链式第一层：证×词", bool(step1.get("ok", false))
		and String(step1.get("produced_evidence", "")) == "EVID_Z_forged_time", str(step1))
	var step2 := comb5.use_item("evidence:EVID_Z_forged_time", "item:ITEMS_ccss")
	check("链式第二层：证×物", bool(step2.get("ok", false))
		and String(step2.get("produced_evidence", "")) == "EVID_Z_strangled", str(step2))
	var strangled := g5.node(g5.key_of("evidence", "EVID_Z_strangled"))
	check("链式产物的五感来自配方", String(strangled.get("sense", "")) == "touch", str(strangled))

	var g6 := GraphState.new(c)
	var comb6 := ComboSystem.new(c, g6)
	g6.add_node("item", "ITEMS_rxbs")
	g6.add_node("evidence", "EVID_CI_zs_word")
	var knife := comb6.use_item("evidence:EVID_CI_zs_word", "item:ITEMS_rxbs")
	check("词×物反向命中", bool(knife.get("ok", false))
		and String(knife.get("produced_evidence", "")) == "EVID_Z_zs_knife", str(knife))

	var g7 := GraphState.new(c)
	var comb7 := ComboSystem.new(c, g7)
	g7.add_node("evidence", "EVID_Z_lamp_notes")
	g7.add_node("evidence", "EVID_Z_note_voice")
	var wrong := comb7.use_item("evidence:EVID_Z_lamp_notes", "evidence:EVID_Z_note_voice")
	check("同 id 但类型不对的配方不命中", not bool(wrong.get("ok", true))
		and not g7.has("evidence", "EVID_Z_lamp_notes_probe"))


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
	scene.debug.dbg_use_temp_progress(TEMP_PROGRESS)
	scene._save.path = TEMP_SAVE
	scene._save_enabled = false

	await _test_word_drops()
	await _test_glyph()
	await _test_tec_hidden_evidence()
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


func _test_word_drops() -> void:
	# 独白：整段一次贴出 = 完整播放。
	scene.debug.dbg_open_monologue("CHARS_luhengs")
	await process_frame
	check("独白完整播放掉落「词」证据", scene.graph.has("evidence", "EVID_CI_lhs_word"))
	check("掉落的词不被当作已捕获的证",
		not bool(scene.graph.node("evidence:EVID_CI_lhs_word").get("captured", true)))
	var logs: int = int(scene.graph.logs.size())
	scene.debug.dbg_chat_close()
	scene.debug.dbg_open_monologue("CHARS_luhengs")
	await process_frame
	check("重播不重复掉落", scene.graph.logs.size() == logs,
		"%d -> %d" % [logs, scene.graph.logs.size()])
	scene.debug.dbg_chat_close()

	# 对话：补全跳过不算完整播放。
	scene.debug.dbg_open_dialogue("DLG_0704_zs_lhs", ["CHARS_zs", "CHARS_luhengs"])
	await process_frame
	var chat: ChatWindow = scene.debug.dbg_chat()
	for i in 40:
		scene.debug.dbg_chat_finish()
		if not scene.debug.dbg_chat_advance():
			break
	check("对话补全跳过不掉「词」", not scene.graph.has("evidence", "EVID_CI_zs_word"))
	scene.debug.dbg_chat_close()

	# 对话：自然打完才掉。
	scene.debug.dbg_open_dialogue("DLG_0704_zs_lhs", ["CHARS_zs", "CHARS_luhengs"])
	await process_frame
	chat = scene.debug.dbg_chat()
	chat.dbg_set_char_ms(0.1)
	var guard := 0
	while guard < 300 and not scene.graph.has("evidence", "EVID_CI_zs_word"):
		guard += 1
		if chat.is_typing():
			await create_timer(0.02).timeout
		elif not scene.debug.dbg_chat_advance():
			break
	check("对话首次完整播放掉落「词」", scene.graph.has("evidence", "EVID_CI_zs_word"),
		"guard=%d" % guard)
	var logs2: int = int(scene.graph.logs.size())
	scene.debug.dbg_chat_close()
	scene.debug.dbg_open_dialogue("DLG_0704_zs_lhs", ["CHARS_zs", "CHARS_luhengs"])
	await process_frame
	chat = scene.debug.dbg_chat()
	chat.dbg_set_char_ms(0.1)
	guard = 0
	while guard < 300 and not chat.state().get("done", false):
		guard += 1
		if chat.is_typing():
			await create_timer(0.02).timeout
		elif not scene.debug.dbg_chat_advance():
			break
	check("对话重播不重复掉落", scene.graph.logs.size() == logs2,
		"%d -> %d" % [logs2, scene.graph.logs.size()])
	scene.debug.dbg_chat_close()

	# 回忆：同口径。
	var mem := c.memory_for("SCENES_0602", "CHARS_luhengs", "SCENES_garden")
	scene._open_memory_play(mem, scene.graph.scene_key("SCENES_garden"))
	await process_frame
	var mem_card: MemCard = scene.debug.dbg_mem_card()
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
		scene.debug.dbg_close_mem()


func _test_glyph() -> void:
	var item: String = scene.debug.dbg_ensure("item", "ITEM_sxbj")
	var word: String = scene.debug.dbg_ensure("evidence", "EVID_CI_lhs_word")
	var zheng: String = scene.debug.dbg_ensure("evidence", "EVID_Z_strangled")
	await process_frame
	for pair in [[item, "物", false], [word, "词", true], [zheng, "证", true]]:
		var card: NodeCard = _cards().get(String(pair[0]), null)
		var glyph_text: String = ""
		if card != null:
			glyph_text = card._glyph.glyph_override if card._glyph.glyph_override != "" \
				else String(KindGlyph.GLYPH_TEXT.get(card._glyph.kind, ""))
		check("卡片字牌 = " + String(pair[1]),
			card != null and glyph_text == String(pair[1])
				and card._glyph.filled == bool(pair[2]),
			"null" if card == null else "%s / %s" % [glyph_text, card._glyph.filled])
	var wcard: NodeCard = _cards().get(word, null)
	if wcard != null:
		check("1x 字牌字号 12", KindGlyph.glyph_font_px(wcard._glyph.radius, 1.0) == 12,
			str(KindGlyph.glyph_font_px(wcard._glyph.radius, 1.0)))
		wcard.set_lod(0.8)
		check("缩略档文字退场、字牌放大",
			not wcard._title.visible and wcard._glyph.visible and wcard._glyph.size.x > 60.0,
			"%.0f" % wcard._glyph.size.x)
		wcard.set_lod(1.0)
	scene.debug.dbg_select(item)
	scene._refresh_detail(true)
	var detail: DetailWin = scene._detail_win
	check("物品详情标出可用作证据原料", detail != null and not detail._status_text(
		scene.graph.node(item), "item").is_empty()
			and detail._status_text(scene.graph.node(item), "item").contains("可用作证据原料"),
		"" if detail == null else detail._status_text(scene.graph.node(item), "item"))

	# 画布合成：Desktop 入口也要把产物上画布、记案卷、弹 toast。
	scene.debug.dbg_ensure("item", "ITEM_taideng")
	await process_frame
	var logs_before: int = int(scene.graph.logs.size())
	scene.debug.dbg_combo_ui("ITEM_sxbj", "ITEM_taideng")
	await process_frame
	var made: String = scene.graph.key_of("evidence", "EVID_Z_lamp_notes")
	var made_card: NodeCard = _cards().get(made, null)
	check("画布合成产物上卡", made_card != null and scene.graph.has("evidence", "EVID_Z_lamp_notes"))
	check("画布合成进案卷", scene.graph.logs.size() > logs_before and _last_log().contains("获得"),
		_last_log())
	check("画布合成有 toast", scene.debug.dbg_toast_text().contains("获得证据"),
		scene.debug.dbg_toast_text())
	check("画布合成产物 origin=synth",
		String(scene.graph.node(made).get("origin", "")) == "synth", str(scene.graph.node(made)))
	check("画布合成原料还在",
		scene.graph.has("item", "ITEM_sxbj") and scene.graph.has("item", "ITEM_taideng"))
	if made_card != null:
		made_card.set_lod(1.0)
	check("画布合成「新」角标", made_card != null and made_card._badge.visible)


func _test_tec_hidden_evidence() -> void:
	## 帘幕上挂着隐藏证「阳光」：TEC 分析应把它落成一张证卡。
	var lianmu: String = scene.debug.dbg_ensure("item", "ITEM_lianmu")
	await process_frame
	check("TEC 开始分析帘幕", scene.debug.dbg_tec_analyze_key(lianmu))
	scene.debug.dbg_tec_complete()
	await process_frame
	await process_frame
	check("TEC 分析掉落「证」", scene.graph.has("evidence", "DATA_T_sun"))
	var card: NodeCard = _cards().get(scene.graph.key_of("evidence", "DATA_T_sun"), null)
	if card != null:
		card.set_lod(1.0)
	check("TEC 证卡带「新」角标", card != null and card._badge.visible
		and scene.graph.has_unread(card.card_key), "null" if card == null else str(card._badge.visible))
	check("TEC 产出的证 origin=tec",
		String(scene.graph.node("evidence:DATA_T_sun").get("origin", "")) == "tec",
		str(scene.graph.node("evidence:DATA_T_sun")))
	check("TEC 产出的证已捕获",
		bool(scene.graph.node("evidence:DATA_T_sun").get("captured", false)))


func _test_drop_rules() -> void:
	var zheng: String = scene.debug.dbg_ensure("evidence", "EVID_Z_zs_knife")
	await process_frame
	scene._apply_drop("bag-dock", zheng)
	check("物品拒证", String(scene.graph.stored.get(zheng, "")) != GraphState.BAG,
		String(scene.graph.stored.get(zheng, "")))
	check("物品拒证话术", _last_log().contains("「物品」收物与词"), _last_log())
	scene._apply_drop("clue-icon", zheng)
	check("证据收证", String(scene.graph.stored.get(zheng, "")) == GraphState.LEDGER,
		String(scene.graph.stored.get(zheng, "")))
	scene.graph.take_back(zheng)
	scene._apply_drop("infer-icon", zheng)
	check("推演桌布收证", scene.graph.matrix_has("EVID_Z_zs_knife"))
	scene._apply_drop("tec-dock", zheng)
	check("TEC 拒收证", not scene._tec.is_analyzing())
	check("TEC 拒收证话术", _last_log().contains("已经是结论"), _last_log())

	var word: String = scene.debug.dbg_ensure("evidence", "EVID_CI_lhs_word")
	await process_frame
	scene._apply_drop("clue-icon", word)
	check("证据拒词", String(scene.graph.stored.get(word, "")) != GraphState.LEDGER)
	check("证据拒词话术", _last_log().contains("「证据」只收证"), _last_log())
	scene._apply_drop("infer-icon", word)
	check("推演桌布拒词", not scene.graph.matrix_has("EVID_CI_lhs_word"))
	check("推演桌布拒词话术", _last_log().contains("带五感的「证」"), _last_log())
	scene._apply_drop("bag-dock", word)
	check("物品收词", String(scene.graph.stored.get(word, "")) == GraphState.BAG,
		String(scene.graph.stored.get(word, "")))
	scene.graph.take_back(word)
	scene._apply_drop("tec-dock", word)
	check("TEC 拒收词", _last_log().contains("词是证言"), _last_log())

	var item: String = scene.debug.dbg_ensure("item", "ITEMS_a4paper")
	await process_frame
	scene._apply_drop("clue-icon", item)
	check("证据拒物", String(scene.graph.stored.get(item, "")) != GraphState.LEDGER)
	check("证据拒物话术", _last_log().contains("物是原料"), _last_log())
	scene._apply_drop("bag-dock", item)
	check("物品收物", String(scene.graph.stored.get(item, "")) == GraphState.BAG,
		String(scene.graph.stored.get(item, "")))
	scene.graph.take_back(item)


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

	scene.debug.dbg_people_row("CHARS_luhengs")
	await process_frame
	await process_frame
	var card = scene.debug.dbg_person_card()
	check("档案卡含两个关键字段", card != null
		and scene.debug.dbg_person_fields("CHARS_luhengs").size() == 2)
	check("有字段时档案卡自动增高", card != null and card.size.y > 360.0,
		str(card.size) if card != null else "null")

	var item: String = scene.graph.key_of("item", "ITEM_sxbj")
	var word: String = scene.graph.key_of("evidence", "EVID_CI_lhs_word")
	var zheng: String = scene.graph.key_of("evidence", "EVID_Z_strangled")
	check("物→字段退回", not scene.debug.dbg_person_field_drop("CHARS_luhengs", "FIELD_lhs_cause", item))
	check("物退回话术", _last_log().contains("是物，只是原料"), _last_log())
	check("词→字段退回", not scene.debug.dbg_person_field_drop("CHARS_luhengs", "FIELD_lhs_cause", word))
	check("词退回话术", _last_log().contains("先和物合成「证」"), _last_log())
	check("证→字段待核对",
		scene.debug.dbg_person_field_drop("CHARS_luhengs", "FIELD_lhs_cause", zheng))
	await process_frame
	check("待核对态", scene.debug.dbg_person_field_state("FIELD_lhs_cause") == "pending",
		scene.debug.dbg_person_field_state("FIELD_lhs_cause"))
	check("待核对虚线框",
		card != null and card.find_child("field_pending_dash", true, false) != null)
	check("词库按钮存在",
		card != null and card.find_child("field_opt_缢死", true, false) != null)
	scene.debug.dbg_person_field_word("CHARS_luhengs", "FIELD_lhs_cause", "刺伤")
	check("错误词条核对退回", scene.debug.dbg_person_check("CHARS_luhengs"))
	await process_frame
	check("错误主张不盖章", scene.debug.dbg_person_field_state("FIELD_lhs_cause") == "empty",
		scene.debug.dbg_person_field_state("FIELD_lhs_cause"))
	check("错误词条不剧透", " ".join(scene.debug.dbg_tec_win().dbg_lines()).contains("站不住"),
		" ".join(scene.debug.dbg_tec_win().dbg_lines().slice(-3)))

	# 两条待核对一起交批：正确词条 + 正确证据。
	check("重新附上结论", scene.debug.dbg_person_field_drop("CHARS_luhengs", "FIELD_lhs_cause", zheng))
	scene.debug.dbg_person_field_word("CHARS_luhengs", "FIELD_lhs_cause", "缢死")
	check("第二字段附上结论",
		scene.debug.dbg_person_field_drop("CHARS_luhengs", "FIELD_lhs_probe", zheng))
	scene.debug.dbg_person_field_word("CHARS_luhengs", "FIELD_lhs_probe", "绳痕")
	check("批量核对 2 条", scene.debug.dbg_person_check("CHARS_luhengs"))
	await process_frame
	check("死因盖章", scene.debug.dbg_person_field_state("FIELD_lhs_cause") == "stamped",
		scene.debug.dbg_person_field_state("FIELD_lhs_cause"))
	check("致死方式盖章", scene.debug.dbg_person_field_state("FIELD_lhs_probe") == "stamped",
		scene.debug.dbg_person_field_state("FIELD_lhs_probe"))
	check("核准进图状态", scene.graph.is_field_confirmed("CHARS_luhengs", "FIELD_lhs_cause")
		and scene.graph.is_field_confirmed("CHARS_luhengs", "FIELD_lhs_probe"))
	var stamped_box := card.find_child("field_FIELD_lhs_cause", true, false) as PanelContainer
	var stamped_sb := stamped_box.get_theme_stylebox("panel") as StyleBoxFlat if stamped_box != null else null
	check("盖章警示朱 2px 框",
		stamped_sb != null and stamped_sb.border_width_top == 2
			and stamped_sb.border_color.is_equal_approx(TecTheme.SPOT_DANGER),
		str(stamped_sb))
	var mc_key: String = scene.graph.key_of("evidence", "CLUES_mc")
	check("字段集齐掉落人物证据", scene.graph.captured.has("CLUES_mc") and scene.graph.has("evidence", "CLUES_mc"))
	check("人物证据 origin=deduce / 已捕获",
		String(scene.graph.node(mc_key).get("origin", "")) == "deduce"
			and bool(scene.graph.node(mc_key).get("captured", false)),
		str(scene.graph.node(mc_key)))
	check("人物证据卡在画布", _cards().has(mc_key))
	var tec_win = scene.debug.dbg_tec_win()
	var true_line := false
	if tec_win != null:
		for row in tec_win._lines.get_children():
			if row is TypewriterLabel and row.find_child("true_clue_mark", true, false) != null:
				true_line = true
				break
	check("真名级证据触发 G14 反白行", true_line)
	# 把注入字段摘掉，避免影响后续测试 / 自动存档。
	ch.evidence_fields.erase(extra)
