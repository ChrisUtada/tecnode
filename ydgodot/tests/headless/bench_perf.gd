extends SceneTree
## F1/F4/F5 合成基准（不进全量回归）。
## 运行：godot --headless --path . --script res://tests/headless/bench_perf.gd
## 输出带 before_/after_ 数值，直接抄进 UX_FLOW_PLAN.md 的验收记录。

const N_NODES := 60
const N_EDGES := 90

var fail := false


func _initialize() -> void:
	print("=== F1/F4/F5 基准 ===")
	var c := CaseLoader.new()
	if not c.load_case():
		push_error(c.load_error)
		quit(1)
		return
	var g := _build_graph(c)
	print("nodes=%d edges=%d" % [g.nodes.size(), g.edges.size()])
	_bench_f1(g)
	_bench_f4(g)
	_bench_f5(g)
	_bench_f6(g)
	_bench_f9(g, c)
	quit(0 if not fail else 1)


func _build_graph(c: CaseLoader) -> GraphState:
	var g := GraphState.new(c)
	var ids: Array = []
	for s in c.case_def.scenes:
		ids.append(["loc", s.id])
	for it in c.case_def.items:
		ids.append(["item", it.id])
	for ch in c.case_def.chars:
		ids.append(["char", ch.id])
	for cl in c.case_def.clues:
		ids.append(["clue", cl.id])
	var keys: Array = []
	for i in mini(ids.size(), N_NODES):
		var pair: Array = ids[i]
		var n := g.add_node(String(pair[0]), String(pair[1]))
		n["x"] = 120.0 + float(i % 10) * 160.0
		n["y"] = 100.0 + float(i / 10) * 110.0
		keys.append(String(n["key"]))
	for i in N_EDGES:
		g.link(String(keys[i % keys.size()]), String(keys[(i * 7 + 5) % keys.size()]), "entity")
	var collapsed := {}
	var k := 0
	for s in c.case_def.scenes:
		if k >= 4:
			break
		collapsed[s.id] = true
		k += 1
	g.collapsed = collapsed
	# 给折叠场景塞 home_scene，制造 F5 的“容器 × 节点 × 边”扫描。
	var j := 0
	for key in g.nodes.keys():
		var n: Dictionary = g.nodes[key]
		if String(n.get("kind", "")) == "item":
			var sids: Array = c.scenes.keys()
			n["home_scene"] = String(sids[j % mini(sids.size(), 4)])
			j += 1
	return g


func _bench_f1(g: GraphState) -> void:
	var keys: Array = []
	for key in g.nodes.keys():
		keys.append(String(key))
	var t0 := Time.get_ticks_usec()
	_legacy_force(g, keys)
	var before := Time.get_ticks_usec() - t0
	var fl = load("res://core/ForceLayout.gd").new()
	t0 = Time.get_ticks_usec()
	fl.prepare(g, keys)
	fl.step(8)
	var quick := Time.get_ticks_usec() - t0
	var total_frame := 0
	var frames := 0
	while not fl.done():
		t0 = Time.get_ticks_usec()
		fl.step(5)
		total_frame += Time.get_ticks_usec() - t0
		frames += 1
	var avg_frame := total_frame / maxi(frames, 1)
	print("F1 nodes=%d before_260_us=%d after_quick8_us=%d after_frame5_us=%d frames=%d"
		% [keys.size(), before, quick, avg_frame, frames])
	print("F1 first_frame_budget_ok=%s" % str(quick < before and avg_frame < before))


func _bench_f4(g: GraphState) -> void:
	var save := SaveSystem.new(g, "A001", "user://bench_perf.save")
	var t0 := Time.get_ticks_usec()
	for i in 20:
		var a := JSON.stringify(save.snapshot())
		var b := JSON.stringify(save.snapshot())
		if a == b:
			pass
		JSON.stringify(save.snapshot())
	var legacy := Time.get_ticks_usec() - t0
	save.dbg_snapshot_calls = 0
	save.dbg_json_calls = 0
	t0 = Time.get_ticks_usec()
	for i in 20:
		var cur := save.snapshot_json()
		if cur == save.last_json:
			continue
		save.last_json = cur
		save.pending_json = cur
	var fast := Time.get_ticks_usec() - t0
	print("F4 20_commits before_snapshots=60 before_json=60 before_us=%d after_snapshots=%d after_json=%d after_us=%d"
		% [legacy, save.dbg_snapshot_calls, save.dbg_json_calls, fast])


func _bench_f5(g: GraphState) -> void:
	var t0 := Time.get_ticks_usec()
	_legacy_hidden(g)
	var before := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	g.recompute_hidden()
	var after := Time.get_ticks_usec() - t0
	print("F5 collapsed=%d nodes=%d before_us=%d after_us=%d speedup=%.1fx"
		% [g.collapsed.size(), g.nodes.size(), before, after, float(before) / maxf(float(after), 1.0)])
	if after >= before and before > 10:
		fail = true


