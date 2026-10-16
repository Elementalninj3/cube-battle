extends RefCounted
## Open-world builder: hybrid Binbun-grass + voxel environment, matching the
## Grass Render demo's look and rendering approach.
##
## Layer A (ground): one 44x44 Binbun-shaded plane (world-space coloring,
## seamless at any size) + one instanced grass-blade MultiMesh, exactly the
## demo's approach. No per-tile nodes.
##
## Layer B (voxel structures): a central dais, two block walls and two
## floating platforms on pillars, merged into ONE MultiMesh (dirt bases +
## grass checker caps, 1 draw call) with a few exact StaticBody boxes.
## The fighter assumes flat ground (bb_fighter lands at y=0), so solid
## structures block movement via push-out circles instead of being climbed.
##
## Returned dict: {obstacles, spawn, camps, grass_count}

const CBLayers = preload("res://core/cb_layers.gd")
const CBPerf = preload("res://core/cb_perf.gd")

const GRASS_DIR := "res://free assets/grassshader/assets/BinbunGrass/src/"

const HALF := 20.0 # playable half-extent (fighters clamp to 19)
const SEED := 1234
const GRASS_COUNT := 11000 # open meadow with clusters, one instanced draw
const CLEAR_C := Vector2(0, 4) # central combat clearing (ellipse radii)
const CLEAR_R := Vector2(10, 8)
const DIRT_COL := Color(0.42, 0.3, 0.2)

# Palette copied 1:1 from BinbunGrass palette_01.tres so ground and blades
# use the downloaded shader's exact intended colors.
const PALETTE := [Color(0.658824, 0.792157, 0.345098),
	Color(0.458824, 0.654902, 0.262745),
	Color(0.27451, 0.509804, 0.196078)]


static var _noise_cached: NoiseTexture2D = null
static var _grad_cached: GradientTexture2D = null
static var _wind_cached: NoiseTexture2D = null
# Shared production materials: every grass/ground field uses identical
# parameters, so one ShaderMaterial each avoids repeat compiles and keeps
# texture binds shared. (No per-mode mutation happens after creation, so
# sharing is safe across Grass Render / OW2 / OW3.)
static var _grass_mat: ShaderMaterial = null
static var _ground_mat: ShaderMaterial = null


static func _noise_tex(seed: int, freq: float, size: int = 256) -> NoiseTexture2D:
	if _noise_cached != null and _noise_cached.width == size:
		return _noise_cached
	var fn := FastNoiseLite.new()
	fn.seed = seed
	fn.frequency = freq
	var nt := NoiseTexture2D.new()
	nt.width = size
	nt.height = size
	nt.seamless = true
	nt.seamless_blend_skirt = 0.2
	nt.noise = fn
	_noise_cached = nt
	return nt


static func _gradient_tex() -> GradientTexture2D:
	if _grad_cached != null:
		return _grad_cached
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.166667, 0.5, 0.833333])
	g.colors = PackedColorArray([PALETTE[0], PALETTE[1], PALETTE[2]])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	_grad_cached = gt
	return gt


static func _wind_tex() -> NoiseTexture2D:
	if _wind_cached != null:
		return _wind_cached
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fn.fractal_octaves = 3
	var nt := NoiseTexture2D.new()
	nt.width = 1024
	nt.height = 1024
	nt.seamless = true
	nt.seamless_blend_skirt = 0.2
	nt.noise = fn
	_wind_cached = nt
	return nt


# The downloaded Binbun ground.gdshader, demo (grass_ground_01.tres) setup.
static func make_ground_material() -> ShaderMaterial:
	if _ground_mat != null and is_instance_valid(_ground_mat):
		return _ground_mat
	var m := ShaderMaterial.new()
	m.shader = load(GRASS_DIR + "shader/ground.gdshader")
	m.set_shader_parameter("noise_texture", _noise_tex(6, 0.008))
	m.set_shader_parameter("color_gradient", _gradient_tex())
	_ground_mat = m
	return m


