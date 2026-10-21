@tool
extends EditorPlugin
## 「画布节点」检查器插件入口。
##
## 作用只有一个：让场景 / 容器物品上的 node_items / node_chars / node_locs /
## node_clues 四栏在检查器里变成「一行摘要 + 编辑按钮」，点开是一份可点选、可拖入的
## 列表 —— 而不是四个要手打 id 的文本框。数据侧仍是 id 字符串，原因见
## `core/defs/SceneDef.gd` 的注释（`.tres` 冷启动不支持循环引用，而地点之间必然互相指）。
##
## 检查器里刻意只放一行：检查器每次刷新都会重建 `EditorProperty`，把列表画在那里
## 等于每次刷新 free + 重建几十个 Control。完整列表在 `node_picker.gd` 的弹窗里，
## 只在用户点「编辑…」时构建。

const Index := preload("res://addons/case_nodes/case_index.gd")

var _inspector: EditorInspectorPlugin = null


func _enter_tree() -> void:
	_inspector = preload("res://addons/case_nodes/node_list_inspector.gd").new()
	add_inspector_plugin(_inspector)
	var fs := get_editor_interface().get_resource_filesystem()
	fs.filesystem_changed.connect(_on_fs_changed)


func _exit_tree() -> void:
	var fs := get_editor_interface().get_resource_filesystem()
	if fs != null and fs.filesystem_changed.is_connected(_on_fs_changed):
		fs.filesystem_changed.disconnect(_on_fs_changed)
	if _inspector != null:
		remove_inspector_plugin(_inspector)
		_inspector = null


## 资源增删 / 改名后丢掉 id → 资源 的索引，下次打开编辑窗口重新扫一遍案件目录
func _on_fs_changed() -> void:
	Index.reset()
