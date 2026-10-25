extends SceneTree
## P1.5 回归：快照 / 撤销栈 / 案件存档
##
## 覆盖：
##   1) 快照字段：节点位置 / 点亮 / 钉住 / 零件 / 收纳去向 / 边 / 探索 / 捕获 / TEC / 折叠 / 五感 / 结局
##   2) 原地恢复：同一个 GraphState 引用继续有效，hidden 重算
##   3) 撤销栈：最多 60 步，后进先出
##   4) JSON 往返与磁盘存档：user://tec_case_<id>.save 同构
##   5) 桌面接线：撤销按钮 / 自动存档点 / 读档后重建卡片
##
## 运行：godot --headless --path ydgodot --script res://tests/headless/test_p15.gd

var fails := 0
var total := 0
var c: CaseLoader


func check(name: String, cond: bool, detail: String = "") -> void:
	total += 1
	if cond:
		print("  PASS  ", name)
	else:
		fails += 1
		print("  FAIL  ", name, ("  [" + detail + "]") if detail != "" else "")


func _initialize() -> void:
	print("=== P1.5 快照 / 撤销 / 存档 ===")
	c = CaseLoader.new()
	check("装载案件", c.load_case(), c.load_error)

	_test_snapshot_roundtrip()
	_test_restore_in_place()
	_test_history()
	_test_undo_knowledge()
	_test_json_and_disk()
	await _test_desktop()
	_cleanup()

	print("=== %d 项，失败 %d ===" % [total, fails])
	quit(0 if fails == 0 else 1)


func _populate(g: GraphState) -> void:
	g.reveal_scene("SCENES_garden")
	g.reveal_container("item", "ITEM_shuzhuo")
	var torch := g.key_of("item", "ITEM_shoudiantong")
	g.add_node("item", "ITEM_shoudiantong")
	g.node(torch)["lit"] = true
	g.node(torch)["pinned"] = true
	g.node(torch)["x"] = 123.5
	g.node(torch)["y"] = 67.25
	g.node(g.key_of("item", "ITEM_shuzhuo"))["installed"]["ITEMS_cz"] = true
	g.capture_clue("CLUES_nm", g.key_of("loc", "SCENES_garden"))
	g.matrix_assign(g.key_of("clue", "CLUES_nm"))
	g.bag_store(g.key_of("item", "ITEM_taideng"))
	g.tec_prog["SCENES_garden"] = 2
	g.collapse("ITEM_shuzhuo")
	g.mark_ending("TRUE_E")
	g.last_scene = "SCENES_garden"
	g.tried["item:ITEM_shoudiantong>item:ITEM_something"] = true
	g.talk_prog["CHARS_LX"] = 2
	g.card_seen["SCENES_garden"] = true
	g.debuted["CHARS_TEC"] = true
	g.time = "MEM_x"
	g.garden = {"seed": true, "plots": [{"at": 123, "hit": true}]}
	g.notes["CHARS_zs"] = "旧笔记：朱穗在隐瞒什么。"


