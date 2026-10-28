class_name TecController
extends Node
## 由 Desktop 挂载的子系统控制器。
## 过渡期直接通过注入的 `desk` 访问宿主成员；搬出的函数名保持不变。

var desk: Desktop


func _build_tec_chip() -> void:
	desk._tec_chip = TecChip.new()
	desk._tec_chip.setup_chip()
	desk._tec_chip.position = Vector2(1068, 608)
	desk._tec_chip.visible = false
	desk._tec_chip.pressed.connect(_open_tec)
	desk._tec_chip.moved.connect(desk._place_toast_anchor)
	desk._desk.add_child(desk._tec_chip)
	desk.windows._place_z(desk._tec_chip, Desktop.ZR_DOCK)


func _tec_teach_evidence() -> void:
	if desk.graph == null or desk._tec == null:
		return
	if int(desk.graph.tec_prog.get("_evi_intro", 0)) > 0:
		return
	desk.graph.tec_prog["_evi_intro"] = 1
	desk._tec.append_line("这是证——它该进「证据」，或者拿去填档案。")
	if desk._people_card != null and is_instance_valid(desk._people_card) and desk._people_card.visible:
		desk._show_toast("TEC：这是证——它该进「证据」，或者拿去填档案。")
	else:
		_open_tec()


func _tec_teach_recipe() -> void:
	if desk.graph == null or desk._tec == null:
		return
	if int(desk.graph.tec_prog.get("_recipe_intro", 0)) > 0:
		return
	desk.graph.tec_prog["_recipe_intro"] = 1
	desk._tec.append_line("物和词只是原料——两两拼成「证」，才能填进档案。")
	if desk._people_card != null and is_instance_valid(desk._people_card) and desk._people_card.visible:
		desk._show_toast("TEC：物和词只是原料——拼成「证」才能填进档案。")
	else:
		_open_tec()


func _tec_key(target: String) -> String:
	if target.contains(":"):
		var parts := target.split(":", true, 1)
		if parts.size() == 2:
			return desk.graph.key_of(parts[0], parts[1])
		return target
	return desk.graph.scene_key(target)


func _open_tec() -> void:
	if not desk.session._require_case():
		return
	if desk._tec == null:
		return
	desk._tec.visible = true
	desk.windows._place_z(desk._tec, Desktop.ZR_TEC)
	desk._tec_min = false
	desk._tec_dot = false
	if desk._tec_chip != null:
		desk._tec_chip.visible = false
	if desk._tutorial_active:
		desk._tutorial_tec_icon_visible = false
		desk.launcher._refresh_app_icons()


func _close_tec() -> void:
	if desk._tec == null:
		return
	## K7：等待任务只有两条路 —— 后台继续（最小化，有进度卡片）或关闭即取消。
	## 关闭时把话说明白，不能让分析悄悄消失。
	var was_analyzing := desk._tec.is_analyzing()
	desk._tec.cancel_analysis()
	desk._tec.visible = false
	desk._tec_min = false
	desk._tec_dot = false
	if desk._tec_chip != null:
		desk._tec_chip.visible = false
	if was_analyzing:
		desk.drag._reject_drop("已取消当前 TEC 分析。想边看边等，请点「–」收成助手卡片。")
	if desk._tutorial_active:
		desk._tutorial_tec_icon_visible = true
		desk.launcher._refresh_app_icons()


func _minimize_tec() -> void:
	if desk._tec == null or not desk._tec.visible:
		return
	desk._tec.visible = false
	desk._tec_min = true
	_sync_tec_chip()
	if desk._tutorial_active:
		desk._tutorial_tec_icon_visible = true
		desk.launcher._refresh_app_icons()


func _hide_tec(reset: bool = false) -> void:
	if desk._tec == null:
		return
	desk._tec.cancel_analysis()
	desk._tec.visible = false
	if reset:
		desk._tec.reset_tec()
	desk._tec_min = false
	desk._tec_dot = false
	desk._tec_before = {}
	if desk._tec_chip != null:
		desk._tec_chip.visible = false


func _toggle_tec() -> void:
	if not desk.session._require_case():
		return
	if desk._tec.visible:
		_close_tec()
	else:
		_open_tec()


func _sync_tec_chip() -> void:
	if desk._tec_chip == null:
		return
	if not desk._tec_min:
		desk._tec_chip.visible = false
		return
	desk._tec_chip.visible = true
	desk.windows._place_z(desk._tec_chip, Desktop.ZR_DOCK)
	if desk._tec.is_analyzing():
		desk._tec_chip.set_analyzing(desk._tec.target_label(), desk._tec.progress())
	else:
		desk._tec_chip.set_idle(desk._tec_dot)


