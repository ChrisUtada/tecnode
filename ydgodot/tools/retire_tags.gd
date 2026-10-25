extends SceneTree
## 一次性迁移：§7 标签退役。
## - 正文里的 [item:/loc:/char:/clue:/data:] 换成显示名（或换行），逻辑只走结构化字段；
## - clue 标签的 id 迁到宿主 hidden_clue.clues / 命令 clues / 反应 clues；
## - sceneTalks 里的 clue 归到对应场景 hidden_clue；talkQueue 归到人物 hidden_clue。
## 保留资源上的其它手写字段（role/fate/relation、node_* 等），不像 json_to_tres 那样重建。
##
## 运行：godot --headless --path ydgodot --script res://tools/retire_tags.gd

const CASE_PATH := "res://cases/a001/case.tres"

var case_def: CaseDef
var by_item := {}
var by_char := {}
var by_scene := {}
var by_evidence := {}
var tag_re: RegEx
var changed := 0


func _initialize() -> void:
	case_def = load(CASE_PATH) as CaseDef
	if case_def == null:
		push_error("加载不了 " + CASE_PATH)
		quit(1)
		return
	tag_re = RegEx.new()
	tag_re.compile("\\[(item|loc|char|clue|data):([^\\]]+)\\]")
	for it in case_def.items:
		by_item[it.id] = it
	for ch in case_def.chars:
		by_char[ch.id] = ch
	for s in case_def.scenes:
		by_scene[s.id] = s
	for cl in case_def.clues:
		by_evidence[cl.id] = cl

	for s in case_def.scenes:
		_process_host(s)
		for cmd in s.commands:
			_process_command(cmd)
	for it in case_def.items:
		_process_host(it)
		for cmd in it.commands:
			_process_command(cmd)
		for ex in it.excerpts:
			_clean_into(ex, "text", [])
	for ch in case_def.chars:
		_process_char(ch)
	for cl in case_def.clues:
		_clean_into(cl, "desc", [])
	for dlg in case_def.dialogues:
		for line in dlg.script_lines:
			_clean_into(line, "text", [])
	for mem in case_def.memories:
		for line in mem.script_lines:
			_clean_into(line, "text", [])
	for e in case_def.endings:
		_clean_into(e, "message", [])
		for line in e.lines:
			_clean_into(line, "text", [])

	_save_all()
	print("=== 标签退役完成：修改 %d 个资源 ===" % changed)
	quit(0)


func _process_host(host: Resource) -> void:
	var ids: Array = []
	_clean_into(host, "content", ids)
	_clean_into(host, "desc", ids)
	_clean_into(host, "lit_on_message", ids)
	_clean_into(host, "lit_off_message", ids)
	_clean_into(host, "lit_fail_message", ids)
	var hc = host.get("hidden_clue")
	if hc != null:
		_clean_into(hc, "text", ids)
	if not ids.is_empty():
		_ensure_hidden(host, ids)


func _process_char(ch: CharDef) -> void:
	var ids: Array = []
	_clean_into(ch, "desc", ids)
	if ch.hidden_clue != null:
		_clean_into(ch.hidden_clue, "text", ids)
	for i in ch.talk_queue.size():
		var line := String(ch.talk_queue[i])
		var got: Array = []
		var clean := _clean_text(line, got)
		if clean != line:
			ch.talk_queue[i] = clean
			ch.set_meta("changed", true)
		ids.append_array(got)
	for st in ch.scene_talks:
		if st == null:
			continue
		var sids: Array = []
		for i in st.lines.size():
			var line := String(st.lines[i])
			var got: Array = []
			var clean := _clean_text(line, got)
			if clean != line:
				st.lines[i] = clean
				ch.set_meta("changed", true)
			sids.append_array(got)
		if st.scene != null and not sids.is_empty():
			_ensure_hidden(st.scene, sids)
	for r in ch.clue_reactions:
		_process_reaction(r)
	for r in ch.item_reactions:
		_process_reaction(r)
	if not ids.is_empty():
		_ensure_hidden(ch, ids)


func _process_reaction(r: ReactionDef) -> void:
	if r == null:
		return
	var ids: Array = []
	_clean_into(r, "text", ids)
	if not ids.is_empty():
		_append_clues(r, ids)


