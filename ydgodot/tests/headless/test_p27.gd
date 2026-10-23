extends SceneTree
## 批 2 交互四项回归：N5 线索双击捕获 / V1 选中环 / V2 点亮 / V3 已捕获 / C4 场景通路。
## 运行：godot --headless --path ydgodot --script res://tests/headless/test_p27.gd
##
## 这一套守的是「代码早已落地、文档却写着没做」的那四项（差距报告 §1.1 N5 / §1.5 V1-V3 / §1.6 C4）。
## 断言刻意走界面入口（真鼠标事件 / `_on_card_combo`），而不是直接调 GraphState：
## 只有这样才证明「玩家点得到、且落到了正确数据」。

var fails := 0
var total := 0
var scene: Control


func check(name: String, cond: bool, detail: String = "") -> void:
	total += 1
	if cond:
		print("  PASS  ", name)
	else:
		fails += 1
		print("  FAIL  ", name, ("  [" + detail + "]") if detail != "" else "")


func _initialize() -> void:
	print("=== 批 2 交互四项（N5 / V1 / V2 / V3 / C4）===")
	scene = load("res://scenes/Desktop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	# 相机钉在 1x 原生格：后面所有点击都按「世界 → 屏幕」1:1 换算。
	scene._view_k = 1.0
	scene._view_pos = Vector2.ZERO
	scene._view_user = true
	scene._apply_view()

	scene.dbg_expand("SCENES_garden")
	await process_frame
	await process_frame

	var toast: Control = scene.get_node_or_null("desk/toast")
	check("前提：toast 节点在", toast != null)

	# ── N5 + V3：双击线索 = 捕获，卡面翻成深色反白 ──────────────────
	var ck: String = scene.dbg_ensure("clue", "CLUES_nm")
	await process_frame
	var clue: NodeCard = _cards().get(ck)
	check("前提：线索卡在画布上", clue != null, ck)
	if clue == null:
		print("=== %d 项，失败 %d ===" % [total, fails])
		quit(1)
		return

	check("前提：还没捕获",
		not (scene.dbg_state()["captured"] as Array).has("CLUES_nm"),
		str(scene.dbg_state()["captured"]))
	check("捕获前：普通外观（plain）", clue.look_state() == "plain", clue.look_state())

	_double_click(clue)
	await process_frame
	await process_frame
	clue = _cards().get(ck)
	check("双击线索：进 graph.captured",
		(scene.dbg_state()["captured"] as Array).has("CLUES_nm"),
		str(scene.dbg_state()["captured"]))
	check("V3：卡面翻成 got", clue.look_state() == "got", clue.look_state())
	var col_hi: Color = clue._mat.get_shader_parameter("col_hi")
	var col_lo: Color = clue._mat.get_shader_parameter("col_lo")
	# 1-bit：反白面是**纯黑**，不再是 #333→#1a1a 的渐变（那在 1-bit 里是三个不同的灰）
	check("V3：反白上缘 = 纯黑", col_hi.is_equal_approx(TecTheme.INK), str(col_hi))
	check("V3：反白下缘 = 纯黑（上下同色，无渐变）", col_lo.is_equal_approx(TecTheme.INK), str(col_lo))
	check("V3：深底上不留虚线框（反白自带边界）", not clue._border.visible)
	check("N5：案卷记一条捕获", _log_has("已捕获线索"))
	check("N5：捕获不弹提示条（Web 刻意）", toast != null and not toast.visible)

	_double_click(clue)
	await process_frame
	check("重复双击：不重复记 captured",
		(scene.dbg_state()["captured"] as Array).count("CLUES_nm") == 1,
		str(scene.dbg_state()["captured"]))
	check("重复双击：案卷留一条「已经捕获过了」", _log_has("已经捕获过了"))
	check("重复双击：仍不弹提示条", toast != null and not toast.visible)

	# ── V1：选中环（单击 = 选中，换选 = 旧的收环）───────────────────
	_single_click(clue)
	await process_frame
	check("V1：单击线索出现选中环", clue.is_selected() and clue._sel.visible)
	var other: NodeCard = _first_card_except(ck)
	check("前提：画布上还有别的卡可换选", other != null)
	if other != null:
		_single_click(other)
		await process_frame
		check("V1：换选后新卡带环", other.is_selected() and other._sel.visible)
		check("V1：换选后旧卡收环", not clue.is_selected() and not clue._sel.visible)

	# ── V2：双击物品 = 点亮，金框 + 暖白底 + 光晕 ────────────────────
	var tk: String = scene.dbg_ensure("item", "ITEM_shoudiantong")
	await process_frame
	var torch: NodeCard = _cards().get(tk)
	check("前提：手电筒卡在画布上", torch != null, tk)
	if torch != null:
		check("点亮前：普通外观", torch.look_state() == "plain", torch.look_state())
		_double_click(torch)
		await process_frame
		await process_frame
		torch = _cards().get(tk)
		check("双击手电筒：数据层点亮",
			bool(scene.dbg_state()["lit"].get("ITEM_shoudiantong", false)))
		check("V2：外观态 = lit", torch.look_state() == "lit", torch.look_state())
		var edge: Color = torch._mat.get_shader_parameter("edge_col")
		var mid: Color = torch._mat.get_shader_parameter("col_mid")
		# 1-bit 的点亮 = **白底 + 2px 黑粗框**。金色对白只有 1.86:1，本来就画不出轮廓。
		check("V2：卡面仍是白（强调交给线，不交给色块）",
			mid.is_equal_approx(TecTheme.CARD), str(mid))
		check("V2：点亮走 2px 粗框（thick_line）",
			torch._border.visible and torch._border.thick_line)
		check("V2：不再有发光（光晕贴图关闭）",
			torch._glow == null or not torch._glow.visible)

		_double_click(torch)
		await process_frame
		await process_frame
		torch = _cards().get(tk)
		check("再双击：熄灭回普通外观", torch.look_state() == "plain", torch.look_state())
		check("熄灭：光晕收起", torch._glow == null or not torch._glow.visible)

	# ── C4：场景通路（数据层）─────────────────────────────────────
	# 数据里的真实通路：书桌正文「返回 [loc:SCENES_garden]」、尸体正文「返回 [loc:SCENES_garden]」。
	# 无通路的样本：0602（只有 [loc:SCENES_fkjl]）⇄ 尸体（只有 [loc:SCENES_garden]）。
	# ⚠ 0602 是**时间类场景**，节点 key 是 `time:SCENES_0602` —— 用 dbg_ensure 的返回值，别手写前缀。
	var k0602: String = scene.dbg_ensure("loc", "SCENES_0602")
	var kbody: String = scene.dbg_ensure("loc", "SCENES_body")
	var kfkjl: String = scene.dbg_ensure("loc", "SCENES_fkjl")
	await process_frame
	check("前提：0602 落成时间类节点（time: 前缀）", k0602 == "time:SCENES_0602", k0602)

	var t1: Dictionary = scene.dbg_combo("ITEM_shuzhuo", "SCENES_garden")
	check("C4：书桌正文 [loc:garden] ⇒ 前往花园",
		String(t1.get("travel", "")) == "SCENES_garden", str(t1))
	var t2: Dictionary = scene.dbg_combo("SCENES_body", "SCENES_garden")
	check("C4：尸体正文 [loc:garden] ⇒ 前往花园",
		String(t2.get("travel", "")) == "SCENES_garden", str(t2))
	var tried_before: int = (scene.graph.tried as Dictionary).size()
	var t3: Dictionary = scene.dbg_combo("SCENES_0602", "SCENES_body")
	check("C4：两场景互不列 loc ⇒ 没有直接通路",
		String(t3.get("message", "")) == "这两个场景之间没有直接通路", str(t3))
	check("C4：无通路标记 no_tried（不画 tried 虚线）",
		bool(t3.get("no_tried", false)), str(t3))
	check("C4：无通路不写 graph.tried",
		(scene.graph.tried as Dictionary).size() == tried_before,
		str(scene.graph.tried.keys()))

	# ── C4：前往分派（界面层：展场景 + 记 act）────────────────────
	check("前提：fkjl 还没探索",
		not (scene.dbg_state()["explored"] as Array).has("SCENES_fkjl"),
		str(scene.dbg_state()["explored"]))
	scene._on_card_combo(k0602, kfkjl)
	await process_frame
	await process_frame
	check("C4 分派：目标场景被展开",
		(scene.dbg_state()["explored"] as Array).has("SCENES_fkjl"),
		str(scene.dbg_state()["explored"]))
	check("C4 分派：案卷记一条「前往场景」", _log_has("前往场景"))

	# 无通路走界面：只留案卷、不弹条
	var tried_before2: int = (scene.graph.tried as Dictionary).size()
	var toast_before: bool = toast != null and toast.visible
	scene._on_card_combo(k0602, kbody)
	await process_frame
	check("C4 分派：无通路写进案卷", _log_has("没有直接通路"))
	check("C4 分派：无通路不弹提示条", toast != null and toast.visible == toast_before)
	check("C4 分派：无通路不落 tried",
		(scene.graph.tried as Dictionary).size() == tried_before2,
		str(scene.graph.tried.keys()))

	print("=== %d 项，失败 %d ===" % [total, fails])
	quit(0 if fails == 0 else 1)


func _log_has(needle: String) -> bool:
	for t in scene.dbg_log_texts():
		if String(t).find(needle) >= 0:
			return true
	return false


func _cards() -> Dictionary:
	var out := {}
	var layer: Node = scene.get_node("desk/case_win/body/stage/cards")
	for c in layer.get_children():
		if c is NodeCard:
			out[(c as NodeCard).card_key] = c
	return out


func _first_card_except(key: String) -> NodeCard:
	for k in _cards().keys():
		if String(k) != key:
			var c: NodeCard = _cards()[k]
			if c.visible:
				return c
	return null


func _press(card: NodeCard, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.global_position = pos
	card._gui_input(ev)


func _release(card: NodeCard, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.global_position = pos
	card._gui_input(ev)


func _single_click(card: NodeCard) -> void:
	var p := card.get_global_rect().get_center()
	_press(card, p)
	_release(card, p)


func _double_click(card: NodeCard) -> void:
	_single_click(card)
	_single_click(card)
