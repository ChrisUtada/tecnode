class_name NarrativeController
extends Node
## 由 Desktop 挂载的子系统控制器。
## 过渡期直接通过注入的 `desk` 访问宿主成员；搬出的函数名保持不变。

var desk: Desktop

## 放映卡当前锚定的节点 key（重排/补间期间跟随）。
var _mem_anchor_key := ""


func _toggle_archive() -> void:
	if not desk.session._require_case():
		return
	if desk._archive_win != null and is_instance_valid(desk._archive_win):
		desk._archive_win.queue_free()
		desk._archive_win = null
		return
	desk._archive_win = ArchiveWin.new()
	desk._archive_win.name = "archive_win"
	desk._archive_win.setup_archive(desk.graph, desk.case_def)
	desk._archive_win.time_selected.connect(_on_archive_time)
	desk._archive_win.closed.connect(func(): desk._archive_win = null)
	desk._desk.add_child(desk._archive_win)
	desk.windows._place_z(desk._archive_win, Desktop.ZR_WIN)
	desk.windows._place_floating_windows()
	_clear_archive_new()
	for sid in desk.graph.timeline_known():
		desk.graph.clear_fresh(desk.graph.scene_key(String(sid)))


func _on_archive_time(tid: String) -> void:
	_select_time(tid)


func _try_memory_combo(tool_key: String, target_key: String, before: Dictionary) -> bool:
	if desk.graph == null or desk.case_def == null or desk.graph.time == GraphState.PRESENT_TIME:
		return false
	var tool := desk.graph.node(tool_key)
	var target := desk.graph.node(target_key)
	if tool.is_empty() or target.is_empty():
		return false
	var who: Dictionary = {}
	var where: Dictionary = {}
	var where_key := ""
	if String(tool["kind"]) == "char":
		who = tool
	elif String(target["kind"]) == "char":
		who = target
	if String(tool["kind"]) == "loc":
		where = tool
		where_key = tool_key
	elif String(target["kind"]) == "loc":
		where = target
		where_key = target_key
	if who.is_empty() or where.is_empty():
		return false
	var mem := desk.case_def.memory_for(desk.graph.time, String(who["id"]), String(where["id"]))
	desk.graph.tried[tool_key + ">" + target_key] = true
	if mem != null:
		_open_memory_play(mem, where_key)
		var title := mem.title if mem.title != "" else mem.id
		desk._show_toast("想起了一段回忆：" + title)
	else:
		desk._show_toast("「%s」里没有「%s」的回忆" % [String(where["label"]), String(who["label"])], true)
	desk.session._commit(before)
	desk.canvas._relayout()
	return true


## 换档 = 改 graph.time → 收掉锚在画布上的浮层 → 带出那天的登场人物 → 重算可见性。
func _select_time(tid: String) -> bool:
	if desk.graph == null or desk.case_def == null:
		return false
	if tid != GraphState.PRESENT_TIME and not desk.case_def.is_time_id(tid):
		return false
	if desk.graph.time == tid:
		if tid != GraphState.PRESENT_TIME:
			_open_time_card(tid)
		return true
	_close_time_transients()
	desk.graph.time = tid
	desk._selected = ""
	desk.graph.selected = ""
	if tid != GraphState.PRESENT_TIME:
		desk.graph.spawn_mem_cast(tid)
	_sync_cards_for_time()
	desk.card_ui._apply_hidden()
	_sync_time_crumb()
	_open_time_card_once(tid)
	desk.session._autosave()
	return true


func _close_time_transients() -> void:
	if desk._pw_pop != null and is_instance_valid(desk._pw_pop):
		desk._pw_pop.queue_free()
	desk._pw_pop = null
	desk._pw_ctx = {}
	if desk._narr != null and is_instance_valid(desk._narr):
		desk._narr.queue_free()
	desk._narr = null
	_close_mem_card()
	_close_chat()


## 把图上已有、但还没上过画布的实体补成卡片；已存在的只刷新（时刻切换不重排）。
func _sync_cards_for_time() -> void:
	for key in desk.graph.nodes.keys():
		var n := desk.graph.node(String(key))
		if n.is_empty() or String(n["kind"]) == "time":
			continue
		if desk._cards.has(String(key)):
			(desk._cards[String(key)] as NodeCard).refresh()
			desk.canvas._sync_card_shell(desk._cards[String(key)])
		else:
			desk.canvas._spawn_card(String(key))


