extends SceneTree
## C-E：三档截图验收。运行：
##   godot --path . --script res://tools/shoot_aesthetic.gd -- --win=960x560 --no-start
## 需要真实渲染（不要加 --headless）。输出 docs/aesthetic/<surface>_<WxH>.png。

var scene
var tag := "960x560"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--win="):
			tag = a.trim_prefix("--win=")
	var packed := load("res://scenes/Desktop.tscn") as PackedScene
	scene = packed.instantiate()
	get_root().add_child(scene)
	await _wait(1.2)
	await _shot("desktop")

	scene.dbg_expand("SCENES_garden")
	await _wait(0.6)
	scene._open_tec()
	await _wait(0.4)
	await _shot("tec")
	scene._close_top_window()
	await _wait(0.2)

	scene._open_people()
	await _wait(0.4)
	await _shot("people")
	scene._close_top_window()
	await _wait(0.2)

	scene._open_log()
	await _wait(0.4)
	await _shot("log")
	scene._close_top_window()
	await _wait(0.2)

	scene._open_archive()
	await _wait(0.4)
	await _shot("archive")
	scene._close_top_window()
	await _wait(0.2)

	# 音乐窗：临时给图上一个已装唱针的节点，只为截图解锁。
	var holder: Dictionary = scene.graph.add_node("item", "ITEMS_changji")
	holder["installed"] = {"ITEMS_cz": true}
	scene._open_music()
	await _wait(0.4)
	await _shot("music")

	quit()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_viewport().get_texture().get_image()
	var path := "res://docs/aesthetic/%s_%s.png" % [name, tag]
	var err := img.save_png(path)
	print("[shot] ", path, " ", img.get_width(), "x", img.get_height(), " err=", err)