func _tec_drop_hit(at_global: Vector2) -> bool:
	if desk._tec_btn != null and desk._tec_btn.get_global_rect().has_point(at_global):
		return true
	if desk._tec.visible and desk._tec.get_global_rect().has_point(at_global):
		return true
	if desk._tec_chip != null and desk._tec_chip.visible and desk._tec_chip.get_global_rect().has_point(at_global):
		return true
	return false


func _start_tec_analysis(key: String) -> bool:
	if not desk.session._require_case() or desk._tec == null:
		return false
	key = _tec_key(key)
	var n := desk.graph.node(key)
	if n.is_empty():
		return false
	if n.kind == "evidence":
		desk.drag._reject_drop(desk.people._evidence_tec_message(n.tier))
		return false
	if desk._tec.is_analyzing():
		if desk._tutorial_active:
			desk.tutorial._tutorial_say("让我先看完这个。")
		else:
			desk._show_toast("TEC 正在分析中，请稍候…", true)
		return false
	if desk._tutorial_active and not desk.tutorial._tutorial_tec_guard(key):
		return false
	if not desk._tec.visible and not desk._tec_min:
		_open_tec()
	return desk._tec.analyze(key, n.label if n.label != "" else key)


func _on_tec_analysis_started(_target: String, _label: String) -> void:
	desk._tec_before = desk._save.snapshot() if desk._save != null else {}
	desk._tec_dot = false
	if desk._tec_min:
		_sync_tec_chip()


func _on_tec_analysis_progress(ratio: float) -> void:
	if desk._tec_min and desk._tec_chip != null:
		desk._tec_chip.set_analyzing(desk._tec.target_label(), ratio)


func _refresh_clue_keys(keys: Array) -> void:
	if keys.is_empty():
		return
	for key in keys:
		desk.canvas._refresh_or_spawn_card(String(key))
	desk.canvas._relayout()


func _hidden_clue_of(kind: String, id: String) -> HiddenClueDef:
	match kind:
		"loc", "time":
			var s := desk.case_def.scene_of(id)
			return s.hidden_clue if s != null else null
		"item":
			var it := desk.case_def.item_of(id)
			return it.hidden_clue if it != null else null
		"char":
			var ch := desk.case_def.char_of(id)
			return ch.hidden_clue if ch != null else null
	return null


func _capture_node_hidden_clues(kind: String, id: String, host_key: String) -> Dictionary:
	var hc := _hidden_clue_of(kind, id)
	if hc == null:
		return {"keys": [], "names": [], "text": ""}
	var got: Array = []
	var names: Array = []
	var seen := {}
	for clue in hc.clues:
		if clue == null or desk.graph.captured.has(clue.id) or seen.has(clue.id):
			continue
		seen[clue.id] = true
		got.append(desk.graph.capture_evidence(clue.id, host_key, -1.0, -1.0, "tec"))
		names.append(clue.label)
	_refresh_clue_keys(got)
	return {"keys": got, "names": names, "text": hc.text}


## TEC 解读完成后落 hidden_clue（字段名沿用，内容为证）。
func _capture_hidden_clue(scene_id: String) -> void:
	var kind := desk.graph.normalize_kind("loc", scene_id)
	var host := desk.graph.key_of(kind, scene_id)
	var res := _capture_node_hidden_clues(kind, scene_id, host)
	if res["keys"].is_empty():
		return
	desk._show_toast("获得证据：" + "、".join(res["names"]))


func _tec_talk_lines(sid: String) -> Array:
	var tec := desk.case_def.char_of("CHARS_TEC")
	if tec == null:
		return []
	for st in tec.scene_talks:
		if st != null and st.scene != null and st.scene.id == sid:
			return st.lines
	return []


## 这条物品 / 线索在 TEC 那里有没有专属反应。首次展开救济与密码连错提示共用。
func _tec_reaction_hit(kind: String, id: String) -> Dictionary:
	var tec := desk.case_def.char_of("CHARS_TEC") if desk.case_def != null else null
	if tec == null:
		return {}
	var groups: Array = []
	if kind == "item":
		groups = [tec.item_reactions]
	elif kind == "clue":
		groups = [tec.clue_reactions]
	else:
		groups = [tec.item_reactions, tec.clue_reactions]
	for group in groups:
		for r in group:
			if r == null or String(r.text) == "":
				continue
			if (r.item != null and r.item.id == id) or (r.clue != null and r.clue.id == id) \
					or r.trigger_id == id:
				return {"text": r.text, "clues": r.clues}
	return {}


