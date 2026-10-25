extends SceneTree

func _initialize() -> void:
	var packed := load("res://scenes/Desktop.tscn") as PackedScene
	var scene = packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene._tutorial_active = false
	scene._save_enabled = false
	var c := CaseLoader.new(CaseCatalog.path_of("A001"))
	c.load_case()
	scene.case_def = c
	scene._active_case = "A001"
	scene._start_slice()
	await process_frame
	scene._expand_scene("SCENES_garden", false)
	await create_timer(0.5).timeout
	var key := "item:ITEM_sxbj"
	if not scene.graph.has("item", "ITEM_sxbj"):
		scene.dbg_ensure("item", "ITEM_sxbj")
	await process_frame
	scene._store_into(GraphState.BAG, key)
	await process_frame
	var at := Vector2(700.0, 400.0)
	scene._sdrag_origin = at
	scene._sdrag_label = "手写笔记"
	scene._sdrag_ghost = scene._make_drag_ghost(scene._sdrag_label)
	scene._sdrag_ghost.position = scene._sdrag_ghost_position(at)
	await process_frame
	await process_frame
	print("cursor=", at, " ghost=", scene._sdrag_ghost.global_position if scene._sdrag_ghost != null else "none")
	_draw_cross(at)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://_debug_drag.png")
	img.save_png(path)
	print("saved ", path)
	quit()

func _push(at: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = at
	ev.global_position = at
	Input.parse_input_event(ev)

func _motion(at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(ev)

func _draw_cross(at: Vector2) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 101
	root.add_child(layer)
	var h := ColorRect.new()
	h.color = Color(1, 0, 0, 1)
	h.position = Vector2(0, at.y)
	h.size = Vector2(1280, 1)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(h)
	var v := ColorRect.new()
	v.color = Color(1, 0, 0, 1)
	v.position = Vector2(at.x, 0)
	v.size = Vector2(1, 720)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(v)
