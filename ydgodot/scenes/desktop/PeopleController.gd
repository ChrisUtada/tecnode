class_name PeopleController
extends Node
## 由 Desktop 挂载的子系统控制器。
## 过渡期直接通过注入的 `desk` 访问宿主成员；搬出的函数名保持不变。

var desk: Desktop


## 名册：Web `people-win`（right 328 / top 60 / 宽 324）—— 紧挨详情窗左侧，列表与详情成一对。
## 宽 324 = 300 + 头像加大的 24px：文本列净宽与 24×24 时代一致，描述不会被压窄。
func _toggle_people() -> void:
	if not desk.session._require_case():
		return
	if desk._people_win != null and is_instance_valid(desk._people_win):
		_close_person_card()
		desk._people_win.queue_free()
		desk._people_win = null
		return
	desk._people_win = PeopleWin.new()
	desk._people_win.name = "people_win"
	desk._people_win.setup_people(desk.graph, desk.case_def, 324.0, 399.0, desk._investigator)
	# 定位按 Web 的 right / top 算，并且跟着**实际尺寸**走（size 含 PAD 的投影余量）
	desk._people_win.position = Vector2(desk._vw() - 328.0 - desk._people_win.size.x + SysWindow.PAD, 60.0)
	desk._people_win.row_clicked.connect(_on_people_row)
	desk._people_win.closed.connect(func():
		desk._people_win = null
		_close_person_card())
	desk._desk.add_child(desk._people_win)
	desk.windows._place_z(desk._people_win, Desktop.ZR_WIN)


func _refresh_people_win() -> void:
	if desk._people_win != null and is_instance_valid(desk._people_win):
		desk._people_win.refresh_people()


## 名册点行 = 打开人物档案卡（PEOPLE_CARD_PLAN）。跳转/叫人降级为卡内「前往此人」。
func _on_people_row(id: String) -> void:
	if not desk.session._require_case():
		return
	_open_person_card(id)


func _person_card_blocks(at_global: Vector2) -> bool:
	return desk._people_card != null and is_instance_valid(desk._people_card) \
		and desk._people_card.visible and desk._people_card.get_global_rect().has_point(at_global)


func _close_person_card() -> void:
	if desk._people_card != null and is_instance_valid(desk._people_card):
		desk._people_card.commit_note()
		desk._people_card.queue_free()
	desk._people_card = null


func _open_person_card(id: String) -> void:
	if desk.graph == null or desk.case_def == null:
		return
	var payload := _person_payload(id)
	if payload.is_empty():
		return
	_close_person_card()
	desk._people_card = Desktop.PersonCardScript.new()
	desk._people_card.setup_card(payload)
	desk._people_card.closed.connect(_close_person_card)
	desk._people_card.action_requested.connect(_on_person_action)
	desk._people_card.note_changed.connect(_on_person_note_changed)
	desk._people_card.note_committed.connect(_on_person_note_committed)
	desk._people_card.field_word_selected.connect(_on_person_field_word)
	desk._people_card.field_check_requested.connect(_check_person_claims)
	desk._desk.add_child(desk._people_card)
	desk.windows._place_z(desk._people_card, Desktop.ZR_PERSON)
	_place_person_card()


func _place_person_card() -> void:
	if desk._people_card == null or not is_instance_valid(desk._people_card) or desk._desk == null:
		return
	var desk_w := desk._desk.size.x
	var desk_h := desk._desk.size.y
	## 玩家拖过就保留位置；resize 只钳回桌面，不再贴回右上。
	if desk._people_card.user_placed():
		var kept: Vector2 = desk._people_card.position
		kept.x = clampf(kept.x, 12.0, maxf(12.0, desk_w - desk._people_card.size.x - 12.0))
		kept.y = clampf(kept.y, 12.0, maxf(12.0, desk_h - desk._people_card.size.y - 12.0))
		desk._people_card.position = kept
		return
	var pos := Vector2(maxf(12.0, desk_w - desk._people_card.size.x - 24.0), 60.0)
	if desk._people_win != null and is_instance_valid(desk._people_win):
		pos = Vector2(desk._people_win.position.x - desk._people_card.size.x - 12.0,
			maxf(12.0, desk._people_win.position.y))
	pos.x = clampf(pos.x, 12.0, maxf(12.0, desk_w - desk._people_card.size.x - 12.0))
	pos.y = clampf(pos.y, 12.0, maxf(12.0, desk_h - desk._people_card.size.y - 12.0))
	desk._people_card.position = pos