func _bench_f6(g: GraphState) -> void:
	g.clear_logs()
	for i in 100:
		g.add_log("F6 history line %d" % i, "sys")
	var lw := LogWin.new()
	lw.setup_log(g)
	var built := lw._rows_built
	g.add_log("F6 append probe", "sys")
	lw.refresh_log()
	print("F6 history=100 append_rows_built=%d total_rows_built=%d"
		% [lw._rows_built - built, lw._rows_built])
	if lw._rows_built - built != 1:
		fail = true
	lw.free()


func _bench_f9(g: GraphState, c: CaseLoader) -> void:
	var plots: Array = []
	for i in 20:
		plots.append({"at": GardenSystem.now_ms_now() - 1000, "x": 10 + i, "y": 40, "hit": false})
	g.garden = {"seed": false, "plots": plots}
	var garden := GardenWin.new()
	get_root().add_child(garden)
	garden.setup_garden(g, c)
	garden._rebuild_plants()
	var before: int = garden._stage_refreshes
	for i in 30:
		garden._refresh_growth()
	var delta: int = garden._stage_refreshes - before
	print("F9 plants=20 refresh_ticks=30 stage_rebuilds_before=600 stage_rebuilds_after=%d" % delta)
	if delta != 0:
		fail = true
	garden.free()


func _legacy_force(g: GraphState, list: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED
	var pos := {}
	for key in list:
		var n := g.node(key)
		var p := Vector2(float(n.get("x", 0.0)), float(n.get("y", 0.0)))
		if p.x < 0.0:
			p = Vector2(rng.randf() * 800.0, rng.randf() * 600.0)
		pos[key] = p
	var free := {}
	var radius := {}
	for key in list:
		free[key] = not bool(g.node(key).get("pinned", false))
		radius[key] = 80.0 if g.is_container_node(key) else 68.0
	for _it in 260:
		for i in list.size():
			var a: String = list[i]
			for j in range(i + 1, list.size()):
				var b: String = list[j]
				var pa: Vector2 = pos[a]
				var pb: Vector2 = pos[b]
				var delta: Vector2 = pb - pa
				var d2 := delta.length_squared()
				if d2 < 1.0:
					delta = Vector2(rng.randf() - 0.5, rng.randf() - 0.5)
					d2 = 1.0
				var d := sqrt(d2)
				var u := delta / d
				var rep := 30000.0 / d2
				if free[a]:
					pa -= u * rep
				if free[b]:
					pb += u * rep
				var min_d: float = float(radius[a]) + float(radius[b]) + 14.0
				if d < min_d:
					var push := (min_d - d) * 0.5
					if free[a]:
						pa -= u * push
					if free[b]:
						pb += u * push
				pos[a] = pa
				pos[b] = pb
		for e in g.edges:
			var a := String(e.get("a", ""))
			var b := String(e.get("b", ""))
			if not pos.has(a) or not pos.has(b):
				continue
			var pa: Vector2 = pos[a]
			var pb: Vector2 = pos[b]
			var delta: Vector2 = pb - pa
			var d := delta.length()
			if d < 0.001:
				continue
			var u := delta / d
			var rest := 185.0
			if String(e.get("rel", "entity")) == "move":
				rest = 300.0
			elif String(e.get("rel", "entity")) == "cond":
				rest = 150.0
			var f := (d - rest) * 0.014
			if free[a]:
				pa += u * f
			if free[b]:
				pb -= u * f
			pos[a] = pa
			pos[b] = pb
		for key in list:
			if not free[key]:
				continue
			var p: Vector2 = pos[key]
			p += Vector2(2000.0 * 0.5 - p.x, 1300.0 * 0.5 - p.y) * 0.0022
			pos[key] = p


func _legacy_hidden(g: GraphState) -> void:
	for key in g.nodes.keys():
		g.hidden.erase(key)
	var changed := true
	while changed:
		changed = false
		for cid in g.collapsed.keys():
			var container_key := g.key_of("loc", String(cid))
			if not g.nodes.has(container_key):
				container_key = g.key_of("item", String(cid))
			for key in g.nodes.keys():
				var n: Dictionary = g.nodes[key]
				if g.stored.has(key) or g.hidden.has(key) or bool(n.get("pinned", false)):
					continue
				if key == container_key:
					continue
				if String(n.get("home_scene", "")) != String(cid):
					continue
				var exported := false
				for e in g.edges:
					if e["a"] != key and e["b"] != key:
						continue
					var other_key: String = String(e["a"]) if e["a"] != key else String(e["b"])
					if other_key == container_key:
						continue
					var other := g.node(other_key)
					if other.is_empty():
						continue
					if g.hidden.has(other_key) or g.stored.has(other_key):
						continue
					if String(other.get("home_scene", "")) == String(cid):
						continue
					exported = true
					break
				if not exported:
					g.hidden[key] = true
					changed = true