func _sync_time_crumb() -> void:
	if desk.graph.time != GraphState.PRESENT_TIME:
		desk.session._set_crumb(desk.session._case_label() + " // " + desk.graph.time_label_of())
		return
	var sid := desk.graph.last_scene
	if sid != "":
		desk.session._set_crumb(desk.session._case_label() + " // " + desk.case_def.scene_title(sid))
	else:
		desk.session._set_crumb(desk.session._case_label() + " // " + desk.graph.time_label_of())


## 每档回忆的放映卡只自动放一遍；重放走档案里点当前档。
func _open_time_card_once(tid: String) -> void:
	if tid == GraphState.PRESENT_TIME or not desk.case_def.is_time_id(tid):
		return
	if bool(desk.graph.card_seen.get(tid, false)):
		return
	desk.graph.card_seen[tid] = true
	_open_time_card(tid)
	desk.session._autosave()


func _open_time_card(tid: String) -> void:
	if tid == GraphState.PRESENT_TIME or not desk.case_def.is_time_id(tid):
		return
	_close_mem_card()
	desk._mem_card = MemCard.new()
	desk._mem_card.name = "mem_card"
	desk._mem_card.case_def = desk.case_def
	desk._mem_card.setup_memory("记忆 · " + desk.case_def.time_label_of(tid), _memory_lines(tid))
	desk._mem_card.closed.connect(_on_mem_closed)
	desk._desk.add_child(desk._mem_card)
	_anchor_memory_card(desk._mem_card, tid)
	desk.windows._place_z(desk._mem_card, Desktop.ZR_NARR)


## 放映卡正文 = 日期场景正文（按行拆）+ 该场景里各角色当天的 sceneTalks。
func _memory_lines(tid: String) -> Array:
	var out: Array = []
	var s := desk.case_def.scene_of(tid)
	if s == null:
		return out
	var body := s.content if s.content.strip_edges() != "" else s.desc
	for raw in body.split("\n"):
		var line := String(raw).strip_edges()
		if line != "":
			out.append(line)
	for tag in desk.case_def.nodes_of_scene(s):
		if String(tag["kind"]) != "char":
			continue
		var cid := String(tag["id"])
		var ch := desk.case_def.char_of(cid)
		if ch == null:
			continue
		for st in ch.scene_talks:
			if st == null or st.scene == null or st.scene.id != tid:
				continue
			for raw in st.lines:
				var talk_line := String(raw).strip_edges()
				if talk_line != "":
					out.append("——%s：%s" % [ch.name, talk_line])
	return out


func _memory_play_lines(mem: MemoryDef) -> Array:
	var out: Array = []
	for line in mem.script_lines:
		if line == null:
			continue
		var text := String(line.text).strip_edges()
		if text == "":
			continue
		var kind := "say" if line.kind == "say" else "narr"
		var who_id := line.who.id if line.who != null else ""
		var who_name := line.who.name if line.who != null else ""
		out.append({"t": kind, "text": text, "who": who_id, "name": who_name})
	return out


func _open_memory_play(mem: MemoryDef, where_key: String) -> void:
	if mem == null:
		return
	_close_mem_card()
	desk._mem_card = MemCard.new()
	desk._mem_card.name = "mem_card"
	desk._mem_card.case_def = desk.case_def
	var title := mem.title if mem.title != "" else mem.id
	desk._log("想起了一段回忆：%s" % title, "sys")
	desk._mem_card.closed.connect(_on_mem_closed)
	desk._mem_card.playback_completed.connect(_on_memory_playback_completed)
	desk._mem_card.setup_play("记忆 · " + title, _memory_play_lines(mem), 420, 300, "char", mem.id)
	desk._desk.add_child(desk._mem_card)
	_anchor_card_to(desk._mem_card, where_key)
	desk.windows._place_z(desk._mem_card, Desktop.ZR_NARR)


## 锚在该时刻的发生地点上方；上方放不下就放下面，再整体钳进桌面。
func _anchor_memory_card(card: MemCard, tid: String) -> void:
	var place := desk.case_def.mem_place_of(tid)
	_anchor_card_to(card, desk.graph.scene_key(place.id) if place != null else "")

## 锚定时的「锚点节点」：节点还在重排补间里飞的时候锚出来的位置是**中途位置**，
## 补间一结束就对不上（实测 448×328 的放映卡压住花园节点）。补间收尾时按新位置重锚。


