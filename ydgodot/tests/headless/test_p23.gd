extends "res://tests/headless/_test_base.gd"
## P2.3 第 1 步：时间轴 / 时刻图层 / 登场门控 / 回忆匹配（纯逻辑）。
## 运行：godot --headless --path ydgodot --script res://tests/headless/test_p23.gd

const TEMP_SAVE := "user://test_p23_case.save"

func _initialize() -> void:
	print("=== P2.3 时间轴 / 时刻图层 / 登场门控 ===")
	var c := CaseLoader.new(CaseCatalog.path_of("A001"))
	check("案件数据装载", c.load_case(), c.load_error)
	if c.case_def == null:
		_finish()
		return
	_test_data(c)
	_test_timeline(c)
	_test_time_nodes(c)
	_test_visibility(c)
	_test_debut(c)
	_test_spawn(c)
	_test_save(c)
	await _test_ui()
	_cleanup()
	_finish()


func _cleanup() -> void:
	if FileAccess.file_exists(TEMP_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))


func _test_data(c: CaseLoader) -> void:
	check("memoryScenes 两档", c.memory_scenes.size() == 2, str(c.memory_scenes.size()))
	check("memoryScenes 顺序 6/2 → 7/4",
		c.memory_scene_ids() == ["SCENES_0602", "SCENES_0704"], str(c.memory_scene_ids()))
	check("6/2 是时刻", c.is_time_id("SCENES_0602"))
	check("花园不是时刻", not c.is_time_id("SCENES_garden"))
	check("时刻 kind = time", c.scene_kind("SCENES_0602") == "time")
	check("普通场景 kind = loc", c.scene_kind("SCENES_garden") == "loc")
	check("现在档标签", c.now_label() == "7月5日", c.now_label())
	check("时刻标签取日期", c.time_label_of("SCENES_0602") == "6月2日")
	check("现在档标签走 nowLabel", c.time_label_of("present") == "7月5日")

	check("6/2 四段回忆", c.memories_for("SCENES_0602").size() == 4, str(c.memories_for("SCENES_0602").size()))
	check("7/4 两段回忆", c.memories_for("SCENES_0704").size() == 2, str(c.memories_for("SCENES_0704").size()))
	var m := c.memory_for("SCENES_0602", "CHARS_zs", "SCENES_garden")
	check("when × who × where 命中", m != null and m.id == "MEM_0602_zs", m.id if m != null else "null")
	check("地点不对不命中", c.memory_for("SCENES_0602", "CHARS_zs", "SCENES_body") == null)
	check("时刻不对不命中", c.memory_for("SCENES_0704", "CHARS_zs", "SCENES_garden") != null
		and c.memory_for("SCENES_0602", "CHARS_zs", "SCENES_garden").id != c.memory_for("SCENES_0704", "CHARS_zs", "SCENES_garden").id)
	check("回忆地点 = 花园", c.mem_place_of("SCENES_0602") != null and c.mem_place_of("SCENES_0602").id == "SCENES_garden")

	# 头像按拼音落到具体角色：槿杉 jin / 陆珩松 lu / 朱穗 zhu / 傅柏 fu。
	var avatar_expect := {
		"CHARS_JS": "res://assets/raw/jin.png",
		"CHARS_luhengs": "res://assets/raw/lu.png",
		"CHARS_zs": "res://assets/raw/zhu.png",
		"NPC_FB": "res://assets/raw/fu.png",
	}
	for cid in avatar_expect.keys():
		var want := String(avatar_expect[cid])
		check("%s 头像 = %s" % [cid, want],
			c.avatar_path_of(cid) == want and ResourceLoader.exists(want),
			c.avatar_path_of(cid))

	var brief := c.time_brief_of("SCENES_0602")
	check("档案简介地点", String(brief["where"]) == "植物学家的花园", String(brief["where"]))
	check("档案简介人物含四人", String(brief["who"]).contains("陆珩松") and String(brief["who"]).contains("朱穗")
		and String(brief["who"]).contains("傅柏") and String(brief["who"]).contains("槿杉"), String(brief["who"]))
	check("档案简介摘到一句旁白", String(brief["sum"]).contains("花园"), String(brief["sum"]))