func _process_command(cmd: CommandDef) -> void:
	if cmd == null:
		return
	var ids: Array = []
	_clean_into(cmd, "fail_message", [])
	if cmd is TextCommandDef:
		_clean_into(cmd, "value", ids)
	elif cmd is ChoiceCommandDef:
		var cc := cmd as ChoiceCommandDef
		_clean_into(cc, "title", [])
		_clean_into(cc, "prompt", [])
		for o in cc.options:
			if o == null:
				continue
			_clean_into(o, "label", [])
			_clean_into(o, "message", [])
			_process_payload(o.payload)
	elif cmd is ConditionalCommandDef:
		var kc := cmd as ConditionalCommandDef
		_clean_into(kc, "success_message", ids)
		for c in kc.conditions:
			if c != null:
				_clean_into(c, "fail_message", [])
		_process_payload(kc.on_success)
	elif cmd is UseItemCommandDef:
		var uc := cmd as UseItemCommandDef
		_clean_into(uc, "success_message", ids)
		_process_payload(uc.on_success)
	elif cmd is PasswordCommandDef:
		_process_payload((cmd as PasswordCommandDef).on_success)
	elif cmd is RevealCommandDef:
		_clean_into(cmd, "value", ids)
	if not ids.is_empty():
		_append_clues(cmd, ids)


func _process_payload(p: PayloadDef) -> void:
	if p == null:
		return
	var ids: Array = []
	_clean_into(p, "message", ids)
	if not ids.is_empty():
		_append_clues(p, ids)


func _clean_into(obj: Object, prop: String, ids: Array) -> void:
	if obj == null:
		return
	var raw = obj.get(prop)
	if not (raw is String) or String(raw) == "":
		return
	var got: Array = []
	var clean := _clean_text(String(raw), got)
	if clean != String(raw):
		obj.set(prop, clean)
		_mark(obj)
	ids.append_array(got)


func _clean_text(raw: String, ids: Array) -> String:
	var s := raw.replace("<br />", "\n").replace("<br/>", "\n").replace("<br>", "\n")
	var out := ""
	var last := 0
	for m in tag_re.search_all(s):
		out += s.substr(last, m.get_start() - last)
		var kind := String(m.get_string(1))
		var id := String(m.get_string(2))
		if kind == "clue" or kind == "data":
			if not ids.has(id):
				ids.append(id)
		out += _label(kind, id)
		last = m.get_end()
	out += s.substr(last)
	return out


func _label(kind: String, id: String) -> String:
	match kind:
		"item":
			var it: ItemDef = by_item.get(id)
			return it.label if it != null else id
		"char":
			var ch: CharDef = by_char.get(id)
			return ch.name if ch != null else id
		"loc":
			var s: SceneDef = by_scene.get(id)
			return s.title if s != null else id
		"clue", "data", "evidence":
			var cl: EvidenceDef = by_evidence.get(id)
			return cl.label if cl != null else id
	return id


func _ensure_hidden(host: Resource, ids: Array) -> void:
	var hc = host.get("hidden_clue")
	if hc == null:
		hc = HiddenClueDef.new()
		host.set("hidden_clue", hc)
		_mark(host)
	_append_clues(hc, ids)


func _append_clues(obj: Object, ids: Array) -> void:
	var refs = obj.get("clues")
	if not (refs is Array):
		refs = []
	var changed_now := false
	for id in ids:
		var cl: EvidenceDef = by_evidence.get(String(id))
		if cl == null:
			continue
		var exists := false
		for r in refs:
			if r is EvidenceDef and (r as EvidenceDef).id == cl.id:
				exists = true
				break
		if not exists:
			refs.append(cl)
			changed_now = true
	if changed_now:
		obj.set("clues", refs)
		_mark(obj)


func _mark(_obj: Object) -> void:
	changed += 1


func _save_all() -> void:
	var seen := {}
	for arr in [case_def.scenes, case_def.items, case_def.chars, case_def.clues,
			case_def.memories, case_def.dialogues, case_def.endings]:
		for res in arr:
			_save_res(res, seen)
	_save_res(case_def, seen)


func _save_res(res: Resource, seen: Dictionary) -> void:
	if res == null:
		return
	var rid := res.get_instance_id()
	if seen.has(rid):
		return
	seen[rid] = true
	## 子资源（HiddenClueDef / 命令 / 反应）的修改不会自动让父资源变脏；
	## 这里统一重写全部宿主，保证 hidden_clue.text 与结构化 clues 一起落盘。
	var err := ResourceSaver.save(res, res.resource_path)
	if err != OK:
		push_error("保存失败 %s：%d" % [res.resource_path, err])
