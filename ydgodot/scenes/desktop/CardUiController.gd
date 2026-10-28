class_name CardUiController
extends Node
## 由 Desktop 挂载的子系统控制器。
## 过渡期直接通过注入的 `desk` 访问宿主成员；搬出的函数名保持不变。

var desk: Desktop


func _on_card_selected(key: String) -> void:
	desk._selected = key
	desk.graph.selected = key
	if desk.graph.has_unread(key):
		desk.graph.clear_fresh(key)
		desk.canvas._sync_card_shell(desk._cards.get(key, null))
	desk.chrome._apply_focus()
	_refresh_detail(true)
	## 选中节点时把详情窗提到当前层，避免被 TEC / 后开的窗口压在下面。
	if desk._detail_win != null and is_instance_valid(desk._detail_win) and desk._detail_win.visible:
		desk.windows._raise_to_front(desk._detail_win)


## 卡片按下（未拖未点都算）：把它的重排落位补间杀掉——卡冻结在指针下面，
## 双击不会因为卡「飞走了」而落空，拖动起手也不会跟 0.34s 过渡打架
func _on_card_pressed(key: String) -> void:
	## F1：玩家接管某张卡时停止后台收敛，避免每帧把卡从他手边推走。
	desk.canvas._cancel_layout_job()
	desk.canvas._kill_move(key)


## 右键 = 钉住 / 取消钉住（Web 里这是唯一入口，拖动不再顺手钉住）
func _open_card_context(key: String, at_global: Vector2) -> void:
	_close_card_context()
	if desk.graph == null or not desk.graph.nodes.has(key):
		return
	var n := desk.graph.node(key)
	var menu := PanelContainer.new()
	menu.name = "card_context"
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := TecTheme.flat(TecTheme.CARD, TecTheme.R_SM, TecTheme.INK, 1)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	menu.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	menu.add_child(col)
	var pin := TecTheme.button("取消钉住" if bool(n.get("pinned", false)) else "钉住")
	pin.name = "ctx_pin"
	pin.custom_minimum_size = Vector2(104, 26)
	pin.pressed.connect(func():
		_on_card_pin_toggled(key)
		_close_card_context())
	col.add_child(pin)
	var detail := TecTheme.button("查看详情")
	detail.name = "ctx_detail"
	detail.custom_minimum_size = Vector2(104, 26)
	detail.pressed.connect(func():
		_on_card_selected(key)
		_close_card_context())
	col.add_child(detail)
	desk._desk.add_child(menu)
	desk.windows._place_z(menu, Desktop.ZR_TOAST)
	menu.reset_size()
	var pos := at_global - desk._desk.get_global_position()
	pos.x = clampf(pos.x, 8.0, maxf(8.0, desk._desk.size.x - menu.size.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, desk._desk.size.y - menu.size.y - 8.0))
	menu.position = pos
	desk._card_ctx = menu
	desk._card_ctx_key = key


func _close_card_context() -> void:
	if desk._card_ctx != null and is_instance_valid(desk._card_ctx):
		desk._card_ctx.queue_free()
	desk._card_ctx = null
	desk._card_ctx_key = ""


func _on_card_pin_toggled(key: String) -> void:
	var n := desk.graph.node(key)
	if n.is_empty():
		return
	var before := desk._save.snapshot()
	n["pinned"] = not bool(n.get("pinned", false))
	desk.canvas._sync_card_shell(desk._cards.get(key, null))
	desk.session._commit(before)


## 节点详情窗（Web `#detail-win`）：选中即显示，点空白即收起
func _ensure_detail() -> DetailWin:
	if desk._detail_win != null and is_instance_valid(desk._detail_win):
		return desk._detail_win
	desk._detail_win = DetailWin.new()
	desk._detail_win.name = "detail_win"
	desk._detail_win.setup_detail(desk.graph, desk.case_def)
	desk._detail_win.renarr_scene.connect(func(id: String): _show_narr(id))
	desk._detail_win.renarr_talk.connect(_replay_talk)
	desk._detail_win.play_monologue.connect(func(id: String): desk.narrative._open_monologue(id))
	desk._detail_win.play_music.connect(desk.garden_music._open_music)
	desk._desk.add_child(desk._detail_win)
	desk._detail_win.place_right(desk._vw())
	desk.windows._place_z(desk._detail_win, Desktop.ZR_DETAIL)
	return desk._detail_win


