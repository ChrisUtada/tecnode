class_name MatrixState
extends RefCounted
## 推演桌布的领域状态：五感槽位 + 已达成结局。
##
## 只存数据与判定，不碰节点表 / 收纳去向 —— 那些是 GraphState 的职责。
## `slots` 与旧版 `GraphState.matrix` 同构（sense -> Array[clue id]），
## 因此 `format: 1` 存档的 `matrix` / `endings` 字段无需迁移。

const MATRIX := "MATRIX"

## 五感顺序与显示名（Web 版 SENSES 的键序 —— 排序、遍历都按它来）
const SENSES := ["vision", "hearing", "touch", "smell", "taste"]
const SENSE_NAMES := {
	"vision": "视觉", "hearing": "听觉", "touch": "触觉",
	"smell": "嗅觉", "taste": "味觉",
}

var slots: Dictionary = {}
var endings: Dictionary = {}      # 已达成结局 id -> true


func _init() -> void:
	reset()


func reset() -> void:
	slots = {}
	for sense in SENSES:
		slots[sense] = []
	endings.clear()


func has_sense(sense: String) -> bool:
	return slots.has(sense)


## 归位到某感官槽位；已在槽内 / 感官不存在时返回 false。
## 一条线索只占一个槽位，换槽会先从旧槽移除。
func assign(id: String, sense: String) -> bool:
	if id == "" or not slots.has(sense):
		return false
	var list: Array = slots[sense]
	if list.has(id):
		return false
	remove(id)
	list.append(id)
	return true


func remove(id: String) -> void:
	for sense in SENSES:
		(slots[sense] as Array).erase(id)


func clear() -> void:
	for sense in SENSES:
		slots[sense] = []


func ids() -> Array:
	var out: Array = []
	for sense in SENSES:
		out.append_array(slots.get(sense, []))
	return out


func count() -> int:
	return ids().size()


func has(id: String) -> bool:
	return ids().has(id)


func slot_of(id: String) -> String:
	for sense in SENSES:
		if (slots.get(sense, []) as Array).has(id):
			return sense
	return ""


## 推演判定：当前槽位里的线索**恰好**等于某条结局的配方（Web 版 executeInference 同口径）。
## 数据顺序优先（ENDINGS.find 的等价实现），返回第一个命中的 EndingDef，否则 null。
func match_ending(case_def: CaseLoader) -> EndingDef:
	if case_def == null:
		return null
	var ids_now := {}
	for id in ids():
		ids_now[String(id)] = true
	for ending in case_def.endings:
		if ending == null or ending.recipe.size() != ids_now.size():
			continue
		var all := true
		for clue in ending.recipe:
			if clue == null or not ids_now.has(clue.id):
				all = false
				break
		if all:
			return ending
	return null


func mark_ending(id: String) -> void:
	if id != "":
		endings[id] = true


func achieved(id: String) -> bool:
	return endings.has(id)


## 存档同构视图：返回副本，供 SaveSystem 序列化。
func to_dict() -> Dictionary:
	var out := {}
	for sense in SENSES:
		out[sense] = (slots.get(sense, []) as Array).duplicate()
	return out


## 从旧档恢复；缺失感官补空槽，未知键忽略。
func from_dict(data) -> void:
	slots = {}
	for sense in SENSES:
		var list = (data as Dictionary).get(sense, []) if data is Dictionary else []
		slots[sense] = (list as Array).duplicate() if list is Array else []
