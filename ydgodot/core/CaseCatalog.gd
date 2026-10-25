class_name CaseCatalog
extends RefCounted

const PROGRESS_PATH := "user://tec_progress.json"
const DEFAULT_ID := "A001"

const CASES := [
	{
		"id": "A001", "data_id": "a001", "code": "CASE A-001",
		"title": "植物学家的花园", "note": "异动区域 · 已解锁",
		"path": "res://cases/a001/case.tres",
	},
	{
		"id": "A002", "data_id": "a002", "code": "CASE A-002",
		"title": "？？？？？？", "note": "锁定 · 需在 A-001 捕获真名后解锁",
		"path": "",
	},
]

var path: String = PROGRESS_PATH
var unlocked: Array = [DEFAULT_ID]
var completed: Array = []
var last: String = DEFAULT_ID
var last_error: String = ""


func _init(p_path: String = PROGRESS_PATH) -> void:
	path = p_path
	load_progress()


static func all() -> Array:
	return CASES.duplicate(true)


static func case_by_id(id: String) -> Dictionary:
	for c in CASES:
		if String(c["id"]) == id:
			return c
	return {}


static func exists(id: String) -> bool:
	return not case_by_id(id).is_empty()


static func code_of(id: String) -> String:
	var c := case_by_id(id)
	return String(c.get("code", id))


static func title_of(id: String) -> String:
	var c := case_by_id(id)
	return String(c.get("title", "？？？？？？"))


static func base_note_of(id: String) -> String:
	var c := case_by_id(id)
	return String(c.get("note", ""))


static func path_of(id: String) -> String:
	var c := case_by_id(id)
	return String(c.get("path", ""))


static func data_id_of(id: String) -> String:
	var c := case_by_id(id)
	return String(c.get("data_id", id.to_lower()))


static func data_ready(id: String) -> bool:
	var p := path_of(id)
	return p != "" and ResourceLoader.exists(p)


static func case_id_for_data(data_id: String) -> String:
	for c in CASES:
		if String(c["data_id"]) == data_id or String(c["id"]).to_lower() == data_id.to_lower():
			return String(c["id"])
	return ""


func is_unlocked(id: String) -> bool:
	return unlocked.has(id)


func is_completed(id: String) -> bool:
	return completed.has(id)


func has_save(id: String) -> bool:
	return FileAccess.file_exists(SaveSystem.save_path_for(data_id_of(id)))


func note_for(id: String) -> String:
	if not is_unlocked(id):
		return base_note_of(id)
	if not data_ready(id):
		return "地址已解锁 · 案件数据待接入"
	return base_note_of(id) + (" · 有存档" if has_save(id) else "")


func unlock(id: String) -> bool:
	if not exists(id) or unlocked.has(id):
		return false
	unlocked.append(id)
	save_progress()
	return true


func unlock_next(from_id: String) -> bool:
	for i in CASES.size():
		if String(CASES[i]["id"]) != from_id:
			continue
		if i + 1 >= CASES.size():
			return false
		return unlock(String(CASES[i + 1]["id"]))
	return false


func mark_completed(id: String) -> bool:
	if not exists(id) or completed.has(id):
		return false
	completed.append(id)
	save_progress()
	return true


func load_progress(p_path: String = "") -> bool:
	var target := p_path if p_path != "" else path
	last_error = ""
	unlocked = [DEFAULT_ID]
	completed = []
	last = DEFAULT_ID
	if not FileAccess.file_exists(target):
		return false
	var f := FileAccess.open(target, FileAccess.READ)
	if f == null:
		last_error = "无法读取进度：%s（错误 %d）" % [target, FileAccess.get_open_error()]
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		last_error = "进度文件不是 JSON 对象"
		return false
	var d: Dictionary = parsed
	var raw_unlocked = d.get("unlocked", [])
	if raw_unlocked is Array:
		for raw in raw_unlocked:
			var id := String(raw)
			if exists(id) and not unlocked.has(id):
				unlocked.append(id)
	if not unlocked.has(DEFAULT_ID):
		unlocked.push_front(DEFAULT_ID)
	var raw_completed = d.get("completed", [])
	if raw_completed is Array:
		for raw in raw_completed:
			var id := String(raw)
			if exists(id) and not completed.has(id):
				completed.append(id)
	var raw_last := String(d.get("last", DEFAULT_ID))
	last = raw_last if exists(raw_last) and unlocked.has(raw_last) else DEFAULT_ID
	return true


func save_progress(p_path: String = "") -> bool:
	var target := p_path if p_path != "" else path
	last_error = ""
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		last_error = "无法写入进度：%s（错误 %d）" % [target, FileAccess.get_open_error()]
		return false
	f.store_string(JSON.stringify({
		"unlocked": unlocked,
		"completed": completed,
		"last": last,
	}, "\t"))
	f.close()
	return true


func clear_progress(p_path: String = "") -> void:
	var target := p_path if p_path != "" else path
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
	unlocked = [DEFAULT_ID]
	completed = []
	last = DEFAULT_ID
	last_error = ""