func _refresh_detail(force := false) -> void:
	## U2 收敛：叙事卡在屏上时，详情完全让位，不并排抢阅读焦点。
	## · 后台刷新（force=false）：只记 pending，等叙事卡关闭后再补；
	## · 玩家明确点节点（force=true）：收掉叙事卡，再切到详情，做成「切换」而不是叠窗。
	if desk._narr != null and is_instance_valid(desk._narr):
		if not force:
			desk._pending_detail = desk._selected != "" and desk.graph != null and desk.graph.nodes.has(desk._selected)
			if desk._detail_win != null and is_instance_valid(desk._detail_win):
				desk._detail_win.hide()
			return
		_dismiss_narr()
	if desk._detail_win == null or not is_instance_valid(desk._detail_win):
		if desk._selected == "" or desk.graph == null or not desk.graph.nodes.has(desk._selected):
			return
		_ensure_detail()
	if desk._selected == "" or desk.graph == null or not desk.graph.nodes.has(desk._selected):
		desk._detail_win.hide()
		return
	if desk._detail_full_once:
		desk._detail_win.show_full_once()
		desk._detail_full_once = false
	if force:
		desk._detail_win.show_node(desk._selected, true)
	else:
		desk._detail_win.show_node(desk._selected)


## 收起叙事卡但不触发「关闭后补详情」：用于玩家点节点、主动切到详情。
func _dismiss_narr() -> void:
	if desk._narr != null and is_instance_valid(desk._narr):
		desk._narr.hide()
		desk._narr.queue_free()
	desk._narr = null
	desk._pending_detail = false


## 「重看对话」：把这个人已经说过的台词整段重放进对话窗（Web `renarrTalk`）
func _replay_talk(key: String) -> bool:
	var n := desk.graph.node(key)
	if n.is_empty() or desk._chat_win != null and is_instance_valid(desk._chat_win):
		return false
	if String(n["kind"]) != "char":
		return false
	var ch := desk.case_def.char_of(String(n["id"]))
	if ch == null:
		return false
	## S13：重看对话要覆盖 talkQueue + 当前 home_scene 的场景限定台词。
	var queue := desk.graph.char_talk_queue(String(ch.id))
	var prog := mini(int(desk.graph.talk_prog.get(key, 0)), queue.size())
	if prog <= 0:
		return false
	var d := DialogueDef.new()
	d.id = "replay_" + String(ch.id)
	var parts: Array[CharDef] = [ch]
	d.participants = parts
	for i in prog:
		var line := DialogueLineDef.new()
		line.kind = "say"
		line.who = ch
		line.text = String(queue[i])
		d.script_lines.append(line)
	return desk.narrative._open_chat(d, [String(ch.id)])


func _on_card_activated(key: String) -> void:
	var n := desk.graph.node(key)
	if n.is_empty():
		return
	if desk._tutorial_active and desk.tutorial._tutorial_on_activate(key):
		return
	var id := String(n["id"])
	# 证是知识代币：双击 = 确认（已由 TEC / 合成产出的证通常已 captured，重复双击只提示）。
	if String(n["kind"]) == "evidence" and String(n.get("tier", "")) == "zheng":
		_capture_clue_node(key)
		return
	if String(n["kind"]) == "evidence":
		return
	if n["kind"] == "loc":
		# Web dblclick：场景若带命令（SCENES[id].commands），双击先跑 commands[0]，
		# 不展开容器 —— 数据里 0/11 的场景用到这条，分支为未来案件铺路
		var sc := desk.case_def.scene_of(id)
		if sc != null and sc.commands.size() > 0:
			var before_loc := desk._save.snapshot()
			var res := desk.combos.activate(key)
			if res.is_empty():
				return
			_apply_outcome(res, key)
			desk.session._commit(before_loc)
			return
		_toggle_container("loc", id)
		return
	if desk.graph.is_container("item", id):
		_toggle_container("item", id)
		return
	# 其余：跑第一条命令（text / password / choice / conditional / reveal 都从这儿进）
	var before := desk._save.snapshot()
	var res := desk.combos.activate(key)
	if res.is_empty():
		if String(n["kind"]) == "char":
			if _say_next_line(id):
				return
			if desk.narrative._open_monologue(id):
				return
		return
	_apply_outcome(res, key)
	desk.session._commit(before)


