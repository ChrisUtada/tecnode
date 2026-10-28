class_name PersonaState
extends RefCounted
## 人物档案的领域状态：备注 / 待核对主张 / 已核准字段 / 对话进度。
##
## 与存档字段一一对应（notes / claims / confirmedFields / talkProg），
## 结构保持不变，旧档可直接读入。

## 人物档案卡备注：id -> 文本（玩家知识，按案件存档；撤销不回滚，读档按存档恢复）
var notes: Dictionary = {}
## 证据主张（待核对）：person_id -> field_id -> {value, evidence_id}。进快照，撤销会回滚。
var claims: Dictionary = {}
## 已核准字段：person_id -> field_id -> {value, evidence_id}。
## 玩家知识：撤销不回滚，读档按存档恢复。
var confirmed_fields: Dictionary = {}
## 人物对话进度：节点 key（`char:ID`）-> 已读条数（P2 对话系统用）
var talk_prog: Dictionary = {}


func reset() -> void:
	notes.clear()
	claims.clear()
	confirmed_fields.clear()
	talk_prog.clear()


func note_of(id: String) -> String:
	return String(notes.get(id, ""))


func set_note(id: String, text: String) -> void:
	if text == "":
		notes.erase(id)
	else:
		notes[id] = text


func claim_of(person_id: String, field_id: String) -> Dictionary:
	var row = claims.get(person_id, null)
	if row is Dictionary:
		return (row as Dictionary).get(field_id, {})
	return {}


func set_claim(person_id: String, field_id: String, value: String = "", evidence_id: String = "") -> void:
	if not claims.has(person_id):
		claims[person_id] = {}
	var row: Dictionary = claims[person_id]
	var old: Dictionary = row.get(field_id, {})
	row[field_id] = {
		"value": value if value != "" else String(old.get("value", "")),
		"evidence_id": evidence_id if evidence_id != "" else String(old.get("evidence_id", "")),
	}


func clear_claim(person_id: String, field_id: String) -> void:
	if not claims.has(person_id):
		return
	var row: Dictionary = claims[person_id]
	row.erase(field_id)
	if row.is_empty():
		claims.erase(person_id)


func pending_claims(person_id: String) -> Dictionary:
	var out := {}
	var row = claims.get(person_id, null)
	if row is Dictionary:
		for fid in (row as Dictionary).keys():
			var claim = (row as Dictionary)[fid]
			if claim is Dictionary and String((claim as Dictionary).get("evidence_id", "")) != "":
				out[String(fid)] = (claim as Dictionary).duplicate(true)
	return out


func pending_claim_count(person_id: String) -> int:
	return pending_claims(person_id).size()


func confirmed_field_of(person_id: String, field_id: String) -> Dictionary:
	var row = confirmed_fields.get(person_id, null)
	if row is Dictionary:
		return (row as Dictionary).get(field_id, {})
	return {}


func is_field_confirmed(person_id: String, field_id: String) -> bool:
	return not confirmed_field_of(person_id, field_id).is_empty()


func confirm_field(person_id: String, field_id: String, value: String, evidence_id: String) -> void:
	if not confirmed_fields.has(person_id):
		confirmed_fields[person_id] = {}
	(confirmed_fields[person_id] as Dictionary)[field_id] = {
		"value": value, "evidence_id": evidence_id,
	}
	clear_claim(person_id, field_id)


## 案件中该人物的证据字段是否已全部盖章。`ch` 为 null 或没有字段时返回 false。
func all_fields_confirmed(ch: CharDef, person_id: String) -> bool:
	if ch == null or ch.evidence_fields.is_empty():
		return false
	for f in ch.evidence_fields:
		if f == null or not is_field_confirmed(person_id, f.id):
			return false
	return true


func talk_of(key: String) -> int:
	return int(talk_prog.get(key, 0))


func set_talk(key: String, n: int) -> void:
	talk_prog[key] = n