func _anchor_card_to(card: MemCard, node_key: String) -> void:
	if card == null:
		return
	_mem_anchor_key = node_key
	desk._wake_process()
	var area := Vector2(desk._vw(), desk._vh() - Desktop.HEADER_H)
	var pos := Vector2(700.0, 290.0)
	var nc := desk._cards.get(node_key) as NodeCard
	if nc != null and is_instance_valid(nc) and nc.visible:
		var origin := desk._desk.get_global_rect().position
		var g := nc.get_global_rect()
		var t := Rect2(g.position - origin, g.size)
		var cs := card.size
		var cx := t.position.x + (t.size.x - cs.x) * 0.5
		var cy := t.position.y + (t.size.y - cs.y) * 0.5
		## 四方位按「上 → 下 → 右 → 左」试，取第一个既不越界、也不压住其它可见卡的位置。
		## 720 基准下桌面只剩 668 高：放映卡（448×328）与节点都居中时，
		## 单靠「上/下」二选一必然压住节点（上方局部 −9 越界、下方 742 越界，
		## 钳回 332 之后正好盖住地点卡）。Web 是流式布局，没这个死角。
		var cands: Array = [
			Vector2(cx, t.position.y - cs.y - 14.0),
			Vector2(cx, t.position.y + t.size.y + 14.0),
			Vector2(t.position.x + t.size.x + 14.0, cy),
			Vector2(t.position.x - cs.x - 14.0, cy),
		]
		var board := Rect2(Vector2(8, 8), area - Vector2(16, 16))
		var picked := Vector2.INF
		for c in cands:
			var r := Rect2(c, cs)
			if board.encloses(r) and not _mem_blocked(r, node_key):
				picked = c
				break
		if not picked.is_finite():
			## 四方位都塞不下：720 基准下桌面只有 668 高，448×328 的放映卡与居中节点
			## 垂直方向正好差几像素（上方 −9、下方 742）。这时把卡压到「上方可用高」以内
			## 再贴顶放下 —— 内容区本来就有滚动条，少 17px 视觉无感。
			var avail_h := maxf(180.0, t.position.y - 8.0 - 14.0)
			if avail_h < cs.y:
				card.set_inner_height(avail_h - SysWindow.PAD * 2.0)
				cs = card.size
			picked = Vector2(cx, t.position.y - cs.y - 14.0)
		pos = picked
	pos.x = clampf(pos.x, Desktop.MEM_CARD_MIN_X, area.x - card.size.x - 8.0)
	pos.y = clampf(pos.y, 8.0, area.y - card.size.y - 8.0)
	card.position = pos


## 回忆卡候选位是否压住别的可见节点（浮窗不算 —— 那本就允许被压）。
func _mem_blocked(r: Rect2, skip_key: String) -> bool:
	var origin := desk._desk.get_global_rect().position
	for k in desk._cards.keys():
		if String(k) == skip_key:
			continue
		var c := desk._cards[k] as NodeCard
		if c == null or not is_instance_valid(c) or not c.visible:
			continue
		var g := c.get_global_rect()
		if r.intersects(Rect2(g.position - origin, g.size)):
			return true
	return false


func _close_mem_card() -> void:
	if desk._mem_card != null and is_instance_valid(desk._mem_card):
		desk._mem_card.queue_free()
	desk._mem_card = null


func _on_mem_closed() -> void:
	desk._mem_card = null


func _close_chat() -> void:
	if desk._chat_win != null and is_instance_valid(desk._chat_win):
		desk._chat_win.queue_free()
	desk._chat_win = null


func _on_chat_closed() -> void:
	desk._chat_win = null


## 对话窗固定贴右上（Web `.chat-win`：right 18 / top 72；desk 已让出 header，再减 PAD 14）。
func _open_chat(entry: DialogueDef, ids: Array, reveal_all := false,
		title_override := "") -> bool:
	if entry == null or desk.case_def == null:
		return false
	_close_chat()
	desk._chat_win = ChatWindow.new()
	desk._chat_win.name = "chat_win"
	## 先接线再 setup：独白是「整段一次贴出」，playback_completed 会在 setup 内同步发射。
	desk._chat_win.closed.connect(_on_chat_closed)
	desk._chat_win.playback_completed.connect(_on_dialogue_playback_completed)
	desk._chat_win.setup_chat(entry, ids, desk.case_def, reveal_all, title_override)
	desk._desk.add_child(desk._chat_win)
	desk.windows._place_z(desk._chat_win, Desktop.ZR_CHAT)
	desk.windows._place_floating_windows()
	return true


## 独白 = 整段台词一次贴出；不像多人对话那样等玩家逐句点。
func _open_monologue(char_id: String) -> bool:
	if desk.dialogues == null:
		return false
	var entry := desk.dialogues.monologue_of(char_id)
	if entry == null:
		return false
	return _open_chat(entry, [char_id], true)


