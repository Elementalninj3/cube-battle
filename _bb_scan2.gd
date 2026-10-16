extends SceneTree

func _initialize() -> void:
	var which := "all"
	var ua := OS.get_cmdline_user_args()
	if ua.size() > 0:
		which = ua[0]
	print("TEST_COMPONENT " + which)
	match which:
		"vfx":
			root.add_child(preload("res://bb_vfx.gd").new())
		"debug":
			root.add_child(preload("res://bb_debug.gd").new())
		"arena":
			var v = preload("res://bb_vfx.gd").new()
			root.add_child(v)
			var a = preload("res://bb_arena.gd").new()
			root.add_child(a)
			a.build(v)
		"fighter":
			var f = preload("res://bb_fighter.gd").new()
			root.add_child(f)
			f.setup_skin("cubecowboy")
		"fighter_knight":
			var f2 = preload("res://bb_fighter.gd").new()
			root.add_child(f2)
			f2.setup_skin("cubeknight")
		"fighter_ninja":
			var f3 = preload("res://bb_fighter.gd").new()
			root.add_child(f3)
			f3.setup_skin("ninja")
		"lighting":
			var n := Node3D.new()
			root.add_child(n)
			preload("res://core/cb_lighting.gd").build(n, 0, true, 1, 2, 2)
		"lighting_nogi":
			var n2 := Node3D.new()
			root.add_child(n2)
			preload("res://core/cb_lighting.gd").build(n2, 0, true, 1, 0, 2)
		"fighter3":
			var a = preload("res://bb_fighter.gd").new()
			root.add_child(a)
			a.setup_skin("cubecowboy")
			a.setup_skin("cubecowboy")
		"fighter2x2":
			var p = preload("res://bb_fighter.gd").new()
			root.add_child(p)
			var q = preload("res://bb_fighter.gd").new()
			root.add_child(q)
			p.setup_skin("cubecowboy")
			q.setup_skin("cubecowboy")
			p.setup_skin("cubecowboy")
			q.setup_skin("cubecowboy")


func _process(_delta: float) -> bool:
	if Engine.get_process_frames() > 8:
		print("TEST_DONE")
		quit()
		return true
	return false
