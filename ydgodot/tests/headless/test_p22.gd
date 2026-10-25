extends SceneTree

const TEMP_PROGRESS := "user://test_p22_progress.json"
const TEMP_SAVE := "user://test_p22_case.save"

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
	print("=== P2.2 TEC 对话 / 分析 / 助手卡片 / 档案解读 ===")
	_test_data()
	await _test_desktop()
	_cleanup()
	print("=== %d 项，失败 %d ===" % [total, fails])
	quit(0 if fails == 0 else 1)


func _cleanup() -> void:
	for path in [TEMP_PROGRESS, TEMP_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_data() -> void:
	var loader := CaseLoader.new(CaseCatalog.path_of("A001"))
	check("案件数据装载", loader.load_case())
	var tec := loader.char_of("CHARS_TEC")
	check("TEC 角色存在", tec != null)
	check("TEC 闲聊 3 条", tec.talk_queue.size() == 3, str(tec.talk_queue.size()))
	check("TEC 场景对白 8 组", tec.scene_talks.size() == 8, str(tec.scene_talks.size()))
	check("TEC 物品反应 4 条", tec.item_reactions.size() == 4, str(tec.item_reactions.size()))

	var body_lines: Array = []
	var garden_lines: Array = []
	for st in tec.scene_talks:
		if st.scene != null and st.scene.id == "SCENES_body":
			body_lines = st.lines
		if st.scene != null and st.scene.id == "SCENES_garden":
			garden_lines = st.lines
	check("尸体档案 2 条", body_lines.size() == 2, str(body_lines.size()))
	check("尸体档案第一条含绷带", body_lines.size() > 0 and String(body_lines[0]).contains("绷带"))
	check("花园档案 1 条", garden_lines.size() == 1, str(garden_lines.size()))


func _test_desktop() -> void:
	_cleanup()
	var scene: Control = load("res://scenes/Desktop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.dbg_use_temp_progress(TEMP_PROGRESS)
	scene._save.path = TEMP_SAVE
	scene._save_enabled = false

	var chip: TecChip = scene.dbg_tec_chip()
	var info: Dictionary = scene.dbg_tec_info()
	check("TEC 窗初始关闭", not bool(info["visible"]))
	check("TEC 初始未收起", not bool(info["min"]))
	check("助手卡片初始隐藏", not bool(info["chip_visible"]))
	check("助手卡片 196×56", chip != null and chip.size == Vector2(196, 56), str(chip.size if chip != null else Vector2.ZERO))
	check("助手卡片贴右下", chip.position == Vector2(1068, 608), str(chip.position))
	check("助手卡片空闲文案", chip.status_text().contains("助手已收起"), chip.status_text())

	scene.dbg_tec_open()
	info = scene.dbg_tec_info()
	check("TEC 窗可打开", bool(info["visible"]))
	check("打开后卡片隐藏", not bool(info["chip_visible"]))
	check("TEC 窗标题", scene.dbg_tec_win().title == "TEC 对话", scene.dbg_tec_win().title)
	check("TEC 头像 60×60", scene.dbg_tec_win().avatar_global_rect().size.x >= 60.0,
		str(scene.dbg_tec_win().avatar_global_rect().size))
	var tec_av := scene.dbg_tec_win().find_child("tec_avatar", true, false) as PanelContainer
	var tec_av_sb := tec_av.get_theme_stylebox("panel") as StyleBoxFlat if tec_av != null else null
	check("B1 TEC 头像框：60×60 方角 + 1px 键线 + BG",
		tec_av != null and tec_av.custom_minimum_size == Vector2(60, 60)
			and tec_av_sb != null
			and tec_av_sb.corner_radius_top_left == 0
			and tec_av_sb.border_width_left == 1
			and tec_av_sb.border_color.is_equal_approx(TecTheme.EDGE)
			and tec_av_sb.bg_color.is_equal_approx(TecTheme.BG),
		str(tec_av_sb))

	scene.dbg_tec_talk()
	var lines: Array = scene.dbg_tec_win().dbg_lines()
	check("闲聊第一条", lines.size() == 1 and String(lines[0]) == scene.case_def.char_of("CHARS_TEC").talk_queue[0],
		str(lines))
	# W26：打字中再点只补全当前行，不叠加下一句。
	scene.dbg_tec_talk()
	check("W26 打字中点击只补全", scene.dbg_tec_win().line_count() == 1
		and not scene.dbg_tec_win().is_typing(),
		"lines=%d typing=%s" % [scene.dbg_tec_win().line_count(), scene.dbg_tec_win().is_typing()])
	check("W26 补全不推进闲聊进度", int(scene.graph.tec_prog.get("_def", 0)) == 1)
	# A5 截图辅助：演示 / 截图时一次揭示完，避免画面停在半个字上。
	scene.dbg_tec_win().finish_typing()
	var typing_left := false
	for c in scene.dbg_tec_win()._lines.get_children():
		if c is TypewriterLabel and (c as TypewriterLabel).visible_characters != -1:
			typing_left = true
	check("A5 finish_typing 一次揭示完", not typing_left)
	check("闲聊进度 1", int(scene.graph.tec_prog.get("_def", 0)) == 1)
	scene.dbg_tec_talk()
	scene.dbg_tec_win().finish_typing()
	scene.dbg_tec_talk()
	scene.dbg_tec_win().finish_typing()
	check("闲聊共 3 条", scene.dbg_tec_win().line_count() == 3, str(scene.dbg_tec_win().line_count()))
	check("闲聊进度 3", int(scene.graph.tec_prog.get("_def", 0)) == 3)
	scene.dbg_tec_talk()
	check("G7 闲聊说完给分级提示", scene.dbg_tec_win().line_count() == 4,
		str(scene.dbg_tec_win().line_count()))
	check("G7 提示不推进闲聊进度", int(scene.graph.tec_prog.get("_def", 0)) == 3)

	scene.dbg_tec_close()
	info = scene.dbg_tec_info()
	check("关闭 TEC 窗", not bool(info["visible"]))
	check("关闭后不显示卡片", not bool(info["chip_visible"]))
	check("关闭保留对话历史", scene.dbg_tec_win().line_count() == 4, str(scene.dbg_tec_win().line_count()))
	scene.dbg_tec_open()
	check("重开保留对话历史", scene.dbg_tec_win().line_count() == 4)

	scene.dbg_tec_minimize()
	info = scene.dbg_tec_info()
	check("– 收起 TEC 窗", not bool(info["visible"]) and bool(info["min"]))
	check("收起后卡片可见", bool(info["chip_visible"]))
	check("收起后状态文案", chip.status_text().contains("助手已收起"), chip.status_text())
	check("收起后不忙", not chip.is_busy())
	# U7：TEC 胶囊可拖，resize 不吸回；未拖动松手才还原。
	var chip_home: Vector2 = chip.position
	var chip_at: Vector2 = chip.get_global_rect().get_center()
	var chip_down := InputEventMouseButton.new()
	chip_down.button_index = MOUSE_BUTTON_LEFT
	chip_down.pressed = true
	chip_down.position = chip_at
	chip_down.global_position = chip_at
	chip.gui_input.emit(chip_down)
	var chip_move := InputEventMouseMotion.new()
	chip_move.button_mask = MOUSE_BUTTON_MASK_LEFT
	chip_move.position = chip_at + Vector2(-160, -90)
	chip_move.global_position = chip_at + Vector2(-160, -90)
	chip.gui_input.emit(chip_move)
	var chip_up := InputEventMouseButton.new()
	chip_up.button_index = MOUSE_BUTTON_LEFT
	chip_up.pressed = false
	chip_up.position = chip_at + Vector2(-160, -90)
	chip_up.global_position = chip_at + Vector2(-160, -90)
	chip.gui_input.emit(chip_up)
	await process_frame
	check("U7 TEC 胶囊可拖动", chip.position != chip_home, str(chip.position) + " / " + str(chip_home))
	check("U7 TEC 胶囊拖动后仍在桌面内",
		scene._desk.get_global_rect().encloses(chip.get_global_rect()), str(chip.get_global_rect()))
	var chip_dragged_pos: Vector2 = chip.position
	scene._place_floating_windows()
	check("U7 TEC 胶囊 resize 不被吸回", chip.position == chip_dragged_pos,
		str(chip.position) + " / " + str(chip_dragged_pos))
	chip.reset_place()
	scene._place_floating_windows()
	var chip_click: Vector2 = chip.get_global_rect().get_center()
	var chip_cdown := InputEventMouseButton.new()
	chip_cdown.button_index = MOUSE_BUTTON_LEFT
	chip_cdown.pressed = true
	chip_cdown.position = chip_click
	chip_cdown.global_position = chip_click
	chip.gui_input.emit(chip_cdown)
	var chip_cup := InputEventMouseButton.new()
	chip_cup.button_index = MOUSE_BUTTON_LEFT
	chip_cup.pressed = false
	chip_cup.position = chip_click
	chip_cup.global_position = chip_click
	chip.gui_input.emit(chip_cup)
	info = scene.dbg_tec_info()
	check("点卡片还原 TEC 窗", bool(info["visible"]) and not bool(info["min"]))
	check("还原后卡片隐藏", not bool(info["chip_visible"]))
	check("还原保留对话历史", scene.dbg_tec_win().line_count() == 4)

	scene.dbg_expand("SCENES_body")
	await process_frame
	check("尸体节点已上画布", scene.graph.has("loc", "SCENES_body"))
	scene.dbg_tec_analyze("SCENES_body")
	info = scene.dbg_tec_info()
	check("拖场景开始分析", bool(info["win"]["analyzing"]))
	check("窗口内分析条可见", bool(info["win"]["analysis_visible"]))
	check("分析目标为尸体", String(info["win"]["target"]) == "loc:SCENES_body", String(info["win"]["target"]))
	check("分析开始追加接收句", scene.dbg_tec_win().dbg_lines().back().contains("接收「尸"))
	var before_lines: int = scene.dbg_tec_win().line_count()
	check("分析中拒绝第二个任务", not scene.dbg_tec_analyze_key("loc:SCENES_garden"))
	scene.dbg_ensure("clue", "CLUES_nm")
	check("线索节点拒绝分析", not scene.dbg_tec_analyze_key("clue:CLUES_nm"))
	scene.dbg_tec_win()._process(0.3)
	check("分析进度推进", scene.dbg_tec_win().progress() > 0.0, str(scene.dbg_tec_win().progress()))

	scene.dbg_tec_minimize()
	info = scene.dbg_tec_info()
	check("分析途中收起", bool(info["min"]) and bool(info["chip_visible"]))
	check("卡片显示分析中", chip.is_busy() and chip.status_text().contains("分析中"), chip.status_text())
	scene.dbg_tec_complete()
	await process_frame
	await process_frame
	info = scene.dbg_tec_info()
	check("分析完成", not bool(info["win"]["analyzing"]))
	var tec_win: TecWindow = scene.dbg_tec_win()
	check("TEC 窗包住页脚", tec_win != null
		and tec_win.get_global_rect().encloses(tec_win._hint.get_global_rect()),
		"null" if tec_win == null else "%s / %s" % [
			tec_win.get_global_rect(), tec_win._hint.get_global_rect()])
	check("捕获尸体隐藏线索", (scene.graph.captured as Dictionary).has("CLUES_V_luheng"))
	check("尸体档案进度 1", int(scene.graph.tec_prog.get("SCENES_body", 0)) == 1)
	check("卡片点未读圆点", bool(info["dot"]) and chip.dbg_state()["dot"])
	check("卡片完成文案", chip.status_text().contains("分析完成"), chip.status_text())
	check("完成后追加档案台词", scene.graph.tec_prog.has("SCENES_body") and scene.dbg_tec_win().line_count() > before_lines,
		str(scene.dbg_tec_win().line_count()))
	var seen_hidden := false
	for line in scene.dbg_tec_win().dbg_lines():
		if String(line).contains("植物学家") or String(line).contains("陆珩松"):
			seen_hidden = true
	check("分析结果写入对话历史", seen_hidden, str(scene.dbg_tec_win().dbg_lines()))
	check("隐藏线索已上画布", (scene.dbg_state()["nodes"] as Array).has("clue:CLUES_V_luheng"))
	var capture_keys: Array = scene.dbg_state()["captured"]
	check("隐藏线索只捕获一次", capture_keys.count("CLUES_V_luheng") == 1)

	scene.dbg_tec_open()
	info = scene.dbg_tec_info()
	check("展开即已读", not bool(info["dot"]) and not bool(info["chip_visible"]))
	check("TEC 完成计数 1", scene.dbg_tec_win().done_count() == 1, str(scene.dbg_tec_win().done_count()))

	var body_prog_before := int(scene.graph.tec_prog.get("SCENES_body", 0))
	scene.dbg_tec_analyze("loc:SCENES_body")
	scene.dbg_tec_complete()
	await process_frame
	await process_frame
	check("尸体档案第二条", int(scene.graph.tec_prog.get("SCENES_body", 0)) == body_prog_before + 1,
		str(scene.graph.tec_prog.get("SCENES_body", 0)))
	check("第二次不再捕获", int(scene.graph.tec_prog.get("SCENES_body", 0)) == 2)
	var body_lines_done := false
	for line in scene.dbg_tec_win().dbg_lines():
		if String(line).contains("大量可以捕获"):
			body_lines_done = true
	check("第二条档案已播出", body_lines_done, str(scene.dbg_tec_win().dbg_lines()))

	scene.dbg_tec_analyze("loc:SCENES_body")
	scene.dbg_tec_complete()
	await process_frame
	await process_frame
	check("档案读完不再推进", int(scene.graph.tec_prog.get("SCENES_body", 0)) == 2)
	var all_read := false
	var no_clue := false
	for line in scene.dbg_tec_win().dbg_lines():
		if String(line).contains("档案已经全部解读完毕"):
			all_read = true
		if String(line).contains("没有可以捕获的线索"):
			no_clue = true
	check("全部读完提示", all_read)
	check("无可捕获提示", no_clue)

	scene.dbg_tec_analyze("loc:SCENES_garden")
	scene.dbg_tec_complete()
	await process_frame
	await process_frame
	check("花园档案解读", int(scene.graph.tec_prog.get("SCENES_garden", 0)) == 1,
		str(scene.graph.tec_prog.get("SCENES_garden", 0)))
	var garden_line := false
	for line in scene.dbg_tec_win().dbg_lines():
		if String(line).contains("黑影"):
			garden_line = true
	check("花园档案台词", garden_line, str(scene.dbg_tec_win().dbg_lines()))

	scene.dbg_ensure("item", "ITEMS_hy")
	scene.dbg_tec_analyze_key("item:ITEMS_hy")
	scene.dbg_tec_complete()
	await process_frame
	await process_frame
	var reaction_line := false
	for line in scene.dbg_tec_win().dbg_lines():
		if String(line).contains("三张合影"):
			reaction_line = true
	check("物品反应表命中", reaction_line, str(scene.dbg_tec_win().dbg_lines()))

	scene.dbg_ensure("item", "ITEMS_bd")
	scene.dbg_tec_analyze_key("item:ITEMS_bd")
	scene.dbg_tec_complete()
	await process_frame
	await process_frame
	var fallback_line := false
	for line in scene.dbg_tec_win().dbg_lines():
		if String(line).contains("没有更多线索"):
			fallback_line = true
	check("无反应兜底", fallback_line)
	check("兜底写入 tried", (scene.graph.tried as Dictionary).has("item:ITEMS_bd>tec-dock"))

	scene.dbg_tec_close()
	scene.dbg_tec_drop("loc:SCENES_garden", scene.dbg_tec_icon_rect().get_center())
	info = scene.dbg_tec_info()
	check("拖到 TEC 图标开始分析", bool(info["win"]["analyzing"]))
	check("拖图标自动开窗", bool(info["visible"]))
	scene.dbg_tec_complete()
	await process_frame
	await process_frame

	scene.dbg_tec_open()
	var av_hit: bool = scene.dbg_tec_drop_hit(scene.dbg_tec_win().avatar_global_rect().get_center())
	check("头像命中拖放点", av_hit)
	scene.dbg_tec_drop("item:ITEMS_hy", scene.dbg_tec_win().avatar_global_rect().get_center())
	check("拖到 TEC 头像开始分析", bool(scene.dbg_tec_info()["win"]["analyzing"]))
	scene.dbg_tec_complete()
	await process_frame
	await process_frame

	scene.dbg_tec_minimize()
	check("收起后卡片是拖放点", scene.dbg_tec_drop_hit(chip.get_global_rect().get_center()))
	scene.dbg_tec_drop("loc:SCENES_garden", chip.get_global_rect().get_center())
	info = scene.dbg_tec_info()
	check("拖到卡片开始分析", bool(info["win"]["analyzing"]))
	check("卡片保持收起", bool(info["min"]) and bool(info["chip_visible"]))
	scene.dbg_tec_complete()
	await process_frame
	await process_frame
	check("完成后卡片打点", bool(scene.dbg_tec_info()["dot"]))
	check("远处不是拖放点", not scene.dbg_tec_drop_hit(Vector2(10, 700)))

	# K7：最小化 = 后台继续；关闭 = 取消并明确告知。
	scene.dbg_tec_drop("loc:SCENES_garden", chip.get_global_rect().get_center())
	check("K7 卡片上可再次开始分析", bool(scene.dbg_tec_info()["win"]["analyzing"]))
	scene._hide_toast()
	scene.dbg_tec_close()
	info = scene.dbg_tec_info()
	check("K7 关闭 TEC 会取消分析", not bool(info["win"]["analyzing"]))
	check("K7 关闭取消有明确提示", scene.dbg_toast_text().contains("取消")
		and scene.dbg_toast_text().contains("助手卡片"), scene.dbg_toast_text())

	scene.dbg_tec_open()
	scene.dbg_tec_win().finish_typing()
	var click_ev := InputEventMouseButton.new()
	click_ev.button_index = MOUSE_BUTTON_LEFT
	click_ev.pressed = true
	var lines_before: int = scene.dbg_tec_win().line_count()
	scene.dbg_tec_win()._gui_input(click_ev)
	check("G7 点窗内闲聊仍给分级提示", scene.dbg_tec_win().line_count() == lines_before + 1,
		str(scene.dbg_tec_win().line_count()))
	check("闲聊进度已满", int(scene.graph.tec_prog.get("_def", 0)) == 3)

	# W1：真实事件路由。点头像只出一句；拖标题栏不再白聊一句。
	scene.dbg_tec_win().finish_typing()
	var w1_before: int = scene.dbg_tec_win().line_count()
	var av_center: Vector2 = scene.dbg_tec_win().avatar_global_rect().get_center()
	var av_down := InputEventMouseButton.new()
	av_down.button_index = MOUSE_BUTTON_LEFT
	av_down.pressed = true
	av_down.position = av_center
	av_down.global_position = av_center
	root.push_input(av_down, true)
	await process_frame
	check("W1 点头像一次只出一句", scene.dbg_tec_win().line_count() == w1_before + 1,
		"%d -> %d" % [w1_before, scene.dbg_tec_win().line_count()])
	var av_up := InputEventMouseButton.new()
	av_up.button_index = MOUSE_BUTTON_LEFT
	av_up.pressed = false
	av_up.position = av_center
	av_up.global_position = av_center
	root.push_input(av_up, true)
	scene.dbg_tec_win().finish_typing()

	var tec_home: Vector2 = scene._tec.position
	var w1_talk_before: int = scene.dbg_tec_win().line_count()
	var bar := scene._tec.get_node("bar") as Control
	var bar_at: Vector2 = bar.get_global_rect().position + Vector2(28.0, bar.size.y * 0.5)
	var bar_down := InputEventMouseButton.new()
	bar_down.button_index = MOUSE_BUTTON_LEFT
	bar_down.pressed = true
	bar_down.position = bar_at
	bar_down.global_position = bar_at
	root.push_input(bar_down, true)
	var bar_move := InputEventMouseMotion.new()
	bar_move.button_mask = MOUSE_BUTTON_MASK_LEFT
	bar_move.position = bar_at + Vector2(24, 16)
	bar_move.global_position = bar_at + Vector2(24, 16)
	root.push_input(bar_move, true)
	var bar_up := InputEventMouseButton.new()
	bar_up.button_index = MOUSE_BUTTON_LEFT
	bar_up.pressed = false
	bar_up.position = bar_at + Vector2(24, 16)
	bar_up.global_position = bar_at + Vector2(24, 16)
	root.push_input(bar_up, true)
	await process_frame
	check("W1 拖 TEC 标题栏不再白聊", scene.dbg_tec_win().line_count() == w1_talk_before,
		"%d -> %d" % [w1_talk_before, scene.dbg_tec_win().line_count()])
	check("W1 标题栏拖动仍生效", scene._tec.position != tec_home,
		str(scene._tec.position) + " / " + str(tec_home))
	scene._tec.position = tec_home

	scene.dbg_ensure("loc", "SCENES_0704")
	scene.dbg_tec_analyze_key("loc:SCENES_0704")
	scene.dbg_tec_complete()
	await process_frame
	await process_frame
	check("0704 档案写入进度", int(scene.graph.tec_prog.get("SCENES_0704", 0)) == 1)
	check("TEC 分析进撤销栈", scene.dbg_undo())
	await process_frame
	await process_frame
	check("撤销回退 TEC 进度", int(scene.graph.tec_prog.get("SCENES_0704", 0)) == 0)

	# G7：双击场景（`_toggle_container`）这条首次展开路径也要有 TEC 引导。
	var lines_before_expand: int = scene.dbg_tec_win().line_count()
	scene._toggle_container("loc", "SCENES_garden")
	check("G7 首次展开场景时 TEC 主动提示",
		scene.dbg_tec_win().line_count() == lines_before_expand + 1,
		str(scene.dbg_tec_win().line_count() - lines_before_expand))
	check("G7 提示指向可解读档案",
		String(scene.dbg_tec_win().dbg_lines()[-1]).contains("档案"),
		String(scene.dbg_tec_win().dbg_lines()[-1]))
	var lines_after_first: int = scene.dbg_tec_win().line_count()
	scene._toggle_container("loc", "SCENES_garden")   # 收起
	scene._toggle_container("loc", "SCENES_garden")   # 再展开
	check("G7 再次展开/收起不重复提示",
		scene.dbg_tec_win().line_count() == lines_after_first,
		str(scene.dbg_tec_win().line_count() - lines_after_first))

	# W26：同文本提示不重复追加。
	scene.dbg_tec_win().finish_typing()
	var dup0: int = scene.dbg_tec_win().line_count()
	scene._tec_hint("W26-重复提示")
	scene.dbg_tec_win().finish_typing()
	scene._tec_hint("W26-重复提示")
	check("W26 同文本提示只追加一次", scene.dbg_tec_win().line_count() == dup0 + 1,
		"%d -> %d" % [dup0, scene.dbg_tec_win().line_count()])

	scene.dbg_tec_analyze("loc:SCENES_garden")
	check("分析中", bool(scene.dbg_tec_info()["win"]["analyzing"]))
	scene.dbg_tec_open()
	await process_frame
	scene._reset_case(true)
	await process_frame
	await process_frame
	info = scene.dbg_tec_info()
	check("重置清空 TEC 分析", not bool(info["win"]["analyzing"]))
	check("重置清空对话历史", scene.dbg_tec_win().line_count() == 0, str(scene.dbg_tec_win().line_count()))
	check("重置隐藏卡片", not bool(info["chip_visible"]) and not bool(info["min"]))

	scene.queue_free()
	await process_frame
