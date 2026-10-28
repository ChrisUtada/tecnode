class_name ScrollBox
extends RefCounted
## 滚动容器的共用操作。


## 滚到底。内容高度要等下一帧才定型，所以先等一帧；节点中途离树则放弃。
static func to_bottom(scroll: ScrollContainer) -> void:
	if scroll == null or not is_instance_valid(scroll) or not scroll.is_inside_tree():
		return
	await scroll.get_tree().process_frame
	if not is_instance_valid(scroll) or not scroll.is_inside_tree():
		return
	scroll.set_deferred("scroll_vertical", 1 << 20)