# The downloaded Binbun grass.gdshader, demo (grass_01.tres) setup:
# billboard quads, 2x2 shape atlas, dithered alpha, gentle breeze (the demo
# ships wind_velocity (0,0); a light breeze shows the intended TIME wind).
static func make_grass_material() -> ShaderMaterial:
	if _grass_mat != null and is_instance_valid(_grass_mat):
		return _grass_mat
	var m := ShaderMaterial.new()
	m.shader = load(GRASS_DIR + "shader/grass.gdshader")
	m.set_shader_parameter("billboard", true)
	m.set_shader_parameter("shape_texture", load(GRASS_DIR + "texture/basic/grass_basic_02.png"))
	m.set_shader_parameter("shape_atlas", load(GRASS_DIR + "texture/basic/grass_basic_atlas.png"))
	m.set_shader_parameter("use_atlas", true)
	m.set_shader_parameter("noise_texture", _noise_tex(6, 0.008))
	m.set_shader_parameter("color_gradient", _gradient_tex())
	m.set_shader_parameter("random_variation", 0.0)
	m.set_shader_parameter("wind_texture", _wind_tex())
	m.set_shader_parameter("wind_velocity", Vector2(0.5, 0.25))
	m.set_shader_parameter("alpha_cut_start", 0.4)
	m.set_shader_parameter("alpha_cut_end", 0.6)
	m.set_shader_parameter("alpha_mode", 1)
	_grass_mat = m
	return m


# Arena-style grass checker for voxel cap tiles.
static func _cap_color(gx: int, gz: int, rng: RandomNumberGenerator) -> Color:
	var v := 0.44 + rng.randf() * 0.05 + float((gx + gz) % 2) * 0.025
	return Color.from_hsv(0.29 + rng.randf() * 0.02, 0.5, v)


static func build(world: Node3D) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_build_ground(world)
	var obstacles: Array = []
	_build_voxels(world, rng, obstacles)
	var grass_count := _plant_grass(world, rng)
	return {"obstacles": obstacles, "spawn": Vector3(0, 0, 14),
		"camps": [], "grass_count": grass_count}


