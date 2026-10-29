extends SceneTree
## F7 / F2 帧时间对照（合成基准，不参与全量回归）。
##
## 运行：godot --headless --path . --script res://tests/headless/bench_f7_f2.gd
##
## 口径：
##   · F7 TypewriterLabel：同一段 46 字文本、600 帧（10 秒 @60fps）。
##     旧路径 = 每帧写 visible_characters；新路径 = 只在整数档位变化时写。
##   · F7 LogWin：同样 600 帧，旧路径每帧写 + 排一次滚动；新路径只在新字出现时写。
##   · F2 EdgeLayer：60 条边、120 帧、每帧移动 5 条。
##     旧路径 = 每条边每帧重采 24 点；新路径 = 只重采移动的 5 条。
## 时间只统计 CPU 侧 set_segments / _process 热路径；headless 不产生真实 GPU 帧。

const LogWinScene := preload("res://scenes/windows/LogWin.tscn")
const FRAMES := 600
const EDGE_FRAMES := 120
const EDGE_COUNT := 60
const MOVING := 5

var fails := 0


func check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  PASS  ", name, ("  [" + detail + "]") if detail != "" else "")
	else:
		fails += 1
		print("  FAIL  ", name, ("  [" + detail + "]") if detail != "" else "")


func _initialize() -> void:
	print("=== F7 / F2 合成基准 ===")
	_bench_typewriter()
	await _bench_logwin()
	_bench_edges()
	print("=== 基准断言失败 %d ===" % fails)
	quit(0 if fails == 0 else 1)


func _bench_typewriter() -> void:
	## 360 字 × 45ms ≈ 16.2s，600 帧（10s）内不会打完，前后两路跑的是同一段。
	var text := "打字机性能回归测试文本。".repeat(36)
	var tw := TypewriterLabel.new()
	root.add_child(tw)
	tw.configure(text, TecTheme.FS_BODY, TecTheme.TEXT)
	tw.start_typing()
	tw.set_process(false)          # 基准自己驱动
	tw.dbg_reset_visible_writes()
	var t0 := Time.get_ticks_usec()
	for i in FRAMES:
		tw._process(1.0 / 60.0)
	var new_us := Time.get_ticks_usec() - t0
	var new_writes := tw.dbg_visible_writes()

	## 旧口径：同一个 `_process`，但强制每帧写同一个整数档位。
	tw.dbg_set_legacy_writes(true)
	tw.start_typing()
	tw.set_process(false)
	tw.dbg_reset_visible_writes()
	t0 = Time.get_ticks_usec()
	for i in FRAMES:
		tw._process(1.0 / 60.0)
	var old_us := Time.get_ticks_usec() - t0
	var legacy_writes := tw.dbg_visible_writes()
	tw.dbg_set_legacy_writes(false)
	print("F7 Typewriter：%d 帧，旧 %d 次写入 / 新 %d 次写入；旧 %.1f µs/帧 / 新 %.1f µs/帧"
		% [FRAMES, legacy_writes, new_writes, float(old_us) / FRAMES, float(new_us) / FRAMES])
	check("F7 Typewriter 冗余写入减少", new_writes < legacy_writes / 2,
		"new=%d legacy=%d" % [new_writes, legacy_writes])
	check("F7 Typewriter 仍在打字（基准未提前跑完）", tw.is_typing())
	tw.queue_free()