func _tec_reaction_text(kind: String, id: String) -> String:
	return String(_tec_reaction_hit(kind, id).get("text", ""))


## G7：TEC 亲口留提示。默认只落进 TEC 对话（不污染「只记结果」的日志）；
## 档案类提示可显式 log_it，窗关着时可显式 announce 用 toast 提醒。
func _tec_hint(text: String, announce := false, log_it := false) -> void:
	if text == "" or desk._tec == null or not is_instance_valid(desk._tec):
		return
	## W26：同一条提示不重复追加；如果它还在打字，点一下只负责补全。
	if desk._tec.last_line_text() == text:
		if desk._tec.is_typing():
			desk._tec.finish_typing()
		return
	desk._tec.append_line(text, TecTheme.MUTED)
	if log_it:
		desk._log("TEC：" + text, "sys")
	if not desk._tec.visible or desk._tec_min:
		desk._tec_dot = true
		if desk._tec_min:
			_sync_tec_chip()
		if announce and not desk._tec.visible:
			desk._show_toast("TEC 留了条提示：" + text)


## G7：所有「第一次展开」路径统一走这里（双击场景 / 容器、组合前往、命令产出场景）。
## 有档案的场景指给 TEC 分析；有专属反应的物品指给 TEC；其余给一句看现场的方向提示。
func _on_first_expand(kind: String, id: String, was_explored: bool) -> void:
	if was_explored or desk._tutorial_active or desk.graph == null or desk.case_def == null:
		return
	var title := desk.case_def.label_of(kind, id)
	if GraphState.is_scene_kind(kind):
		if desk.case_def.is_time_id(id):
			desk._log("「%s」可以当一段回忆的锚点（把它拖到一个地点上，再拖一个人物上去）" % title, "sys")
		if not _tec_talk_lines(id).is_empty():
			_tec_hint("「%s」的档案可以解读——把场景节点拖给我分析。" % title, false, true)
		else:
			_tec_hint("先看看「%s」里有什么；可疑的东西可以拖给我。" % title)
	elif _tec_reaction_text(kind, id) != "" or _hidden_clue_of(kind, id) != null:
		_tec_hint("「%s」可以拖给我看看。" % title)


func _tec_reaction(key: String) -> bool:
	var n := desk.graph.node(key)
	if n.is_empty() or desk._tec == null:
		return false
	if desk.case_def.char_of("CHARS_TEC") == null:
		return false
	var id := n.id
	var hit := _tec_reaction_hit(n.kind, id)
	var raw := String(hit.get("text", ""))
	if raw == "":
		desk._tec.append_line("关于「%s」，我暂时没有更多证据。试试把它和别的节点组合。" % n.label)
		desk._log("TEC 对「%s」没有特别的反应" % n.label, "warn")
		desk.graph.tried[key + ">tec-dock"] = true
		return false
	var got := desk.graph.capture_clue_refs(hit.get("clues", []), key)
	var reaction_line := "（分析 %s）%s" % [n.label, raw]
	if desk._has_true_name_clue(got):
		desk._tec.append_true_clue(reaction_line)
	else:
		desk._tec.append_line(reaction_line)
	_refresh_clue_keys(got)
	return true


## G7：闲聊队列耗尽后不再静默。按当前进度给「方向 → 操作 → 明示」三档提示，
## 每次点击换下一条；状态越具体，提示越接近可执行动作。
func _tec_next_hint() -> String:
	var hints: Array = []
	if desk.graph == null or desk.case_def == null:
		return "（把节点拖到我身上，我来分析）"
	if desk.graph.explored.is_empty():
		hints.append("方向：先双击「%s」，把现场展开。" % desk.case_def.scene_title(Desktop.SLICE_SCENE))
	else:
		hints.append("方向：还有没展开的现场或容器；双击它们，再看看人物名册。")
	if desk.graph.matrix_count() <= 0:
		hints.append("操作：双击「推演」，把证放到推演桌布上。")
		hints.append("明示：桌布空着不会触发推演——先放至少一条证，再长按执行者。")
	else:
		hints.append("操作：长按桌布中央的执行者推演；不对就把证取回画布再换。")
		hints.append("明示：配方要正好匹配——多一条、少一条都会失败；先在日志里核对已有的证。")
	## G11：场上有带密码锁、且 TEC 有专属反应的东西时，直接把「拖给我」说明白。
	for key in desk.graph.nodes.keys():
		var n := desk.graph.node(String(key))
		if n.is_empty() or n.kind != "item":
			continue
		var it := desk.case_def.item_of(n.id)
		if it == null:
			continue
		var locked := false
		for cmd in it.commands:
			if cmd is PasswordCommandDef:
				locked = true
				break
		if locked and _tec_reaction_text("item", n.id) != "":
			hints.append("明示：带密码锁的「%s」可以拖给我，我能读出数字提示。" % n.label)
			break
	for ch in desk.case_def.chars.values():
		var missing := ""
		for f in ch.evidence_fields:
			if f != null and not desk.graph.is_field_confirmed(ch.id, f.id):
				missing = f.label
				break
		if missing != "":
			hints.append("提示：「%s」档案里的「%s」还缺结论证据。" % [ch.name, missing])
			break
	var tier := int(desk.graph.tec_prog.get("_hint", 0))
	desk.graph.tec_prog["_hint"] = tier + 1
	return String(hints[tier % hints.size()])


