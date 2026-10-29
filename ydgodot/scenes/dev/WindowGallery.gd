extends Control
## 开发预览：WindowGallery
##
## 打开方式：在编辑器里打开本场景，按 F6 运行当前场景。
##
## 目的：不改任何产品窗口的创建路径，用真实的 Desktop + DesktopDebug 接缝
## 把代表性系统窗逐个摆到屏幕中央，方便目视检查标题栏、边距、按钮、滚动区
## 和窗口尺寸。它是 dev-only 工具，不要从产品代码引用，也不要挂进主场景。
##
## 键盘 / 鼠标：点击上方按钮切换窗口；窗口本身仍可拖动、点击。
## 这个场景不写存档、不改案件进度、不启动教学。

const PREVIEWS := [
	{"id": "bag", "label": "物品"},
	{"id": "ledger", "label": "证据"},
	{"id": "map", "label": "案件"},
	{"id": "log", "label": "日志"},
	{"id": "detail", "label": "详情"},
	{"id": "chat", "label": "对话"},
	{"id": "matrix", "label": "推演"},
	{"id": "password", "label": "密码"},
	{"id": "cert", "label": "证件"},
	{"id": "people", "label": "人物"},
]

var _desktop: Desktop
var _toolbar: PanelContainer
var _status_label: Label
var _buttons: Dictionary = {}
var _current_id := ""
var _current_window: Control


func _ready() -> void:
	theme = TecTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(_sync_toolbar_size)
	_build_toolbar()
	await _prepare_desktop()
	_show_preview("bag")


func _build_toolbar() -> void:
	var layer := CanvasLayer.new()
	layer.name = "gallery_ui"
	layer.layer = 200
	add_child(layer)

	_toolbar = PanelContainer.new()
	_toolbar.name = "toolbar"
	_toolbar.add_theme_stylebox_override("panel",
		TecTheme.flat(TecTheme.CARD, TecTheme.R_SM, TecTheme.INK, 1))
	layer.add_child(_toolbar)
	_sync_toolbar_size()

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_toolbar.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := TecTheme.label("WINDOW GALLERY", TecTheme.FS_BODY, TecTheme.TEXT)
	head.add_child(title)
	_status_label = TecTheme.label("正在准备 A-001 静态预览……", TecTheme.FS_BODY, TecTheme.MUTED)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.clip_text = true
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_status_label)
	col.add_child(head)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	for entry in PREVIEWS:
		var id := String(entry["id"])
		var b := TecTheme.button(String(entry["label"]))
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 24)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = true
		b.pressed.connect(_show_preview.bind(id))
		row.add_child(b)
		_buttons[id] = b
	col.add_child(row)


func _sync_toolbar_size() -> void:
	if _toolbar == null:
		return
	var w := size.x
	if w <= 0.0:
		w = get_viewport_rect().size.x
	_toolbar.position = Vector2(8, 8)
	_toolbar.size = Vector2(maxf(w - 16.0, 640.0), 56.0)


func _prepare_desktop() -> void:
	var packed := load("res://scenes/Desktop.tscn") as PackedScene
	if packed == null:
		_status("无法加载 Desktop.tscn")
		return
	_desktop = packed.instantiate() as Desktop
	add_child(_desktop)
	await get_tree().process_frame
	await get_tree().process_frame
	if _desktop == null or not is_instance_valid(_desktop):
		return
	if _desktop.debug == null:
		_status("需要以调试构建运行（F6）；当前没有 DesktopDebug 接缝。")
		return

	## 静态预览：关掉存档、跳过开始页和教学，直接进 A-001 切片。
	_desktop._save_enabled = false
	_desktop.session._close_start_screen()
	_desktop.session._start_slice()
	_desktop.debug.dbg_set_investigator({
		"name": "林雾",
		"id": "TEC-GD-2160",
		"sense": ["vision"],
		"avatarId": "CHARS_EXEC",
	})
	_desktop.debug.dbg_expand("SCENES_garden")
	await get_tree().process_frame

	## 让预览区只剩窗口本身：主案卷窗 / 图标栏 / 页眉 / TEC / 右下角案件卡都藏掉。
	## 尽量走 DesktopDebug 查询接缝，避免这个 dev 工具跟 Desktop 私有字段绑死。
	var case_win: Control = _desktop.debug.dbg_case_win()
	if case_win != null:
		case_win.visible = false
	var header := _desktop.get_node_or_null("header") as Control
	if header != null:
		header.visible = false
	var icons: Control = _desktop.debug.dbg_icon_layer()
	if icons != null:
		icons.visible = false
	var tec: Control = _desktop.debug.dbg_tec_win()
	if tec != null:
		tec.visible = false
	var dock: Control = _desktop.debug.dbg_dock_card()
	if dock != null:
		dock.visible = false
	var narr: Control = _desktop.debug.dbg_narr()
	if narr != null:
		narr.visible = false

	_seed_samples()
	_desktop.debug.dbg_hide_toast()
	_desktop.resized.connect(_place_current_preview)
	for id in _buttons:
		(_buttons[id] as Button).disabled = false
	_status("点击按钮切换窗口 · 尺寸与真实运行一致")


