class_name FloatingPanel
extends RefCounted
## 浮窗几何的共用实现：夹在父容器内、按内容收放前等一帧。
##
## 只放**与业务无关**的几何步骤；窗口各自的目标高度 / 边距仍留在窗口里。

## 把浮窗左上角夹进父 Control 的可视区（父容器不存在时原样返回）。
static func clamp_pos(panel: Control, p: Vector2) -> Vector2:
	var parent := panel.get_parent() as Control
	if parent == null:
		return p
	return Vector2(
		clampf(p.x, 0.0, maxf(0.0, parent.size.x - panel.size.x)),
		clampf(p.y, 0.0, maxf(0.0, parent.size.y - panel.size.y)))


## 等节点进树 + 一帧，让内容最小尺寸定型。
## 返回 false 表示节点中途离树，调用方应直接放弃本次收放。
static func settle(panel: Control) -> bool:
	if panel == null or not is_instance_valid(panel):
		return false
	if not panel.is_inside_tree():
		await panel.tree_entered
		if not is_instance_valid(panel) or not panel.is_inside_tree():
			return false
	await panel.get_tree().process_frame
	return is_instance_valid(panel) and panel.is_inside_tree()


## 视口高度；无头 / 极小窗（< 320）按 720 兜底，与各窗口原先的写死值一致。
static func viewport_height(panel: Control) -> float:
	var vh := 720.0
	if panel.is_inside_tree():
		var raw := panel.get_viewport_rect().size.y
		if raw >= 320.0:
			vh = raw
	return vh


## 底边超出视口时把顶边提上来，保证整窗可见（至少留 8px）。
static func keep_bottom_visible(panel: Control) -> void:
	var vh := viewport_height(panel)
	if panel.position.y + panel.size.y > vh - 8.0:
		panel.position.y = maxf(8.0, vh - 8.0 - panel.size.y)