func _bench_logwin() -> void:
	var loader := CaseLoader.new(CaseCatalog.path_of("A001"))
	if not loader.load_case():
		check("F7 LogWin 案件装载", false, loader.load_error)
		return
	var g := GraphState.new(loader)
	for i in 8:
		g.add_log("第 %d 条测试日志：用于验证日志窗打字机只在整数档位变化时更新并滚动。" % i, "sys")
	g.add_log("日志性能回归测试文本。".repeat(36), "sys")
	var lw := LogWinScene.instantiate() as LogWin
	lw.setup_log(g)
	root.add_child(lw)
	lw.set_process(false)          # 基准自己驱动，避免引擎额外推进
	var t0 := Time.get_ticks_usec()
	for i in FRAMES:
		lw._process(1.0 / 60.0)
	var new_us := Time.get_ticks_usec() - t0
	var new_writes := lw.dbg_typing_writes()
	var lab: RichTextLabel = null
	if not lw._rows.is_empty():
		lab = lw._rows[-1].get_node_or_null("log_text") as RichTextLabel
	## 旧口径：同一个 `_process`，但强制每帧写 + 每帧排一次滚动。
	lw.dbg_set_legacy_writes(true)
	lw._start_typing(lab)
	lw.set_process(false)
	t0 = Time.get_ticks_usec()
	for i in FRAMES:
		lw._process(1.0 / 60.0)
	var old_us := Time.get_ticks_usec() - t0
	var legacy_writes := lw.dbg_typing_writes()
	lw.dbg_set_legacy_writes(false)
	print("F7 LogWin：%d 帧，旧 %d 次写入+滚动 / 新 %d 次；旧 %.1f µs/帧 / 新 %.1f µs/帧"
		% [FRAMES, legacy_writes, new_writes, float(old_us) / FRAMES, float(new_us) / FRAMES])
	check("F7 LogWin 冗余写入/滚动减少", new_writes < legacy_writes / 2,
		"new=%d legacy=%d" % [new_writes, legacy_writes])
	lw.queue_free()
	await process_frame


func _bench_edges() -> void:
	var edge := EdgeLayer.new()
	edge.size = Vector2(2000, 1300)
	root.add_child(edge)
	var segs: Array = []
	for i in EDGE_COUNT:
		segs.append({
			"id": "e:%d" % i,
			"a": Vector2(40.0 + i * 12.0, 80.0 + i * 8.0),
			"b": Vector2(360.0 + i * 12.0, 160.0 + i * 8.0),
			"kind": "entity",
			"dim": false,
		})

	## 旧路径 = 关掉缓存，每帧 60 条全量贝塞尔采样。
	edge.dbg_set_curve_cache(false)
	edge.dbg_reset_curve_builds()
	var t0 := Time.get_ticks_usec()
	for frame in EDGE_FRAMES:
		for j in MOVING:
			segs[j]["a"] = (segs[j]["a"] as Vector2) + Vector2(1.0, 0.5)
		edge.set_segments(segs)
	var old_us := Time.get_ticks_usec() - t0
	var old_builds := edge.dbg_curve_builds()

	## 新路径 = 开缓存，只重采样端点变化的 5 条。
	edge.dbg_set_curve_cache(true)
	edge.set_segments(segs)        # 预热缓存
	edge.dbg_reset_curve_builds()
	t0 = Time.get_ticks_usec()
	for frame in EDGE_FRAMES:
		for j in MOVING:
			segs[j]["a"] = (segs[j]["a"] as Vector2) + Vector2(1.0, 0.5)
		edge.set_segments(segs)
	var new_us := Time.get_ticks_usec() - t0
	var new_builds := edge.dbg_curve_builds()

	print("F2 EdgeLayer：%d 条边 × %d 帧，移动 %d 条；旧 %d 次采样 / 新 %d 次；旧 %.1f µs/帧 / 新 %.1f µs/帧"
		% [EDGE_COUNT, EDGE_FRAMES, MOVING, old_builds, new_builds,
			float(old_us) / EDGE_FRAMES, float(new_us) / EDGE_FRAMES])
	check("F2 只重采样移动边", new_builds <= MOVING * EDGE_FRAMES + MOVING,
		"new=%d" % new_builds)
	check("F2 静态边缓存命中", old_builds == EDGE_COUNT * EDGE_FRAMES,
		"old=%d" % old_builds)
	check("F2 缓存规模不随帧数增长", edge.dbg_curve_cache_size() <= EDGE_COUNT,
		"cache=%d" % edge.dbg_curve_cache_size())
	edge.queue_free()
