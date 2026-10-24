extends SceneTree
## 详情窗自适应增高回归：内容（含按钮）不许溢出窗框、不设滚动条。
## 运行：godot --headless --path ydgodot --script res://tests/headless/test_p28.gd

var fails := 0
var total := 0
var scene: Control


func check(name: String, cond: bool, detail: String = "") -> void:
	total += 1
	if cond:
		print("  PASS  ", name)
	else:
		fails += 1
		print("  FAIL  ", name, ("  [" + detail + "]") if detail != "" else "")


func _initialize() -> void:
	print("=== P28 详情窗自适应增高 ===")
	scene = load("res://scenes/Desktop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene._view_k = 1.0
	scene._view_pos = Vector2.ZERO
	scene._view_user = true
	scene._apply_view()
	scene.dbg_expand("SCENES_garden")
	await process_frame

	# 双击书桌：选中 + 激活交错触发两次 _rebuild，是溢出的历史路径
	scene._on_card_selected("item:ITEM_shuzhuo")
	scene._on_card_activated("item:ITEM_shuzhuo")
	for i in 20:
		await process_frame
	_assert_fit("书桌（容器 + 重看叙事按钮）")

	scene._on_card_selected("loc:SCENES_garden")
	for i in 20:
		await process_frame
	_assert_fit("花园（场景 + 重看场景叙事按钮）")

	var char_key := ""
	for k in scene._cards.keys():
		if String(k).begins_with("char:"):
			char_key = k
			break
	if char_key != "":
		scene._on_card_selected(char_key)
		for i in 20:
			await process_frame
		_assert_fit("人物节点")

	print("---")
	print("P28: %d/%d 通过" % [total - fails, total])
	quit(1 if fails > 0 else 0)


## 不变量：rows 内容底边不许越过窗框 bg 底边；窗口整体不许越出视口
func _assert_fit(tag: String) -> void:
	var w: DetailWin = scene._detail_win
	if w == null or not is_instance_valid(w) or not w.visible:
		check(tag + "：详情窗可见", false, "window not visible")
		return
	var bg := w.get_node("bg") as Control
	var body := w.get_node("body") as Control
	var rows := body.get_node("content").get_node("rows") as VBoxContainer
	var content_bottom := body.position.y + rows.position.y + rows.size.y
	var bg_bottom := bg.position.y + bg.size.y
	check(tag + "：内容不溢出窗框", content_bottom <= bg_bottom + 0.5,
		"content_bottom=%.1f bg_bottom=%.1f" % [content_bottom, bg_bottom])
	var vh := scene.get_viewport_rect().size.y
	if vh < 320.0:
		vh = 720.0  # 无头假视口：与 DetailWin._fit_to_content 的回退口径一致
	check(tag + "：窗底不出视口", w.position.y + w.size.y <= vh + 0.5,
		"win_bottom=%.1f vh=%.1f" % [w.position.y + w.size.y, vh])
	# 等 typing 结束再断言一次：打字收尾不许改变「不溢出」的结论
	var para := rows.get_node_or_null("dt_desc") as TypewriterLabel
	if para != null and para.is_typing():
		para.finish_typing()
		for i in 5:
			await process_frame
		var cb2 := body.position.y + rows.position.y + rows.size.y
		check(tag + "：打字收尾后仍不溢出", cb2 <= bg_bottom + 0.5,
			"content_bottom=%.1f bg_bottom=%.1f" % [cb2, bg_bottom])