## 双击线索 = 捕获（对齐 Web `08-interact.js:346`）。
## 捕获进 `graph.captured` + 卡面翻成 `.got` + 案卷一条 `cap`；重复双击只留一条 warn。
## **不进 toast** —— Web 这里刻意不弹，让画面自己说话。
func _capture_clue_node(key: String) -> void:
	var n := desk.graph.node(key)
	if n.is_empty():
		return
	var id := String(n["id"])
	var lab := String(n.get("label", id))
	if desk.graph.captured.has(id):
		desk._log("证据「%s」已经确认过了" % lab, "warn")
		return
	var before := desk._save.snapshot()
	desk.graph.capture_evidence(id, key, -1.0, -1.0, "tec")
	desk.canvas._refresh_or_spawn_card(key)
	desk._log("已确认证据「%s」" % lab, "cap")
	_on_card_selected(key)
	desk.session._commit(before)


## 容器双重身份：第一次双击展开，已展开再双击收起（对齐 Web 的展开 / 折叠）
func _toggle_container(kind: String, id: String) -> void:
	var before := desk._save.snapshot()
	var was_explored := desk.graph.explored.has(id)
	if was_explored and not desk.graph.is_collapsed(id):
		desk.graph.collapse(id)
		_apply_hidden()
		var left := 0
		var self_key := desk.graph.key_of(kind, id)
		for k in desk.graph.nodes.keys():
			var kk := String(k)
			if kk == self_key:
				continue
			var nn := desk.graph.node(kk)
			if String(nn.get("home_scene", "")) != id:
				continue
			if desk.graph.visible_node(nn):
				left += 1
		if left > 0:
			desk._log("「%s」另有 %d 个节点留在画布上（已固定 / 与场外相连）"
				% [desk.case_def.label_of(kind, id), left], "sys")
		desk._show_toast("收起了「%s」" % desk.case_def.label_of(kind, id))
		desk.canvas._relayout(true)
		desk.session._commit(before)
		return
	var fresh := desk.graph.reveal_container(kind, id)
	desk.graph.uncollapse(id)
	_apply_hidden()
	for k in fresh:
		desk.canvas._spawn_card(String(k))
	if desk._cards.has(desk.graph.key_of(kind, id)):
		desk._cards[desk.graph.key_of(kind, id)].refresh()
		desk.canvas._sync_card_shell(desk._cards[desk.graph.key_of(kind, id)])
	desk.canvas._relayout(true)
	if kind == "loc":
		_show_narr(id)
		desk.session._set_crumb(desk.session._case_label() + " // " + desk.case_def.scene_title(id))
	else:
		desk._show_toast("展开了「%s」" % desk.case_def.label_of(kind, id))
	desk.tec._on_first_expand(kind, id, was_explored)
	desk.session._commit(before)


## 把图状态的隐藏结论落到卡片上（对齐 Web 的 recomputeHidden：钉住的、跟场外有连线的都不藏）
func _apply_hidden() -> void:
	desk.graph.recompute_hidden()
	for key in desk._cards.keys():
		(desk._cards[key] as NodeCard).visible = desk.graph.visible_node(desk.graph.node(String(key)))
	desk.canvas._repaint_edges()
	_refresh_detail()


## 统一落地一次命令结果：提示 / 长卡片 / 刷新 / 重排
func _apply_outcome(res: Dictionary, node_key: String) -> void:
	if res.get("needs_password", false):
		_open_password(node_key)
		return
	var blocked := bool(res.get("blocked", false))
	var msg := String(res.get("message", ""))
	if msg != "":
		var nlab := String(desk.graph.node(node_key).get("label", node_key))
		desk._log("「%s」：%s" % [nlab, msg], "warn" if blocked else "act")
		desk._show_toast(msg, blocked)
	for m in res.get("messages", []):
		if String(m) != "":
			desk._show_toast(String(m))
	for k in res.get("spawn", []):
		desk.canvas._spawn_card(String(k))
	for k in res.get("reveal", []):
		desk.canvas._spawn_card(String(k))
	for k in res.get("captured", []):
		desk.canvas._refresh_or_spawn_card(String(k))
	for k in res.get("consumed", []):
		desk.canvas._despawn_card(String(k))
	if bool(res.get("lit_changed", false)):
		if desk._cards.has(node_key):
			desk._cards[node_key].refresh()
			desk.canvas._sync_card_shell(desk._cards[node_key])
		var flavor := String(res.get("flavor", ""))
		if flavor != "":
			desk._show_toast(flavor)
	if res.has("next_scene") and String(res.get("next_scene", "")) != "":
		desk.session._set_crumb(desk.session._case_label() + " // " + desk.case_def.scene_title(String(res["next_scene"])))
	var first_scene := String(res.get("first_scene", ""))
	if first_scene != "":
		desk.tec._on_first_expand("loc", first_scene, false)
	desk.canvas._relayout()