func _test_timeline(c: CaseLoader) -> void:
	var g := GraphState.new(c)
	check("初始在现在档", g.time == GraphState.PRESENT_TIME)
	var stages := g.timeline_stages()
	check("时间轴三档", stages.size() == 3, str(stages.size()))
	check("首档是现在", String(stages[0]["id"]) == "present" and String(stages[0]["label"]) == "7月5日")
	check("现在档 keys = null（全显）", stages[0]["keys"] == null)
	check("6/2 档顺序", String(stages[1]["id"]) == "SCENES_0602")
	check("7/4 档顺序", String(stages[2]["id"]) == "SCENES_0704")
	var keys_0602: Array = stages[1]["keys"]
	var keys_0704: Array = stages[2]["keys"]
	check("6/2 派生地点 + 四人", keys_0602.size() == 5, str(keys_0602))
	check("6/2 含花园", keys_0602.has("loc:SCENES_garden"))
	check("6/2 含朱穗 / 陆珩松 / 傅柏 / 槿杉",
		keys_0602.has("char:CHARS_zs") and keys_0602.has("char:CHARS_luhengs")
		and keys_0602.has("char:NPC_FB") and keys_0602.has("char:CHARS_JS"))
	check("7/4 派生地点 + 两人", keys_0704.size() == 3, str(keys_0704))
	check("7/4 含陆珩松 / 朱穗", keys_0704.has("char:CHARS_luhengs") and keys_0704.has("char:CHARS_zs"))


func _test_time_nodes(c: CaseLoader) -> void:
	var g := GraphState.new(c)
	var fresh := g.reveal_scene("SCENES_fkjl")
	check("展开访客记录长出节点", fresh.size() >= 3, str(fresh.size()))
	check("6/2 画布键是 time:", g.nodes.has("time:SCENES_0602"), str(g.nodes.keys()))
	check("7/4 画布键是 time:", g.nodes.has("time:SCENES_0704"))
	check("不会分裂出 loc: 时间节点", not g.nodes.has("loc:SCENES_0602") and not g.nodes.has("loc:SCENES_0704"))
	check("引用 loc: 自动收敛到 time:", g.has("loc", "SCENES_0602") and g.node("time:SCENES_0602").kind == "time")
	check("时间节点有标题", String(g.node("time:SCENES_0602").label) == "6月2日")
	check("时间节点带「新」角标", g.has_unread("time:SCENES_0602"))
	check("已知时刻按配置顺序", g.timeline_known() == ["SCENES_0602", "SCENES_0704"], str(g.timeline_known()))
	check("重复展开不重复建节点", g.reveal_scene("SCENES_fkjl").size() == 0)
	check("展开 6/2 后标记已探索", g.reveal_scene("SCENES_0602").size() > 0 and g.explored.has("SCENES_0602"))
	check("6/2 的 loc 引用仍指向 time: 节点", g.scene_key("SCENES_0602") == "time:SCENES_0602")


func _test_visibility(c: CaseLoader) -> void:
	var g := GraphState.new(c)
	g.reveal_scene("SCENES_garden")
	g.reveal_scene("SCENES_fkjl")
	var garden_key := g.scene_key("SCENES_garden")
	var time_key := g.scene_key("SCENES_0602")
	check("现在档：地点可见", g.visible_node(g.node(garden_key)))
	check("现在档：物品可见", g.visible_node(g.node(g.key_of("item", "ITEM_lianmu"))))
	check("现在档：时间节点由档案承载", g.timeline_known().has("SCENES_0602"))

	g.time = "SCENES_0602"
	check("6/2 档：花园可见", g.visible_node(g.node(garden_key)))
	check("6/2 档：物品隐藏", not g.visible_node(g.node(g.key_of("item", "ITEM_lianmu"))))
	check("6/2 档：时间节点仍隐藏", not g.visible_node(g.node(time_key)))
	check("6/2 档：未登场的朱穗不可见", not g.visible_node(g.node(g.key_of("char", "CHARS_zs"))))
	check("当前档标签", g.time_label_of() == "6月2日", g.time_label_of())


