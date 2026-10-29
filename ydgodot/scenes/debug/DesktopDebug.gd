extends "res://scenes/debug/DesktopDebugApps.gd"
## 截图流程（--shot / --shot-p2 / --shot-p3）与最后的私有 helper。
## 公共 dbg_* API 由前五层继承；本文件不再持有 desk 字段。


func _wait(sec: float) -> void:
	await desk.get_tree().create_timer(sec).timeout


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = desk.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[shot] ", path, " ", img.get_width(), "x", img.get_height())


func _shot_flow() -> void:
	await _wait(0.6)
	await _shot("res://docs/p0_1_desktop.png")

	desk.card_ui._expand_scene("SCENES_garden", true)
	await _wait(0.5)
	await _shot("res://docs/p0_2_garden.png")

	# 开局不再直接给手电筒（对齐 Web）：截图流程走真实链路 书桌 → 抽屉 → 左侧抽屉
	desk.card_ui._on_card_activated("item:ITEM_shuzhuo")
	await _wait(0.25)
	desk.card_ui._on_card_activated("item:ITEM_chouti")
	await _wait(0.25)
	desk.card_ui._on_card_activated("loc:SCENES_choutiyi")
	await _wait(0.25)

	desk.combos.toggle_light("item:ITEM_shoudiantong")
	if desk._cards.has("item:ITEM_shoudiantong"):
		desk._cards["item:ITEM_shoudiantong"].refresh()
		desk.canvas._sync_card_shell(desk._cards["item:ITEM_shoudiantong"])
	desk.card_ui._on_card_combo("item:ITEM_shoudiantong", "item:ITEM_something")
	await _wait(0.5)
	await _shot("res://docs/p0_3_body.png")

	desk.tec._toggle_tec()
	desk.tec._start_tec_analysis("loc:SCENES_body")
	await _wait(1.1)                      # 分析进行中（真实 5–8 秒，这里取中段）
	await _shot("res://docs/p0_4_tec.png")
	desk._tec.finish_now()
	await _wait(0.25)
	# P1.4 起 TEC 分析不再直接触发结局：这里仍按 P0 基线直接放 TRUE_E，只为保留对拍图
	desk._ending.play(desk.case_def.ending_by_id("TRUE_E"))
	await _wait(0.25)
	await _shot("res://docs/p0_5_ending.png")
	desk._ending.finish_now()
	await _wait(0.25)
	await _shot("res://docs/p0_6_ending_full.png")

	# ── P1 新特性：容器展开 / 选项节点 / 密码弹窗 / 折叠 ──
	desk._ending.visible = false
	desk.session._start_slice()
	await _wait(0.3)
	desk.card_ui._expand_scene("SCENES_garden", false)
	await _wait(0.2)
	_ensure_card("item", "ITEM_shuzhuo")
	desk.card_ui._toggle_container("item", "ITEM_shuzhuo")
	await _wait(0.35)
	await _shot("res://docs/p1_1_container.png")

	desk.card_ui._toggle_container("item", "ITEM_chouti")    # choice：两个抽屉一起上画布
	await _wait(0.35)
	await _shot("res://docs/p1_2_choice.png")

	_ensure_card("item", "ITEMS_jzmh")
	desk.card_ui._open_password(desk.graph.key_of("item", "ITEMS_jzmh"))
	await _wait(0.35)
	await _shot("res://docs/p1_3_password.png")
	desk.card_ui._submit_password("0321")
	await _wait(0.35)
	await _shot("res://docs/p1_4_unlocked.png")

	desk.card_ui._toggle_container("item", "ITEM_shuzhuo")   # 再双击 = 收起
	await _wait(0.35)
	await _shot("res://docs/p1_5_collapsed.png")

	# ── 收纳三态（P1.2）：物品 / 证据两扇窗 ──
	desk.session._start_slice()
	await _wait(0.3)
	desk.card_ui._expand_scene("SCENES_garden", false)
	await _wait(0.2)
	_ensure_card("item", "ITEM_taideng")
	dbg_select("item:ITEM_taideng")
	dbg_store("BAG")
	_ensure_card("clue", "CLUES_nm")
	dbg_select("clue:CLUES_nm")
	dbg_store("LEDGER")
	desk.drag._toggle_storage(GraphState.BAG)
	await _wait(0.35)
	await _shot("res://docs/p1_6_bag.png")

	desk.drag._toggle_storage(GraphState.LEDGER)
	await _wait(0.35)
	await _shot("res://docs/p1_7_ledger.png")

	# ── 推演桌布（P1.4）：五感归位 → 长按 → 真名遮罩 ──
	var true_e: EndingDef = desk.case_def.ending_by_id("TRUE_E")
	for clue in true_e.recipe:
		_ensure_card("clue", clue.id)
		desk.matrix._assign_to_matrix(desk.graph.key_of("clue", clue.id))
	dbg_open_matrix()
	await _wait(0.4)
	await _shot("res://docs/p1_8_matrix.png")

	dbg_matrix_charge()
	await _wait(0.3)
	dbg_ending_finish()
	await _wait(0.3)
	await _shot("res://docs/p1_9_truename.png")
	desk.quit_app()


