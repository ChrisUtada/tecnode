extends SceneTree

const TEMP_PROGRESS := "user://test_p21_progress.json"
const TEMP_SAVE := "user://test_p21_case.save"

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
	print("=== P2.1 案件地图 / 停车 / 续档 / 角标 ===")
	_test_catalog()
	await _test_desktop()
	_cleanup()
	print("=== %d 项，失败 %d ===" % [total, fails])
	quit(0 if fails == 0 else 1)


func _file_text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _test_catalog() -> void:
	_cleanup()
	var c := CaseCatalog.new(TEMP_PROGRESS)
	check("案件表 2 条", CaseCatalog.all().size() == 2, str(CaseCatalog.all().size()))
	check("A001 数据 id = a001", CaseCatalog.data_id_of("A001") == "a001")
	check("A001 路径可加载", CaseCatalog.data_ready("A001"))
	check("A002 数据未接入", not CaseCatalog.data_ready("A002"))
	check("数据 id 反查 A002", CaseCatalog.case_id_for_data("a002") == "A002")
	check("默认只解锁 A001", c.unlocked == ["A001"], str(c.unlocked))
	check("默认最后案件 A001", c.last == "A001")
	check("默认无完成记录", c.completed.is_empty())
	check("A002 锁定文案", c.note_for("A002") == CaseCatalog.base_note_of("A002"))
	check("A001 已解密文案", c.note_for("A001").contains("已解密"), c.note_for("A001"))

	check("解锁 A002 成功", c.unlock("A002"))
	check("A002 解锁文案待接入", c.note_for("A002").contains("待接入"), c.note_for("A002"))
	check("重复解锁返回 false", not c.unlock("A002"))
	check("标记 A001 完成", c.mark_completed("A001"))
	check("重复完成返回 false", not c.mark_completed("A001"))
	c.last = "A002"
	check("进度写盘", c.save_progress())
	check("进度文件存在", FileAccess.file_exists(TEMP_PROGRESS))

	var r := CaseCatalog.new(TEMP_PROGRESS)
	check("读回解锁列表", r.unlocked.has("A001") and r.unlocked.has("A002"), str(r.unlocked))
	check("读回完成列表", r.is_completed("A001"))
	check("读回最后案件", r.last == "A002", r.last)
	check("有存档时 A001 文案", r.note_for("A001").contains("有存档") == FileAccess.file_exists(
		SaveSystem.save_path_for("a001")))

	_write_text(TEMP_PROGRESS, "[]")
	var bad := CaseCatalog.new(TEMP_PROGRESS)
	check("坏进度回退 A001", bad.unlocked == ["A001"] and bad.last == "A001", str(bad.unlocked))
	check("坏进度记录错误", bad.last_error != "")

	_write_text(TEMP_PROGRESS, JSON.stringify({
		"unlocked": ["A002", "NOPE"], "completed": ["A001", "NOPE"], "last": "NOPE"}))
	var sane := CaseCatalog.new(TEMP_PROGRESS)
	check("清洗未知解锁 id", sane.unlocked == ["A001", "A002"], str(sane.unlocked))
	check("清洗未知完成 id", sane.completed == ["A001"], str(sane.completed))
	check("清洗未知 last", sane.last == "A001", sane.last)

	sane.clear_progress(TEMP_PROGRESS)
	check("清进度后无文件", not FileAccess.file_exists(TEMP_PROGRESS))
	check("清进度后回默认", sane.unlocked == ["A001"] and sane.last == "A001")