func _test_debut(c: CaseLoader) -> void:
	var g := GraphState.new(c)
	check("朱穗 debut = 7/4", g.char_debut("CHARS_zs") == "SCENES_0704")
	check("陆珩松 debut = 尸体房", g.char_debut("CHARS_luhengs") == "SCENES_lhsdst")
	check("TEC 无 debut ⇒ 常驻", g.char_debut("CHARS_TEC") == "" and g.char_debuted("CHARS_TEC"))
	check("朱穗未登场", not g.char_debuted("CHARS_zs"))

	g.reveal_scene("SCENES_lhsdst")
	check("展开尸体房 ⇒ 陆珩松登场", g.char_debuted("CHARS_luhengs"))
	check("陆珩松现在档登场点 = 尸体房", g.char_now_scene("CHARS_luhengs") == "SCENES_lhsdst")
	check("现在档：陆珩松可见", g.visible_node(g.node(g.key_of("char", "CHARS_luhengs"))))
	check("现在档：槿杉没有登场点", g.char_now_scene("CHARS_JS") == "" and not g.visible_node(g.node(g.key_of("char", "CHARS_JS"))))

	check("门的后面还没探索 ⇒ 朱穗现在档未登场", not g.char_now_met("CHARS_zs"))
	g.reveal_scene("SCENES_mdhm")
	check("探索门的后面 ⇒ 朱穗现在档登场点达成", g.char_now_met("CHARS_zs"))
	check("但 debut 未到 ⇒ 仍不显示", not g.visible_node(g.node(g.key_of("char", "CHARS_zs"))))
	g.reveal_scene("SCENES_0704")
	check("到过 7/4 ⇒ 朱穗 debut 置位", g.char_debuted("CHARS_zs"))
	check("两道门都过 ⇒ 现在档可见", g.visible_node(g.node(g.key_of("char", "CHARS_zs"))))

	g.time = "SCENES_0704"
	check("7/4 档：朱穗可见", g.visible_node(g.node(g.key_of("char", "CHARS_zs"))))
	check("7/4 档：陆珩松（已 debut）可见", g.visible_node(g.node(g.key_of("char", "CHARS_luhengs"))))
	g.time = "SCENES_0602"
	check("6/2 档：朱穗已 debut 也可见", g.visible_node(g.node(g.key_of("char", "CHARS_zs"))))


func _test_spawn(c: CaseLoader) -> void:
	var g := GraphState.new(c)
	g.reveal_scene("SCENES_garden")
	check("进入 6/2 前没有人物卡", not g.has("char", "NPC_FB") and not g.has("char", "CHARS_JS"))
	var added := g.spawn_mem_cast("SCENES_0602")
	check("6/2 带出两位 debut 人物", added == 2, str(added))
	check("傅柏上画布", g.has("char", "NPC_FB"))
	check("槿杉上画布", g.has("char", "CHARS_JS"))
	check("朱穗（debut 7/4）不提前上画布", not g.has("char", "CHARS_zs"))
	check("陆珩松（debut 尸体房）不提前上画布", not g.has("char", "CHARS_luhengs"))
	check("傅柏 / 槿杉 debut 置位", g.char_debuted("NPC_FB") and g.char_debuted("CHARS_JS"))
	check("新人物带「新」角标", g.has_unread("char:NPC_FB") and g.has_unread("char:CHARS_JS"))
	check("人物挂 entity 边到花园",
		g.has_edge("loc:SCENES_garden", "char:NPC_FB", "entity") and g.has_edge("loc:SCENES_garden", "char:CHARS_JS", "entity"))
	check("重复进入不再带人", g.spawn_mem_cast("SCENES_0602") == 0)
	check("位置不落在花园正上方", Vector2(float(g.node("char:NPC_FB").x), float(g.node("char:NPC_FB").y)) != Vector2.ZERO)
	g.clear_fresh("char:NPC_FB")
	check("点过摘角标", not g.has_unread("char:NPC_FB"))

	var added2 := g.spawn_mem_cast("SCENES_0704")
	check("7/4 只带出朱穗", added2 == 1, str(added2))
	check("朱穗 debut 置位", g.char_debuted("CHARS_zs"))
	check("陆珩松仍不上 7/4 画布", not g.has("char", "CHARS_luhengs"))
	check("现在档（未到尸体房）陆珩松仍不可见", not g.visible_node(g.node(g.key_of("char", "CHARS_luhengs"))))


