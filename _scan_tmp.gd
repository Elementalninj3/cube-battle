extends SceneTree

const PATHS := [
	"res://block_brawl.tscn",
	"res://openworld/ow_world.tscn",
	"res://openworld/ow1_world.tscn",
	"res://openworld/ow2_world.tscn",
]


func _initialize() -> void:
	_run()


func _run() -> void:
	for p in PATHS:
		if not ResourceLoader.exists(p):
			print("MISSING ", p)
			continue
		var ps := load(p) as PackedScene
		if ps == null:
			print("LOADFAIL ", p)
			continue
		var n := ps.instantiate()
		root.add_child(n)
		for i in 6:
			await process_frame
		print("=== ", p)
		_scan(n)
		n.free()
		for i in 2:
			await process_frame
	print("=== DONE")
	quit()


func _scan(n: Node) -> void:
	var stack: Array = [n]
	var nulls: Array = []
	var culled: Array = []
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		stack.append_array(cur.get_children())
		if cur is GeometryInstance3D:
			var g := cur as GeometryInstance3D
			var why := ""
			if cur is MeshInstance3D:
				var mi := cur as MeshInstance3D
				if mi.mesh == null:
					why = "mesh=null"
				elif mi.mesh.get_surface_count() == 0:
					why = "mesh has 0 surfaces (%s)" % mi.mesh.get_class()
				else:
					for s in mi.mesh.get_surface_count():
						if mi.mesh.surface_get_material(s) == null:
							why = "surface %d/%d material=null" % [s, mi.mesh.get_surface_count()]
							break
			elif cur is MultiMeshInstance3D:
				var mmi := cur as MultiMeshInstance3D
				if mmi.multimesh == null:
					why = "multimesh=null"
				elif mmi.multimesh.mesh == null:
					why = "mm.mesh=null"
				else:
					for s in mmi.multimesh.mesh.get_surface_count():
						if mmi.multimesh.mesh.surface_get_material(s) == null:
							why = "mm surface %d/%d material=null" % [s, mmi.multimesh.mesh.get_surface_count()]
							break
			else:
				why = "other GI type (no mesh)"
			if why != "" and g.material_override == null:
				nulls.append("%s [%s] override=%s %s" % [str(cur.get_path()), cur.get_class(), g.material_override != null, why])
			if g.extra_cull_margin != 0.0 or g.visibility_range_end > 0.0 \
			or g.visibility_range_end_margin != 0.0 or g.visibility_range_fade_mode != 0:
				culled.append("%s | margin=%s vr_end=%s vr_margin=%s fade=%s" % [
					str(cur.get_path()), g.extra_cull_margin, g.visibility_range_end,
					g.visibility_range_end_margin, g.visibility_range_fade_mode])
	print("  NULL_MATERIAL count=", nulls.size())
	for x in nulls:
		print("    ", x)
	print("  CULLED count=", culled.size())
	for x in culled:
		print("    ", x)