# ── 1. 快照 → 恢复：字段一字不差 ───────────────────────────────────────
func _test_snapshot_roundtrip() -> void:
	var g := GraphState.new(c)
	_populate(g)
	var ss := SaveSystem.new(g, "a001")
	var snap := ss.snapshot()
	check("快照：带格式号", int(snap.get("format", 0)) == SaveSystem.FORMAT)
	check("快照：节点全在", (snap["nodes"] as Dictionary).size() == g.nodes.size())
	check("快照：边全在", (snap["edges"] as Array).size() == g.edges.size())
	check("快照：探索 / 捕获 / 折叠 / 结局 / 五感字段都在",
		snap.has("explored") and snap.has("captured") and snap.has("collapsed")
		and snap.has("endings") and snap.has("matrix") and snap.has("tecProg"))
	var torch_key := g.key_of("item", "ITEM_shoudiantong")
	var torch_snap: Dictionary = snap["nodes"][torch_key]
	var bagged_snap: Dictionary = snap["nodes"][g.key_of("item", "ITEM_taideng")]
	var desk_snap: Dictionary = snap["nodes"][g.key_of("item", "ITEM_shuzhuo")]
	check("快照：位置带小数", is_equal_approx(float(torch_snap["x"]), 123.5))
	check("快照：点亮 / 钉住", bool(torch_snap["lit"]) and bool(torch_snap["pinned"]))
	check("快照：收纳去向而不是 stored 布尔", String(bagged_snap["storedIn"]) == GraphState.BAG)
	check("快照：零件记账", bool(desk_snap["installed"].get("ITEMS_cz", false)))
	check("快照：五感槽位", (snap["matrix"]["hearing"] as Array).has("CLUES_nm"))
	check("快照：TEC 进度", int(snap["tecProg"]["SCENES_garden"]) == 2)
	check("快照：tried / talkProg / cardSeen / debuted",
		(snap["tried"] as Array).has("item:ITEM_shoudiantong>item:ITEM_something")
		and int(snap["talkProg"]["CHARS_LX"]) == 2
		and bool(snap["cardSeen"]["SCENES_garden"])
		and bool(snap["debuted"]["CHARS_TEC"]))
	check("快照：time / garden", String(snap["time"]) == "MEM_x"
		and bool(snap["garden"]["seed"]) and int(snap["garden"]["plots"][0]["at"]) == 123)
	check("快照：人物备注", String((snap["notes"] as Dictionary).get("CHARS_zs", "")) == "旧笔记：朱穗在隐瞒什么。")

	var json_before := JSON.stringify(snap)
	var g2 := GraphState.new(c)
	var ss2 := SaveSystem.new(g2, "a001")
	check("恢复：返回成功", ss2.restore(snap))
	check("恢复：节点数一致", g2.nodes.size() == g.nodes.size())
	check("恢复：边数一致", g2.edges.size() == g.edges.size())
	check("恢复：探索记录一致", g2.explored.size() == g.explored.size())
	check("恢复：捕获记录一致", g2.captured.size() == g.captured.size())
	check("恢复：TEC 进度一致", int(g2.tec_prog["SCENES_garden"]) == 2)
	check("恢复：折叠状态一致", g2.collapsed.has("ITEM_shuzhuo"))
	check("恢复：五感槽位一致", (g2.matrix["hearing"] as Array).has("CLUES_nm"))
	check("恢复：收纳去向一致", String(g2.stored.get(g2.key_of("item", "ITEM_taideng"), "")) == GraphState.BAG)
	check("恢复：位置一致", is_equal_approx(float(g2.node(torch_key)["x"]), 123.5))
	check("恢复：点亮 / 钉住一致", bool(g2.node(torch_key)["lit"]) and bool(g2.node(torch_key)["pinned"]))
	check("恢复：零件一致", bool(g2.node(g2.key_of("item", "ITEM_shuzhuo"))["installed"].get("ITEMS_cz", false)))
	check("恢复：结局一致", g2.endings.has("TRUE_E"))
	check("恢复：lastScene 一致", g2.last_scene == "SCENES_garden")
	check("恢复：tried / talkProg", g2.tried.has("item:ITEM_shoudiantong>item:ITEM_something")
		and int(g2.talk_prog.get("CHARS_LX", 0)) == 2)
	check("恢复：cardSeen / debuted", bool(g2.card_seen.get("SCENES_garden", false))
		and bool(g2.debuted.get("CHARS_TEC", false)))
	check("恢复：time / garden", g2.time == "MEM_x" and bool(g2.garden.get("seed", false))
		and int((g2.garden["plots"] as Array)[0]["at"]) == 123)
	check("恢复：人物备注", String(g2.notes.get("CHARS_zs", "")) == "旧笔记：朱穗在隐瞒什么。")
	check("恢复：快照 JSON 可重复", JSON.stringify(ss2.snapshot()) == json_before)