func _test_save(c: CaseLoader) -> void:
	var g := GraphState.new(c)
	g.reveal_scene("SCENES_garden")
	g.reveal_scene("SCENES_fkjl")
	g.spawn_mem_cast("SCENES_0602")
	g.time = "SCENES_0602"
	g.card_seen["SCENES_0602"] = true
	g.clear_fresh("char:NPC_FB")

	var ss := SaveSystem.new(g, "A001", TEMP_SAVE)
	var snap := ss.snapshot()
	check("快照带当前时刻", String(snap["time"]) == "SCENES_0602")
	check("快照带卡已读", bool((snap["cardSeen"] as Dictionary).get("SCENES_0602", false)))
	check("快照带登场位", bool((snap["debuted"] as Dictionary).get("NPC_FB", false)))
	check("快照带时间节点 kind",
		String((snap["nodes"] as Dictionary)["time:SCENES_0602"]["kind"]) == "time")

	var g2 := GraphState.new(c)
	var ss2 := SaveSystem.new(g2, "A001", TEMP_SAVE)
	check("快照恢复成功", ss2.restore(snap))
	check("恢复当前时刻", g2.time == "SCENES_0602")
	check("恢复卡已读", g2.card_seen.has("SCENES_0602"))
	check("恢复登场位", g2.debuted.has("NPC_FB"))
	check("恢复时间节点 kind", String(g2.node("time:SCENES_0602").kind) == "time")
	check("恢复「新」角标状态", g2.has_unread("char:CHARS_JS") and not g2.has_unread("char:NPC_FB"))
	check("恢复后时刻可见性可算", g2.visible_node(g2.node("loc:SCENES_garden")))


