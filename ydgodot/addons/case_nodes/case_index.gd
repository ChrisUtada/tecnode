@tool
extends RefCounted
## 案件资源索引：把 `id` 反查成资源路径与显示名，供「画布节点」的编辑窗口使用。
##
## 为什么需要它：`SceneDef.node_items` 等四栏存的是 **id 字符串**（`.tres` 不支持环，
## 见 `SceneDef.gd` 的注释），要把 id 显示成「书桌 / ITEM_shuzhuo」这种可读的样子，
## 就必须知道每个 id 对应哪个文件。
##
## ⚠ 扫描方式：**读 `.tres` 文本**，不 `ResourceLoader.load`。实测 load 87 个案件资源要
## 约 1.3 秒（每个都会连带加载 CommandDef / ExcerptDef 依赖），而读文本只要几十毫秒 ——
## 这个差距在编辑器里就是「点开窗口卡一下」和「立刻出来」的区别。
## 目录名 → 类型是写死的（`items/chars/scenes/evidence`），所以也不必 load 才知道类型。

const ROOT := "res://cases"

## 目录名 → 四栏之一
const DIR_KIND := {
	"items": "item",
	"chars": "char",
	"scenes": "loc",
	"evidence": "evidence",
}

## 全编辑器共用一个索引：只在**第一次打开编辑窗口**时扫一遍案件目录，
## 资源增删 / 改名（`filesystem_changed`）时由插件调 `reset()` 丢掉。
## ⚠ 不要在检查器的 `_update_property()` 里碰它 —— 那是每次刷新都会跑的地方。
static var _inst = null

var _by_kind: Dictionary = {}       # kind → { id: {path, title} }
var _scanned := false


static func get_index() -> RefCounted:
	if _inst == null or not is_instance_valid(_inst):
		_inst = preload("res://addons/case_nodes/case_index.gd").new()
	_inst.ensure()
	return _inst


static func reset() -> void:
	_inst = null


## 读 `SceneDef` / `ItemDef` 上的一栏 id。
## 用 `typeof` 而不是 `is`：后者对 Packed* 内置类型在部分版本里判断不稳，会静默拿到空数组。
static func read_field(obj: Object, field: String) -> PackedStringArray:
	if obj == null:
		return PackedStringArray()
	var v: Variant = obj.get(field)
	if typeof(v) == TYPE_PACKED_STRING_ARRAY:
		return PackedStringArray(v)
	if typeof(v) == TYPE_ARRAY:
		var out := PackedStringArray()
		for e in v:
			out.append(String(e))
		return out
	push_warning("[Case Nodes] 读不到 %s 的 %s（typeof=%d）—— 确认 defs 脚本带 @tool 且默认值是 PackedStringArray()" % [
		obj, field, typeof(v)])
	return PackedStringArray()


func ensure() -> void:
	if not _scanned:
		rescan()


func rescan() -> void:
	_scanned = true
	_by_kind = {"item": {}, "char": {}, "loc": {}, "evidence": {}}
	for case_dir in _subdirs(ROOT):
		for dir_name in DIR_KIND:
			var d: String = case_dir.path_join(String(dir_name))
			if not DirAccess.dir_exists_absolute(d):
				continue
			var kind := String(DIR_KIND[dir_name])
			for p in _tres_files(d):
				var rec := _parse_tres(p)
				if rec.is_empty():
					continue
				_by_kind[kind][String(rec["id"])] = {"path": p, "title": String(rec["title"])}


## 资源属于哪一栏（`_add_paths` 用来校验用户挑的资源类型对不对）
static func kind_of(r: Resource) -> String:
	if r is SceneDef:
		return "loc"
	if r is ItemDef:
		return "item"
	if r is CharDef:
		return "char"
	if r is EvidenceDef:
		return "evidence"
	return ""


static func title_of_res(r: Resource) -> String:
	for prop in ["title", "label", "name"]:
		var v: Variant = r.get(prop)
		if v != null and String(v) != "":
			return String(v)
	return String(r.get("id"))


func title_of(kind: String, id: String) -> String:
	var t: Dictionary = _by_kind.get(kind, {})
	return String(t[id]["title"]) if t.has(id) else ""


func path_of(kind: String, id: String) -> String:
	var t: Dictionary = _by_kind.get(kind, {})
	return String(t[id]["path"]) if t.has(id) else ""


# ── 文本解析 ─────────────────────────────────────────────────────────────

## 从 `.tres` 文本里抠出 `id` 与 `title` / `label`。
## 只认 `[resource]` 段之后的字段：`[ext_resource]` 里也有 `id="1_xxx"`（无空格、
## 且值不同），`sub_resource` 里可能有自己的 `id`，从段头往后找最省事也最稳。
func _parse_tres(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	var head := txt.find("\n[resource]")
	var body := txt if head < 0 else txt.substr(head)
	var rid := _grab(body, "id")
	if rid == "":
		return {}
	var title := _grab(body, "title")
	if title == "":
		title = _grab(body, "label")
	if title == "":
		title = _grab(body, "name")
	return {"id": rid, "title": title if title != "" else rid}


## 取 `key = "value"` 里的 value（第一处）。不处理多行字符串 —— 这几个字段都是一行。
func _grab(body: String, key: String) -> String:
	var pat := "\n" + key + " = \""
	var i := body.find(pat)
	if i < 0:
		return ""
	i += pat.length()
	var j := body.find("\"", i)
	if j < 0:
		return ""
	return body.substr(i, j - i)


# ── 目录遍历 ─────────────────────────────────────────────────────────────

## `res://cases` 下的一级子目录（每个案件一个）
func _subdirs(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	while true:
		var n := d.get_next()
		if n == "":
			break
		if n.begins_with(".") or not d.current_is_dir():
			continue
		out.append(dir_path.path_join(n))
	d.list_dir_end()
	return out


## 递归收集目录下的 .tres
func _tres_files(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	while true:
		var n := d.get_next()
		if n == "":
			break
		if n.begins_with("."):
			continue
		var full := dir_path.path_join(n)
		if d.current_is_dir():
			out.append_array(_tres_files(full))
		elif n.ends_with(".tres"):
			out.append(full)
	d.list_dir_end()
	return out
