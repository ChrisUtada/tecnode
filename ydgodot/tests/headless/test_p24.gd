extends SceneTree
## P2.4 多人对话 / 独白：语境匹配、loose 选中、等待加入、打字机窗口。

const TEMP_PROGRESS := "user://test_p24_progress.json"
const TEMP_SAVE := "user://test_p24_case.save"

var fails := 0
var total := 0


func check(name: String, cond: bool, detail: String = "") -> void:
	total += 1
	if cond:
		print("  PASS  ", name)
	else:
		fails += 1
		print("  FAIL  ", name, ("  [" + detail + "]") if detail != "" else "")


func _initialize() -> void:
	print("=== P2.4 多人对话 / 打字机 / 中途加入 / 独白 ===")
	var c := CaseLoader.new(CaseCatalog.path_of("A001"))
	check("案件数据装载", c.load_case(), c.load_error)
	if c.case_def == null:
		_finish()
		return
	_test_data(c)
	_test_context(c)
	_test_session(c)
	await _test_desktop(c)
	_finish()


func _finish() -> void:
	_cleanup()
	print("=== %d 项，失败 %d ===" % [total, fails])
	quit(0 if fails == 0 else 1)


func _cleanup() -> void:
	for path in [TEMP_PROGRESS, TEMP_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_data(c: CaseLoader) -> void:
	check("三条对话剧本", c.dialogues.size() == 3, str(c.dialogues.size()))
	check("三人剧本存在", c.dialogues.any(func(d): return d.id == "DLG_garden_review"))
	check("语境剧本存在", c.dialogues.any(func(d): return d.id == "DLG_0704_zs_lhs"))
	check("独白存在", c.dialogues.any(func(d): return d.id == "DLG_lhs_alone"))
	var garden: DialogueDef = null
	var ctx: DialogueDef = null
	var solo: DialogueDef = null
	for d in c.dialogues:
		if d.id == "DLG_garden_review":
			garden = d
		elif d.id == "DLG_0704_zs_lhs":
			ctx = d
		elif d.id == "DLG_lhs_alone":
			solo = d
	check("三人剧本 6 行", garden != null and garden.script_lines.size() == 6,
		str(garden.script_lines.size() if garden != null else -1))
	check("三人剧本 3 位参与者", garden != null and garden.participants.size() == 3)
	check("三人剧本第一行旁白", garden != null and garden.script_lines[0].kind == "narr")
	check("语境剧本 12 行", ctx != null and ctx.script_lines.size() == 12,
		str(ctx.script_lines.size() if ctx != null else -1))
	check("语境剧本绑 7/4 × 花园", ctx != null and ctx.context_when != null
		and ctx.context_when.id == "SCENES_0704" and ctx.context_where != null
		and ctx.context_where.id == "SCENES_garden")
	check("独白 4 行", solo != null and solo.script_lines.size() == 4,
		str(solo.script_lines.size() if solo != null else -1))
	check("独白单参与者", solo != null and solo.participants.size() == 1)


func _test_context(c: CaseLoader) -> void:
	var g := GraphState.new(c)
	var ds := DialogueSystem.new(c, g)
	check("现在没有回忆语境", ds.context().is_empty(), str(ds.context()))

	g.time = "SCENES_0704"
	var here := ds.context()
	check("7/4 语境 when", String(here.get("when", "")) == "SCENES_0704", str(here))
	check("7/4 语境 where = 花园", String(here.get("where", "")) == "SCENES_garden", str(here))
	var zs_lhs := ds.lookup(["CHARS_zs", "CHARS_luhengs"])
	check("7/4 两人命中语境剧本", zs_lhs != null and zs_lhs.id == "DLG_0704_zs_lhs",
		zs_lhs.id if zs_lhs != null else "null")
	check("键顺序无关", ds.set_key(["CHARS_luhengs", "CHARS_zs"]) == ds.set_key(["CHARS_zs", "CHARS_luhengs"]))
	check("两人不是独白", not ds.has_monologue("CHARS_zs"))

	var wrong_where := {"when": "SCENES_0704", "where": "SCENES_body"}
	check("地点不符 = miss", ds.dialogue_fit(zs_lhs, wrong_where) == "miss",
		ds.dialogue_fit(zs_lhs, wrong_where))

	g.time = "SCENES_0602"
	check("6/2 两人不播 7/4 剧本", ds.lookup(["CHARS_zs", "CHARS_luhengs"]) == null)
	check("6/2 两人算语境不合", ds.blocked(["CHARS_zs", "CHARS_luhengs"]))
	var fb := ds.lookup(["CHARS_zs", "NPC_FB"])
	check("两人可 loose 命中三人剧本", fb != null and fb.id == "DLG_garden_review",
		fb.id if fb != null else "null")
	check("loose 不是精确集合", ds.set_key(ds.participant_ids(fb)) != ds.set_key(["CHARS_zs", "NPC_FB"]))
	check("三人全集精确命中", ds.lookup(["CHARS_zs", "NPC_FB", "CHARS_JS"]).id == "DLG_garden_review")
	check("不相干组合没有剧本", ds.lookup(["CHARS_luhengs", "NPC_FB"]) == null)
	check("不相干组合不算 blocked", not ds.blocked(["CHARS_luhengs", "NPC_FB"]))

	var miss := ds.fallback(["CHARS_zs", "CHARS_luhengs"])
	check("语境不合 fallback 文案", miss.script_lines[0].text == "此刻他们没什么可说的。",
		miss.script_lines[0].text)
	var plain := ds.fallback(["CHARS_luhengs", "NPC_FB"])
	check("普通 fallback 文案", plain.script_lines[0].text == "他们没什么可说的。",
		plain.script_lines[0].text)
	check("fallback 只一行", plain.script_lines.size() == 1)
	check("fallback 带参与者", plain.participants.size() == 2)

	var solo := ds.monologue_of("CHARS_luhengs")
	check("陆珩松独白命中", solo != null and solo.id == "DLG_lhs_alone",
		solo.id if solo != null else "null")
	check("独白可跨语境", ds.monologue_of("CHARS_luhengs", {"when": "SCENES_0602", "where": "SCENES_garden"}) != null)
	check("朱穗没有独白", ds.monologue_of("CHARS_zs") == null)
	check("按 id 取剧本", ds.by_id("DLG_0704_zs_lhs") != null and ds.by_id("NOPE") == null)


func _test_session(c: CaseLoader) -> void:
	var ds := DialogueSystem.new(c, GraphState.new(c))
	var entry := ds.by_id("DLG_garden_review")
	var s := DialogueSession.new(entry, ["CHARS_zs", "NPC_FB"])
	check("会话总数", s.total() == 6, str(s.total()))
	check("初始两人已加入", s.joined.size() == 2 and s.is_joined("CHARS_zs") and s.is_joined("NPC_FB"))
	var r := s.step()
	check("第一行旁白", String(r.get("status", "")) == "line" and r["line"].kind == "narr")
	r = s.step()
	check("第二行朱穗", String(r.get("status", "")) == "line" and r["line"].who.id == "CHARS_zs")
	r = s.step()
	check("第三行等槿杉", String(r.get("status", "")) == "wait" and s.waiting_for == "CHARS_JS", str(r))
	check("等待不推进 index", s.index == 2, str(s.index))
	check("重复 step 仍等待", String(s.step().get("status", "")) == "wait" and s.index == 2)
	var join_wrong := s.join("NPC_FB")
	check("已加入者不重复", not bool(join_wrong.get("ok", true)) and String(join_wrong.get("reason", "")) == "joined")
	join_wrong = s.join("CHARS_luhengs")
	check("错的人插不上", not bool(join_wrong.get("ok", true)) and String(join_wrong.get("reason", "")) == "wrong")
	check("错的人不改变等待", s.waiting_for == "CHARS_JS")
	var join_ok := s.join("CHARS_JS")
	check("等的人可加入", bool(join_ok.get("ok", false)) and s.waiting_for == "")
	check("加入后可续播", String(s.step().get("status", "")) == "line" and s.index == 3, str(s.index))
	check("三人已齐", s.joined.size() == 3 and s.is_joined("CHARS_JS"))
	var guard := 0
	while not s.done and guard < 20:
		s.step()
		guard += 1
	check("播完 done", s.done and s.index == 6, "done=%s idx=%d" % [str(s.done), s.index])
	check("播完再 step 仍 done", String(s.step().get("status", "")) == "done")
	check("播完不能再加人", not bool(s.join("CHARS_JS").get("ok", true)))

	var st := s.state()
	check("state 带 participants", (st["participants"] as Array).size() == 3, str(st["participants"]))
	check("state 带 joined", (st["joined"] as Array).size() == 3, str(st["joined"]))
	check("state 带 total", int(st["total"]) == 6 and int(st["idx"]) == 6)

	var ctx := ds.by_id("DLG_0704_zs_lhs")
	var s2 := DialogueSession.new(ctx, ["CHARS_zs", "CHARS_luhengs"])
	s2.join("CHARS_JS")
	check("不在等待时插不上", s2.joined.size() == 2)


func _test_desktop(c: CaseLoader) -> void:
	print("--- P2.4 对话窗 / 拖人加入 / 独白 / 生命周期 ---")
	var scene: Control = load("res://scenes/Desktop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.dbg_use_temp_progress(TEMP_PROGRESS)
	scene._save.path = TEMP_SAVE
	scene._save_enabled = false
	check("对话系统就绪", scene.dbg_dialogues() != null)
	check("初始无对话窗", scene.dbg_chat() == null)

	scene.dbg_expand("SCENES_lhsdst")
	scene.dbg_expand("SCENES_fkjl")
	await process_frame
	scene.dbg_set_time("SCENES_0602")
	await process_frame
	scene.dbg_set_time("SCENES_0704")
	await process_frame
	scene.dbg_close_mem()
	await process_frame
	check("7/4 已切换", scene.dbg_time() == "SCENES_0704", scene.dbg_time())

	scene.dbg_combo_ui("CHARS_zs", "CHARS_luhengs")
	await process_frame
	var chat: ChatWindow = scene.dbg_chat()
	check("人物拖人物开对话窗", chat != null)
	if chat == null:
		scene.queue_free()
		return
	var state: Dictionary = scene.dbg_chat_state()
	check("对话窗 id", String(state["id"]) == "DLG_0704_zs_lhs", str(state["id"]))
	check("对话窗标题带日期与两人", scene.dbg_chat_title() == "DIALOGUE // 7月4日 · 朱穗 × 陆珩松",
		scene.dbg_chat_title())
	check("初始两行参与者已加入", (state["joined"] as Array).size() == 2, str(state["joined"]))
	check("对话窗贴右上", chat.position == Vector2(858, 58), str(chat.position))
	check("对话窗 390 宽", chat.size.x == 418.0, str(chat.size))
	check("首行已贴出", int(state["lines"]) == 1 and chat.line_count() == 1, str(state["lines"]))
	check("打字未完成", chat.is_typing())
	check("打字机 45ms/字", ChatWindow.CHAR_MS == 45.0, str(ChatWindow.CHAR_MS))
	var first_text := String(scene.dbg_dialogues().by_id("DLG_0704_zs_lhs").script_lines[0].text)
	check("首行是旁白原文", chat.current_text() == first_text, chat.current_text())
	check("补全本句", scene.dbg_chat_advance())
	check("补全后仍只有一行", chat.line_count() == 1 and not chat.is_typing())
	check("再点出朱穗台词", scene.dbg_chat_advance() and chat.line_count() == 2)
	scene.dbg_chat_finish()
	check("台词行已贴出", chat.line_count() == 2)

	check("切时刻关对话窗", scene.dbg_set_time("SCENES_0602") and scene.dbg_chat() == null)
	await process_frame
	scene.dbg_close_mem()
	scene.dbg_set_time("present")
	await process_frame
	scene.dbg_close_mem()
	await process_frame
	scene.dbg_combo_ui("CHARS_zs", "CHARS_luhengs")
	await process_frame
	chat = scene.dbg_chat()
	check("现在档语境不合仍开窗", chat != null)
	if chat != null:
		state = scene.dbg_chat_state()
		check("fallback id 为空", String(state["id"]) == "" and int(state["total"]) == 1, str(state))
		check("fallback 文案", chat.current_text() == "此刻他们没什么可说的。", chat.current_text())
		scene.dbg_chat_close()
	check("close 后引用清空", scene.dbg_chat() == null)

	scene.dbg_set_time("SCENES_0704")
	await process_frame
	scene.dbg_close_mem()
	check("双击人物开独白", scene.dbg_activate("char:CHARS_luhengs") or scene.dbg_chat() != null)
	await process_frame
	chat = scene.dbg_chat()
	check("独白窗打开", chat != null)
	if chat != null:
		state = scene.dbg_chat_state()
		check("独白标题", scene.dbg_chat_title() == "独白 // 陆珩松", scene.dbg_chat_title())
		check("独白 id", String(state["id"]) == "DLG_lhs_alone", str(state["id"]))
		check("独白一人", String(state["id"]) == "DLG_lhs_alone"
			and (state["participants"] as Array).size() == 1)
		check("独白 4 句", int(state["total"]) == 4, str(state["total"]))
		check("独白首行旁白", chat.current_text() == String(
			scene.dbg_dialogues().by_id("DLG_lhs_alone").script_lines[0].text))
		scene.dbg_chat_close()

	check("测试钩子开三人剧本", scene.dbg_open_dialogue("DLG_garden_review", ["CHARS_zs", "NPC_FB"]))
	await process_frame
	chat = scene.dbg_chat()
	check("三人剧本开窗", chat != null)
	if chat != null:
		check("三人剧本标题无日期", scene.dbg_chat_title() == "DIALOGUE // 朱穗 × 傅柏",
			scene.dbg_chat_title())
		scene.dbg_chat_finish()
		scene.dbg_chat_advance()
		scene.dbg_chat_finish()
		scene.dbg_chat_advance()
		state = scene.dbg_chat_state()
		check("播到槿杉开始等待", String(state["waitingFor"]) == "CHARS_JS", str(state["waitingFor"]))
		check("等待时贴提示", scene.dbg_chat_hint() == "把「槿杉」拖进对话框", scene.dbg_chat_hint())
		await process_frame
		check("等待时不再贴行", chat.line_count() == 2, str(chat.line_count()))
		check("等待时点击不推进", not scene.dbg_chat_advance() and chat.line_count() == 2)
		check("错的人插不上", not scene.dbg_chat_drop("char", "CHARS_luhengs"))
		check("插不上话提示", scene.dbg_chat_hint() == "插不上话", scene.dbg_chat_hint())
		check("错的人不解除等待", String(scene.dbg_chat_state()["waitingFor"]) == "CHARS_JS")
		check("非人物不能加入", not scene.dbg_chat_drop("item", "ITEM_shoudiantong"))
		check("非人物提示", scene.dbg_chat_hint() == "只有人物能加入这段对话", scene.dbg_chat_hint())
		var key := "char:CHARS_JS"
		scene._on_card_drag_released(key, scene.dbg_chat_rect().get_center())
		await process_frame
		state = scene.dbg_chat_state()
		check("拖对人加入", (state["joined"] as Array).has("CHARS_JS"), str(state["joined"]))
		check("加入后续播", String(state["waitingFor"]) == "" and chat.line_count() == 3,
			"wait=%s lines=%d" % [str(state["waitingFor"]), chat.line_count()])
		check("加入后提示消失", scene.dbg_chat_hint() == "", scene.dbg_chat_hint())
		scene.dbg_chat_finish()
		var guard := 0
		while not bool(scene.dbg_chat_state()["done"]) and guard < 20:
			scene.dbg_chat_advance()
			scene.dbg_chat_finish()
			guard += 1
		check("三人剧本播完", bool(scene.dbg_chat_state()["done"]), str(scene.dbg_chat_state()))
		check("六行全贴出", chat.line_count() == 6, str(chat.line_count()))
		scene.dbg_chat_close()

	check("重置关对话窗", scene.dbg_open_dialogue("DLG_garden_review", ["CHARS_zs", "NPC_FB"])
		and scene.dbg_chat() != null)
	scene.dbg_chat_close()
	check("时钟切换后无残留", scene.dbg_chat() == null)

	scene.queue_free()
	await process_frame
