extends "res://tests/headless/_test_base.gd"
## P2.5 音乐播放器 / 花园彩蛋：唱针解锁、播放 / 暂停 / 收起、真名种子、
## 真实时间生长、旁白分段、老档迁移与存档。

const TEMP_PROGRESS := "user://test_p25_progress.json"
const TEMP_SAVE := "user://test_p25_case.save"

func _initialize() -> void:
	print("=== P2.5 音乐播放器 / 花园彩蛋 ===")
	var c := CaseLoader.new(CaseCatalog.path_of("A001"))
	check("案件数据装载", c.load_case(), c.load_error)
	if c.case_def == null:
		_finish()
		return
	_test_garden_core(c)
	_test_migration(c)
	await _test_desktop(c)
	_finish()

func _cleanup() -> void:
	for path in [TEMP_PROGRESS, TEMP_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_garden_core(c: CaseLoader) -> void:
	print("--- 花园纯逻辑 ---")
	var g := GraphState.new(c)
	check("初始花园空", g.garden["seed"] == false and (g.garden["plots"] as Array).is_empty())
	check("花园空判定", not GardenSystem.has_garden(g))
	check("五个生长档位", GardenSystem.STAGE_MS.size() == 5
		and GardenSystem.STAGE_MS[2] == 90000 and GardenSystem.STAGE_MS[4] == 180000,
		str(GardenSystem.STAGE_MS))
	check("五张阶段图", GardenSystem.STAGE_IMAGES.size() == 5)
	check("阶段名", GardenSystem.STAGE_NAMES[0] == "种子" and GardenSystem.STAGE_NAMES[4] == "开花")

	check("落点夹紧 x", GardenSystem.spot_of(-20, 200) == {"x": 8, "y": 85},
		str(GardenSystem.spot_of(-20, 200)))
	check("落点夹紧内保留", GardenSystem.spot_of(50.4, 58.6) == {"x": 50, "y": 59},
		str(GardenSystem.spot_of(50.4, 58.6)))

	var plot := {"at": 1000, "hit": false, "x": 50, "y": 50}
	check("下种即种子档", GardenSystem.stage_of(plot, 1000) == 0)
	check("44.999s 仍种子", GardenSystem.stage_of(plot, 45999) == 0)
	check("45s 嫩芽", GardenSystem.stage_of(plot, 46000) == 1)
	check("89.999s 嫩芽", GardenSystem.stage_of(plot, 90999) == 1)
	check("90s 展叶", GardenSystem.stage_of(plot, 91000) == 2)
	check("135s 舒叶", GardenSystem.stage_of(plot, 136000) == 3)
	check("179.999s 未开花", GardenSystem.stage_of(plot, 180999) == 3)
	check("180s 开花", GardenSystem.stage_of(plot, 181000) == 4)
	check("开花判定", GardenSystem.is_bloomed(plot, 181000) and not GardenSystem.is_bloomed(plot, 180999))
	check("进度 0", GardenSystem.progress_of(plot, 1000) == 0.0)
	check("进度 0.5", absf(GardenSystem.progress_of(plot, 91000) - 0.5) < 0.0001,
		str(GardenSystem.progress_of(plot, 91000)))
	check("进度封顶 1", GardenSystem.progress_of(plot, 999999) == 1.0)
	check("时间回拨不倒长", GardenSystem.stage_of(plot, 500) == 0
		and GardenSystem.progress_of(plot, 500) == 0.0)

	var raw := GraphState.new(c)
	raw.garden = {"seed": false, "plots": [null, {"at": "7", "x": -20, "y": 120},
		{"at": 8, "x": 50, "y": 60, "hit": true}]}
	var norm := GardenSystem.normalize(raw)
	var plots: Array = norm["plots"]
	check("归一化过滤 null", plots.size() == 2, str(plots))
	check("归一化夹坐标", int(plots[0]["x"]) == 8 and int(plots[0]["y"]) == 85, str(plots[0]))
	check("归一化 at 转 int", int(plots[0]["at"]) == 7 and bool(plots[1]["hit"]))

	var truth := c.ending_by_id("TRUE_E")
	check("真名结局存在", truth != null and truth.is_true_capture)
	var msg := GardenSystem.true_ending_message(c)
	check("真名说明非空", msg.length() > 300, str(msg.length()))
	check("真名说明来自结局", msg == truth.message)

	var g3 := GraphState.new(c)
	check("发种子成功", GardenSystem.grant_seed(g3, msg, c))
	check("种子已发", bool(g3.garden["seed"]))
	check("narr 已存", String(g3.garden.get("narr", "")) == msg)
	check("有种子即花园出现", GardenSystem.has_garden(g3))
	check("重复发种子失败", not GardenSystem.grant_seed(g3, msg, c))
	check("种子仍只有一枚", bool(g3.garden["seed"]) and (g3.garden["plots"] as Array).is_empty())

	check("无种子不能种", not GardenSystem.plant(GraphState.new(c), 50, 50))
	check("种下成功", GardenSystem.plant(g3, 120, -10, 5000))
	check("种下后种子没了", not bool(g3.garden["seed"]))
	var p1: Dictionary = (g3.garden["plots"] as Array)[0]
	check("种下坐标夹紧", int(p1["x"]) == 92 and int(p1["y"]) == 30, str(p1))
	check("种下 at 写入", int(p1["at"]) == 5000 and not bool(p1["hit"]))
	check("种下后重复发种子失败", not GardenSystem.grant_seed(g3, msg, c))
	check("有株即是花园", GardenSystem.has_garden(g3))

	var g4 := GraphState.new(c)
	g4.garden = {"seed": false, "plots": [{"at": 1, "x": 30, "y": 40}]}
	GardenSystem.normalize(g4, c)
	check("老档有株补 narr", String(g4.garden.get("narr", "")) == msg)
	check("缺 hit 补 false", not bool((g4.garden["plots"] as Array)[0].get("hit", true)))

	var segs := GardenSystem.narr_segments(msg)
	check("narr 分成多段", segs.size() > 1, str(segs.size()))
	check("narr 段不空", not (segs as Array).has(""))
	var joined := ""
	for s in segs:
		joined += String(s)
	check("narr 不丢字", joined.replace(" ", "") == msg.replace(" ", ""),
		"%d / %d" % [joined.length(), msg.length()])
	var longest := 0
	for s in segs:
		longest = maxi(longest, String(s).length())
	check("narr 段长受控", longest <= 190, str(longest))
	check("空文本无段", GardenSystem.narr_segments("").is_empty())
	check("短句一段", GardenSystem.narr_segments("你好。").size() == 1)
	var long_no_punct := "字".repeat(400)
	var hard := GardenSystem.narr_segments(long_no_punct)
	check("无标点长文也能切", hard.size() > 1 and String(hard[0]).length() <= 140,
		"%d / %d" % [hard.size(), String(hard[0]).length()])
	check("空档无段", GardenSystem.narr_segments("   ").is_empty())


func _test_migration(c: CaseLoader) -> void:
	print("--- P2.5 老档迁移 ---")
	var g := GraphState.new(c)
	var s := SaveSystem.new(g, "A001")
	var old := {"nodes": {"loc:SCENES_garden": {"key": "loc:SCENES_garden", "kind": "loc",
		"id": "SCENES_garden"}}, "endings": ["TRUE_E"]}
	check("旧档恢复成功", s.restore(old))
	check("旧档真名补种子", bool(g.garden.get("seed", false)))
	check("旧档花园无株", (g.garden["plots"] as Array).is_empty())

	var g2 := GraphState.new(c)
	var s2 := SaveSystem.new(g2, "A001")
	var old2 := {"nodes": {"loc:SCENES_garden": {"key": "loc:SCENES_garden", "kind": "loc",
		"id": "SCENES_garden"}}, "endings": ["TRUE_E"],
		"garden": {"seed": false, "plots": [{"at": 100, "x": 44, "y": 55}]}}
	check("旧档有花园恢复成功", s2.restore(old2))
	check("旧档有花园不重复发种", not bool(g2.garden.get("seed", false)))
	GardenSystem.normalize(g2, c)
	check("旧档有株回填 narr", String(g2.garden.get("narr", "")) == GardenSystem.true_ending_message(c))

	# S5：旧版「遮罩期间退出」留下的档——结局在、garden 字段在但 seed=false 且无株。
	var g3 := GraphState.new(c)
	g3.endings["TRUE_E"] = true
	g3.garden = {"seed": false, "plots": []}
	var g3n := GardenSystem.normalize(g3, c)
	check("S5 旧档补回丢失的真名种子", bool(g3n.get("seed", false)), str(g3n))
	check("S5 旧档补种同时补 narr",
		String(g3n.get("narr", "")) == GardenSystem.true_ending_message(c),
		String(g3n.get("narr", "")))


func _test_desktop(c: CaseLoader) -> void:
	print("--- P2.5 播放器 / 花园窗 / 存档 ---")
	var scene: Control = load("res://scenes/Desktop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.debug.dbg_use_temp_progress(TEMP_PROGRESS)
	scene.debug.dbg_save_system().path = TEMP_SAVE
	scene.debug.dbg_set_save_enabled(false)

	check("音乐图标初始隐藏", not scene.debug.dbg_music_icon_visible())
	check("花园图标初始隐藏", not scene.debug.dbg_garden_icon_visible())
	check("音乐窗初始关", scene.debug.dbg_music_win() == null)
	check("音乐资源存在", ResourceLoader.exists("res://assets/raw/Air_Bach.ogg"))
	check("曲目表 1 首", MusicWin.TRACKS.size() == 1)
	check("曲目名", MusicWin.title_of("Air_Bach") == "Air (Bach)")

	var changji_key: String = scene.debug.dbg_ensure("item", "ITEMS_changji")
	scene.debug.dbg_ensure("item", "ITEMS_cz")
	await process_frame
	check("唱机已在画布", not scene.graph.node(changji_key).is_empty())
	scene.debug.dbg_combo_ui("ITEMS_cz", "ITEMS_changji")
	await process_frame
	var ins: Dictionary = scene.graph.node(changji_key).installed
	check("唱针装上唱机", bool(ins.get("ITEMS_cz", false)), str(ins))
	check("装针后音乐图标出现", scene.debug.dbg_music_icon_visible())
	check("装针后花园仍隐藏", not scene.debug.dbg_garden_icon_visible())
	check("装针进入撤销栈", scene.debug.dbg_history_size() >= 1, str(scene.debug.dbg_history_size()))

	var w: MusicWin = scene.debug.dbg_open_music()
	check("打开播放器", w != null and w.visible)
	if w == null:
		scene.queue_free()
		return
	check("播放器标题", w.title == "播放器", w.title)
	check("播放器位置", w.position == Vector2(906, 414), str(w.position))
	check("播放器宽度", w.size.x == 360.0, str(w.size))
	var st: Dictionary = scene.debug.dbg_music_state()
	check("播放器一首曲目", int(st["rows"]) == 1, str(st))
	check("初始未播放", String(st["current"]) == "" and not bool(st["playing"]))
	check("E3 播放键是 18×18 自绘键", w._play_btn.size == Vector2(18, 18)
		and w._play_btn._mode == "play", str(w._play_btn.size))
	# D1：曲目列表的小节标题是黑条白字（h4），且排在列表之上。
	var head_bar := w._head as PanelContainer
	var head_sb := head_bar.get_theme_stylebox("panel") as StyleBoxFlat if head_bar != null else null
	var head_lab := head_bar.get_child(0) as Label if head_bar != null and head_bar.get_child_count() > 0 else null
	check("D1 曲目小节 = 黑条白字",
		head_sb != null and head_sb.bg_color.is_equal_approx(TecTheme.INK)
			and head_lab != null and not head_lab.text.is_empty()
			and head_lab.get_theme_color("font_color").is_equal_approx(TecTheme.TEXT_ON_DARK),
		str(head_sb) + " / " + (head_lab.text if head_lab != null else "null"))
	check("D1 小节条在曲目列表之上", head_bar != null and w._list != null
		and head_bar.get_index() < w._list.get_index())
	var rec: Dictionary = w._rows["Air_Bach"]
	var row_btn := rec["button"] as Button
	var row_sb := row_btn.get_theme_stylebox("normal") as StyleBoxFlat
	check("B2 曲目行是纸底 + 1px 键线（不是黑药丸）",
		row_sb.bg_color.is_equal_approx(TecTheme.CARD) and row_sb.border_width_top == 1,
		str(row_sb.bg_color) + " / " + str(row_sb.border_width_top))
	check("B2 曲目行有音符 glyph", (rec["glyph"] as Control).size == Vector2(12, 12))
	check("B2 未播放时不亮标记", not bool(rec["mark"].shown))

	check("播放 Air", scene.debug.dbg_music_play("Air_Bach"))
	await process_frame
	st = scene.debug.dbg_music_state()
	check("正在播放", bool(st["playing"]) and not bool(st["paused"]), str(st))
	check("E3 播放中图标切成暂停", w._play_btn._mode == "pause", w._play_btn._mode)
	check("曲目 id", String(st["current"]) == "Air_Bach")
	check("曲目时长", float(st["duration"]) > 0.0, str(st["duration"]))
	row_sb = row_btn.get_theme_stylebox("normal") as StyleBoxFlat
	check("B2 播放中仍是纸底，只加粗键线",
		row_sb.bg_color.is_equal_approx(TecTheme.CARD) and row_sb.border_width_top == 2,
		str(row_sb.bg_color) + " / " + str(row_sb.border_width_top))
	check("B2 播放中行尾方块实心", bool(rec["mark"].shown) and bool(rec["mark"].playing))
	check("B2 当前曲目音符转墨色", bool(rec["glyph"].inked))
	w.seek_ratio(0.5)
	await process_frame
	st = scene.debug.dbg_music_state()
	check("进度可跳转", float(st["time"]) > float(st["duration"]) * 0.4, str(st))
	# W18：进度条按住拖动，不是只能点一下。
	var w18_prog := w.find_child("music_prog", true, false) as ProgressBar
	check("W18 进度条存在", w18_prog != null)
	if w18_prog != null:
		var w18_fill := w18_prog.get_theme_stylebox("fill") as StyleBoxFlat
		check("C-B 播放进度条用强调青",
			w18_fill != null and w18_fill.bg_color.is_equal_approx(TecTheme.SPOT_ACCENT))
	if w18_prog != null:
		var w18_down := InputEventMouseButton.new()
		w18_down.button_index = MOUSE_BUTTON_LEFT
		w18_down.pressed = true
		w18_down.position = Vector2(6.0, 5.0)
		w._on_prog_input(w18_down)
		check("W18 按下进入拖动", w._prog_dragging)
		var w18_move := InputEventMouseMotion.new()
		w18_move.position = Vector2(w18_prog.size.x * 0.75, 5.0)
		w._on_prog_input(w18_move)
		st = scene.debug.dbg_music_state()
		check("W18 按住拖动跟手", float(st["time"]) > float(st["duration"]) * 0.6, str(st))
		var w18_up := InputEventMouseButton.new()
		w18_up.button_index = MOUSE_BUTTON_LEFT
		w18_up.pressed = false
		w18_up.position = w18_move.position
		w._on_prog_input(w18_up)
		check("W18 松手结束拖动", not w._prog_dragging)
	check("同曲再点暂停", not scene.debug.dbg_music_toggle())
	st = scene.debug.dbg_music_state()
	check("暂停状态", bool(st["paused"]) and not bool(st["playing"]), str(st))
	check("E3 暂停后图标切回播放", w._play_btn._mode == "play", w._play_btn._mode)
	check("B2 暂停时行尾方块转空心", bool(rec["mark"].shown) and not bool(rec["mark"].playing))
	check("再点续播", scene.debug.dbg_music_toggle())
	st = scene.debug.dbg_music_state()
	check("续播状态", bool(st["playing"]) and not bool(st["paused"]))

	scene.debug.dbg_click_music_icon()
	st = scene.debug.dbg_music_state()
	check("K9 单击音乐图标不再关窗", bool(st["win_visible"]) and bool(st["playing"]), str(st))
	scene.debug.dbg_close_music()
	st = scene.debug.dbg_music_state()
	check("× 关闭后音频继续", not bool(st["win_visible"]) and bool(st["playing"]), str(st))
	scene.debug.dbg_set_icon_last("", -100000)
	scene.debug.dbg_click_music_icon()
	st = scene.debug.dbg_music_state()
	check("K9 单击音乐图标不直接开窗", not bool(st["win_visible"]), str(st))
	scene.debug.dbg_double_click_icon("music")
	st = scene.debug.dbg_music_state()
	check("K9 双击音乐图标开窗", bool(st["win_visible"]) and not bool(st["dock_visible"]), str(st))

	scene.debug.dbg_close_music()
	st = scene.debug.dbg_music_state()
	check("关闭窗后音频继续", not bool(st["win_visible"]) and bool(st["playing"]), str(st))
	w = scene.debug.dbg_open_music()
	check("点图标恢复窗", w != null and w.visible)

	scene.debug.dbg_minimize_music()
	st = scene.debug.dbg_music_state()
	var dock: MusicDock = scene.debug.dbg_music_dock()
	check("最小化隐藏窗", not bool(st["win_visible"]))
	check("最小化出 dock", dock != null and bool(st["dock_visible"]))
	if dock != null:
		check("dock 位置", dock.position == Vector2(1026, 532), str(dock.position))
		check("dock 曲名", String(dock.state().get("title", "")) == "Air (Bach)")
		check("E3 dock 键也是 18×18 且同步播放中",
			dock._toggle_btn.size == Vector2(18, 18) and dock._toggle_btn._mode == "pause",
			str(dock._toggle_btn.size))
		# U7：音乐坞可拖，resize 不吸回；未拖动松手才还原。
		var dock_home: Vector2 = dock.position
		var dock_at: Vector2 = dock.get_global_rect().get_center()
		var dock_down := InputEventMouseButton.new()
		dock_down.button_index = MOUSE_BUTTON_LEFT
		dock_down.pressed = true
		dock_down.position = dock_at
		dock_down.global_position = dock_at
		dock.gui_input.emit(dock_down)
		var dock_move := InputEventMouseMotion.new()
		dock_move.button_mask = MOUSE_BUTTON_MASK_LEFT
		dock_move.position = dock_at + Vector2(-150, -80)
		dock_move.global_position = dock_at + Vector2(-150, -80)
		dock.gui_input.emit(dock_move)
		var dock_up := InputEventMouseButton.new()
		dock_up.button_index = MOUSE_BUTTON_LEFT
		dock_up.pressed = false
		dock_up.position = dock_at + Vector2(-150, -80)
		dock_up.global_position = dock_at + Vector2(-150, -80)
		dock.gui_input.emit(dock_up)
		await process_frame
		check("U7 音乐坞可拖动", dock.position != dock_home, str(dock.position) + " / " + str(dock_home))
		check("U7 音乐坞拖动后仍在桌面内",
			scene.debug.dbg_desk().get_global_rect().encloses(dock.get_global_rect()), str(dock.get_global_rect()))
		var dock_dragged: Vector2 = dock.position
		scene.debug.dbg_layout_music_windows()
		check("U7 音乐坞 resize 不被吸回", dock.position == dock_dragged,
			str(dock.position) + " / " + str(dock_dragged))
		var dock_click: Vector2 = dock.get_global_rect().get_center()
		var dock_cdown := InputEventMouseButton.new()
		dock_cdown.button_index = MOUSE_BUTTON_LEFT
		dock_cdown.pressed = true
		dock_cdown.position = dock_click
		dock_cdown.global_position = dock_click
		dock.gui_input.emit(dock_cdown)
		var dock_cup := InputEventMouseButton.new()
		dock_cup.button_index = MOUSE_BUTTON_LEFT
		dock_cup.pressed = false
		dock_cup.position = dock_click
		dock_cup.global_position = dock_click
		dock.gui_input.emit(dock_cup)
	check("收起后音频继续", bool(st["playing"]))
	st = scene.debug.dbg_music_state()
	check("dock 还原窗", bool(st["win_visible"]) and not bool(st["dock_visible"]))

	scene.debug.dbg_music_stop()
	st = scene.debug.dbg_music_state()
	check("停止清空曲目", String(st["current"]) == "" and not bool(st["playing"])
		and not bool(st["paused"]), str(st))

	# S4：先撤销一个和音乐无关的动作，播放器与音频必须原样保留。
	check("S4 前置：重新播放", scene.debug.dbg_music_play("Air_Bach"))
	await process_frame
	var torch_key: String = scene.debug.dbg_ensure("item", "ITEM_shoudiantong")
	await process_frame
	scene.debug.dbg_activate(torch_key)
	await process_frame
	check("S4 前置：无关操作进入撤销栈", scene.debug.dbg_history_size() >= 1,
		str(scene.debug.dbg_history_size()))
	check("S4 撤销无关操作", scene.debug.dbg_undo())
	await process_frame
	# F3：撤销走 card_key 增量 reconcile，不再把整批卡片销毁重建。
	var f3_stats: Dictionary = scene.debug.dbg_last_rebuild_stats()
	check("F3 撤销复用已有卡片", int(f3_stats.get("reused", 0)) > 0, str(f3_stats))
	st = scene.debug.dbg_music_state()
	check("S4 撤销无关操作后播放器还在", scene.debug.dbg_music_win() != null)
	check("S4 撤销无关操作不掐音乐",
		bool(st["win_visible"]) and bool(st["playing"]), str(st))

	# 撤销「装针」本身会让音乐重新锁定，此时收起播放器是正确语义；
	# S4 只保证无关撤销不误伤正在播的歌。
	check("撤销装针", scene.debug.dbg_undo())
	await process_frame
	check("撤销装针后音乐图标隐藏", not scene.debug.dbg_music_icon_visible())
	check("撤销装针后播放器按锁定态释放", scene.debug.dbg_music_win() == null)

	check("真名结局可播", scene.debug.dbg_ending() != null)
	scene.debug.dbg_hide_toast()
	scene.debug.dbg_play_true_ending()
	check("结局遮罩已开", scene.debug.dbg_ending().visible)
	scene.debug.dbg_confirm_ending()
	await process_frame
	var g: GraphState = scene.graph
	check("确认捕获后发种子", bool(g.garden.get("seed", false)), str(g.garden))
	check("narr 是真名说明", String(g.garden.get("narr", "")) == GardenSystem.true_ending_message(c))
	check("花园图标出现", scene.debug.dbg_garden_icon_visible())
	check("花园种子角标", scene.debug.dbg_garden_badge_text() == "种子", scene.debug.dbg_garden_badge_text())
	check("G3 种子提示指向左侧花园图标",
		scene.debug.dbg_toast_text().contains("拖") and scene.debug.dbg_toast_text().contains("左侧")
			and scene.debug.dbg_toast_text().contains("花园"), scene.debug.dbg_toast_text())
	check("重复确认不再发", not GardenSystem.grant_seed(g, "x", c))
	check("重复确认不改 narr", String(g.garden.get("narr", "")) == GardenSystem.true_ending_message(c))

	var matrix: MatrixWin = scene.debug.dbg_open_matrix()
	check("桌布种子气泡可见", matrix != null and matrix.seed_visible())
	var garden: GardenWin = scene.debug.dbg_open_garden()
	check("花园窗打开", garden != null and garden.visible)
	if g == null or garden == null or matrix == null:
		scene.queue_free()
		return
	check("花园窗标题", garden.title == "花园", garden.title)
	check("花园宽 520", garden.size.x == 548.0, str(garden.size))
	check("G3 桌布与花园并排、不互相遮挡",
		not matrix.get_global_rect().intersects(garden.get_global_rect()),
		"%s / %s" % [matrix.get_global_rect(), garden.get_global_rect()])
	var view_rect := Rect2(Vector2.ZERO, Vector2(scene.debug.dbg_vw(), scene.debug.dbg_vh()))
	check("G3 桌布与花园都在视口内",
		view_rect.encloses(matrix.get_global_rect()) and view_rect.encloses(garden.get_global_rect()),
		"%s / %s" % [matrix.get_global_rect(), garden.get_global_rect()])
	var field: Rect2 = garden.field_global_rect()
	check("花圃有宽度", field.size.x > 400.0 and field.size.y == 260.0, str(field))
	check("花圃在窗内", garden.get_global_rect().encloses(field), str(garden.get_global_rect()))
	check("空花圃提示种子", bool(garden.dbg_state()["hint_visible"]))

	matrix.dbg_drop_seed(field.get_center())
	await process_frame
	check("拖种成功", not bool(g.garden.get("seed", false)) and (g.garden["plots"] as Array).size() == 1,
		str(g.garden))
	var plot: Dictionary = (g.garden["plots"] as Array)[0]
	check("落点靠近中心", absi(int(plot["x"]) - 50) <= 2 and absi(int(plot["y"]) - 50) <= 2, str(plot))
	check("落点在花圃范围", int(plot["x"]) >= 8 and int(plot["x"]) <= 92
		and int(plot["y"]) >= 30 and int(plot["y"]) <= 85)
	check("拖种后气泡消失", not matrix.seed_visible())
	check("种下后提示消失", not bool(garden.dbg_state()["hint_visible"]))
	check("花园角标 1 株", scene.debug.dbg_garden_badge_text() == "1 株", scene.debug.dbg_garden_badge_text())
	var gs: Dictionary = garden.dbg_state()
	check("花园状态 1 株", (gs["plots"] as Array).size() == 1, str(gs))
	check("下种即种子档", int((gs["plots"] as Array)[0]["stage"]) == 0)
	check("下种有 at", int(plot["at"]) > 0)

	var base_h := garden.size.y
	var now := GardenSystem.now_ms_now()
	check("回拨生长时间", scene.debug.dbg_touch_garden_plot(0, now - 181000))
	# P2 Toast 改为同屏一条、后来者排队：先清掉上一条，下面才能立即断言开花提示。
	scene.debug.dbg_hide_toast()
	garden._process(1.1)
	await process_frame
	gs = garden.dbg_state()
	plot = (g.garden["plots"] as Array)[0]
	check("180s 后开花", int((gs["plots"] as Array)[0]["stage"]) == 4,
		str((gs["plots"] as Array)[0]))
	check("开花写入 hit", bool(plot.get("hit", false)))
	check("开花弹提示", scene.debug.dbg_toast_text() == "花园里的种子开花了", scene.debug.dbg_toast_text())
	check("旁白段数 > 1", int(gs["narr_segments"]) > 1, str(gs["narr_segments"]))

	check("点花打开旁白", garden.dbg_open_narr(0))
	await process_frame
	gs = garden.dbg_state()
	check("旁白首段", int(gs["narr_index"]) == 0 and int(gs["narr_shown"]) == 1, str(gs))
	check("旁白增高窗", garden.size.y > base_h, "%s / %s" % [str(garden.size.y), str(base_h)])
	check("旁白完整落在窗内", garden._narr != null
		and garden.get_global_rect().encloses(garden._narr.get_global_rect()),
		"null" if garden._narr == null else "%s / %s" % [
			garden.get_global_rect(), garden._narr.get_global_rect()])
	var segs := GardenSystem.narr_segments(GardenSystem.true_ending_message(c))
	check("旁白可继续", garden.dbg_advance_narr())
	gs = garden.dbg_state()
	check("旁白第二段", int(gs["narr_shown"]) == 2, str(gs))
	var wr: Rect2 = gs["win_rect"]
	check("旁白窗不越界", wr.position.y + wr.size.y <= 792.0, str(wr))
	check("旁白继续到末段", int(gs["narr_shown"]) < segs.size())
	var guard := 0
	while int(garden.dbg_state()["narr_shown"]) < segs.size() and guard < 200:
		garden.dbg_advance_narr()
		guard += 1
	check("旁白读到最后", int(garden.dbg_state()["narr_shown"]) == segs.size(), str(guard))
	gs = garden.dbg_state()
	wr = gs["win_rect"]
	check("末段窗不越界", wr.position.y + wr.size.y <= 792.0, str(wr))
	check("末段不再推进", not garden.dbg_advance_narr())
	garden.close_narr()
	await process_frame
	check("关旁白缩回", garden.size.y <= base_h + 1.0, str(garden.size.y))

	check("拖动已种下的株", garden.dbg_drag_plant(0, 25, 40))
	plot = (g.garden["plots"] as Array)[0]
	check("拖动后坐标更新", int(plot["x"]) == 25 and int(plot["y"]) == 40, str(plot))
	# F9：阶段未变时不再重载贴图 / 重建 stylebox / 改标签。
	var f9_before: int = garden._stage_refreshes
	garden._refresh_growth()
	garden._refresh_growth()
	check("F9 同阶段刷新不重复换装", garden._stage_refreshes == f9_before,
		"%d -> %d" % [f9_before, garden._stage_refreshes])

	check("写临时存档", scene.debug.dbg_save())
	check("存档文件存在", FileAccess.file_exists(TEMP_SAVE))
	var g2 := GraphState.new(c)
	var s2 := SaveSystem.new(g2, "A001", TEMP_SAVE)
	check("读取临时存档", s2.load_from_disk(), s2.last_error)
	GardenSystem.normalize(g2, c)
	check("存档种子状态", not bool(g2.garden.get("seed", false)))
	check("存档株数", (g2.garden["plots"] as Array).size() == 1)
	check("存档 at 保留", int((g2.garden["plots"] as Array)[0]["at"]) == int(plot["at"]))
	check("存档 hit 保留", bool((g2.garden["plots"] as Array)[0]["hit"]))
	check("存档 narr 保留", String(g2.garden.get("narr", "")) == String(g.garden.get("narr", "")))

	# A7：点桌布窗内 × 关闭时，被遮罩淡出的卡片必须恢复（用户截图：节点消失、连线还在）。
	# S16 会给未读节点补入场 pop，pop 未结束的卡 alpha < 1；等它跑完再挑「正常可见」的卡。
	for i in 30:
		await process_frame
	var probe: NodeCard = null
	for key in scene.debug.dbg_cards().keys():
		var c2 := scene.debug.dbg_cards()[key] as NodeCard
		if c2 == null or not c2.visible or c2.modulate.a < 0.99:
			continue
		if probe == null:
			probe = c2
		if not scene.graph.neighbors(String(key)).is_empty():
			probe = c2
			break
	if probe != null:
		var saved_global := probe.global_position
		var probe_has_edges: bool = not scene.graph.neighbors(probe.card_key).is_empty()
		if not probe_has_edges:
			for key in scene.debug.dbg_cards().keys():
				var other := scene.debug.dbg_cards()[key] as NodeCard
				if other != null and other.visible and other.card_key != probe.card_key:
					scene.graph.link(probe.card_key, other.card_key, "entity")
					probe_has_edges = true
					break
		scene.debug.dbg_repaint_edges()
		var segs_before: int = scene.debug.dbg_edge_layer().segment_count()
		probe.global_position = matrix.global_position + Vector2(20, 20)
		scene.debug.dbg_matrix_sync_occlusion()
		scene.debug.dbg_repaint_edges()
		if probe_has_edges and segs_before > 0:
			check("A7 淡出卡不再画连线",
				scene.debug.dbg_edge_layer().segment_count() < segs_before,
				str(segs_before) + " -> " + str(scene.debug.dbg_edge_layer().segment_count()))
		check("A7 矩阵覆盖的卡淡出", probe.modulate.a == 0.0, str(probe.modulate.a))
		matrix._on_close_pressed()
		await process_frame
		check("A7 关闭矩阵后引用清空", scene.debug.dbg_matrix_win() == null)
		check("A7 关闭矩阵后覆盖卡恢复", probe.modulate.a == 1.0, str(probe.modulate.a))
		probe.global_position = saved_global

	# F2：EdgeLayer 按边身份缓存贝塞尔采样点，只重采样端点真的变了的边。
	var el := EdgeLayer.new()
	el.size = Vector2(1000.0, 800.0)
	root.add_child(el)
	var fsegs: Array = []
	for i in 10:
		fsegs.append({
			"id": "e:%d" % i,
			"a": Vector2(20.0 + i * 10.0, 30.0 + i * 6.0),
			"b": Vector2(300.0 + i * 10.0, 120.0 + i * 6.0),
			"kind": "entity", "dim": false,
		})
	el.dbg_set_curve_cache(true)
	el.set_segments(fsegs)
	check("F2 首帧建满 10 条曲线", el.dbg_curve_builds() == 10, str(el.dbg_curve_builds()))
	el.dbg_reset_curve_builds()
	el.set_segments(fsegs)
	check("F2 端点没变：0 次重采样", el.dbg_curve_builds() == 0, str(el.dbg_curve_builds()))
	fsegs[0]["dim"] = true
	el.set_segments(fsegs)
	check("F2 只改 dim 不重采样", el.dbg_curve_builds() == 0, str(el.dbg_curve_builds()))
	fsegs[0]["a"] = Vector2(25.0, 35.0)
	el.set_segments(fsegs)
	check("F2 只有移动的 1 条边重采样", el.dbg_curve_builds() == 1,
		str(el.dbg_curve_builds()))
	fsegs.remove_at(1)
	el.set_segments(fsegs)
	check("F2 删边后缓存收缩", el.dbg_curve_cache_size() == 9,
		str(el.dbg_curve_cache_size()))
	check("F2 segment_count 跟随输入", el.segment_count() == 9, str(el.segment_count()))
	el.dbg_set_curve_cache(false)
	el.dbg_reset_curve_builds()
	el.set_segments(fsegs)
	check("F2 关缓存复现旧版全量采样", el.dbg_curve_builds() == 9,
		str(el.dbg_curve_builds()))
	el.queue_free()

	scene.queue_free()
	await process_frame
