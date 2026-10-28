extends "res://tests/headless/_test_base.gd"

const TEMP_INV := "user://test_p16_investigator.json"
const TEMP_INV_DESK := "user://test_p16_desktop_investigator.json"

func _initialize() -> void:
	print("=== P1.6 开场适性测试 / 调查员证 ===")
	_test_sense()
	_test_card()
	_test_store()
	await _test_intro_ui()
	await _test_desktop()
	_cleanup()
	_finish()


func _test_sense() -> void:
	check("三问（2 视觉 1 听觉）→ 视觉", Investigator.pick_sense(["vision", "vision", "hearing"]) == "vision")
	check("平局取先达到的", Investigator.pick_sense(["hearing", "vision", "touch"]) == "hearing")
	check("空答案回退视觉", Investigator.pick_sense([]) == "vision")
	check("五感名称齐全", Investigator.SENSE_NAMES.size() == 5)
	check("五感描述齐全", Investigator.SENSE_FLAVOR.size() == 5)
	check("题库 3 问", Investigator.QUIZ.size() == 3)
	var all_five := true
	for q in Investigator.QUIZ:
		if (q["opts"] as Array).size() != 5:
			all_five = false
	check("每题 5 个选项", all_five)


func _test_card() -> void:
	var re := RegEx.new()
	re.compile("^TEC-[A-Z]{2}-[0-9]{4}$")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261020
	var id := Investigator.gen_id(rng)
	check("编号格式 TEC-XX-0000", re.search(id) != null, id)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 20261020
	check("同种子编号可复现", Investigator.gen_id(rng2) == id)
	var card := Investigator.make_card("  林雾  ", ["smell", "smell", "taste"], "CHARS_TEC",
		"2026-10-20", rng)
	check("姓名去空格", card["name"] == "林雾", String(card["name"]))
	check("倾向取多数", card["sense"] == "smell")
	check("头像记录", card["avatarId"] == "CHARS_TEC")
	check("签发日期", card["date"] == "2026-10-20")
	check("编号已生成", re.search(String(card["id"])) != null, String(card["id"]))
	var dflt := Investigator.make_card("执行者", ["vision"], "", "2026-10-20", rng)
	check("空头像回退执行者", dflt["avatarId"] == "CHARS_EXEC")


func _test_store() -> void:
	Investigator.clear(TEMP_INV)
	check("初始无存档", Investigator.load_from(TEMP_INV).is_empty())
	check("空证不写盘", not Investigator.save_to({}, TEMP_INV))
	var card := Investigator.make_card("陆珩松", ["touch", "touch", "vision"], "CHARS_EXEC", "2026-10-20")
	check("写盘成功", Investigator.save_to(card, TEMP_INV))
	var back := Investigator.load_from(TEMP_INV)
	check("读回姓名", back.get("name", "") == "陆珩松")
	check("读回编号", back.get("id", "") == card["id"])
	check("读回倾向", back.get("sense", "") == "touch")
	check("读回头像", back.get("avatarId", "") == "CHARS_EXEC")
	check("读回日期", back.get("date", "") == "2026-10-20")
	var f := FileAccess.open(TEMP_INV, FileAccess.WRITE)
	f.store_string("[]")
	f.close()
	check("坏存档视为无证", Investigator.load_from(TEMP_INV).is_empty())
	Investigator.clear(TEMP_INV)
	check("删除成功", not FileAccess.file_exists(TEMP_INV))