static func _build_ground(world: Node3D) -> void:
	# Layer A: single Binbun plane + one ground collision box.
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var gp := PlaneMesh.new()
	gp.size = Vector2(HALF * 2.0 + 4.0, HALF * 2.0 + 4.0)
	ground.mesh = gp
	ground.material_override = make_ground_material()
	# The big flat cash-crop: no shadow-pass work for the ground itself.
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	world.add_child(ground)
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	CBLayers.apply_static(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(HALF * 2.0, 1.0, HALF * 2.0)
	shape.shape = box
	body.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	world.add_child(body)


# Layer B: merged voxel structures. Dirt bases + grass caps go in one
# MultiMesh (1 draw call); solid ones get one exact StaticBody each.
# rects/tops feed grass placement (footprint rejection + cap-top blades).
static func _build_voxels(world: Node3D, rng: RandomNumberGenerator, obstacles: Array) -> void:
	var boxes: Array = [] # {pos, size, col}
	var solids: Array = [] # {pos, size} collision boxes
	var rects: Array = [] # {c: Vector2, r: Vector2} grass rejection footprints
	var tops: Array = [] # {c: Vector2, r: Vector2, y: float} blade beds on caps

	# Dirt skirt under the plane rim (finishes the plate edge, 1 instance).
	boxes.append({"pos": Vector3(0, -0.54, 0),
		"size": Vector3(HALF * 2.0, 1.0, HALF * 2.0), "col": DIRT_COL})
	# Central dais 5x5x1 at (-7,-5): dirt base + 25 checker caps.
	_add_block(world, boxes, solids, rects, tops, obstacles, rng,
		Vector2(-7, -5), Vector2(5, 5), 1.0, true, 3.0)
	# Two low walls (cover obstacles): 4x1 and 3x1, 1m tall.
	_add_block(world, boxes, solids, rects, tops, obstacles, rng,
		Vector2(7.5, 2), Vector2(4, 1), 1.0, true, 0.0)
	_add_block(world, boxes, solids, rects, tops, obstacles, rng,
		Vector2(-2, -12), Vector2(3, 1), 1.0, true, 0.0)
	# Stepped formation east: 4x4 base half-height with a 2x2 second step.
	_add_block(world, boxes, solids, rects, tops, obstacles, rng,
		Vector2(12, -2), Vector2(4, 4), 0.5, true, 0.0)
	_add_block(world, boxes, solids, rects, tops, obstacles, rng,
		Vector2(12, -2), Vector2(2, 2), 1.0, true, 0.0)
	# Low grassy ledge south-west: 2x2, half height.
	_add_block(world, boxes, solids, rects, tops, obstacles, rng,
		Vector2(-13, -6), Vector2(2, 2), 0.5, true, 0.0)
	# Two floating platforms 3x3 (slab y 2.4..2.9) on slim pillars.
	_add_float(world, boxes, obstacles, rects, tops, rng, Vector2(7, -8))
	_add_float(world, boxes, obstacles, rects, tops, rng, Vector2(-12, 6))

	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	bm.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bm
	mm.instance_count = boxes.size()
	for i in boxes.size():
		var b: Dictionary = boxes[i]
		mm.set_instance_transform(i,
			Transform3D(Basis.from_scale(b["size"]), b["pos"]))
		mm.set_instance_color(i, b["col"])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Voxels"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mmi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	CBPerf.apply_mmi_culling(mmi, HALF + 4.0)
	world.add_child(mmi)
	for s in solids:
		var sd: Dictionary = s
		var body := StaticBody3D.new()
		CBLayers.apply_static(body)
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sd["size"]
		shape.shape = bs
		body.position = sd["pos"]
		body.add_child(shape)
		world.add_child(body)
	# Stash layout for grass: world stores it on itself for _plant_grass.
	world.set_meta("ow_rects", rects)
	world.set_meta("ow_tops", tops)


# Solid checker block: dirt base (y 0..h) + grass cap tiles on top.
# Extra circle r_extra (dais) or footprint-derived circles block movement.
static func _add_block(world: Node3D, boxes: Array, solids: Array,
		rects: Array, tops: Array, obstacles: Array, rng: RandomNumberGenerator,
		center: Vector2, footprint: Vector2, h: float, solid: bool,
		extra_r: float) -> void:
	var top_y := h
	boxes.append({"pos": Vector3(center.x, top_y * 0.5, center.y),
		"size": Vector3(footprint.x, top_y, footprint.y), "col": DIRT_COL})
	var gx0 := int(center.x - footprint.x * 0.5)
	var gz0 := int(center.y - footprint.y * 0.5)
	for ix in int(footprint.x):
		for iz in int(footprint.y):
			boxes.append({"pos": Vector3(gx0 + ix + 0.5, top_y + 0.06, gz0 + iz + 0.5),
				"size": Vector3(0.985, 0.12, 0.985),
				"col": _cap_color(gx0 + ix, gz0 + iz, rng)})
	if solid:
		solids.append({"pos": Vector3(center.x, top_y * 0.5, center.y),
			"size": Vector3(footprint.x, top_y, footprint.y)})
	rects.append({"c": center, "r": footprint * 0.5 + Vector2(0.4, 0.4)})
	tops.append({"c": center, "r": footprint * 0.5 - Vector2(0.4, 0.4),
		"y": top_y + 0.12})
	if extra_r > 0.0:
		obstacles.append({"p": center, "r": extra_r})
	else:
		# One circle per ~2 blocks along the long axis.
		var n := maxi(1, int(maxf(footprint.x, footprint.y) / 2.0))
		for i in n:
			var f := (float(i) + 0.5) / float(n) - 0.5
			if footprint.x >= footprint.y:
				obstacles.append({"p": center + Vector2(f * footprint.x, 0), "r": 1.1})
			else:
				obstacles.append({"p": center + Vector2(0, f * footprint.y), "r": 1.1})


# Floating 3x3 slab with grass caps on a slim pillar. The slab is above
# head height (player top ~1.9): only the pillar blocks movement.
static func _add_float(world: Node3D, boxes: Array, obstacles: Array,
		rects: Array, tops: Array, rng: RandomNumberGenerator,
		center: Vector2) -> void:
	var slab_y := 2.4
	boxes.append({"pos": Vector3(center.x, slab_y + 0.25, center.y),
		"size": Vector3(3, 0.5, 3), "col": DIRT_COL})
	var gx0 := int(center.x - 1.5)
	var gz0 := int(center.y - 1.5)
	for ix in 3:
		for iz in 3:
			boxes.append({"pos": Vector3(gx0 + ix + 0.5, slab_y + 0.56, gz0 + iz + 0.5),
				"size": Vector3(0.985, 0.12, 0.985),
				"col": _cap_color(gx0 + ix, gz0 + iz, rng)})
	boxes.append({"pos": Vector3(center.x, slab_y * 0.5, center.y),
		"size": Vector3(0.4, slab_y, 0.4), "col": DIRT_COL})
	var body := StaticBody3D.new()
	CBLayers.apply_static(body)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.4, slab_y, 0.4)
	shape.shape = bs
	body.position = Vector3(center.x, slab_y * 0.5, center.y)
	body.add_child(shape)
	world.add_child(body)
	rects.append({"c": center, "r": Vector2(0.6, 0.6)})
	obstacles.append({"p": center, "r": 0.65})
	tops.append({"c": center, "r": Vector2(1.1, 1.1), "y": slab_y + 0.62})