func _on_person_action(id: String) -> void:
	_close_person_card()
	if id == GraphState.INVESTIGATOR_ID:
		desk.session._open_cert_review()
	elif id == "CHARS_TEC":
		desk.tec._open_tec()
	elif id == "CHARS_EXEC":
		desk.launcher._open_matrix()
	else:
		desk.canvas._goto_char(id)


func _on_person_note_changed(id: String, text: String) -> void:
	if desk.graph == null or id == "":
		return
	if text.strip_edges() == "":
		desk.graph.notes.erase(id)
	else:
		desk.graph.notes[id] = text
	desk.session._queue_autosave()


func _on_person_note_committed(id: String, text: String) -> void:
	_on_person_note_changed(id, text)
	desk.session._autosave()


func _person_payload(id: String) -> Dictionary:
	if id == GraphState.INVESTIGATOR_ID:
		if desk._investigator.is_empty():
			return {}
		var iname := String(desk._investigator.get("name", "调查员"))
		var avatar_id := String(desk._investigator.get("avatarId", ""))
		return {
			"id": id,
			"name": iname,
			"role": "调查员",
			"state": "在册",
			"photo": desk.case_def.avatar_path_of(avatar_id) if desk.case_def != null else "",
			"initial": iname.substr(0, 1) if iname != "" else "?",
			"meta_lines": [
				"编号 · " + String(desk._investigator.get("id", "")),
				"入职 · " + String(desk._investigator.get("date", "")),
				"首次记录 · TEC办公室",
			],
			"note": String(desk.graph.notes.get(id, "")),
			"action": "查看证件",
		}

	var ch := desk.case_def.char_of(id)
	var name_text := id
	var role := ""
	var state := "存活"
	var relation := ""
	var photo := ""
	var first_scene := ""
	if ch != null:
		name_text = ch.name if ch.name != "" else id
		role = ch.role if ch.role != "" else desk.card_ui._first_sentence(ch.desc)
		state = ch.fate if ch.fate != "" else "存活"
		relation = ch.relation
		photo = _person_photo(id, ch)
		var n := desk.graph.node(desk.graph.key_of("char", id))
		if not n.is_empty():
			first_scene = n.home_scene
		if first_scene == "" and ch.debut != null:
			first_scene = ch.debut.id
	elif id == "CHARS_EXEC":
		name_text = "执行者"
		role = "推演执行者"
		state = "待命"
		relation = "长按执行者推演"
		photo = "res://assets/raw/executor-avatar.png"
	if id == "CHARS_TEC":
		role = "AI 助手" if role == "" else role
		state = "在线" if state == "" else state
		photo = "res://assets/raw/tec-avatar.png"
	var first := ""
	if id == "CHARS_TEC":
		first = "T.E.C-OS"
	elif id == "CHARS_EXEC":
		first = "推演桌布"
	if first_scene != "" and desk.case_def.scene_of(first_scene) != null:
		first = desk.case_def.scene_title(first_scene)
	var meta: Array = []
	if first != "":
		meta.append("首次记录 · " + first)
	if relation != "":
		meta.append("关联 · " + relation)
	return {
		"id": id,
		"name": name_text,
		"role": role,
		"state": state,
		"photo": photo,
		"initial": name_text.substr(0, 1) if name_text != "" else "?",
		"meta_lines": meta,
		"note": String(desk.graph.notes.get(id, "")),
		"action": "打开对话窗" if id == "CHARS_TEC" else ("打开推演" if id == "CHARS_EXEC" else "前往此人"),
		"evidence_fields": _person_field_payload(id),
	}


func _person_photo(id: String, ch: CharDef) -> String:
	if desk.case_def != null:
		var path := desk.case_def.avatar_path_of(id)
		if path != "":
			return path
	return CaseLoader.avatar_path_of_def(ch)