# ── 2. 原地恢复：外部 graph / 命令系统引用不失效 ───────────────────────
func _test_restore_in_place() -> void:
	var g := GraphState.new(c)
	var cs := CommandSystem.new(c, g)
	_populate(g)
	var ss := SaveSystem.new(g, "a001")
	var snap := ss.snapshot()
	g.capture_clue("CLUES_mc")
	check("恢复前：状态已变", g.captured.has("CLUES_mc"))
	check("原地恢复成功", ss.restore(snap))
	check("原地恢复：同一 graph 引用", cs.graph == g)
	check("原地恢复：新增证据被撤掉", not g.captured.has("CLUES_mc"))
	check("原地恢复：命令系统仍能执行", not cs.execute(g.key_of("item", "ITEM_taideng"), null)["ok"])
	check("原地恢复：hidden 已重算",
		g.is_visible(g.key_of("item", "ITEM_shuzhuo"))
		and not g.is_visible(g.key_of("item", "ITEM_taideng")))


# ── 3. 撤销栈：LIFO / 上限 60 ─────────────────────────────────────────────
func _test_history() -> void:
	var g := GraphState.new(c)
	var ss := SaveSystem.new(g, "a001")
	g.reveal_scene("SCENES_garden")
	var before := ss.snapshot()
	ss.push_history(before)
	g.capture_clue("CLUES_nm")
	check("撤销：栈里有 1 步", ss.can_undo() and ss.history.size() == 1)
	check("撤销：执行成功", ss.undo())
	check("撤销：回到捕获前", not g.captured.has("CLUES_nm"))
	check("撤销：栈清空", not ss.can_undo())
	check("撤销：空栈返回 false", not ss.undo())

	for i in 65:
		ss.push_history({"step": i})
	check("撤销：最多保留 60 步", ss.history.size() == SaveSystem.HISTORY_MAX, str(ss.history.size()))
	check("撤销：挤掉最老的一步", int(ss.history[0]["step"]) == 5)
	ss.clear_history()
	check("撤销：清空历史", not ss.can_undo())


# ── 3b. S8：撤销不把玩家知识退回快照 ───────────────────────────────────
func _test_undo_knowledge() -> void:
	var g := GraphState.new(c)
	g.reveal_scene("SCENES_garden")
	var key := g.scene_key("SCENES_garden")
	g.node(key)["unread"] = true
	g.card_seen["SCENES_0602"] = true
	g.debuted["NPC_FB"] = true
	g.notes["CHARS_luhengs"] = "旧备注"
	var ss := SaveSystem.new(g, "a001")
	var before := ss.snapshot()

	# 玩家在快照之后：点掉新角标、认识新人物，同时给撤销一点图结构可回滚。
	g.node(key)["unread"] = false
	g.card_seen["SCENES_0602"] = false
	g.card_seen["SCENES_0704"] = true
	g.debuted["NPC_FB"] = false
	g.debuted["CHARS_zs"] = true
	g.notes["CHARS_luhengs"] = "新备注：玩家刚写的"
	g.add_node("item", "ITEMS_bd")
	ss.push_history_snapshot(before)
	check("S8 撤销成功", ss.undo())
	check("S8 撤销保留「已读」：unread 不被快照复活",
		not bool(g.node(key).get("unread", true)))
	check("S8 撤销保留 cardSeen 当前值（true 与 false）",
		not bool(g.card_seen.get("SCENES_0602", true))
			and bool(g.card_seen.get("SCENES_0704", false)),
		str(g.card_seen))
	check("S8 撤销保留 debuted 当前值（true 与 false）",
		not bool(g.debuted.get("NPC_FB", true))
			and bool(g.debuted.get("CHARS_zs", false)),
		str(g.debuted))
	check("S8 图结构仍按快照回滚", not g.has("item", "ITEMS_bd"))
	check("S8 撤销不回滚人物备注",
		String(g.notes.get("CHARS_luhengs", "")) == "新备注：玩家刚写的",
		String(g.notes.get("CHARS_luhengs", "")))

	# 普通读档（非撤销）不能把当前知识并进旧档。
	var g2 := GraphState.new(c)
	g2.card_seen["SCENES_extra"] = true
	g2.debuted["CHARS_extra"] = true
	var ss2 := SaveSystem.new(g2, "a001")
	check("S8 读档恢复成功", ss2.restore(before))
	check("S8 读档按存档知识：不保留当前额外的 cardSeen/debuted",
		not g2.card_seen.has("SCENES_extra") and not g2.debuted.has("CHARS_extra"),
		str(g2.card_seen) + " / " + str(g2.debuted))
	check("S8 读档恢复存档里的 unread", bool(g2.node(key).get("unread", false)))
	check("S8 读档按存档恢复备注",
		String(g2.notes.get("CHARS_luhengs", "")) == "旧备注",
		String(g2.notes.get("CHARS_luhengs", "")))


