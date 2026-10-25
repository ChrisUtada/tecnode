extends SceneTree
## P2.6 批 1：人物名册（PeopleWin）/ 因果追踪（LogWin）/ 图标栏 8 项 + 自由拖动 + 四角标。
##
## 口径全部对齐 Web：
##   · 日志 = 案卷，只记「结果」（`03-utils.js:250-262`）—— 展开容器、收入取出、对话台词本身都不记；
##   · 名册 = 常驻两人 + 已结识（`12-panels.js:380-506`）—— 纸面提及不算、常驻在前；
##   · 图标栏 = `ICON_LAYOUT` 8 项 + 动态 2 项，位置可拖（不进撤销栈、重置不回位）。

const TEMP_PROGRESS := "user://test_p26_progress.json"
const TEMP_SAVE := "user://test_p26_case.save"

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
	print("=== P2.6 人物名册 / 因果追踪 / 图标栏 ===")
	var c := CaseLoader.new(CaseCatalog.path_of("A001"))
	check("案件数据装载", c.load_case(), c.load_error)
	if c.case_def == null:
		_finish()
		return
	_test_log_core(c)
	_test_roster_core(c)
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


# ── 日志底层 ────────────────────────────────────────────────────────────

func _test_log_core(c: CaseLoader) -> void:
	print("--- 因果追踪：底层 ---")
	var g := GraphState.new(c)
	check("初始没有日志", g.log_count() == 0 and g.logs.is_empty())

	g.add_log("第一条")
	g.add_log("第二条", "warn")
	check("追加两条", g.log_count() == 2, str(g.log_count()))
	check("默认 kind 为空串", String(g.logs[0]["kind"]) == "", str(g.logs[0]))
	check("kind 原样保留", String(g.logs[1]["kind"]) == "warn", str(g.logs[1]))
	check("文本原样保留", String(g.logs[0]["text"]) == "第一条")

	g.add_log("")
	check("空文本不入账", g.log_count() == 2, str(g.log_count()))

	# 日志是 DOM 级的旁挂状态：快照里没有它，撤销 / 读档也不会动它
	var ss := SaveSystem.new(g)
	var snap := ss.snapshot()
	check("快照不含日志", not snap.has("logs"), str(snap.keys()))
	g.add_log("撤销也不该吞掉我", "sys")
	check("读档不回滚日志", ss.restore(snap) and g.log_count() == 3, str(g.log_count()))
	check("读档后文本仍在", String(g.logs[2]["text"]) == "撤销也不该吞掉我")

	g.clear_logs()
	check("清空日志", g.log_count() == 0)


# ── 名册底层 ────────────────────────────────────────────────────────────