## 档案卡关键字段的显示载荷。`correct` 不下发给 UI，避免在卡面 / 调试出口里直接看到答案。
func _person_field_payload(person_id: String) -> Array:
	var out: Array = []
	var ch := desk.case_def.char_of(person_id) if desk.case_def != null else null
	if ch == null:
		return out
	for f in ch.evidence_fields:
		if f == null:
			continue
		var claim := desk.graph.claim_of(person_id, f.id)
		var confirmed := desk.graph.confirmed_field_of(person_id, f.id)
		var state := "empty"
		if not confirmed.is_empty():
			state = "stamped"
		elif String(claim.get("evidence_id", "")) != "":
			state = "pending"
		elif String(claim.get("value", "")) != "":
			state = "draft"
		var ev_id := String(confirmed.get("evidence_id", claim.get("evidence_id", "")))
		out.append({
			"id": f.id,
			"label": f.label,
			"prompt": f.prompt,
			"options": f.options,
			"value": String(confirmed.get("value", claim.get("value", ""))),
			"state": state,
			"evidence_id": ev_id,
			"evidence_label": desk.case_def.label_of("evidence", ev_id) if ev_id != "" else "",
		})
	return out


func _find_evidence_field(person_id: String, field_id: String) -> EvidenceFieldDef:
	var ch := desk.case_def.char_of(person_id) if desk.case_def != null else null
	if ch == null:
		return null
	for f in ch.evidence_fields:
		if f != null and f.id == field_id:
			return f
	return null


func _evidence_tec_message(tier: String) -> String:
	match tier:
		"ci":
			return "词是证言，不用分析——它得先和物拼成「证」。"
		"zheng":
			return "证已经是结论了，不用再分析——把它拖到「证据」或档案字段上。"
	return "证据不需要再分析。"


func _refresh_person_card_fields() -> void:
	if desk._people_card == null or not is_instance_valid(desk._people_card):
		return
	if not desk._people_card.visible:
		return
	desk._people_card.refresh_evidence(_person_field_payload(String(desk._people_card.person_id)))


## 把「证」级证据附到某个人物的关键字段上，进入待核对。
func _assign_evidence_to_field(person_id: String, field_id: String, key: String,
		_source: String = "canvas") -> bool:
	if desk.graph == null or desk.case_def == null:
		return false
	var n := desk.graph.node(key)
	var field := _find_evidence_field(person_id, field_id)
	if n.is_empty() or field == null:
		return false
	var label := n.label if n.label != "" else key
	if desk.graph.is_field_confirmed(person_id, field_id):
		desk.drag._reject_drop("「%s」已经核准，不能再附证据。" % field.label)
		return false
	var kind := n.kind
	if kind == "item":
		desk.drag._reject_drop("「%s」是物，只是原料——先和词合成「证」。" % label)
		return false
	if kind != "evidence":
		desk.drag._reject_drop("只有「证」能填进档案字段。")
		return false
	var tier := n.tier
	if tier != "zheng":
		desk.drag._reject_drop("「%s」是词，只是证言——先和物合成「证」。" % label)
		return false
	var before := desk._save.snapshot()
	desk.graph.set_claim(person_id, field_id, "", n.id)
	_refresh_person_card_fields()
	desk._log("将证据「%s」附到「%s」的「%s」字段，待核对" % [
		label, desk.case_def.char_of(person_id).name if desk.case_def.char_of(person_id) != null else person_id,
		field.label], "act")
	_tec_teach_claim()
	if desk.graph.pending_claim_count(person_id) >= 3:
		_check_person_claims(person_id, before)
	else:
		desk.session._commit(before)
	return true


func _on_person_field_word(person_id: String, field_id: String, value: String) -> void:
	if desk.graph == null or desk.case_def == null:
		return
	var field := _find_evidence_field(person_id, field_id)
	if field == null or desk.graph.is_field_confirmed(person_id, field_id):
		return
	if not field.options.has(value):
		return
	var before := desk._save.snapshot()
	desk.graph.set_claim(person_id, field_id, value)
	_refresh_person_card_fields()
	_tec_teach_claim()
	desk.session._commit(before)


