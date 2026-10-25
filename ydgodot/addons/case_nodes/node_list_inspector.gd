@tool
extends EditorInspectorPlugin
## 把 `SceneDef` / `ItemDef` 上的四栏「画布节点」换成**一行摘要 + 编辑按钮**。
##
## 这四栏本身是 `PackedStringArray`（存 id），默认检查器只会给一个要手打 id 的
## 文本框 —— 那是作者最容易出错的地方。这里接管它们的渲染，别的属性一个不碰。
##
## ⚠ 检查器里**只放一行**、不放列表：检查器每次刷新都会重建 `EditorProperty`，
## 把列表画在属性里等于每次刷新 free + 重建几十个 Control（旧版就是这么拖慢的）。
## 完整列表在点开后弹出的 `node_picker.gd` 里。

const Row := preload("res://addons/case_nodes/node_field_editor.gd")

const FIELDS := {
	"node_items": "item",
	"node_chars": "char",
	"node_locs": "loc",
	"node_clues": "evidence",
}


func _can_handle(object: Object) -> bool:
	return object is SceneDef or object is ItemDef


func _parse_property(_object: Object, _type: Variant.Type, name: String,
		_hint_type: PropertyHint, _hint_string: String,
		_usage_flags: int, _wide: bool) -> bool:
	if not FIELDS.has(name):
		return false
	var ed: EditorProperty = Row.new()
	ed.field = name
	ed.kind = String(FIELDS[name])
	add_property_editor(name, ed)
	return true