func _test_roster_core(c: CaseLoader) -> void:
	print("--- 人物名册：底层 ---")
	var g := GraphState.new(c)
	check("常驻两人", GraphState.ROSTER_PINNED == ["CHARS_TEC", "CHARS_EXEC"])
	check("空档只有常驻", g.met_char_ids() == ["CHARS_TEC", "CHARS_EXEC"], str(g.met_char_ids()))

	# 常驻在前、其余按 id 排序
	g.explored["SCENES_0602"] = true
	var met := g.met_char_ids()
	check("探索过的场景收录人物", met.size() == 5, str(met))
	check("常驻仍在前两位", String(met[0]) == "CHARS_TEC" and String(met[1]) == "CHARS_EXEC")
	check("其余按 id 排序", met.slice(2) == ["CHARS_JS", "CHARS_luhengs", "NPC_FB"], str(met.slice(2)))

	# 只读到名字（纸面提及）不算结识
	var g2 := GraphState.new(c)
	g2.add_node("clue", "CLUES_CBKW")
	check("纸面提及不进名册", g2.met_char_ids() == ["CHARS_TEC", "CHARS_EXEC"], str(g2.met_char_ids()))

	# 有节点但还没登场（debuted）也不算
	g2.add_node("char", "CHARS_zs")
	check("节点未登场不进名册", not g2.met_char_ids().has("CHARS_zs"), str(g2.met_char_ids()))
	g2.meet_char_at("CHARS_zs", "SCENES_0704")
	check("登场后进名册", g2.met_char_ids().has("CHARS_zs"), str(g2.met_char_ids()))

	# 到过某个时刻（放过放映卡）也算
	var g3 := GraphState.new(c)
	g3.card_seen["SCENES_0704"] = true
	var met3 := g3.met_char_ids()
	check("到过时刻收录该时刻的人", met3.has("CHARS_zs") and met3.has("CHARS_luhengs"), str(met3))

	# 对话队列 = talkQueue + 他所在的场景(sceneTalks)
	var g4 := GraphState.new(c)
	var n := g4.add_node("char", "CHARS_luhengs")
	check("九/十句基础队列", g4.char_talk_queue("CHARS_luhengs").size() == 11,
		str(g4.char_talk_queue("CHARS_luhengs").size()))
	check("没落场景就不加场台词", g4.char_talk_queue("CHARS_JS").is_empty(),
		str(g4.char_talk_queue("CHARS_JS").size()))
	(n as Dictionary)["home_scene"] = "SCENES_0704"
	check("落场后加到 14 句", g4.char_talk_queue("CHARS_luhengs").size() == 14,
		str(g4.char_talk_queue("CHARS_luhengs").size()))
	check("队列没有空行", not g4.char_talk_queue("CHARS_luhengs").has(""))

	var pr: Dictionary = g4.char_progress("CHARS_luhengs")
	check("进度初始 0", int(pr["prog"]) == 0 and int(pr["total"]) == 14, str(pr))
	g4.talk_prog[g4.key_of("char", "CHARS_luhengs")] = 3
	pr = g4.char_progress("CHARS_luhengs")
	check("进度跟随 talk_prog", int(pr["prog"]) == 3, str(pr))

	var g5 := GraphState.new(c)
	check("无节点时进度归 0", int(g5.char_progress("CHARS_zs")["prog"]) == 0)


# ── 桌面：图标栏 / 日志窗 / 名册窗 ──────────────────────────────────────

