class_name DialogueSystem
extends RefCounted
## 多人对话查询（对齐 Web `11-dialog.js` 的语境匹配）：
## 剧本可绑定 when × where；没写语境 = 通用，写了但当前对不上 = 不播。

var case_def: CaseLoader
var graph: GraphState


func _init(p_case: CaseLoader, p_graph: GraphState) -> void:
	case_def = p_case
	graph = p_graph


func context() -> Dictionary:
	var t := graph.time if graph != null else GraphState.PRESENT_TIME
	if t == "" or t == GraphState.PRESENT_TIME:
		return {}
	var here := case_def.mem_place_of(t)
	return {"when": t, "where": here.id if here != null else ""}


func dialogue_fit(d: DialogueDef, ctx = null) -> String:
	if d == null:
		return "miss"
	var when := d.context_when.id if d.context_when != null else ""
	var where := d.context_where.id if d.context_where != null else ""
	if when == "" and where == "":
		return "free"
	if ctx == null or (ctx as Dictionary).is_empty() or when != String(ctx.get("when", "")):
		return "miss"
	var ctx_where := String(ctx.get("where", ""))
	if where != "" and ctx_where != "" and where != ctx_where:
		return "miss"
	return "fit"


func by_id(id: String) -> DialogueDef:
	for d in case_def.dialogues:
		if d.id == id:
			return d
	return null


func participant_ids(d: DialogueDef) -> Array:
	var out: Array = []
	if d == null:
		return out
	for c in d.participants:
		if c != null:
			out.append(c.id)
	return out


func set_key(ids: Array) -> String:
	var sorted := ids.duplicate()
	sorted.sort()
	return "|".join(sorted)


func pick(list: Array, ctx = null) -> DialogueDef:
	for d in list:
		if dialogue_fit(d, ctx) == "fit":
			return d
	for d in list:
		if dialogue_fit(d, ctx) == "free":
			return d
	return null


func lookup(ids: Array, ctx = null) -> DialogueDef:
	if ctx == null:
		ctx = context()
	var key := set_key(ids)
	var exact: Array = []
	for d in case_def.dialogues:
		if set_key(participant_ids(d)) == key:
			exact.append(d)
	var hit := pick(exact, ctx)
	if hit != null:
		return hit
	var loose: Array = []
	for d in case_def.dialogues:
		if exact.has(d):
			continue
		var pool := participant_ids(d)
		var all := true
		for id in ids:
			if not pool.has(id):
				all = false
				break
		if all:
			loose.append(d)
	return pick(loose, ctx)


func blocked(ids: Array, ctx = null) -> bool:
	if ctx == null:
		ctx = context()
	for d in case_def.dialogues:
		var pool := participant_ids(d)
		var all := true
		for id in ids:
			if not pool.has(id):
				all = false
				break
		if all and dialogue_fit(d, ctx) == "miss":
			return true
	return false


func monologue_of(char_id: String, ctx = null) -> DialogueDef:
	if ctx == null:
		ctx = context()
	var list: Array = []
	for d in case_def.dialogues:
		var pool := participant_ids(d)
		if pool.size() == 1 and String(pool[0]) == char_id:
			list.append(d)
	return pick(list, ctx)


func has_monologue(char_id: String) -> bool:
	return monologue_of(char_id) != null


func fallback(ids: Array, ctx = null) -> DialogueDef:
	if ctx == null:
		ctx = context()
	var d := DialogueDef.new()
	d.id = ""
	for id in ids:
		var ch := case_def.char_of(String(id))
		if ch != null:
			d.participants.append(ch)
	var line := DialogueLineDef.new()
	line.kind = "narr"
	line.text = "此刻他们没什么可说的。" if blocked(ids, ctx) else "他们没什么可说的。"
	d.script_lines.append(line)
	return d