func _tec_teach_claim() -> void:
	if desk.graph == null or desk._tec == null:
		return
	if int(desk.graph.tec_prog.get("_claim_intro", 0)) > 0:
		return
	desk.graph.tec_prog["_claim_intro"] = 1
	## 不抢开 TEC：玩家正在档案卡上选词 / 附证据，TEC 窗压过卡片会打断操作。
	## 台词先存进 TEC，另用一条轻提示把节拍说出来。
	desk._tec.append_line("主张先放着，攒几条我一起核对。")
	desk._show_toast("TEC：主张先放着，攒几条我一起核对。")


## TEC 批量核对：逐条判词条 + 证据，正确的盖章，错误的退回；全部字段核准后掉落人物线索。
func _check_person_claims(person_id: String, before := {}) -> bool:
	if desk.graph == null or desk.case_def == null:
		return false
	var ch := desk.case_def.char_of(person_id)
	var pending := desk.graph.pending_claims(person_id)
	if ch == null or pending.is_empty():
		desk._show_toast("还没有待核对的主张。", true)
		return false
	var snap: Dictionary = before if not before.is_empty() else desk._save.snapshot()
	desk.tec._open_tec()
	desk._tec.finish_typing()
	desk._tec.append_line("核对「%s」的 %d 条主张。" % [ch.name, pending.size()])
	var passed := 0
	var rejected := 0
	for raw_fid in pending.keys():
		var fid := String(raw_fid)
		var field := _find_evidence_field(person_id, fid)
		var claim: Dictionary = pending[raw_fid]
		if field == null:
			desk.graph.clear_claim(person_id, fid)
			continue
		var value := String(claim.get("value", ""))
		var ev_id := String(claim.get("evidence_id", ""))
		var supported := false
		for ev in field.support:
			if ev != null and ev.id == ev_id:
				supported = true
				break
		if value == field.correct and supported:
			desk.graph.confirm_field(person_id, fid, value, ev_id)
			passed += 1
			desk._tec.append_line("「%s」核准：%s。" % [field.label, value])
			desk._log("主张核准：%s · %s = %s" % [ch.name, field.label, value], "act")
		else:
			desk.graph.clear_claim(person_id, fid)
			rejected += 1
			desk._tec.append_line("「%s」这条主张还站不住。词条或证据有一处不对，再看一遍。" % field.label)
			desk._log("主张退回：%s · %s" % [ch.name, field.label], "warn")
	desk._tec.append_line("本轮核对 %d 条：核准 %d，退回 %d。" % [pending.size(), passed, rejected])
	if desk.graph.all_fields_confirmed(person_id):
		_drop_person_completion_clues(person_id)
	_refresh_person_card_fields()
	desk.session._commit(snap)
	return true


## 关键字段全部盖章后，把该人物档案里的演绎证据落到画布（origin=deduce，落地即已捕获）。
func _drop_person_completion_clues(person_id: String) -> void:
	var ch := desk.case_def.char_of(person_id)
	if ch == null:
		return
	var person_key := desk.graph.key_of("char", person_id)
	var names: Array = []
	for f in ch.evidence_fields:
		if f == null or f.drop_clue == null:
			continue
		if desk.graph.captured.has(f.drop_clue.id):
			continue
		var key := desk.graph.capture_evidence(f.drop_clue.id, person_key, -1.0, -1.0, "deduce")
		desk.graph.mark_fresh(key)
		desk.canvas._refresh_or_spawn_card(key)
		names.append(f.drop_clue.label)
		var line := "档案核准：从「%s」的档案里得出人物证据「%s」。（落地即已捕获）" % [
			ch.name, f.drop_clue.label]
		if desk._has_true_name_clue([key]):
			desk._tec.append_true_clue(line)
		else:
			desk._tec.append_line(line)
		desk._log("人物证据「%s」落地（已捕获）" % f.drop_clue.label, "cap")
	if not names.is_empty():
		desk.canvas._relayout()
		desk._show_toast("获得人物证据：" + "、".join(names))
	else:
		desk._tec.append_line("「%s」的档案已经全部核准。" % ch.name)
