extends RefCounted
## Open World — Grass builder: the exact same Big 1v1 Arena (same tiles,
## same props, same 1v1 lighting) with Binbun grass blades across the floor.
##
## Ground visuals come from ow_big_builder (bb_arena style, SIZE 40);
## grass is one instanced MultiMesh using the project's Binbun grass
## shader/material, like the old grass_render mode.

const BigBuilder = preload("res://openworld/ow_big_builder.gd")
const GrassMats = preload("res://openworld/ow_builder.gd")
const CBPerf = preload("res://core/cb_perf.gd")

const GRASS_COUNT := 50000
const SEED := 7


static func build(world: Node3D) -> Dictionary:
	var built: Dictionary = BigBuilder.build(world)
	_plant_grass(world, built)
	built["grass_count"] = GRASS_COUNT
	return built


static func _plant_grass(world: Node3D, built: Dictionary) -> void:
	# Exact same blades as the Grass Render world (grass_render.gd): 0.4x0.4
	# billboard quads, 2x2 subdiv, base at y=0, random yaw, uniform scatter,
	# one instanced draw call, no shadows. (~50% smaller than the old blades
	# this map used.) Only prop trunks are kept clear so grass never clips
	# through rocks/trees.
	var arena = built.get("arena", null)
	var blocked: Array = []
	if arena != null and is_instance_valid(arena):
		for p in arena.props:
			var bp: Vector3 = p["pos"]
			blocked.append({"p": Vector2(bp.x, bp.z), "r": 1.2})
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	# Tri budget: single quad = 2 tris/blade. 20k cap: ~40k prims.
	# Same look (shape is texture; bend linear vs curved on 0.4m blades).
	quad.subdivide_width = 0
	quad.subdivide_depth = 0
	quad.center_offset = Vector3(0, 0.2, 0)
	var qm := StandardMaterial3D.new()
	qm.vertex_color_use_as_albedo = true
	qm.roughness = 0.9
	quad.material = qm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# No custom-data buffer: the active Binbun shader never reads
	# INSTANCE_CUSTOM (only the unused cb_grass_opt variant does).
	mm.use_custom_data = false
	mm.mesh = quad
	var quality := 2
	var cc := ConfigFile.new()
	if cc.load("user://cubebox_settings.cfg") == OK:
		quality = clampi(int(cc.get_value("game", "quality", 2)), 0, 2)
	var target := CBPerf.grass_count_for_quality(quality, GRASS_COUNT)
	mm.instance_count = target
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var half: float = 40.0
	var placed := 0
	var guard := 0
	while placed < target and guard < target * 6:
		guard += 1
		var p := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		var bad := false
		for b in blocked:
			var bd: Vector2 = b["p"]
			var dx := p.x - bd.x
			var dy := p.y - bd.y
			var rr: float = b["r"]
			if dx * dx + dy * dy < rr * rr:
				bad = true
				break
		if bad:
			continue
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		mm.set_instance_transform(placed, Transform3D(basis, Vector3(p.x, 0.0, p.y)))
		# Custom-data writes removed (Binbun ignores them); the RNG draws
		# are still consumed so the deterministic layout is unchanged.
		rng.randf()
		rng.randf()
		placed += 1
	mm.visible_instance_count = placed
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GrassField"
	mmi.multimesh = mm
	mmi.material_override = GrassMats.make_grass_material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	CBPerf.apply_mmi_culling(mmi, half + 2.0)
	world.add_child(mmi)
	world.set_meta("ow_grass_full", placed)
