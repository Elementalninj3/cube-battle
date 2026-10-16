extends SceneTree
## TEMPORARY benchmark bootstrap (deleted after use, never committed).
## Run: Godot.exe --path <project> --resolution 1280x720 --audio-driver Dummy
##   --script res://bench_tmp.gd -- --scene res://grass_render.tscn
##   --preset 4 --warmup 300 --measure 600 --shot C:/.../shot.png


class Driver extends Node:
	var warmup := 300
	var measure := 600
	var shot := ""
	var inst: Node = null
	var camrot := 0
	var _n := 0
	var _m := 0
	var _t0 := 0
	var _draws := 0.0
	var _prims := 0.0
	var _objs := 0.0
	var _done := false

	func _process(_d: float) -> void:
		if _done:
			return
		if inst == null or not is_instance_valid(inst):
			return
		if String(inst.get("state")) != "play":
			return
		if camrot != 0 and "cam" in inst and inst.get("cam") != null:
			var c = inst.get("cam")
			if int(c.get("yaw_step")) != camrot:
				c.set("yaw_step", camrot)
				c.set("yaw", PI * 0.25 + float(camrot) * PI * 0.5)
				c.set("pending", 0)
				_n = 0
				_m = 0
				_draws = 0.0
				_prims = 0.0
				_objs = 0.0
				return
		if _n < warmup:
			_n += 1
			return
		if _m == 0:
			_t0 = Time.get_ticks_usec()
		if _m < measure:
			_draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			_objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
			_m += 1
			if _m >= measure:
				_finish()

	func _finish() -> void:
		_done = true
		var secs := float(Time.get_ticks_usec() - _t0) / 1000000.0
		var fps := float(_m) / maxf(secs, 0.001)
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
		print("[BENCH] frames=%d secs=%.2f fps=%.1f ms=%.2f draws=%.0f prims=%.0f objs=%.0f" % [_m, secs, fps, 1000.0 / maxf(fps, 0.01), _draws / _m, _prims / _m, _objs / _m])
		await get_tree().process_frame
		await get_tree().process_frame
		if shot != "":
			var img := get_tree().root.get_texture().get_image()
			img.save_png(shot)
			print("[BENCH] shot=" + shot)
		get_tree().quit()


func _parse() -> Dictionary:
	var out := {"scene": "res://grass_render.tscn", "preset": "0",
		"warmup": "300", "measure": "600", "shot": "", "camrot": "0"}
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
	c.save("user://cubebox_settings.cfg")
	var inst := (load(String(args["scene"])) as PackedScene).instantiate()
	root.add_child(inst)
	var d := Driver.new()
	d.warmup = int(args["warmup"])
	d.measure = int(args["measure"])
	d.shot = String(args["shot"])
	d.camrot = int(args["camrot"])
	d.inst = inst
	root.add_child(d)
