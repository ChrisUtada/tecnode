@tool
extends AcceptDialog
## 「画布节点」编辑窗口：四栏（物品 / 人物 / 地点 / 证据）各一个 tab。
##
## 为什么不在检查器里做：检查器每次刷新都重建 `EditorProperty`，把列表画在那里
## 等于每次刷新 free + 重建几十个 Control，还要扫案件目录 —— 检查器会明显变卡。
## 富交互放在这里：只在用户点「编辑…」时构建一次，之后复用同一个窗口实例。
##
## 写回仍然走检查器的官方通道（`EditorProperty.emit_changed`），撤销 / 标脏由它处理。

signal changed(field: String, arr: PackedStringArray)

const PARTS: Array = [
	{"field": "node_items", "kind": "item", "label": "物品", "dir": "items"},
	{"field": "node_chars", "kind": "char", "label": "人物", "dir": "chars"},
	{"field": "node_locs", "kind": "loc", "label": "地点", "dir": "scenes"},
	{"field": "node_clues", "kind": "evidence", "label": "证据", "dir": "evidence"},
]
const KIND_LABEL := {"item": "物品", "char": "人物", "loc": "地点", "evidence": "证据"}
const Index := preload("res://addons/case_nodes/case_index.gd")

## 单例：编辑器里只存在一个窗口，反复点「编辑…」只是换绑对象（避免窗口越开越多）
static var _inst = null


## 拖放接收区：编辑器 FileSystem 面板拖过来的 `{files: [...]}` 由它接。
class DropZone extends VBoxContainer:
	signal dropped(files: PackedStringArray)

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return typeof(data) == TYPE_DICTIONARY and data.has("files")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		dropped.emit(data["files"])


var _obj: Object = null
var _built := false
var _draft: Dictionary = {}      # field -> PackedStringArray
var _lists: Dictionary = {}      # field -> DropZone
var _counts: Dictionary = {}     # field -> Label
var _tabs: TabContainer = null
var _head: Label = null


static func open_for(obj: Object, focus_kind: String) -> Node:
	if _inst == null or not is_instance_valid(_inst):
		_inst = preload("res://addons/case_nodes/node_picker.gd").new()
		EditorInterface.get_base_control().add_child(_inst)
	_inst.call("bind_to", obj)
	_inst.call("focus_kind", focus_kind)
	(_inst as Window).popup_centered(Vector2i(680, 540))
	return _inst


# ── 绑定与构建 ───────────────────────────────────────────────────────────

func bind_to(obj: Object) -> void:
	_obj = obj
	_build()
	title = "画布节点 — %s" % _display_name(obj)
	_head.text = String((obj as Resource).resource_path) if obj is Resource else ""
	for spec in PARTS:
		var f := String(spec["field"])
		_draft[f] = Index.read_field(obj, f)
		_refresh(f)


func focus_kind(kind: String) -> void:
	if _tabs == null:
		return
	for i in PARTS.size():
		if String(PARTS[i]["kind"]) == kind:
			_tabs.current_tab = i


func _build() -> void:
	if _built:
		return
	_built = true
	ok_button_text = "关闭"

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(660, 470)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)

	var hint := Label.new()
	hint.text = "点「＋ 添加」挑资源，或把 .tres 拖到列表里"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	bar.add_child(hint)

	# 编辑器会把资源缓存在内存里：`.tres` 被外部（迁移脚本 / git / 手改）改过之后，
	# 检查器这一份可能还是旧的。真因（defs 少了 @tool）已修，这里是兜底出口。
	var reload := Button.new()
	reload.text = "⟳ 重读磁盘"
	reload.tooltip_text = "按磁盘重新加载这个资源（会丢弃未保存的修改）"
	reload.pressed.connect(_on_reload)
	bar.add_child(reload)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)

	for spec in PARTS:
		var f := String(spec["field"])
		var page := VBoxContainer.new()
		page.name = String(spec["label"])
		page.add_theme_constant_override("separation", 4)
		_tabs.add_child(page)

		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 6)
		page.add_child(top)

		var add := Button.new()
		add.text = "＋ 添加%s…" % String(spec["label"])
		add.pressed.connect(_on_add.bind(f))
		top.add_child(add)

		var cnt := Label.new()
		cnt.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
		top.add_child(cnt)
		_counts[f] = cnt

		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		page.add_child(scroll)

		var list := DropZone.new()
		list.mouse_filter = Control.MOUSE_FILTER_STOP
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.dropped.connect(_on_drop.bind(f))
		scroll.add_child(list)
		_lists[f] = list

	_head = Label.new()
	_head.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(_head)


# ── 渲染 ─────────────────────────────────────────────────────────────────

func _refresh(f: String) -> void:
	var box: VBoxContainer = _lists[f]
	# 倒序 + 立即 free：正序 remove_child 会在 Container 排序回调里改子节点表，
	# 触发 `Condition "p_child->get_parent() != this"` 断言刷屏。
	for i in range(box.get_child_count() - 1, -1, -1):
		var c := box.get_child(i)
		box.remove_child(c)
		c.free()

	var arr: PackedStringArray = _draft.get(f, PackedStringArray())
	var spec := _spec(f)
	var idx: RefCounted = Index.get_index()
	var missing := 0
	for id in arr:
		var sid := String(id)
		box.add_child(_row(f, String(spec["kind"]), idx, sid))
		if idx.title_of(String(spec["kind"]), sid) == "":
			missing += 1

	var cnt: Label = _counts[f]
	cnt.text = "共 %d 项" % arr.size()
	if missing > 0:
		cnt.text += "   ⚠ %d 个 id 找不到资源" % missing
		cnt.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
	else:
		cnt.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))

	if arr.is_empty():
		var hint := Label.new()
		hint.text = "（空 —— 展开这个容器时不出现任何%s）" % String(spec["label"])
		hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		box.add_child(hint)


