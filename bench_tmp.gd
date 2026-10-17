extends SceneTree
## TEMPORARY benchmark bootstrap (deleted after use, never committed).
## Run: Godot.exe --path <project> --resolution 1280x720 --audio-driver Dummy
##   --script res://bench_tmp.gd -- --scene res://grass_render.tscn
##   --preset 0 --warmup 300 --measure 600 --shot C:/.../shot.png
## Options:
##   --turns N     sweep camera through N quarter-turns (default 1: settled view)
##   --hidegrass 1 hide all MultiMeshInstance3D (isolates grass cost)
##   --noshadow 1  disable sun shadows (isolates shadow cost)
##   --scale F     viewport 3D scaling (fill-rate test)
## Reports wall frame time percentiles (p50/p95/p99/max), 1% low FPS,
## stutter counts, TIME_PROCESS/TIME_PHYSICS monitors, draws/prims/objects,
## static + video memory.


class Driver extends Node:
	var warmup := 300
	var measure := 600
	var shot := ""
	var inst: Node = null
	var turns := 1
	var hidegrass := false
	var noshadow := false
	var scale := 1.0
	var msaa := -1
	var nofog := false
	var trace := false
	var toggles: PackedStringArray = PackedStringArray()
	var _ab_mats: Dictionary = {}
	var _ab_orig: Dictionary = {}
	var _seg_dts: Array = []
	var _seg := -2
	var _seg_skip := 12
	var _grass_nodes: Array = []
	var _env: Environment = null
	var _sun: DirectionalLight3D = null

	func _cache_nodes() -> void:
		if not _grass_nodes.is_empty():
			return
		for n in inst.find_children("*", "MultiMeshInstance3D", true, false):
			_grass_nodes.append(n)
		var we := inst.find_children("*", "WorldEnvironment", true, false)
		if not we.is_empty():
			_env = (we[0] as WorldEnvironment).environment
		var ls := inst.find_children("*", "DirectionalLight3D", true, false)
		if not ls.is_empty():
			_sun = ls[0]

	func _apply_toggle(t: String) -> void:
		_cache_nodes()
		match t:
			"grass_off":
				for n in _grass_nodes:
					(n as Node3D).visible = false
			"grass_on":
				for n in _grass_nodes:
					(n as Node3D).visible = true
			"msaa0", "msaa1", "msaa2":
				get_tree().root.msaa_3d = int(t.substr(4, 1))
			"fog_off":
				if _env != null:
					_env.fog_enabled = false
			"fog_on":
				if _env != null:
					_env.fog_enabled = true
			"shadow_off":
				if _sun != null:
					_sun.shadow_enabled = false
			"shadow_on":
				if _sun != null:
					_sun.shadow_enabled = true
			"orig":
				for mmi in _ab_mats.keys():
					(mmi as MultiMeshInstance3D).material_override = _ab_mats[mmi]
			"cutout":
				for mmi in _ab_orig.keys():
					(mmi as MultiMeshInstance3D).material_override = _ab_orig[mmi]

	func _apply_seg() -> void:
		_apply_toggle(toggles[_seg])
		_seg_skip = 15
	var _applied := false
	var _turn := 0
	var _n := 0
	var _m := 0
	var _done := false
	var _draws := 0.0
	var _prims := 0.0
	var _objs := 0.0
	var _proc := 0.0
	var _phys := 0.0
	var _dt_turn: PackedFloat32Array = PackedFloat32Array()
	var _dt_all: PackedFloat32Array = PackedFloat32Array()
	var _last_usec := 0
	var _t0 := 0

	func _apply_turn() -> void:
		if "cam" in inst and inst.get("cam") != null:
			var c = inst.get("cam")
			c.set("yaw_step", _turn)
			c.set("yaw", PI * 0.25 + float(_turn) * PI * 0.5)
			c.set("pending", 0)
		_n = 0
		_m = 0
		_dt_turn = PackedFloat32Array()
		if not toggles.is_empty():
			_seg_dts = []
			for i in toggles.size():
				_seg_dts.append(PackedFloat32Array())
			_seg = -2
			_seg_skip = 0
			_apply_seg()

	func _process(_d: float) -> void:
		if _done:
			return
		if inst == null or not is_instance_valid(inst):
			return
		if String(inst.get("state")) != "play":
			return
		if not _applied:
			_applied = true
			if hidegrass:
				for n in inst.find_children("*", "MultiMeshInstance3D", true, false):
					(n as Node3D).visible = false
			if noshadow:
				for n in inst.find_children("*", "DirectionalLight3D", true, false):
					(n as DirectionalLight3D).shadow_enabled = false
			if absf(scale - 1.0) > 0.0001:
				get_tree().root.scaling_3d_scale = scale
			if msaa >= 0:
				get_tree().root.msaa_3d = msaa
			if nofog:
				var we := inst.find_children("*", "WorldEnvironment", true, false)
				if not we.is_empty():
					((we[0] as WorldEnvironment).environment as Environment).fog_enabled = false
			if not toggles.is_empty():
				var orig_sh: Shader = load("res://_bench_variants/orig_grass.gdshader")
				_cache_nodes()
				for n in _grass_nodes:
					var mmi := n as MultiMeshInstance3D
					if mmi.material_override is ShaderMaterial:
						var om: ShaderMaterial = (mmi.material_override as ShaderMaterial).duplicate()
						om.shader = orig_sh
						_ab_mats[mmi] = om
						_ab_orig[mmi] = mmi.material_override
		var now_usec := Time.get_ticks_usec()
		if _n == 0 and _m == 0:
			_last_usec = now_usec
			_apply_turn()
		var dt_ms := float(now_usec - _last_usec) / 1000.0
		_last_usec = now_usec
		if _n < warmup:
			_n += 1
			return
		if _m == 0:
			_t0 = now_usec
		if _m < measure:
			var collect := true
			if not toggles.is_empty():
				var seg := _m / maxi(1, measure / toggles.size())
				seg = mini(seg, toggles.size() - 1)
				if seg != _seg:
					_seg = seg
					_apply_seg()
				if _seg_skip > 0:
					_seg_skip -= 1
					collect = false
			if collect:
				_dt_turn.append(dt_ms)
				_dt_all.append(dt_ms)
				if not toggles.is_empty() and _seg >= 0 and _seg < _seg_dts.size():
					var seg_arr: PackedFloat32Array = _seg_dts[_seg]
					seg_arr.append(dt_ms)
					_seg_dts[_seg] = seg_arr
				_draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
				_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
				_objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
				_proc += Performance.get_monitor(Performance.TIME_PROCESS)
				_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
			_m += 1
			if _m >= measure:
				_report_turn()
				_turn += 1
				if _turn >= turns:
					_finish()
				else:
					_apply_turn()

	func _stats(dts: PackedFloat32Array, label: String) -> void:
		if dts.is_empty():
			return
		var s := dts.duplicate()
		s.sort()
		var n := s.size()
		var total := 0.0
		for v in s:
			total += v
		var avg := total / float(n)
		var p50 := s[int(n * 0.50)]
		var p95 := s[int(min(n - 1, int(n * 0.95)))]
		var p99 := s[int(min(n - 1, int(n * 0.99)))]
		var worst := s[n - 1]
		var low_n := maxi(1, int(ceil(float(n) * 0.01)))
		var low_ms := 0.0
		for i in low_n:
			low_ms += s[n - 1 - i]
		low_ms /= float(low_n)
		var over16 := 0
		var over33 := 0
		var over50 := 0
		for v in s:
			if v > 16.67:
				over16 += 1
			if v > 33.33:
				over33 += 1
			if v > 50.0:
				over50 += 1
		print("[BENCH] %s n=%d avg=%.2fms(=%.1f fps) p50=%.2f p95=%.2f p99=%.2f max=%.2f | 1%%low=%.1f fps | >16.7ms=%d >33.3ms=%d >50ms=%d" % [
			label, n, avg, 1000.0 / maxf(avg, 0.001), p50, p95, p99, worst,
			1000.0 / maxf(low_ms, 0.001), over16, over33, over50])

	func _report_turn() -> void:
		_stats(_dt_turn, "turn%d" % _turn)
		if not toggles.is_empty():
			for i in _seg_dts.size():
				_stats(_seg_dts[i], "seg%d:%s" % [i, toggles[i]])
		if trace:
			var parts: PackedStringArray = PackedStringArray()
			for i in mini(_dt_turn.size(), 240):
				parts.append("%.1f" % _dt_turn[i])
			print("[BENCH] trace=" + ",".join(parts))

	func _finish() -> void:
		_done = true
		var secs := float(Time.get_ticks_usec() - _t0) / 1000000.0
		var n := _dt_all.size()
		print("[BENCH] turns=%d frames=%d secs=%.2f" % [turns, n, secs])
		_stats(_dt_all, "overall")
		print("[BENCH] monitors: process=%.2fms physics=%.2fms draws=%.0f prims=%.0f objects=%.0f" % [
			_proc / maxf(float(n), 1.0), _phys / maxf(float(n), 1.0),
			_draws / maxf(float(n), 1.0), _prims / maxf(float(n), 1.0),
			_objs / maxf(float(n), 1.0)])
		print("[BENCH] mem: static=%.1fMB video=%.1fMB" % [
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
		var chunks := 0
		var vis_total := 0
		var inst_total := 0
		if "grass_chunks" in inst:
			var arr: Array = inst.get("grass_chunks")
			chunks = arr.size()
			for gm in arr:
				var mm: MultiMesh = (gm as MultiMeshInstance3D).multimesh
				vis_total += mm.visible_instance_count
				inst_total += mm.instance_count
		else:
			var gm2 := inst.get_node_or_null("GrassField") as MultiMeshInstance3D
			if gm2 != null and gm2.multimesh != null:
				chunks = 1
				vis_total = gm2.multimesh.visible_instance_count
				inst_total = gm2.multimesh.instance_count
		print("[BENCH] chunks=%d blades_vis=%d blades_tot=%d" % [chunks, vis_total, inst_total])
		await get_tree().process_frame
		await get_tree().process_frame
		if shot != "":
			var img := get_tree().root.get_texture().get_image()
			img.save_png(shot)
			print("[BENCH] shot=" + shot)
		get_tree().quit()


func _parse() -> Dictionary:
	var out := {"scene": "res://grass_render.tscn", "preset": "0",
		"warmup": "300", "measure": "600", "shot": "", "turns": "1",
		"hidegrass": "0", "noshadow": "0", "scale": "1.0", "ov": "",
		"msaa": "-1", "nofog": "0", "trace": "0", "toggles": ""}
	var raw := OS.get_cmdline_user_args()
	var i := 0
	while i < raw.size():
		var a := String(raw[i])
		if a.begins_with("--") and i + 1 < raw.size():
			out[a.trim_prefix("--")] = String(raw[i + 1])
			i += 2
		else:
			i += 1
	return out


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var args := _parse()
	var c := ConfigFile.new()
	c.set_value("game", "quality", 2)
	c.set_value("game", "shadow_quality", 1)
	c.set_value("game", "lighting_profile", int(args["preset"]))
	if String(args.get("ov", "")) != "":
		var ov := {}
		for pair in String(args["ov"]).split(";"):
			var kv := pair.split("=")
			if kv.size() == 2:
				ov[kv[0]] = float(kv[1])
		c.set_value("light_profile_%d" % int(args["preset"]), "overrides", ov)
	c.save("user://cubebox_settings.cfg")
	var inst := (load(String(args["scene"])) as PackedScene).instantiate()
	root.add_child(inst)
	var d := Driver.new()
	d.warmup = int(args["warmup"])
	d.measure = int(args["measure"])
	d.shot = String(args["shot"])
	d.turns = maxi(1, int(args["turns"]))
	d.hidegrass = String(args["hidegrass"]) == "1"
	d.noshadow = String(args["noshadow"]) == "1"
	d.scale = float(args["scale"])
	d.msaa = int(args["msaa"])
	d.nofog = String(args["nofog"]) == "1"
	d.trace = String(args["trace"]) == "1"
	if String(args["toggles"]) != "":
		d.toggles = String(args["toggles"]).split(",")
	d.inst = inst
	root.add_child(d)