func _test_desktop() -> void:
	_cleanup()
	var scene: Control = load("res://scenes/Desktop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.dbg_use_temp_progress(TEMP_PROGRESS)
	var info: Dictionary = scene.dbg_case_info()
	check("桌面当前案件 A001", info["id"] == "A001", str(info["id"]))
	check("桌面案件窗默认展开", bool(info["open"]))
	check("桌面无 dock", not bool(info["dock_visible"]))
	check("桌面无关闭角标", not bool(info["badge_visible"]))
	check("桌面标题含案件 A-001", String(info["title"]).contains("案件 A-001"), String(info["title"]))
	check("桌面进度为临时路径", info["progress_path"] == TEMP_PROGRESS)

	var map: CaseMapWin = scene.dbg_open_case_map()
	await process_frame
	check("案件地图可打开", map != null and map.visible)
	check("案件地图 2 行", map != null and map.dbg_row_count() == 2, str(map.dbg_row_count() if map != null else -1))
	check("A001 当前状态", scene.dbg_case_map_state("A001") == "当前", scene.dbg_case_map_state("A001"))
	check("A002 锁定状态", scene.dbg_case_map_state("A002") == "锁定", scene.dbg_case_map_state("A002"))
	check("当前案件不可重复进入", not scene.dbg_case_map_click("A001"))
	check("锁定案件不可点击", not scene.dbg_case_map_click("A002"))

	scene._save.path = TEMP_SAVE
	scene._save_enabled = true
	check("× 收起进案件图标", scene.dbg_park_case("icon"))
	await process_frame
	info = scene.dbg_case_info()
	check("收起后案件窗关闭", not bool(info["open"]))
	check("收起后图标角标显示", bool(info["badge_visible"]))
	check("收起后无 dock", not bool(info["dock_visible"]))
	check("收起时自动存档", FileAccess.file_exists(TEMP_SAVE) and _file_text(TEMP_SAVE) != "")
	check("案件窗隐藏", not scene._case_win.visible)
	scene._save_enabled = false

	scene.dbg_open_case_map()
	await process_frame
	check("收起后地图本案可进入", scene.dbg_case_map_state("A001") == "进入", scene.dbg_case_map_state("A001"))
	check("点击本案行重新展开", scene.dbg_case_map_click("A001"))
	await process_frame
	info = scene.dbg_case_info()
	check("重开后案件窗可见", bool(info["open"]) and scene._case_win.visible)
	check("重开后角标隐藏", not bool(info["badge_visible"]))
	check("重开后地图关闭", scene.dbg_case_map_win() == null)

	check("– 收进 dock", scene.dbg_park_case("dock"))
	await process_frame
	info = scene.dbg_case_info()
	check("dock 可见", bool(info["dock"]) and bool(info["dock_visible"]))
	check("U6 dock 卡片完整落在桌面内",
		scene._desk.get_global_rect().encloses(scene._dock_card.get_global_rect()),
		str(scene._dock_card.get_global_rect()))
	var desk_old: Vector2 = scene._desk.size
	scene._desk.size = Vector2(960.0, 508.0)
	scene._place_case_dock()
	check("U6 960×560 下 dock 仍在桌面内",
		scene._desk.get_global_rect().encloses(scene._dock_card.get_global_rect()),
		str(scene._dock_card.get_global_rect()))
	scene._desk.size = desk_old
	scene._place_case_dock()
	check("dock 模式无图标角标", not bool(info["badge_visible"]))
	check("dock 卡片有内容", scene._dock_title.text != "" and scene._dock_sub.text != "")
	scene.dbg_reopen_case()
	info = scene.dbg_case_info()
	check("点 dock 重新展开", bool(info["open"]) and not bool(info["dock_visible"]))

	scene.dbg_park_case("icon")
	await process_frame
	scene.dbg_open_case_map()
	await process_frame
	check("未解锁 A002 不可进入", not scene.dbg_enter_case("A002"))
	check("未解锁不切换案件", String(scene.dbg_case_info()["id"]) == "A001")
	check("解锁 A002", scene.dbg_catalog_unlock("A002"))
	check("地图 A002 待接入", scene.dbg_case_map_state("A002") == "待接入", scene.dbg_case_map_state("A002"))
	check("A002 无数据不可切换", not scene.dbg_enter_case("A002"))
	check("切换失败保持 A001", String(scene.dbg_case_info()["id"]) == "A001")
	check("进度已写入临时档", CaseCatalog.new(TEMP_PROGRESS).is_unlocked("A002"))
	check("重复解锁 A002 返回 false", not scene.dbg_catalog_unlock("A002"))
	check("A001 下一案已解锁", not scene.dbg_catalog_unlock_next("A001"))

	scene.dbg_use_temp_progress(TEMP_PROGRESS)
	scene.dbg_reopen_case()
	var true_e = scene.case_def.ending_by_id("TRUE_E")
	var assigned := true
	for clue in true_e.recipe:
		scene.dbg_ensure("clue", clue.id)
		if not scene.dbg_matrix_assign("clue:" + clue.id):
			assigned = false
	check("配方线索全部归位", assigned and (scene.dbg_state()["matrix_ids"] as Array).size() == 5,
		str(scene.dbg_state()["matrix_ids"]))
	scene.dbg_open_matrix()
	scene.dbg_matrix_charge()
	await process_frame
	info = scene.dbg_case_info()
	check("真名结局标记完成", (info["completed"] as Array).has("A001"), str(info["completed"]))
	check("真名结局解锁 A002", (info["unlocked"] as Array).has("A002"), str(info["unlocked"]))
	check("解锁进度已落盘", CaseCatalog.new(TEMP_PROGRESS).is_unlocked("A002"))
	scene.dbg_ending_finish()

	scene.dbg_use_temp_progress(TEMP_PROGRESS)
	scene._sync_case_progress_from_graph()
	info = scene.dbg_case_info()
	check("旧存档补记完成", (info["completed"] as Array).has("A001"), str(info["completed"]))
	check("旧存档补解锁 A002", (info["unlocked"] as Array).has("A002"), str(info["unlocked"]))

	scene.queue_free()
	await process_frame


func _cleanup() -> void:
	for path in [TEMP_PROGRESS, TEMP_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