func _row(f: String, kind: String, idx: RefCounted, id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var title: String = idx.title_of(kind, id)
	var name_lb := Label.new()
	name_lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if title == "":
		name_lb.text = "⚠ " + id
		name_lb.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
		name_lb.tooltip_text = "案件里没有 id 为「%s」的%s资源" % [id, String(KIND_LABEL.get(kind, kind))]
	else:
		name_lb.text = title
		name_lb.tooltip_text = idx.path_of(kind, id)
	row.add_child(name_lb)

	var id_lb := Label.new()
	id_lb.text = id
	id_lb.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	id_lb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(id_lb)

	for spec in [["↑", -1, "上移"], ["↓", 1, "下移"], ["×", 0, "从清单里移除（只解绑，不删资源文件）"]]:
		var b := Button.new()
		b.text = String(spec[0])
		b.flat = true
		b.tooltip_text = String(spec[2])
		if int(spec[1]) == 0:
			b.pressed.connect(_remove.bind(f, id))
		else:
			b.pressed.connect(_move.bind(f, id, int(spec[1])))
		row.add_child(b)

	return row


# ── 操作 ─────────────────────────────────────────────────────────────────

## 写回：走编辑器的撤销栈（`mark_unsaved` 默认 true ⇒ 资源会被标脏），
## **不**依赖检查器那边 `EditorProperty` 的实例还活着 —— 检查器刷新可能把它重建掉，
## 那时窗口还开着，靠 `emit_changed` 传就会静默丢失。值先落到对象上再说。
func _commit(f: String, arr: PackedStringArray) -> void:
	var old := Index.read_field(_obj, f)
	_draft[f] = arr
	_refresh(f)
	if _obj != null and old != arr:
		var ur := EditorInterface.get_editor_undo_redo()
		if ur != null:
			ur.create_action("画布节点：修改「%s」" % String(_spec(f)["label"]))
			ur.add_do_property(_obj, f, arr)
			ur.add_undo_property(_obj, f, old)
			ur.add_do_method(_obj, "emit_changed")
			ur.add_undo_method(_obj, "emit_changed")
			ur.commit_action()
		else:
			_obj.set(f, arr)
			if _obj.has_method("emit_changed"):
				_obj.call("emit_changed")
	changed.emit(f, arr)


func _on_add(f: String) -> void:
	var spec := _spec(f)
	var dlg := EditorFileDialog.new()
	dlg.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILES
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.add_filter("*.tres", "案件资源")
	dlg.title = "选择要加入「%s」的资源" % String(spec["label"])
	dlg.current_dir = _dir_hint(spec)
	dlg.files_selected.connect(_add_paths.bind(f))
	dlg.canceled.connect(dlg.queue_free)
	EditorInterface.get_base_control().add_child(dlg)
	dlg.popup_centered_ratio(0.55)


func _on_drop(files: PackedStringArray, f: String) -> void:
	_add_paths(files, f)


func _add_paths(files: PackedStringArray, f: String) -> void:
	var spec := _spec(f)
	var kind := String(spec["kind"])
	var arr: PackedStringArray = _draft.get(f, PackedStringArray())
	var added := 0
	for p in files:
		var r: Resource = ResourceLoader.load(p)
		if r == null:
			push_warning("[Case Nodes] 加载不了 " + p)
			continue
		var k := Index.kind_of(r)
		if k != kind:
			push_warning("[Case Nodes]「%s」是%s，不是%s，已跳过" % [
				p, String(KIND_LABEL.get(k, k)), String(KIND_LABEL.get(kind, kind))])
			continue
		var rid := String(r.get("id"))
		if rid == "":
			push_warning("[Case Nodes]「%s」没填 id 字段，已跳过" % p)
			continue
		if arr.has(rid):
			continue
		arr.append(rid)
		added += 1
	if added > 0:
		_commit(f, arr)


func _remove(f: String, id: String) -> void:
	var arr: PackedStringArray = _draft.get(f, PackedStringArray())
	var i := arr.find(id)
	if i < 0:
		return
	arr.remove_at(i)
	_commit(f, arr)


func _move(f: String, id: String, step: int) -> void:
	var arr: PackedStringArray = _draft.get(f, PackedStringArray())
	var i := arr.find(id)
	var j := i + step
	if i < 0 or j < 0 or j >= arr.size():
		return
	var t := arr[i]
	arr[i] = arr[j]
	arr[j] = t
	_commit(f, arr)


func _on_reload() -> void:
	if not (_obj is Resource):
		return
	var path := String((_obj as Resource).resource_path)
	if path == "" or not FileAccess.file_exists(path):
		return
	var fresh: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if fresh == null:
		push_warning("[Case Nodes] 重读失败：" + path)
		return
	EditorInterface.inspect_object.call_deferred(fresh)
	bind_to(fresh)


# ── 小工具 ───────────────────────────────────────────────────────────────

func _spec(f: String) -> Dictionary:
	for spec in PARTS:
		if String(spec["field"]) == f:
			return spec
	return PARTS[0]


func _dir_hint(spec: Dictionary) -> String:
	if not (_obj is Resource):
		return "res://cases"
	var p := String((_obj as Resource).resource_path)
	if p == "":
		return "res://cases"
	var case_dir := p.get_base_dir().get_base_dir()
	var d := case_dir.path_join(String(spec["dir"]))
	return d if DirAccess.dir_exists_absolute(d) else case_dir


func _display_name(obj: Object) -> String:
	for p in ["title", "label", "name", "id"]:
		var v: Variant = obj.get(p)
		if v != null and String(v) != "":
			return String(v)
	return "（未命名）"