func _shot_intro_flow() -> void:
	await _wait(0.4)
	desk._inv_path = "user://shot_investigator.json"
	Investigator.clear(desk._inv_path)
	desk._investigator = {}
	desk.session._refresh_chip()
	var w: IntroWin = desk.session._open_intro()
	await _wait(0.4)
	await _shot("res://docs/p1_10_intro_name.png")
	w.dbg_set_name("林雾")
	w.dbg_begin()
	await _wait(0.3)
	await _shot("res://docs/p1_11_intro_quiz.png")
	w.dbg_answer(0)
	w.dbg_answer(0)
	w.dbg_answer(2)
	await _wait(0.3)
	await _shot("res://docs/p1_12_intro_avatar.png")
	w.dbg_confirm_pick()
	await _wait(0.3)
	await _shot("res://docs/p1_13_intro_card.png")
	w.dbg_confirm()
	await _wait(0.5)
	await _shot("res://docs/p1_14_investigator.png")
	desk.session._open_cert_review()
	await _wait(0.3)
	await _shot("res://docs/p1_15_cert.png")
	Investigator.clear(desk._inv_path)
	desk.quit_app()


func _shot_p2_flow() -> void:
	await _wait(0.5)
	desk._catalog.clear_progress(desk._progress_path)
	desk._catalog = CaseCatalog.new(desk._progress_path)
	desk.session._update_case_park_ui()

	# ── P4.2：桌面图标的按下态（只反白标签条，图标本体不垫底板）──
	# 必须**在流程开头**拍：跑到结尾时图标栏已经切紧凑模式、标签被收掉了。
	var pressed_icon: Button = desk.launcher._icon_by_app("bag")
	if pressed_icon != null:
		pressed_icon.set_selected(true)
		desk._hide_toast()
		await _wait(0.3)
		await _shot("res://docs/p2_23_icon_press.png")
		pressed_icon.set_selected(false)

	dbg_open_case_map()
	await _wait(0.35)
	await _shot("res://docs/p2_1_case_map.png")
	if desk._map_win != null and is_instance_valid(desk._map_win):
		desk._map_win.queue_free()
	desk._map_win = null

	dbg_park_case("dock")
	await _wait(0.35)
	await _shot("res://docs/p2_2_case_dock.png")

	dbg_reopen_case()
	await _wait(0.25)
	dbg_park_case("icon")
	await _wait(0.35)
	await _shot("res://docs/p2_3_case_closed.png")

	dbg_catalog_unlock("A002")
	dbg_open_case_map()
	await _wait(0.35)
	await _shot("res://docs/p2_4_case_unlocked.png")
	if desk._map_win != null and is_instance_valid(desk._map_win):
		desk._map_win.queue_free()
	desk._map_win = null

	desk.session._reopen_case()
	desk.session._start_slice()
	await _wait(0.3)
	desk.card_ui._expand_scene("SCENES_body", false)
	desk.tec._open_tec()
	desk.tec._tec_talk()
	desk.tec._tec_talk()
	desk._tec.finish_typing()
	desk._hide_toast()
	await _wait(0.35)
	await _shot("res://docs/p2_5_tec_chat.png")

	desk.tec._start_tec_analysis("loc:SCENES_body")
	await _wait(2.5)
	await _shot("res://docs/p2_6_tec_analysis.png")

	desk.tec._minimize_tec()
	await _wait(0.35)
	await _shot("res://docs/p2_7_tec_chip.png")

	desk._tec.finish_now()
	await _wait(0.3)
	desk._hide_toast()
	await _wait(0.2)
	await _shot("res://docs/p2_8_tec_chip_done.png")

	desk.tec._open_tec()
	await _wait(0.35)
	await _shot("res://docs/p2_9_tec_archive.png")

	desk.tec._hide_tec()
	desk.card_ui._expand_scene("SCENES_fkjl", false)
	await _wait(0.35)
	desk.narrative._toggle_archive()
	await _wait(0.35)
	await _shot("res://docs/p2_10_archive.png")
	desk.narrative._toggle_archive()
	await _wait(0.15)

	desk.card_ui._expand_scene("SCENES_lhsdst", false)
	await _wait(0.2)
	desk.narrative._select_time("SCENES_0602")
	await _wait(0.5)
	_show_mem_lines(3)
	await _wait(0.3)
	await _shot("res://docs/p2_11_memory_card.png")

	desk.narrative._close_mem_card()
	desk.card_ui._on_card_combo("char:NPC_FB", "loc:SCENES_garden")
	await _wait(0.3)
	_show_mem_lines(4)
	await _wait(0.35)
	await _shot("res://docs/p2_12_memory_play.png")

	desk.narrative._close_mem_card()
	desk.narrative._select_time("SCENES_0704")
	await _wait(0.5)
	desk.narrative._close_mem_card()
	desk._hide_toast()
	desk.card_ui._on_card_combo("char:CHARS_zs", "char:CHARS_luhengs")
	await _wait(0.35)
	_show_chat_lines(5)
	desk._hide_toast()
	await _wait(0.35)
	await _shot("res://docs/p2_13_dialogue.png")
	desk.narrative._close_chat()

	var garden: DialogueDef = desk.dialogues.by_id("DLG_garden_review") if desk.dialogues != null else null
	desk.narrative._open_chat(garden, ["CHARS_zs", "NPC_FB"])
	await _wait(0.3)
	desk._chat_win.finish_line()
	desk._chat_win.advance()
	desk._chat_win.finish_line()
	desk._chat_win.advance()
	desk._hide_toast()
	await _wait(0.35)
	await _shot("res://docs/p2_14_dialogue_join.png")
	desk.narrative._close_chat()

	desk.narrative._open_monologue("CHARS_luhengs")
	await _wait(0.3)
	_show_chat_lines(4)
	desk._hide_toast()
	await _wait(0.35)
	await _shot("res://docs/p2_15_monologue.png")
	desk.narrative._close_chat()

	# ── P2.5 音乐播放器 / 花园彩蛋 ──
	_ensure_card("item", "ITEMS_changji")
	_ensure_card("item", "ITEMS_cz")
	dbg_combo_ui("ITEMS_cz", "ITEMS_changji")
	desk._hide_toast()
	var music := dbg_open_music()
	if music != null:
		music.play_track("Air_Bach")
		await _wait(0.2)
		music.seek_ratio(0.25)
	await _wait(0.8)
	await _shot("res://docs/p2_16_music.png")
	desk.garden_music._minimize_music()
	await _wait(0.45)
	await _shot("res://docs/p2_17_music_dock.png")
	desk.garden_music._restore_music()
	desk.garden_music._stop_music()
	desk.garden_music._on_music_closed()

	dbg_play_true_ending()
	dbg_confirm_ending()
	await _wait(0.25)
	dbg_open_matrix()
	desk._hide_toast()
	await _wait(0.4)
	await _shot("res://docs/p2_18_matrix_seed.png")
	if desk._matrix_win != null and is_instance_valid(desk._matrix_win):
		desk._matrix_win.queue_free()
	desk._matrix_win = null
	var gwin := dbg_open_garden()
	desk._hide_toast()
	await _wait(0.45)
	await _shot("res://docs/p2_19_garden_seed.png")
	if gwin != null:
		desk.garden_music._drop_seed(gwin.field_global_rect().get_center())
		dbg_touch_garden_plot(0, GardenSystem.now_ms_now() - 181000)
		gwin._process(1.1)
		await _wait(0.2)
		gwin.dbg_open_narr(0)
		gwin.dbg_advance_narr()
		desk._hide_toast()
		await _wait(0.45)
		await _shot("res://docs/p2_20_garden_narr.png")

	# ── 批 1：人物名册 / 因果追踪 ──
	dbg_close_garden()
	await _wait(0.3)
	var people := dbg_open_people()
	desk._hide_toast()
	await _wait(0.45)
	await _shot("res://docs/p2_21_people.png")
	dbg_close_people()
	await _wait(0.25)
	dbg_open_log()
	desk._hide_toast()
	await _wait(0.45)
	await _shot("res://docs/p2_22_log.png")
	dbg_close_log()
	desk.quit_app()