## 人物对物品 / 线索的反应：仍进独白窗，但标题带上反应对象；
## 单句反应一次贴完，不再只写进案卷让玩家错过。
func _open_reaction_monologue(char_id: String, text: String, trigger_label: String) -> bool:
	if char_id == "" or text.strip_edges() == "" or desk.case_def == null:
		return false
	## 正在播多人对话时不抢窗；反应仍保留在案卷与画布产出里。
	if desk._chat_win != null and is_instance_valid(desk._chat_win) and not desk._chat_win.is_monologue():
		return false
	var ch := desk.case_def.char_of(char_id)
	if ch == null:
		return false
	var entry := DialogueDef.new()
	var parts: Array[CharDef] = [ch]
	entry.participants = parts
	var line := DialogueLineDef.new()
	line.kind = "say"
	line.who = ch
	line.text = text
	entry.script_lines.append(line)
	var tail := "对「%s」的反应" % trigger_label if trigger_label != "" else "反应"
	return _open_chat(entry, [char_id], true, "独白 · %s · %s" % [ch.name, tail])


## 把一条证据落到画布。已存在（含在「物品」里）就复用，不再刷「新」。
func _grant_evidence(ev: EvidenceDef, from_key: String = "", x: float = -1.0,
		y: float = -1.0) -> String:
	if ev == null or desk.case_def == null or desk.graph == null:
		return ""
	var existed := desk.graph.has("evidence", ev.id)
	var key := desk.graph.capture_evidence(ev.id, from_key, x, y)
	if key == "":
		return ""
	if not existed:
		var n := desk.graph.node(key)
		desk.canvas._refresh_or_spawn_card(key)
		desk.canvas._relayout()
		desk._log("获得证据「%s」" % String(n.get("label", ev.label)), "cap")
		desk._show_toast("获得证据：" + String(n.get("label", ev.label)))
		desk.tec._tec_teach_evidence()
	return key


## 一次掉一组证据，返回实际新增的 key 列表（已存在的跳过）。
func _grant_evidences(evs: Array, from_key: String = "") -> Array:
	var out: Array = []
	for raw in evs:
		var ev := raw as EvidenceDef
		if ev == null:
			continue
		if desk.graph != null and desk.graph.has("evidence", ev.id):
			continue
		var key := _grant_evidence(ev, from_key)
		if key != "":
			out.append(key)
	return out


func _on_dialogue_playback_completed(id: String) -> void:
	if id == "" or desk.dialogues == null or desk.graph == null:
		return
	var d := desk.dialogues.by_id(id)
	if d == null or d.drops_evidence.is_empty():
		return
	var before := desk._save.snapshot()
	if not _grant_evidences(d.drops_evidence).is_empty():
		desk.session._commit(before)


func _on_memory_playback_completed(id: String) -> void:
	if id == "" or desk.case_def == null or desk.graph == null:
		return
	for m in desk.case_def.memories:
		if m == null or m.id != id or m.drops_evidence.is_empty():
			continue
		var from_key := desk.graph.key_of("char", m.who.id) if m.who != null else ""
		if from_key != "" and not desk.graph.nodes.has(from_key):
			from_key = desk.graph.scene_key(m.where.id) if m.where != null else ""
		var before := desk._save.snapshot()
		if not _grant_evidences(m.drops_evidence, from_key).is_empty():
			desk.session._commit(before)
		return


func _try_dialogue_combo(tool_key: String, target_key: String) -> bool:
	if desk.dialogues == null:
		return false
	var a := desk.graph.node(tool_key)
	var b := desk.graph.node(target_key)
	if a.is_empty() or b.is_empty():
		return false
	if String(a["kind"]) != "char" or String(b["kind"]) != "char":
		return false
	var ids := [String(a["id"]), String(b["id"])]
	var entry := desk.dialogues.lookup(ids)
	if entry == null:
		entry = desk.dialogues.fallback(ids)
	return _open_chat(entry, ids)


func _chat_drop_hit(at_global: Vector2) -> bool:
	var chat := desk._chat_win
	return chat != null and chat.get_global_rect().has_point(at_global)


func _chat_drop(key: String) -> bool:
	var chat := desk._chat_win
	if chat == null or desk.graph == null:
		return false
	var n := desk.graph.node(key)
	if n.is_empty():
		return false
	return chat.drop_node(String(n["kind"]), String(n["id"]))


func _mark_archive_new() -> void:
	desk._archive_new = true
	if desk._archive_badge != null:
		desk._archive_badge.visible = true


func _clear_archive_new() -> void:
	desk._archive_new = false
	if desk._archive_badge != null:
		desk._archive_badge.visible = false