func _test_ui() -> void:
	print("--- 第 2 步：档案窗 / 回忆放映卡 ---")
	var scene: Control = load("res://scenes/Desktop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	check("桌面建起来", scene != null and scene.debug.dbg_state()["cards"] >= 1)
	# 「现在档的物品在回忆档里应隐藏、切回来应重新可见」需要一件真实存在的物品；
	# 开局不再预置手电筒（对齐 Web），这里自己造一把
	scene.debug.dbg_ensure("item", "ITEM_shoudiantong")
	await process_frame

	scene.debug.dbg_expand("SCENES_fkjl")
	await process_frame
	check("访客记录带出两档已知时刻",
		scene.debug.dbg_time_known() == ["SCENES_0602", "SCENES_0704"], str(scene.debug.dbg_time_known()))
	check("新时刻点亮档案「新」角标", scene.debug.dbg_archive_new())

	var win: ArchiveWin = scene.debug.dbg_open_archive()
	await process_frame
	check("档案窗打开", win != null and is_instance_valid(win))
	check("打开档案即清角标", not scene.debug.dbg_archive_new())
	var rows: Array = win.rows_info()
	check("档案三档", rows.size() == 3, str(rows.size()))
	check("现在档在最上", rows.size() > 0 and String(rows[0]["id"]) == "present"
		and String(rows[0]["label"]) == "7月5日")
	check("已获得时刻倒序（7/4 在 6/2 之上）", rows.size() > 2
		and String(rows[1]["id"]) == "SCENES_0704" and String(rows[2]["id"]) == "SCENES_0602")
	check("现在档简介", rows.size() > 0 and String(rows[0]["sub"]) == "侦查进行中")
	check("时刻简介含地点与人物", rows.size() > 2
		and String(rows[2]["sub"]).contains("植物学家的花园")
		and String(rows[2]["sub"]).contains("傅柏"), String(rows[2]["sub"]) if rows.size() > 2 else "")
	check("现在档标「当前」", rows.size() > 0 and String(rows[0]["status"]) == "当前")
	check("未看过的档没有回顾标记", rows.size() > 2 and String(rows[2]["status"]) == "")
	var first_row := win.find_child("row_present", true, false) as Control
	var sep: ColorRect = null
	if first_row != null:
		sep = first_row.get_node_or_null("sep") as ColorRect
	var sep_ok := sep != null and sep.size.y == 1.0 and sep.offset_left == 8.0 \
		and sep.offset_right == -8.0 and sep.color.is_equal_approx(TecTheme.edge(0.18))
	check("D2 档案行间 1px 发丝线（左右缩进 8px）", sep_ok,
		"null" if sep == null else str(sep.size) + " / " + str(sep.position))
	var last_row := win.find_child("row_SCENES_0602", true, false) as Control
	check("D2 档案末行不拖尾线", last_row != null and last_row.get_node_or_null("sep") == null)

	check("档案里点 6/2 能换档", scene.debug.dbg_archive_press("SCENES_0602"))
	await process_frame
	check("graph.time 切到 6/2", scene.debug.dbg_time() == "SCENES_0602", scene.debug.dbg_time())
	check("当前档标签 = 6月2日", scene.debug.dbg_time_label() == "6月2日", scene.debug.dbg_time_label())
	## 页眉面包屑在 P3 改回 Web 口径：显示「节点 / 已探索 / 组合 / 线索 / 结局」计数，
	## 不再兼任场景名（场景与时刻显示在档案窗与案件窗标题栏）。所以这里查计数格式，
	## 「换档」本身由上面 `dbg_time()` / 档案窗当前档两条钉住。
	var crumb := scene.get_node_or_null("header/crumb") as Label
	check("页眉面包屑是计数口径（不再是场景名）",
		crumb != null and crumb.text.contains("节点") and crumb.text.contains("已探索场景")
		and not crumb.text.contains("6月2日"),
		crumb.text if crumb != null else "null")
	check("6/2 档：花园可见", scene.debug.dbg_card_visible("loc:SCENES_garden"))
	check("6/2 档：现在档的物品隐藏", not scene.debug.dbg_card_visible("item:ITEM_shoudiantong"))
	check("6/2 档：傅柏 / 槿杉上画布并可见",
		scene.debug.dbg_card_visible("char:NPC_FB") and scene.debug.dbg_card_visible("char:CHARS_JS"))
	check("6/2 档：朱穗（7/4 才登场）不出现", not scene.debug.dbg_card_visible("char:CHARS_zs"))

	var card: MemCard = scene.debug.dbg_mem_card()
	check("6/2 首次进入自动开放映卡", card != null and is_instance_valid(card))
	check("卡已读记进状态", bool(scene.graph.card_seen.get("SCENES_0602", false)))
	check("放映卡标题", card != null and String(card.title).contains("6月2日"))
	check("正文从日期场景正文起", card != null and card.line_count() > 0
		and card.line_at(0).contains("6月2日"), card.line_at(0) if card != null and card.line_count() > 0 else "")
	var has_talk := false
	if card != null:
		for i in card.line_count():
			if card.line_at(i).begins_with("——"):
				has_talk = true
	check("正文带当天角色台词", has_talk)
	# 画布有缩放 / 平移 ⇒ 「谁压住谁」只能在屏幕空间里比（world 坐标比必然误判）
	var garden_rect: Rect2 = scene.debug.dbg_card_global("loc:SCENES_garden")
	var mem_rect: Rect2 = scene.debug.dbg_mem_global()
	check("放映卡锚在地点旁且不压住节点", card != null and not garden_rect.intersects(mem_rect),
		str(garden_rect) + " / " + str(mem_rect))
	check("首行在打字", card != null and card.is_typing())
	check("放映卡无滚动条", card != null and card.find_children("*", "ScrollContainer", true, false).is_empty())
	check("放映卡预排全文行", card != null and card._rows.size() == card.line_count(),
		str(card._rows.size()) if card != null else "null")
	# W1：点标题栏不能冒泡到 MemCard 的 advance（不翻行、不补全）。
	if card != null:
		var mem_bar := card.get_node("bar") as Control
		var mem_bar_at: Vector2 = mem_bar.get_global_rect().position + Vector2(26.0, mem_bar.size.y * 0.5)
		var mem_idx := card.index()
		var mem_typing := card.is_typing()
		var mem_down := InputEventMouseButton.new()
		mem_down.button_index = MOUSE_BUTTON_LEFT
		mem_down.pressed = true
		mem_down.position = mem_bar_at
		mem_down.global_position = mem_bar_at
		root.push_input(mem_down, true)
		var mem_up := InputEventMouseButton.new()
		mem_up.button_index = MOUSE_BUTTON_LEFT
		mem_up.pressed = false
		mem_up.position = mem_bar_at
		mem_up.global_position = mem_bar_at
		root.push_input(mem_up, true)
		await process_frame
		check("W1 MemCard 点标题栏不翻行", card.index() == mem_idx,
			"%d -> %d" % [mem_idx, card.index()])
		check("W1 MemCard 点标题栏不补全", card.is_typing() == mem_typing)
	var mem_border: Control = null
	if card != null:
		mem_border = card.get_node_or_null("mem_border") as Control
	check("放映卡黑框随内容增高", mem_border != null
		and absf(mem_border.size.y - (card.size.y - SysWindow.PAD * 2.0)) < 0.5,
		"null" if mem_border == null else "%.0f / %.0f" % [mem_border.size.y, card.size.y])
	check("单击先补全本行", scene.debug.dbg_mem_advance() and not card.is_typing())
	check("补全后文字完整", card != null and card.typed_text() == card.current_text())
	var idx_before := card.index()
	check("再单击出下一行", scene.debug.dbg_mem_advance() and card.index() == idx_before + 1)

	var win2: ArchiveWin = scene.debug.dbg_open_archive()
	await process_frame
	check("再开档案不重新亮角标", not scene.debug.dbg_archive_new())
	var rows2: Array = win2.rows_info()
	check("当前 6/2 档标「当前」", rows2.size() > 2 and String(rows2[2]["status"]) == "当前",
		str(rows2[2]["status"]) if rows2.size() > 2 else "")
	check("档案里点「现在」能回现在档", scene.debug.dbg_archive_press("present"))
	await process_frame
	check("回到现在档", scene.debug.dbg_time() == "present")
	check("换回现在档时收走放映卡", scene.debug.dbg_mem_card() == null)
	check("手电筒重新可见", scene.debug.dbg_card_visible("item:ITEM_shoudiantong"))
	check("傅柏不会跟回现在档", not scene.debug.dbg_card_visible("char:NPC_FB"))

	var win3: ArchiveWin = scene.debug.dbg_open_archive()
	await process_frame
	var rows3: Array = win3.rows_info()
	check("离开 6/2 后标「已回顾」", rows3.size() > 2 and String(rows3[2]["status"]) == "已回顾",
		str(rows3[2]["status"]) if rows3.size() > 2 else "")

	scene.debug.dbg_open_archive()
	await process_frame
	scene.debug.dbg_archive_press("SCENES_0602")
	await process_frame
	check("已读档再进入不自动放映", scene.debug.dbg_mem_card() == null)

	scene.debug.dbg_open_archive()
	await process_frame
	scene.debug.dbg_archive_press("SCENES_0602")
	await process_frame
	check("点当前档 = 重放回忆", scene.debug.dbg_mem_card() != null)

	scene.debug.dbg_open_archive()
	await process_frame
	scene.debug.dbg_archive_press("SCENES_0704")
	await process_frame
	check("切到 7/4", scene.debug.dbg_time() == "SCENES_0704")
	check("7/4 带出朱穗并可见", scene.debug.dbg_card_visible("char:CHARS_zs"))
	check("7/4 档不显示傅柏", not scene.debug.dbg_card_visible("char:NPC_FB"))
	check("7/4 首次进入自动放映", scene.debug.dbg_mem_card() != null)

	print("--- 第 3 步：回忆小剧场 ---")
	check("切回 6/2 档", scene.debug.dbg_set_time("SCENES_0602"))
	await process_frame
	check("已读档切回不自动开卡", scene.debug.dbg_mem_card() == null)

	scene.debug.dbg_combo_ui("NPC_FB", "SCENES_garden")
	await process_frame
	var play: MemCard = scene.debug.dbg_mem_card()
	check("人物 × 地点 × 时刻触发小剧场", play != null and play.is_play())
	check("小剧场标题带人物", play != null and String(play.title).contains("傅柏"),
		play.title if play != null else "null")
	check("傅柏回忆七行", play != null and play.line_count() == 7,
		str(play.line_count()) if play != null else "null")
	check("首行是旁白", play != null and play.line_kind_at(0) == "narr")
	check("第二行是傅柏台词", play != null and play.line_kind_at(1) == "say"
		and play.line_who_at(1) == "NPC_FB")
	check("台词行带说话人名字", play != null and play.line_name_at(1) == "傅柏",
		play.line_name_at(1) if play != null else "null")
	check("傅柏回忆六段台词", play != null and play.say_count() == 6,
		str(play.say_count()) if play != null else "null")
	check("台词文本完整", play != null and play.line_at(1).contains("第三次"),
		play.line_at(1) if play != null and play.line_count() > 1 else "")
	var mem_av := play.find_child("mem_say_avatar", true, false) as PanelContainer if play != null else null
	var mem_art := mem_av.find_child("art", true, false) as TextureRect if mem_av != null else null
	var mem_path := mem_art.texture.resource_path if mem_art != null and mem_art.texture != null else ""
	check("小剧场头像走 CharDef（傅柏 → fu.png）", mem_path == "res://assets/raw/fu.png", mem_path)
	check("小剧场有 tried 痕迹",
		bool(scene.graph.tried.get("char:NPC_FB>loc:SCENES_garden", false)))
	var play_garden: Rect2 = scene.debug.dbg_card_global("loc:SCENES_garden")
	var play_rect: Rect2 = scene.debug.dbg_mem_global()
	check("小剧场锚在地点旁且不压住节点", play != null and not play_garden.intersects(play_rect),
		str(play_garden) + " / " + str(play_rect))
	var rail := Rect2(Vector2(22, 30), Vector2(96, 290))
	check("小剧场不压左侧图标栏", play != null and not rail.intersects(play_rect),
		str(rail) + " / " + str(play_rect))
	check("小剧场逐行打字", play != null and play.is_typing())
	check("小剧场单击补全", scene.debug.dbg_mem_advance() and not play.is_typing())
	check("小剧场补全后整句完整", play != null and play.typed_text() == play.current_text())

	scene.debug.dbg_combo_ui("CHARS_JS", "SCENES_garden")
	await process_frame
	var play2: MemCard = scene.debug.dbg_mem_card()
	check("换人物换回忆", play2 != null and String(play2.title).contains("槿杉"),
		play2.title if play2 != null else "null")
	check("槿杉回忆四行", play2 != null and play2.line_count() == 4,
		str(play2.line_count()) if play2 != null else "null")
	check("槿杉台词带名字", play2 != null and play2.line_name_at(1) == "槿杉",
		play2.line_name_at(1) if play2 != null else "null")

	# P2 Toast 排队：上一条「想起了一段回忆」还在屏上，先清掉再断言错误提示。
	scene.debug.dbg_hide_toast()
	scene.debug.dbg_combo_ui("NPC_FB", "SCENES_fkjl")
	await process_frame
	check("时刻里没有这对组合时给提示", scene.debug.dbg_toast_text().contains("没有")
		and scene.debug.dbg_toast_text().contains("回忆"), scene.debug.dbg_toast_text())
	check("没有回忆时保留原卡", scene.debug.dbg_mem_card() == play2)

	check("切到 7/4", scene.debug.dbg_set_time("SCENES_0704"))
	await process_frame
	check("换档收起小剧场", scene.debug.dbg_mem_card() == null)
	scene.debug.dbg_combo_ui("CHARS_zs", "SCENES_garden")
	await process_frame
	var play3: MemCard = scene.debug.dbg_mem_card()
	check("7/4 朱穗小剧场", play3 != null and play3.is_play()
		and String(play3.title).contains("朱穗"), play3.title if play3 != null else "null")
	check("朱穗回忆五行 / 三段台词", play3 != null and play3.line_count() == 5
		and play3.say_count() == 3, str(play3.line_count()) if play3 != null else "null")

	check("回现在档", scene.debug.dbg_set_time("present"))
	await process_frame
	check("现在档收起小剧场", scene.debug.dbg_mem_card() == null)
	scene.debug.dbg_combo_ui("NPC_FB", "SCENES_garden")
	await process_frame
	check("现在档人物 × 地点不演回忆", scene.debug.dbg_mem_card() == null)

	scene.queue_free()
	await process_frame
	await process_frame
