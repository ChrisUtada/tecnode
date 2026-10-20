class_name DialogueSession
extends RefCounted
## 多人对话的纯状态机：谁在场 / 下一句 / 是否在等某人加入。
## 界面只负责把 step() 返回的行画出来，推进规则可单独测试。

var entry: DialogueDef
var joined: Array = []
var index := 0
var waiting_for := ""
var done := false


func _init(p_entry: DialogueDef = null, initial_ids: Array = []) -> void:
	entry = p_entry
	for id in initial_ids:
		var sid := String(id)
		if sid != "" and not joined.has(sid):
			joined.append(sid)


func total() -> int:
	return entry.script_lines.size() if entry != null else 0


func is_joined(id: String) -> bool:
	return joined.has(id)


func step() -> Dictionary:
	if done or entry == null:
		return {"status": "done"}
	if index >= total():
		done = true
		return {"status": "done"}
	var line := entry.script_lines[index]
	var who := line.who.id if line.who != null else ""
	if line.kind == "say" and who != "" and not joined.has(who):
		waiting_for = who
		return {"status": "wait", "who": who}
	index += 1
	waiting_for = ""
	return {"status": "line", "line": line}


func join(char_id: String) -> Dictionary:
	if joined.has(char_id):
		return {"ok": false, "reason": "joined"}
	if waiting_for == "":
		return {"ok": false, "reason": "not_waiting"}
	if waiting_for != char_id:
		return {"ok": false, "reason": "wrong"}
	joined.append(char_id)
	waiting_for = ""
	return {"ok": true}


func state() -> Dictionary:
	var participants: Array = []
	if entry != null:
		for c in entry.participants:
			if c != null:
				participants.append(c.id)
	return {
		"id": entry.id if entry != null else "",
		"when": entry.context_when.id if entry != null and entry.context_when != null else "",
		"participants": participants,
		"joined": joined.duplicate(),
		"idx": index,
		"total": total(),
		"waitingFor": waiting_for,
		"done": done,
	}