func _first_sentence(text: String) -> String:
	var clean := text.strip_edges()
	if clean == "":
		return ""
	var idx := clean.find("。")
	if idx > 0:
		return clean.substr(0, idx)
	return clean


## 说下一句（Web `showCharLine`）：推进 talkQueue、收下台词里提到的线索、开对话窗。
## 说完 / 没有台词时不推进 —— 点了也不再出新句。
func _say_next_line(id: String) -> bool:
	if desk.case_def == null:
		return false
	var key := desk.graph.key_of("char", id)
	var ch := desk.case_def.char_of(id)
	if ch == null:
		return false
	var queue := desk.graph.char_talk_queue(id)
	var prog := int(desk.graph.talk_prog.get(key, 0))
	if queue.is_empty() or prog >= queue.size():
		return false
	if desk._chat_win != null and is_instance_valid(desk._chat_win):
		return false        # 对话窗开着：不叠第二扇（Web 的 dlg-win 独立，P2.4 侧待补）
	var before := desk._save.snapshot() if desk._save != null else {}
	desk.graph.talk_prog[key] = prog + 1
	var line := String(queue[prog])
	var d := DialogueDef.new()
	d.id = "talk_" + String(ch.id)
	var parts: Array[CharDef] = [ch]
	d.participants = parts
	var ld := DialogueLineDef.new()
	ld.kind = "say"
	ld.who = ch
	ld.text = line
	d.script_lines.append(ld)
	desk.narrative._open_chat(d, [String(ch.id)])
	desk.session._commit(before)
	return true


func _labels_of(ids: Array) -> Array:
	var out: Array = []
	for cid in ids:
		out.append(desk.case_def.label_of("clue", String(cid)))
	return out


func _open_password(node_key: String) -> void:
	var n := desk.graph.node(node_key)
	var it := desk.case_def.item_of(String(n.get("id", "")))
	if it == null:
		return
	var cmd: PasswordCommandDef = null
	for c in it.commands:
		if c is PasswordCommandDef:
			cmd = c
			break
	if cmd == null:
		return
	if desk._pw_pop != null and is_instance_valid(desk._pw_pop):
		if desk._pw_pop.get_parent() != null:
			desk._pw_pop.get_parent().remove_child(desk._pw_pop)
		desk._pw_pop.queue_free()
	var card: NodeCard = desk._cards.get(node_key, null)
	desk._pw_pop = PasswordPop.new()
	desk._pw_pop.name = "pw_pop"
	desk._pw_pop.setup_password(it.label, cmd.label)
	var base := Vector2(300, 300)
	if card != null:
		var r := card.get_global_rect()
		base = Vector2(r.position.x - desk._desk.get_global_rect().position.x,
			r.end.y - desk._desk.get_global_rect().position.y + 10.0)
	## W15：密码浮层也要夹在桌面内；卡片贴底边时不能把输入框裁到看不见。
	var desk_size := desk._desk.size if desk._desk != null and is_instance_valid(desk._desk) else Vector2(desk._vw(), desk._vh())
	base.x = clampf(base.x, 8.0, maxf(8.0, desk_size.x - desk._pw_pop.size.x - 8.0))
	base.y = clampf(base.y, 8.0, maxf(8.0, desk_size.y - desk._pw_pop.size.y - 8.0))
	desk._pw_pop.position = base
	desk._pw_pop.submitted.connect(_submit_password)
	desk._desk.add_child(desk._pw_pop)
	desk.windows._place_z(desk._pw_pop, Desktop.ZR_PW)
	desk._pw_ctx = {"node_key": node_key, "cmd": cmd}