static func _rect_has(rects: Array, p: Vector2) -> bool:
	for r in rects:
		var rd: Dictionary = r
		var d: Vector2 = (p - (rd["c"] as Vector2)).abs()
		if d.x <= (rd["r"] as Vector2).x and d.y <= (rd["r"] as Vector2).y:
			return true
	return false


# Demo approach: billboard quads, per-instance yaw/scale, no shadows.
# Blades cover the plane (minus structure footprints + spawn clearing)
# with a small extra bed on each grass cap top. Count is quality-capped.
# No custom-data buffer: the active Binbun shader never reads
# INSTANCE_CUSTOM (only the unused cb_grass_opt variant does), and the
# whole field gets one explicit AABB so frustum culling is one test.
static func _plant_grass(world: Node3D, rng: RandomNumberGenerator) -> int:
	var quality := 2
	var cc := ConfigFile.new()
	if cc.load("user://cubebox_settings.cfg") == OK:
		quality = clampi(int(cc.get_value("game", "quality", 2)), 0, 2)
	var target := CBPerf.grass_count_for_quality(quality, GRASS_COUNT)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.7)
	# Tri budget: single quad = 2 tris/blade -> 11k blades = ~22k prims.
	# Same look (shape is texture; bend linear vs curved on 0.5m blades).
	quad.subdivide_width = 0
	quad.subdivide_depth = 0
	quad.center_offset = Vector3(0, 0.35, 0)
	var qm := StandardMaterial3D.new()
	qm.vertex_color_use_as_albedo = true
	qm.roughness = 0.9
	quad.material = qm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = false
	mm.mesh = quad
	mm.instance_count = target
	var rects: Array = world.get_meta("ow_rects")
	var tops: Array = world.get_meta("ow_tops")
	var placed := 0
	var guard := 0
	while placed < target and guard < target * 6:
		guard += 1
		# A share of blades goes to cap tops, the rest to the plane.
		if placed % 12 == 11 and not tops.is_empty():
			var t: Dictionary = tops[rng.randi_range(0, tops.size() - 1)]
			var tc: Vector2 = t["c"]
			var tr: Vector2 = t["r"]
			var tp := Vector2(rng.randf_range(tc.x - tr.x, tc.x + tr.x),
				rng.randf_range(tc.y - tr.y, tc.y + tr.y))
			_place_blade(mm, placed, tp, float(t["y"]), rng)
			placed += 1
			continue
		# ~2 in 9 blades clusters around structure edges instead of the
		# open field, so density varies naturally instead of uniformly.
		# Cluster blades are ~30% smaller than field blades.
		if placed % 9 >= 7 and not rects.is_empty():
			var cp := _cluster_point(rects, rng)
			if cp.distance_to(Vector2(0, 14)) < 2.5:
				continue
			if _rect_has(rects, cp):
				continue
			_place_blade(mm, placed, cp, 0.0, rng, 0.7)
			placed += 1
			continue
		var p := Vector2(rng.randf_range(-HALF, HALF),
			rng.randf_range(-HALF, HALF))
		if p.distance_to(Vector2(0, 14)) < 2.5: # spawn clearing
			continue
		if _in_clearing(p): # central combat clearing stays open
			continue
		if _rect_has(rects, p):
			continue
		_place_blade(mm, placed, p, 0.0, rng)
		placed += 1
	mm.visible_instance_count = placed
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GrassField"
	mmi.multimesh = mm
	mmi.material_override = make_grass_material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	CBPerf.apply_mmi_culling(mmi, HALF + 2.0)
	world.add_child(mmi)
	world.set_meta("ow_grass_full", placed)
	return placed