# ── 4. JSON / 磁盘存档往返 ──────────────────────────────────────────────
func _test_json_and_disk() -> void:
	var g := GraphState.new(c)
	_populate(g)
	var ss := SaveSystem.new(g, "a001", "user://test_p15_roundtrip.save")
	var text := ss.snapshot_json()
	var g2 := GraphState.new(c)
	var ss2 := SaveSystem.new(g2, "a001")
	check("JSON：恢复成功", ss2.restore_json(text))
	check("JSON：节点回来", g2.nodes.size() == g.nodes.size())
	check("JSON：五感回来", (g2.matrix["hearing"] as Array).has("CLUES_nm"))
	check("JSON：非对象存档被拒", not ss2.restore_json("[]"))
	check("JSON：坏存档不破坏当前图", g2.nodes.size() == g.nodes.size())

	var p := "user://test_p15_save.save"
	ss.clear_save(p)
	check("存档：初始不存在", not ss.has_save(p))
	check("存档：写盘成功", ss.save_to_disk(p))
	check("存档：文件存在", ss.has_save(p))
	g.capture_clue("CLUES_mc")
	check("存档：读盘成功", ss.load_from_disk(p))
	check("存档：读回旧状态", not g.captured.has("CLUES_mc"))
	check("存档：读盘恢复人物备注",
		String(g.notes.get("CHARS_zs", "")) == "旧笔记：朱穗在隐瞒什么。",
		String(g.notes.get("CHARS_zs", "")))
	check("存档：读档清空撤销栈", not ss.can_undo())
	check("存档：坏文件读失败", not ss.load_from_disk("user://test_p15_missing.save"))
	# F4：自动写盘复用 _commit 已算好的 JSON，不再 snapshot/stringify 第三遍。
	ss.dbg_snapshot_calls = 0
	ss.dbg_json_calls = 0
	var f4_json := ss.snapshot_json()
	ss.last_json = f4_json
	ss.pending_json = f4_json
	check("F4 自动写盘复用待写 JSON", ss.flush_pending(p))
	check("F4 一次提交只快照/序列化一次",
		ss.dbg_snapshot_calls == 1 and ss.dbg_json_calls == 1,
		"%d/%d" % [ss.dbg_snapshot_calls, ss.dbg_json_calls])
	ss.clear_save(p)
	check("存档：删除成功", not ss.has_save(p))