func _shot_p3_flow() -> void:
	await _wait(0.5)
	desk.session._new_runtime()
	## 与 Web 侧对拍脚本对齐：那边走完开场适性测试（姓名「陈调整」），页眉才有证章。
	## 证号写死成 TEC-GD-2160，两边的证章文字才逐字相同。
	desk._investigator = {"name": "陈调整", "id": "TEC-GD-2160", "sense": ["vision"], "avatarId": "CHARS_EXEC"}
	desk.session._refresh_chip()
	var loc := desk.graph.add_node("loc", desk.SLICE_SCENE)
	loc.x = 40.0
	loc.y = 30.0
	desk.graph.mark_fresh(loc.key)
	desk.canvas._spawn_card(loc.key)
	desk.canvas._relayout()
	desk._hide_toast()
	await _wait(0.5)
	await _shot("res://docs/p3/godot/start.png")
	desk.quit_app()


func _show_chat_lines(n: int) -> void:
	if desk._chat_win == null or not is_instance_valid(desk._chat_win):
		return
	desk._chat_win.finish_line()
	for i in maxi(0, n - 1):
		if not desk._chat_win.advance():
			break
		desk._chat_win.finish_line()


func _show_mem_lines(n: int) -> void:
	if desk._mem_card == null or not is_instance_valid(desk._mem_card):
		return
	desk._mem_card.finish_line()
	for i in maxi(0, n - 1):
		if not desk._mem_card.advance():
			break
		desk._mem_card.finish_line()


func _ensure_card(kind: String, id: String) -> void:
	var n := desk.graph.add_node(kind, id)
	desk.canvas._spawn_card(n.key)
	desk.canvas._relayout()