static func _in_clearing(p: Vector2) -> bool:
	var dx := (p.x - CLEAR_C.x) / CLEAR_R.x
	var dy := (p.y - CLEAR_C.y) / CLEAR_R.y
	return dx * dx + dy * dy < 1.0


# A point just outside a random structure footprint edge: tufts hugging
# platform rims and pillars rather than blanketing the field.
static func _cluster_point(rects: Array, rng: RandomNumberGenerator) -> Vector2:
	var rd: Dictionary = rects[rng.randi_range(0, rects.size() - 1)]
	var c: Vector2 = rd["c"]
	var r: Vector2 = rd["r"]
	var side := rng.randi_range(0, 3)
	var e := Vector2.ZERO
	match side:
		0:
			e = Vector2(rng.randf_range(-r.x, r.x), -r.y)
		1:
			e = Vector2(rng.randf_range(-r.x, r.x), r.y)
		2:
			e = Vector2(-r.x, rng.randf_range(-r.y, r.y))
		_:
			e = Vector2(r.x, rng.randf_range(-r.y, r.y))
	var a := rng.randf() * TAU
	var d := rng.randf_range(0.5, 2.5)
	return c + e + Vector2(cos(a), sin(a)) * d


static func _place_blade(mm: MultiMesh, i: int, p: Vector2, y: float,
		rng: RandomNumberGenerator, size_mul := 1.0) -> void:
	var s := rng.randf_range(0.8, 1.35) * size_mul
	var yaw := rng.randf()
	var basis := Basis(Vector3.UP, yaw * TAU).scaled(Vector3.ONE * s)
	mm.set_instance_transform(i, Transform3D(basis, Vector3(p.x, y, p.y)))
	# No INSTANCE_CUSTOM writes: the active Binbun shader ignores them
	# (only cb_grass_opt would read them). The two RNG draws are still
	# consumed so the deterministic meadow layout is byte-identical.
	if mm.use_custom_data:
		mm.set_instance_custom_data(i, Color(yaw, s / 1.35, rng.randf(), rng.randf_range(0.6, 1.0)))
	else:
		rng.randf()
		rng.randf_range(0.6, 1.0)