func _submit_password(text: String) -> void:
	if desk._pw_ctx.is_empty():
		return
	var before := desk._save.snapshot()
	var pw_key := String(desk._pw_ctx.get("node_key", ""))
	var res := desk._cmds.submit_password(pw_key, desk._pw_ctx["cmd"], text)
	if bool(res.get("wrong_password", false)):
		if desk._pw_pop != null and is_instance_valid(desk._pw_pop):
			desk._pw_pop.reject_wrong()
		var pw_lab := String(desk.graph.node(pw_key).get("label", pw_key))
		var pw_txt := String(text) if String(text) != "" else "(空)"
		desk._log("「%s」密码 %s 不正确" % [pw_lab, pw_txt], "warn")
		desk._show_toast(String(res.get("message", "")), true)
		## G11：连续错两次，指向已有救济（TEC 分析木盒），而不是让玩家一直穷举。
		var wrong := int(desk._pw_wrong.get(pw_key, 0)) + 1
		desk._pw_wrong[pw_key] = wrong
		if wrong == 2:
			var hint := "连续错两次了。这个锁我可能有办法——把「%s」拖给 TEC 分析，看看有没有数字提示。" % pw_lab
			var n := desk.graph.node(pw_key)
			if desk.tec._tec_reaction_text("item", String(n.get("id", ""))) != "":
				desk.tec._tec_hint("「%s」的密码？把它拖给我，我看看能不能读出数字。" % pw_lab, false)
				desk._show_toast(hint, true)
				desk._log(hint, "warn")
			else:
				desk._show_toast("连续错两次了。去现场找带数字的纸片或记录，再回来试。", true)
		return
	desk._pw_wrong.erase(pw_key)
	if desk._pw_pop != null and is_instance_valid(desk._pw_pop):
		desk._pw_pop.queue_free()
	desk._pw_pop = null
	_apply_outcome(res, String(desk._pw_ctx["node_key"]))
	desk._pw_ctx = {}
	desk.session._commit(before)


func _on_card_combo(tool_key: String, target_key: String) -> void:
	# 折叠的容器（场景 / 书桌 / 垃圾桶）既不收纳也不组合：里面的东西看不见，隔空命中的结果没有着力点
	var tn := desk.graph.node(target_key)
	if not tn.is_empty() and desk.graph.is_container_node(target_key) \
		and desk.graph.collapsed.has(String(tn.get("id", ""))):
		desk._show_toast("「%s」已折叠：先双击展开，或把节点拖到「物品」" % String(tn.get("label", "")), true)
		return
	var before := desk._save.snapshot()
	# 标签要在 use_item 之前取：工具可能被消耗并从图中移除，事后再拿只剩内部 key。
	var tool_label := String(desk.graph.node(tool_key).get("label", tool_key))
	var target_label := String(tn.get("label", target_key))
	if desk.narrative._try_memory_combo(tool_key, target_key, before):
		return
	if desk.narrative._try_dialogue_combo(tool_key, target_key):
		return
	var res := desk.combos.use_item(tool_key, target_key)
	# 前往：容器正文里 `[loc:对方]` 列着它 ⇒ 展开目标场景（Web 的 revealScene）。
	# 案卷记一条 act；不弹提示条，也不写「组合」字样 —— 这是走动，不是合成。
	var travel := String(res.get("travel", ""))
	if travel != "":
		desk._log("前往场景「%s」" % desk.case_def.scene_title(travel), "act")
		_expand_scene(travel, true)
		desk.session._commit(before)
		return
	if res.has("blocked") and res["blocked"]:
		# 发光门：不记 tried、不进撤销，但拦下的理由要进案卷（Web 09-commands.js:10）
		desk._log(String(res.get("message", "")), "warn")
		desk._show_toast(String(res.get("message", "")), true)
		return
	if res.get("ok", false):
		# 组合成功**不弹提示条**（Web 刻意）：结果靠画面自证，正文与「获得 / 消耗」只进案卷（C8）
		var bits := "组合 %s ⇒ %s：%s" % [tool_label, target_label, String(res.get("message", ""))]
		var gained: Array = []
		for k in res.get("reveal", []):
			gained.append(String(desk.graph.node(String(k)).get("label", k)))
		for k in res.get("captured", []):
			gained.append(String(desk.graph.node(String(k)).get("label", k)))
		if not gained.is_empty():
			bits += "　［获得 %s］" % "、".join(gained)
		var consumed: Array = []
		for k in res.get("consumed", []):
			var kk := String(k)
			var iid := kk.substr(kk.find(":") + 1)
			consumed.append(desk.case_def.label_of("item", iid))
		if not consumed.is_empty():
			bits += "　［消耗 %s］" % "、".join(consumed)
		desk._log(bits, "act")
		var next_scene := String(res.get("next_scene", ""))
		if next_scene != "":
			_expand_scene(next_scene, true)
		for k in res.get("reveal", []):
			desk.canvas._spawn_card(String(k))
		for k in res.get("captured", []):
			desk.canvas._refresh_or_spawn_card(String(k))
		for k in res.get("consumed", []):
			desk.canvas._despawn_card(String(k))
		desk.canvas._relayout()
		if bool(res.get("evidence_recipe", false)):
			var produced := String(res.get("produced_evidence", ""))
			desk.tec._tec_teach_evidence()
			desk.tec._tec_teach_recipe()
			desk._show_toast("获得证据：" + desk.case_def.label_of("evidence", produced))
		## 反应表命中：除案卷与节点产出外，再用独白把台词面对面说出来。
		## TEC 的反应归 TEC 窗（分析链路），不要重复弹独白。
		var reaction_owner := String(res.get("reaction_owner", ""))
		if reaction_owner != "" and reaction_owner != "CHARS_TEC":
			var trigger_id := String(res.get("reaction_trigger", ""))
			var trigger_label := target_label
			if trigger_id != "":
				trigger_label = desk.case_def.label_of(CaseLoader.kind_of_ref(trigger_id), trigger_id)
			desk.narrative._open_reaction_monologue(reaction_owner, String(res.get("message", "")),
				trigger_label)
		desk.session._commit(before)
	else:
		var msg := String(res.get("message", ""))
		if msg != "":
			# 失败**不弹提示条**（Web `05-combine.js:168` 的 fail()：条件不足 = 什么也没发生，
			# 原因只留在案卷里）。原先这里还弹一张条，等于一边说「组合失败」一边打断画面。
			desk._log("组合失败：" + msg, "warn")
		# 失败只多一条「试过」虚线，**不动坐标**（以前这里跑 _relayout，等于每次失败都把全场归位）
		desk.canvas._repaint_edges()


