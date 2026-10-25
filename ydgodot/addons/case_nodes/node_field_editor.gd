@tool
extends EditorProperty
## 「画布节点」四栏在检查器里的**一行摘要**：`物品 · 6 项   [编辑…]`。
##
## 为什么这么薄：检查器每次刷新（选中对象、撤销、改任何属性）都会**重建**
## `EditorProperty` 实例。旧版把完整列表（每行 5 个 Control）画在属性里，等于每次刷新
## 都 free + 重建几十个节点，还顺手扫了一遍案件目录 —— 检查器就卡。
## 现在这里只有 2 个节点、只改一次文本，零文件 IO；列表 / 增删 / 调序 / 拖放全部搬进
## 点击后打开的 `node_picker.gd`，只在用户主动点开时构建。

const KIND_LABEL := {"item": "物品", "char": "人物", "loc": "地点", "evidence": "证据"}
const Index := preload("res://addons/case_nodes/case_index.gd")

## 由 `node_list_inspector.gd` 在 `add_property_editor()` 之前设好
var field := ""
var kind := ""

var _summary: Label


func _init() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	# 官方写法：先 add_child 再 set_bottom_editor —— 后者只负责「排到属性名下方」，
	# 不负责挂树；只调它会得到检查器一片空白 + Container 排序断言刷屏。
	add_child(row)

	_summary = Label.new()
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_summary.add_theme_color_override("font_color", Color(0.78, 0.78, 0.78))
	row.add_child(_summary)

	var edit := Button.new()
	edit.text = "编辑…"
	edit.tooltip_text = "在弹出窗口里增删 / 调序（不用手打 id）"
	edit.pressed.connect(_on_edit)
	row.add_child(edit)

	set_bottom_editor(row)


func _update_property() -> void:
	var obj := get_edited_object()
	if obj == null or field == "":
		_summary.text = ""
		return
	var arr := Index.read_field(obj, field)
	_summary.text = "%s · %d 项" % [String(KIND_LABEL.get(kind, kind)), arr.size()]
	_summary.tooltip_text = "—\n".join(arr) if not arr.is_empty() else "（空 —— 展开时不出现任何节点）"


func _on_edit() -> void:
	var obj := get_edited_object()
	if obj == null or field == "":
		return
	var picker: Node = preload("res://addons/case_nodes/node_picker.gd").open_for(obj, kind)
	if not picker.changed.is_connected(_on_picked):
		picker.changed.connect(_on_picked)


## 窗口改了某一栏 → 值已经在窗口里写进对象（走编辑器的撤销栈），这里只刷新摘要。
## 不用 `emit_changed()` 写回：那要依赖本实例还活着，而检查器随时可能重建它。
func _on_picked(f: String, _arr: PackedStringArray) -> void:
	if f == field:
		update_property()