func _seed_samples() -> void:
	var d = _desktop.debug
	## 两个收纳窗：物品 + 证据各一条。
	var lamp = d.dbg_ensure("item", "ITEM_taideng")
	d.dbg_store_into(GraphState.BAG, lamp)
	var torch = d.dbg_ensure("item", "ITEM_shoudiantong")
	d.dbg_store_into(GraphState.BAG, torch)
	var zheng = d.dbg_ensure("evidence", "EVID_Z_strangled")
	d.dbg_store_into(GraphState.LEDGER, zheng)
	## 推演桌布：放一条证，避免空白窗。
	var knife = d.dbg_ensure("evidence", "EVID_Z_zs_knife")
	d.dbg_matrix_assign(knife)
	## 详情窗按当前选中卡生成；日志窗至少有一条本场景日志。
	d.dbg_select("loc:SCENES_garden")
	d.dbg_ensure_detail()
	d.dbg_refresh_detail(true)
	d.dbg_add_log("WindowGallery：日志窗静态预览。", "sys")


func _show_preview(id: String) -> void:
	if _desktop == null or not is_instance_valid(_desktop) or _desktop.debug == null:
		return
	_current_id = id
	_hide_all_previews()
	var w := _ensure_preview(id)
	_current_window = w
	if w == null or not is_instance_valid(w):
		_status("预览创建失败：" + _label_of(id))
		return
	w.visible = true
	w.move_to_front()
	_place_preview(w)
	_status("%s · %d × %d" % [_label_of(id), int(w.size.x), int(w.size.y)])
	if _buttons.has(id):
		(_buttons[id] as Button).set_pressed_no_signal(true)
	await get_tree().process_frame
	if is_instance_valid(w) and w.visible:
		_place_preview(w)


func _ensure_preview(id: String) -> Control:
	var d = _desktop.debug
	match id:
		"bag":
			if d.dbg_bag_win() == null:
				d.dbg_open_storage(GraphState.BAG)
			return d.dbg_bag_win()
		"ledger":
			if d.dbg_ledger_win() == null:
				d.dbg_open_storage(GraphState.LEDGER)
			return d.dbg_ledger_win()
		"map":
			if d.dbg_map_win() == null:
				d.dbg_open_case_map()
			return d.dbg_map_win()
		"log":
			if d.dbg_log_win() == null:
				d.dbg_open_log()
			return d.dbg_log_win()
		"detail":
			if d.dbg_detail_win() == null:
				d.dbg_select("loc:SCENES_garden")
				d.dbg_ensure_detail()
				d.dbg_refresh_detail(true)
			return d.dbg_detail_win()
		"chat":
			if d.dbg_chat() == null:
				d.dbg_open_dialogue("DLG_0704_zs_lhs", ["CHARS_zs", "CHARS_luhengs"])
			return d.dbg_chat()
		"matrix":
			if d.dbg_matrix_win() == null:
				d.dbg_open_matrix()
			return d.dbg_matrix_win()
		"password":
			var pw := _desktop.find_child("pw_pop", true, false) as Control
			if pw == null:
				d.dbg_ensure("item", "ITEMS_jzmh")
				d.dbg_pw_open("item:ITEMS_jzmh")
				pw = _desktop.find_child("pw_pop", true, false) as Control
			return pw
		"cert":
			if d.dbg_cert_win() == null:
				d.dbg_open_cert()
			return d.dbg_cert_win()
		"people":
			if d.dbg_people_win() == null:
				d.dbg_open_people()
			return d.dbg_people_win()
	return null


func _hide_all_previews() -> void:
	if _desktop == null or _desktop.debug == null:
		return
	var d = _desktop.debug
	var wins := [
		d.dbg_bag_win(), d.dbg_ledger_win(), d.dbg_map_win(), d.dbg_log_win(),
		d.dbg_detail_win(), d.dbg_chat(), d.dbg_matrix_win(), d.dbg_cert_win(),
		d.dbg_people_win(), _desktop.find_child("pw_pop", true, false),
	]
	for w in wins:
		if w != null and is_instance_valid(w):
			(w as Control).visible = false


func _place_preview(w: Control) -> void:
	if w == null or not is_instance_valid(w):
		return
	var top := 76.0
	var vw: float = _desktop.debug.dbg_vw()
	var vh: float = _desktop.debug.dbg_vh()
	var x := maxf(8.0, (vw - w.size.x) * 0.5)
	var y := top + maxf(8.0, (vh - top - w.size.y) * 0.5)
	w.position = Vector2(x, y)


func _place_current_preview() -> void:
	if _current_window != null and is_instance_valid(_current_window) and _current_window.visible:
		_place_preview.call_deferred(_current_window)


func _status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _label_of(id: String) -> String:
	for entry in PREVIEWS:
		if String(entry["id"]) == id:
			return String(entry["label"])
	return id