func _test_desktop(c: CaseLoader) -> void:
	print("--- 桌面：图标栏 / 日志窗 / 名册窗 ---")
	var scene: Control = load("res://scenes/Desktop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.dbg_use_temp_progress(TEMP_PROGRESS)
	scene._save.path = TEMP_SAVE
	scene._save_enabled = false

	var win_bar := scene.get_node_or_null("desk/case_win/bar") as Control
	check("主窗标题栏内高 27（Web 28 - 1 分隔线）",
		win_bar != null and win_bar.size.y == 27.0,
		str(win_bar.size) if win_bar != null else "null")
	var close := scene.get_node_or_null("desk/case_win/bar/close") as Button
	check("关闭按钮实际 18×18（字形不再撑高）",
		close != null and close.size == Vector2(18, 18)
		and close.get_combined_minimum_size() == Vector2(18, 18),
		(str(close.size) + " / " + str(close.get_combined_minimum_size())) if close != null else "null")
	var badge := scene.get_node_or_null("desk/icons/icon_infer/infer_badge") as PanelContainer
	var badge_sb: StyleBoxFlat = null
	if badge != null:
		badge_sb = badge.get_theme_stylebox("panel") as StyleBoxFlat
	check("图标角标是药丸（P4.1 恢复圆头）",
		badge_sb != null and badge_sb.corner_radius_top_left >= 100,
		str(badge_sb.corner_radius_top_left) if badge_sb != null else "null")

	# 1) 图标栏：8 项常驻，顺序即 ICON_LAYOUT
	var apps: Array = scene.dbg_icon_apps()
	check("图标栏 8 项", apps.size() == 8, str(apps))
	check("图标顺序对齐 ICON_LAYOUT",
		apps == ["infer", "goto", "clue", "people", "bag", "tec", "log", "map"], str(apps))
	check("推演器在首位", scene.dbg_icon_pos("infer").x == 18.0 and scene.dbg_icon_pos("infer").y == 16.0,
		str(scene.dbg_icon_pos("infer")))
	var pitch: float = float(scene.dbg_icon_pos("goto").y) - float(scene.dbg_icon_pos("infer").y)
	## P2：常驻档按「64px 槽 + 12px 间距」= 76；只有 960×560 放不下时才切紧凑。
	## 720 基准（desk 668）8 项总高 612，仍走常驻档。
	var want_pitch := 76.0
	check("步距按 P2 图标秩序 = 64 + 12", absf(pitch - want_pitch) < 0.01,
		str(pitch) + " / want " + str(want_pitch))
	var even := true
	for i in range(1, apps.size()):
		var gap: float = scene.dbg_icon_pos(String(apps[i])).y - scene.dbg_icon_pos(String(apps[i - 1])).y
		if absf(gap - pitch) > 0.01:
			even = false
	check("八项等距", even, str(pitch))
	check("播放器 / 花园初始不占位",
		not scene.dbg_icon_visible("music") and not scene.dbg_icon_visible("garden"))

	# 2) 自由拖动：位置变了、不进撤销栈
	var hist0: int = scene.dbg_history_size()
	scene.dbg_drag_icon("infer", Vector2(300, 420))
	check("图标可拖到任意位置", scene.dbg_icon_pos("infer") == Vector2(300, 420),
		str(scene.dbg_icon_pos("infer")))
	check("拖动不进撤销栈", scene.dbg_history_size() == hist0, str(scene.dbg_history_size()))
	scene.dbg_drag_icon("infer", Vector2(18, 16))
	check("拖回原位", scene.dbg_icon_pos("infer") == Vector2(18, 16), str(scene.dbg_icon_pos("infer")))

	# 2a) 真指针事件走 DeskIcon 自己的手势：5px 内 = 点击，超出 = 拖动且吞掉点击
	var ic: Control = scene.get_node("desk/icons/icon_infer")
	var hits := {"n": 0}
	ic.clicked.connect(func(): hits["n"] += 1)
	var base: Vector2 = ic.position
	var at: Vector2 = ic.get_global_rect().get_center()
	_icon_press(ic, at, true)
	_icon_press(ic, at + Vector2(1, 1), false)
	check("1px 抖动 = 点击", int(hits["n"]) == 1, str(hits["n"]))
	check("点击不挪位置", ic.position == base, str(ic.position))
	check("单击图标进入选中", bool(ic.get("_selected")))
	scene._clear_selection()
	check("空白点击清图标选中", not bool(ic.get("_selected")))

	_icon_press(ic, at, true)
	_icon_move(ic, at + Vector2(40, 30))
	_icon_press(ic, at + Vector2(40, 30), false)
	check("拖动：位置跟着指针走", ic.position == base + Vector2(40, 30), str(ic.position))
	check("拖动后吞掉点击", int(hits["n"]) == 1, str(hits["n"]))
	scene.dbg_drag_icon("infer", Vector2(18, 16))
	check("拖回后坐标复原", ic.position == Vector2(18, 16), str(ic.position))

	# 2b) 双击图标才开窗（单击只选中）
	var people_ic: Control = scene.get_node("desk/icons/icon_people")
	scene.dbg_double_click_icon("people")
	check("双击人物图标开名册", scene.dbg_people_win() != null)
	check("双击后图标不残留选中", not bool(people_ic.get("_selected")))
	scene.dbg_close_people()
	await process_frame
	scene.dbg_double_click_icon("log")
	check("双击日志图标开日志窗", scene.dbg_log_win() != null)
	scene.dbg_close_log()
	await process_frame
	check("关窗后引用清空", scene.dbg_people_win() == null and scene.dbg_log_win() == null)

	# 3) 四个角标：推演器 / 证物袋 / 线索册 / 日志
	check("初始四角标都收着",
		scene.dbg_badge_text("infer") == "" and scene.dbg_badge_text("bag") == ""
		and scene.dbg_badge_text("clue") == "" and scene.dbg_badge_text("log") == "")

	var item_key: String = scene.dbg_ensure("item", "ITEMS_changji")
	scene.dbg_select(item_key)
	await process_frame
	check("收进证物袋", scene.dbg_store(GraphState.BAG))
	await process_frame
	check("证物袋角标 1 件", scene.dbg_badge_text("bag") == "1 件", scene.dbg_badge_text("bag"))
	var bag_ic := scene.get_node_or_null("desk/icons/icon_bag") as DeskIcon
	var bag_badge := scene.get_node_or_null("desk/icons/icon_bag/bag_badge") as Control
	check("E2 徽章右沿贴在图标外 2px",
		bag_ic != null and bag_badge != null
			and absf(bag_badge.position.x + bag_badge.size.x
				- (bag_ic._icon.position.x + DeskIcon.GLYPH_SIZE + 2.0)) < 0.6,
		"null" if bag_badge == null else str(bag_badge.position + bag_badge.size))
	check("E2 徽章顶沿贴在图标外 2px",
		bag_ic != null and bag_badge != null
			and absf(bag_badge.position.y - (bag_ic._icon.position.y - 2.0)) < 0.01,
		"null" if bag_badge == null else str(bag_badge.position.y))

	var clue_key: String = scene.dbg_ensure("clue", "CLUES_CBKW")
	scene.dbg_select(clue_key)
	await process_frame
	check("收进线索册", scene.dbg_store(GraphState.LEDGER))
	await process_frame
	check("线索册角标 1 条", scene.dbg_badge_text("clue") == "1 条", scene.dbg_badge_text("clue"))

	# 4) 日志窗：关着时累未读，开窗清零
	var before_n: int = scene.graph.log_count()
	scene.dbg_add_log("测试：一条案卷", "warn")
	check("写案卷即入账", scene.graph.log_count() == before_n + 1)
	check("窗关着累计未读", scene.dbg_log_unread() == 1, str(scene.dbg_log_unread()))
	check("日志角标显示未读数", scene.dbg_badge_text("log") == "1", scene.dbg_badge_text("log"))

	var lw: LogWin = scene.dbg_open_log()
	check("日志窗打开", lw != null and lw.visible)
	if lw == null:
		scene.queue_free()
		return
	check("K10 日志窗标题统一为「日志」", lw.title == "日志", lw.title)
	check("开窗清未读", scene.dbg_log_unread() == 0)
	check("开窗收角标", scene.dbg_badge_text("log") == "")
	# 补两条已知 kind 的行，样式断言才有靶子
	scene.dbg_add_log("测试：一条系统条", "sys")
	scene.dbg_add_log("测试：一条警告条", "warn")
	lw.refresh_log()
	await process_frame
	check("条目数等于案卷条数", lw.entry_count() == scene.graph.log_count(),
		"%d / %d" % [lw.entry_count(), scene.graph.log_count()])
	check("kind 逐条对齐", lw.kinds() == scene.dbg_log_kinds(), str(lw.kinds()))

	var sys_row := ""
	var warn_row := ""
	for i in lw.entry_count():
		var t := lw.entry_label(i)
		if String(scene.dbg_log_kinds()[i]) == "sys":
			sys_row = t
		elif String(scene.dbg_log_kinds()[i]) == "warn":
			warn_row = t
	check("sys 行正常字重 + ▍ 前缀", sys_row.begins_with("▍ ") and not sys_row.contains("[b]"), sys_row)
	check("warn 行 ※ 前缀", warn_row.begins_with("※ "), warn_row)

	# 5) 日志口径：只记结果，不记操作流水
	# 展开一个「既不是时间锚点、TEC 也没有档案」的场景：一条都不该记
	var n0: int = scene.graph.log_count()
	scene.dbg_expand("SCENES_choutiyi")
	await process_frame
	check("展开容器不记日志", scene.graph.log_count() == n0, str(scene.graph.log_count() - n0))

	n0 = scene.graph.log_count()
	var ck: String = scene.dbg_ensure("clue", "CLUES_JSBW")
	scene.dbg_select(ck)
	await process_frame
	scene.dbg_store(GraphState.LEDGER)
	await process_frame
	check("收入线索册不记日志", scene.graph.log_count() == n0, str(scene.graph.log_count() - n0))

	# 组合成功：一条 act，且不弹提示条（Web 刻意：结果靠画面自证）
	scene.dbg_ensure("item", "ITEMS_cz")
	await process_frame
	var cz_key := "item:ITEMS_cz"
	scene.graph.tried[cz_key + ">loc:SCENES_garden"] = true
	n0 = scene.graph.log_count()
	var toast_before: String = scene.dbg_toast_text()
	scene.dbg_combo_ui("ITEMS_cz", "ITEMS_changji")
	await process_frame
	check("U5 组合消耗后卡片已移除", not scene._cards.has(cz_key))
	check("U5 组合消耗后 tried 已清",
		not scene.graph.tried.has(cz_key + ">loc:SCENES_garden"))
	check("组合成功记一条", scene.graph.log_count() == n0 + 1, str(scene.graph.log_count() - n0))
	var last_kind := String(scene.dbg_log_kinds()[-1])
	check("组合成功是 act", last_kind == "act", last_kind)
	check("组合成功不弹提示条", scene.dbg_toast_text() == toast_before,
		scene.dbg_toast_text())
	var last_text := String(scene.dbg_log_texts()[-1])
	check("组合文案带 ⇒ 与获得", last_text.contains("⇒") and last_text.contains("获得"), last_text)

	# 组合失败：一条 warn
	n0 = scene.graph.log_count()
	scene.dbg_combo_ui("CLUES_CBKW", "ITEMS_changji")
	await process_frame
	if scene.graph.log_count() > n0:
		check("组合失败是 warn", String(scene.dbg_log_kinds()[-1]) == "warn",
			String(scene.dbg_log_kinds()[-1]))
	else:
		check("无效组合不写案卷", scene.graph.log_count() == n0, "没有失败也算对（本就无反应）")

	# 撤销也不回滚案卷
	n0 = scene.graph.log_count()
	scene.dbg_add_log("撤销前的最后一条", "sys")
	var after_log: int = scene.graph.log_count()
	check("撤销不动案卷", scene.dbg_undo() and scene.graph.log_count() == after_log,
		"%d -> %d" % [after_log, scene.graph.log_count()])
	check("案卷只增不减", scene.graph.log_count() == n0 + 1)

	# 6) 名册窗
	scene.dbg_set_time("SCENES_0704")
	await process_frame
	scene.dbg_close_mem()
	await process_frame
	var pw: PeopleWin = scene.dbg_open_people()
	check("名册窗打开", pw != null and pw.visible)
	if pw == null:
		scene.queue_free()
		return
	check("名册窗标题", pw.title == "人物", pw.title)
	await process_frame
	var rows: Array = pw.row_ids()
	check("名册 = met_char_ids", rows == scene.graph.met_char_ids(), str(rows))
	check("常驻两人在册", rows.has("CHARS_TEC") and rows.has("CHARS_EXEC"), str(rows))
	check("到过 7/4 ⇒ 陆珩松在册", rows.has("CHARS_luhengs"), str(rows))
	check("K10 常驻行状态词统一", pw.row_state("CHARS_TEC") == "助手窗"
		and pw.row_state("CHARS_EXEC") == "推演器",
		pw.row_state("CHARS_TEC") + " / " + pw.row_state("CHARS_EXEC"))
	# K3：再次打开名册仍是同一扇窗；点常驻行只提层，不把窗关掉。
	scene._open_icon_app("people")
	check("K3 再次打开名册不关窗", scene._people_win != null and scene._people_win.visible)
	scene._on_people_row("CHARS_TEC")
	scene._on_people_row("CHARS_TEC")
	check("K3 名册点 TEC 两次仍保持打开",
		scene._tec.visible and scene._people_win != null and scene._people_win.visible)
	scene.dbg_tec_close()
	check("状态词不带计数", not pw.row_state("CHARS_luhengs").contains("/"),
		pw.row_state("CHARS_luhengs"))
	var av := pw.find_child("av", true, false) as PanelContainer
	var av_sb := av.get_theme_stylebox("panel") as StyleBoxFlat if av != null else null
	check("B1 名册头像框：48×48 方角 + 1px 键线 + BG",
		av != null and av.custom_minimum_size == Vector2(48, 48)
			and av_sb != null
			and av_sb.corner_radius_top_left == 0
			and av_sb.border_width_left == 1
			and av_sb.border_color.is_equal_approx(TecTheme.EDGE)
			and av_sb.bg_color.is_equal_approx(TecTheme.BG),
		str(av_sb))
	var tec_row := pw.find_child("row_CHARS_TEC", true, false) as PanelContainer
	var tec_sb := tec_row.get_theme_stylebox("panel") as StyleBoxFlat if tec_row != null else null
	check("D2 名册行：仅底部 1px 发丝线",
		tec_sb != null
			and tec_sb.border_width_bottom == 1
			and tec_sb.border_width_top == 0
			and tec_sb.border_width_left == 0
			and tec_sb.border_width_right == 0
			and tec_sb.border_color.is_equal_approx(TecTheme.edge(0.18)),
		str(tec_sb))
	check("D2 名册发丝线左右缩进 8px",
		tec_sb != null and tec_sb.expand_margin_left == -8.0
			and tec_sb.expand_margin_right == -8.0, str(tec_sb))

	# 点常驻行 = 打开各自的窗
	scene.dbg_people_row("CHARS_TEC")
	await process_frame
	check("点 TEC 行开 TEC 窗", scene.dbg_tec_win() != null and scene.dbg_tec_win().visible)
	scene.dbg_tec_close()

	# 点普通行 = 叫到画布 + 说下一句
	var prog0 := int(scene.graph.talk_prog.get(scene.graph.key_of("char", "CHARS_luhengs"), 0))
	scene.dbg_people_row("CHARS_luhengs")
	await process_frame
	var key_lhs: String = scene.graph.key_of("char", "CHARS_luhengs")
	check("点人一行：上画布", scene.graph.nodes.has(key_lhs))
	check("点人一行：已选中", String(scene.dbg_state()["selected"]) == key_lhs,
		String(scene.dbg_state()["selected"]))
	check("点人一行：说下一句", int(scene.graph.talk_prog.get(key_lhs, 0)) == prog0 + 1,
		str(scene.graph.talk_prog.get(key_lhs, 0)))
	check("点人一行：开对话窗", scene.dbg_chat() != null)
	if scene.dbg_chat() != null:
		check("对话窗是这句台词", scene.dbg_chat_title().begins_with("独白 · ")
			or scene.dbg_chat_title().begins_with("对话 · "), scene.dbg_chat_title())
		scene.dbg_chat_close()
	await process_frame
	pw.refresh_people()
	await process_frame
	check("聊过一句 ⇒ 状态变「可继续」", pw.row_state("CHARS_luhengs") == "可继续",
		pw.row_state("CHARS_luhengs"))

	scene.dbg_close_people()
	await process_frame
	check("关名册窗", scene.dbg_people_win() == null)
	scene.dbg_close_log()
	await process_frame
	check("关日志窗", scene.dbg_log_win() == null)

	scene.queue_free()
	await process_frame


## 合成一个左键事件直接喂给图标（走它自己的 _gui_input，不绕过手势判定）
func _icon_press(icon: Control, at: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.global_position = at
	ev.position = at
	icon._gui_input(ev)


func _icon_move(icon: Control, at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.global_position = at
	ev.position = at
	icon._gui_input(ev)