func _tec_talk() -> void:
	if not desk.session._require_case() or desk._tec == null:
		return
	if not desk._tec.visible:
		_open_tec()
	## W26：打字中再点只补全当前行，不叠加下一句（对齐 MemCard 单击补全惯例）。
	if desk._tec.is_typing():
		desk._tec.finish_typing()
		return
	if desk._tutorial_active:
		desk.tutorial._tutorial_say(desk.tutorial._tutorial_talk_line())
		return
	var tec := desk.case_def.char_of("CHARS_TEC")
	var queue: Array = tec.talk_queue if tec != null else []
	if queue.is_empty():
		_tec_hint("（把节点拖到我身上，我来分析）")
		return
	var idx := int(desk.graph.tec_prog.get("_def", 0))
	if idx < queue.size():
		desk.graph.tec_prog["_def"] = idx + 1
		desk._tec.append_line(String(queue[idx]))
		desk.session._autosave()
		return
	_tec_hint(_tec_next_hint())
	desk.session._autosave()


func _on_tec_analysis_done(target: String) -> void:
	var key := _tec_key(target)
	if desk._tutorial_active and desk.tutorial._tutorial_on_tec_done(key):
		desk._tec_before = {}
		return
	var n := desk.graph.node(key)
	if n.is_empty():
		desk._tec_before = {}
		return
	var kind := n.kind
	var id := n.id
	var label := n.label if n.label != "" else id
	if GraphState.is_scene_kind(kind):
		var talks := _tec_talk_lines(id)
		var prog := int(desk.graph.tec_prog.get(id, 0))
		var unread := talks.size() - prog
		var hidden := _capture_node_hidden_clues(kind, id, key)
		if not (hidden["keys"] as Array).is_empty():
			var hidden_line := "分析完成：「%s」中得出证 —— %s。（已落到画布上，可自由拖动）" \
				% [label, "、".join(hidden["names"])]
			if desk._has_true_name_clue(hidden["keys"]):
				desk._tec.append_true_clue(hidden_line)
			else:
				desk._tec.append_line(hidden_line)
			if String(hidden["text"]) != "":
				desk._tec.append_line(String(hidden["text"]))
			desk._log("TEC 从「%s」得出证：%s" % [label, "、".join(hidden["names"])], "cap")
			desk._show_toast("获得证据：" + "、".join(hidden["names"]))
		elif unread <= 0:
			desk._tec.append_line("分析完成：「%s」中没有新的证。" % label)
			desk._log("TEC 分析「%s」：没有新的证" % label, "warn")
		if not talks.is_empty() and unread > 0:
			var line := String(talks[prog])
			desk.graph.tec_prog[id] = prog + 1
			desk._tec.append_line(line)
			desk._log("TEC 解读了「%s」的档案（%d/%d）" % [label, prog + 1, talks.size()], "sys")
		elif not talks.is_empty():
			desk._tec.append_line("「%s」的档案已经全部解读完毕。" % label)
	else:
		_tec_reaction(key)
		var ent_hidden := _capture_node_hidden_clues(kind, id, key)
		if not (ent_hidden["keys"] as Array).is_empty():
			var ent_line := "分析完成：「%s」中得出证 —— %s。（已落到画布上，可自由拖动）" \
				% [label, "、".join(ent_hidden["names"])]
			if desk._has_true_name_clue(ent_hidden["keys"]):
				desk._tec.append_true_clue(ent_line)
			else:
				desk._tec.append_line(ent_line)
			if String(ent_hidden["text"]) != "":
				desk._tec.append_line(String(ent_hidden["text"]))
			desk._log("TEC 从「%s」得出证：%s" % [label, "、".join(ent_hidden["names"])], "cap")
			desk._show_toast("获得证据：" + "、".join(ent_hidden["names"]))
	if desk._tec_min:
		desk._tec_dot = true
		_sync_tec_chip()
	desk.session._commit(desk._tec_before)
	desk._tec_before = {}