func _test_intro_ui() -> void:
	Investigator.clear(TEMP_INV)
	var w := IntroWin.new()
	w.store_path = TEMP_INV
	w.setup(Investigator.AVATAR_INITIAL, {"CHARS_EXEC": "执行者", "CHARS_TEC": "TEC"}, 4)
	root.add_child(w)
	await process_frame
	check("开场停在第 0 步：姓名", w.dbg_step() == "name", str(w.dbg_step()))
	check("标题是适性测试", w.dbg_title() == "调查员适性测试", w.dbg_title())
	check("A4 开场浮层有 3px 硬影", w._panel_shadow != null and w._panel_shadow.visible)
	if w._panel_shadow != null:
		check("A4 开场影偏移 = OFFSET_SHADOW",
			w._panel_shadow.position.is_equal_approx(w._panel.position + SysWindow.OFFSET_SHADOW),
			str(w._panel_shadow.position))
		check("A4 开场影尺寸 = 面板", w._panel_shadow.size.is_equal_approx(w._panel.size),
			str(w._panel_shadow.size))
		check("A4 开场影在面板之下", w._panel_shadow.get_index() < w._panel.get_index())
	# A3：弹窗按视口居中，不再写死 1280。
	w.size = Vector2(960, 560)
	w._fit()
	var panel := w.find_child("panel", true, false) as Control
	check("A3 960 宽开场弹窗居中",
		panel != null and absf(panel.position.x + panel.size.x * 0.5 - 480.0) < 1.0,
		str(panel.position) if panel != null else "null")
	w.size = Vector2(1280, 720)
	w._fit()
	w.dbg_begin()
	check("空姓名不进入问答", w.dbg_step() == "name")
	w.dbg_set_name("林雾")
	w.dbg_begin()
	check("姓名后进入第 1 问", w.dbg_step() == 0, str(w.dbg_step()))
	check("第 1 问有 5 个选项", w.dbg_option_count() == 5, str(w.dbg_option_count()))
	w.dbg_answer(0)
	w.dbg_answer(0)
	w.dbg_answer(2)
	check("答完进入选头像", w.dbg_step() == "avatar", str(w.dbg_step()))
	check("标题切到选择头像", w.dbg_title() == "选择头像", w.dbg_title())
	check("证件倾向 = 视觉", w.dbg_card().get("sense", "") == "vision")
	w.dbg_pick("CHARS_TEC")
	check("选头像记录", w.dbg_card().get("avatarId", "") == "CHARS_TEC")
	w.dbg_confirm_pick()
	check("进入领证页", w.dbg_step() == "card", str(w.dbg_step()))
	check("标题切到调查员证", w.dbg_title() == "调查员证", w.dbg_title())
	var cert := w.find_child("cert", true, false)
	check("证件版式已生成", cert != null)
	# G8：写盘失败必须留在领证页，不能假装成功关闭。
	w.store_path = "user://"
	w.dbg_confirm()
	check("G8 写盘失败留在领证页", w.dbg_step() == "card", str(w.dbg_step()))
	var intro_err := w.find_child("intro_error", true, false) as Label
	check("G8 写盘失败给出提示", intro_err != null and intro_err.visible and intro_err.text != "")
	w.store_path = TEMP_INV
	var got := {"card": {}}
	w.finished.connect(func(card: Dictionary): got["card"] = card)
	w.dbg_confirm()
	check("确认领证发出信号", not (got["card"] as Dictionary).is_empty())
	check("信号里带姓名", String((got["card"] as Dictionary).get("name", "")) == "林雾")
	check("调查员证写盘", FileAccess.file_exists(TEMP_INV))
	var saved := Investigator.load_from(TEMP_INV)
	check("写盘姓名一致", saved.get("name", "") == "林雾")
	check("写盘倾向一致", saved.get("sense", "") == "vision")
	check("写盘头像一致", saved.get("avatarId", "") == "CHARS_TEC")
	await create_timer(0.5).timeout
	check("领证后窗口收场", not is_instance_valid(w))
	Investigator.clear(TEMP_INV)


func _test_desktop() -> void:
	Investigator.clear(TEMP_INV_DESK)
	var scene: Control = load("res://scenes/Desktop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	check("无头模式不自动弹开场", not scene.debug.dbg_intro_open())
	scene.debug.dbg_use_temp_investigator(TEMP_INV_DESK)
	check("临时调查员路径为空", scene.debug.dbg_investigator().is_empty())
	var chip: Button = scene.get_node_or_null("header/inv_chip") as Button
	check("页眉证件位存在", chip != null)
	check("无证时不显示证章", chip == null or not chip.visible)
	var intro: IntroWin = scene.debug.dbg_open_intro()
	await process_frame
	check("可以手动打开开场", scene.debug.dbg_intro_open())
	check("开场仍停在第 0 步", intro.dbg_step() == "name", str(intro.dbg_step()))
	intro.dbg_set_name("执行者")
	intro.dbg_begin()
	intro.dbg_answer(1)
	intro.dbg_answer(1)
	intro.dbg_answer(1)
	check("答题结果 = 听觉", intro.dbg_card().get("sense", "") == "hearing")
	intro.dbg_confirm_pick()
	intro.dbg_confirm()
	await create_timer(0.5).timeout
	check("领证后开场关闭", not scene.debug.dbg_intro_open())
	var inv: Dictionary = scene.debug.dbg_investigator()
	check("桌面记住调查员", String(inv.get("name", "")) == "执行者")
	check("调查员证持久化", FileAccess.file_exists(TEMP_INV_DESK))
	check("页眉证章出现", chip != null and chip.visible)
	check("页眉证章带编号", chip != null and String(chip.text).contains(String(inv.get("id", ""))))
	scene.debug.dbg_open_cert()
	await process_frame
	check("可回看调查员证", scene.debug.dbg_cert_open())
	scene._view_user = true
	scene._view_k = 1.8
	scene._view_pos = Vector2(-4000.0, -4000.0)
	scene.canvas._apply_view()
	scene.debug.dbg_reset_case()
	await process_frame
	check("重置先弹确认", scene._confirm_win != null and scene._confirm_win.visible)
	if scene._confirm_win != null:
		scene._confirm_win.dbg_cancel()
	await process_frame
	check("取消后确认窗关闭", scene._confirm_win == null)
	scene.debug.dbg_reset_case(true)
	await process_frame
	await process_frame
	check("S1 重置后镜头回到自动档", not scene._view_user)
	var start_slice_key := "loc:SCENES_garden"
	check("S1 重置后起始节点在可视区",
		scene._cards.has(start_slice_key)
			and scene._stage.get_global_rect().intersects(
				(scene._cards[start_slice_key] as NodeCard).get_global_rect()))
	check("重来不清调查员", String(scene.debug.dbg_investigator().get("name", "")) == "执行者")
	scene.debug.dbg_clear_investigator()
	check("清证后内存为空", scene.debug.dbg_investigator().is_empty())
	check("清证后文件删除", not FileAccess.file_exists(TEMP_INV_DESK))
	check("清证后证章隐藏", chip == null or not chip.visible)
	scene.queue_free()
	await process_frame


func _cleanup() -> void:
	Investigator.clear(TEMP_INV)
	Investigator.clear(TEMP_INV_DESK)