# ── 5. 桌面：撤销按钮 / 自动记录 / 读档重建 ────────────────────────────
func _test_desktop() -> void:
	var scene: Control = load("res://scenes/Desktop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var temp := "user://test_p15_desktop.save"
	scene.dbg_use_temp_save(temp)
	check("桌面：开局没有撤销步", scene.dbg_history_size() == 0)
	check("桌面：没有可撤销", not bool(scene.dbg_state()["can_undo"]))
	var undo_btn := scene.get_node("header/btn_撤销") as Button
	check("K8 空栈时撤销按钮禁用", undo_btn != null and undo_btn.disabled)

	# 开局不再凭空给手电筒（对齐 Web `17-boot.js`：画布上只有一张起始场景卡），
	# 这一节只验撤销栈，工具自己造一把摆上桌
	scene.dbg_ensure("item", "ITEM_shoudiantong")
	await process_frame

	scene.dbg_activate("item:ITEM_shoudiantong")
	await process_frame
	check("桌面：开关灯进了撤销栈", scene.dbg_history_size() == 1)
	check("K8 有历史时撤销按钮可用", undo_btn != null and not undo_btn.disabled)
	check("桌面：灯亮了", bool(scene.dbg_state()["lit"].get("ITEM_shoudiantong", false)))
	check("桌面：撤销一步", scene.dbg_undo())
	await process_frame
	await process_frame
	check("桌面：灯回到熄灭", not bool(scene.dbg_state()["lit"].get("ITEM_shoudiantong", true)))
	check("桌面：撤销栈空了", scene.dbg_history_size() == 0)
	check("K8 撤销后按钮重新禁用", undo_btn != null and undo_btn.disabled)

	scene.dbg_activate("loc:SCENES_garden")
	await process_frame
	check("桌面：展开场景进撤销栈", scene.dbg_history_size() == 1)
	check("桌面：场景已探索", (scene.dbg_state()["explored"] as Array).has("SCENES_garden"))
	check("桌面：撤销展开", scene.dbg_undo())
	await process_frame
	await process_frame
	check("桌面：场景回到未探索", not (scene.dbg_state()["explored"] as Array).has("SCENES_garden"))
	check("桌面：撤销后卡片重建", _cards(scene).has("item:ITEM_shoudiantong"))

	scene.dbg_ensure("item", "ITEM_taideng")
	await process_frame
	scene.dbg_select("item:ITEM_taideng")
	check("桌面：收进证物袋", scene.dbg_store("BAG"))
	check("桌面：收纳进撤销栈", scene.dbg_history_size() == 1)
	scene.dbg_open_storage(GraphState.BAG)
	await process_frame
	var bag: StorageWin = scene.get_node_or_null("desk/bag_win") as StorageWin
	check("桌面：袋窗打开", bag != null)
	bag._take("item:ITEM_taideng")
	await process_frame
	check("桌面：取出成功", not (scene.dbg_state()["stored"] as Array).has("item:ITEM_taideng"))
	check("桌面：取回也进撤销栈", scene.dbg_history_size() == 2)
	check("桌面：撤销取回", scene.dbg_undo())
	await process_frame
	await process_frame
	check("桌面：物品回到袋里", (scene.dbg_state()["stored"] as Array).has("item:ITEM_taideng"))

	scene.dbg_use_temp_save(temp)
	check("桌面：写临时存档", scene.dbg_save())
	check("桌面：存档路径正确", scene.dbg_save_path() == temp)
	scene.dbg_activate("item:ITEM_shoudiantong")
	await process_frame
	check("桌面：读档前灯是亮的", bool(scene.dbg_state()["lit"].get("ITEM_shoudiantong", false)))
	check("桌面：读档成功", scene.dbg_load())
	await process_frame
	await process_frame
	check("桌面：读档恢复灯状态", not bool(scene.dbg_state()["lit"].get("ITEM_shoudiantong", true)))
	check("桌面：读档清空撤销栈", scene.dbg_history_size() == 0)
	check("K8 读档后撤销按钮禁用", undo_btn != null and undo_btn.disabled)
	check("桌面：读档后卡片重建", _cards(scene).has("item:ITEM_taideng"))
	scene.dbg_clear_save()
	check("桌面：临时存档已删", not FileAccess.file_exists(temp))
	scene.queue_free()
	await process_frame


func _cards(scene: Control) -> Dictionary:
	var out := {}
	var layer: Node = scene.get_node("desk/case_win/body/stage/cards")
	for child in layer.get_children():
		if child is NodeCard:
			out[(child as NodeCard).card_key] = child
	return out


func _cleanup() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_p15_save.save"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_p15_desktop.save"))