func _expand_scene(sid: String, show_narr: bool) -> void:
	var was_explored := desk.graph.explored.has(sid)
	var fresh := desk.graph.reveal_scene(sid)
	var key := desk.graph.scene_key(sid)
	var had := desk._cards.has(key)
	for k in fresh:
		desk.canvas._spawn_card(String(k))
	if not had:
		desk.canvas._spawn_card(key)
	if desk._cards.has(key):
		desk._cards[key].refresh()
		desk.canvas._sync_card_shell(desk._cards[key])
	desk.canvas._relayout()
	if show_narr:
		_show_narr(sid)
	desk.session._set_crumb(desk.session._case_label() + " // " + desk.case_def.scene_title(sid))
	desk.tec._on_first_expand("loc", sid, was_explored)


func _show_narr(sid: String) -> void:
	var n := desk.graph.node(desk.graph.scene_key(sid))
	if n.is_empty():
		return
	var body := desk.case_def.text_of(desk.graph.normalize_kind("loc", sid), sid)
	if desk._narr != null and is_instance_valid(desk._narr):
		desk._narr.queue_free()
	desk._narr = NarrCard.new()
	desk._narr.name = "narr_card"
	desk._narr.setup_narr(desk.case_def.scene_title(sid), body, 340, 300)
	## W22：不再写死 (700,290)；按桌布实际尺寸收进视口。
	var desk_size := desk._desk.size if desk._desk != null and is_instance_valid(desk._desk) else Vector2(desk._vw(), desk._vh())
	desk._narr.position = Vector2(
		minf(700.0, maxf(24.0, desk_size.x - desk._narr.size.x - 24.0)),
		minf(290.0, maxf(24.0, desk_size.y - desk._narr.size.y - 24.0)))
	desk._narr.closed.connect(_on_narr_closed)
	desk._narr.typing_finished.connect(_on_narr_typing_finished)
	desk._desk.add_child(desk._narr)
	desk.windows._place_z(desk._narr, Desktop.ZR_NARR)
	## U2：叙事先播，详情后显示；已有详情先收起，等这一段打完。
	desk._pending_detail = desk._selected != "" and desk.graph.nodes.has(desk._selected)
	if desk._detail_win != null and is_instance_valid(desk._detail_win):
		desk._detail_win.hide()
	if not desk._narr.is_typing():
		_on_narr_typing_finished()


func _on_narr_typing_finished() -> void:
	## 叙事卡还在屏上，详情继续让位。等玩家关掉叙事卡 / 明确点节点后再显示。
	desk._pending_detail = desk._pending_detail or (desk._selected != "" and desk.graph != null
		and desk.graph.nodes.has(desk._selected))


func _on_narr_closed() -> void:
	desk._narr = null
	if desk._pending_detail:
		desk._pending_detail = false
		desk._detail_full_once = true
		_refresh_detail()
