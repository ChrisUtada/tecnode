class_name TimelineState
extends RefCounted
## 时间轴 / 玩家知识时间线的领域状态。
##
## 只存「现在处于哪一刻」与两个记录玩家阅知程度的集合；由 case_def 派生
## 的可见集 / 登场点仍留在 GraphState（它们要读场景与回忆数据）。

const PRESENT := "present"

var time: String = PRESENT
## 时刻 -> true（玩家读过该时刻的放映卡，不再自动重放）
var card_seen: Dictionary = {}
## 人物 id -> true（登场置位）
var debuted: Dictionary = {}


func reset() -> void:
	time = PRESENT
	card_seen.clear()
	debuted.clear()


func is_present() -> bool:
	return time == PRESENT


func set_time(t: String) -> void:
	time = t if t != "" else PRESENT


func mark_seen(t: String) -> void:
	if t != "":
		card_seen[t] = true


func seen(t: String) -> bool:
	return card_seen.has(t)


func debut(id: String) -> void:
	if id != "":
		debuted[id] = true


func has_debuted(id: String) -> bool:
	return debuted.has(id)
