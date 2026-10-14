extends RefCounted
## Open-world environment builder: assembles the explorable nature area from
## the downloaded assets (BinbunGrass shaders + Stylized Nature Megakit).
##
## Layout is hand-designed (not random scatter): a central meadow, N-S and
## E-W dirt paths, four themed groves, a landmark twisted tree, boulder
## clusters and three enemy camps, ringed by a pine border wall.
## Everything is deterministic (seeded) so the world is identical each run.
##
## Returned dict: {obstacles, spawn, camps, grass_count}
##   obstacles: Array of {"p": Vector2, "r": float} push-out circles used by
##     gameplay movement, grass rejection and enemy placement validation.
##   camps: Array of {"pos": Vector3, "skins": PackedStringArray}.

# Converted 1:1 from the Stylized Nature Megakit's .gltf sources (same
# meshes, materials and embedded textures). The original downloads in
# "free assets" stay untouched as the source of truth; KIT_SRC is the
# fallback source used when the .glb has no import data yet (e.g. the
# project was never opened in the GUI editor since the models arrived).
const KIT := "res://openworld/models/"
const KIT_SRC := "res://free assets/Stylized Nature MegaKit[Standard]/glTF/"
const GRASS_DIR := "res://free assets/grassshader/assets/BinbunGrass/src/"

const WORLD_R := 31.0 # playable half-extent (fighters clamp to this)
const GRASS_R := 32.0 # grass field half-extent
const GRASS_COUNT := 9000
const SEED := 1234

# Palette copied 1:1 from BinbunGrass palette_01.tres so the ground shader
# and the grass shader use the exact downloaded colors.
const PALETTE := [Color(0.658824, 0.792157, 0.345098),
	Color(0.458824, 0.654902, 0.262745),
	Color(0.27451, 0.509804, 0.196078)]


static func _noise_tex(seed: int, freq: float, size: int = 256) -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.seed = seed
	fn.frequency = freq
	var nt := NoiseTexture2D.new()
	nt.width = size
	nt.height = size
	nt.seamless = true
	nt.seamless_blend_skirt = 0.2
	nt.noise = fn
	return nt


static func _wind_tex() -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fn.fractal_octaves = 3
	var nt := NoiseTexture2D.new()
	nt.width = 1024
	nt.height = 1024
	nt.seamless = true
	nt.seamless_blend_skirt = 0.2
	nt.noise = fn
	return nt


static func _gradient_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.166667, 0.5, 0.833333])
	g.colors = PackedColorArray([PALETTE[0], PALETTE[1], PALETTE[2]])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	return gt


# Binbun ground.gdshader with the downloaded palette + noise setup, so the
# ground and the grass blades share one look (no seams / color mismatch).
static func make_ground_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(GRASS_DIR + "shader/ground.gdshader")
	m.set_shader_parameter("noise_texture", _noise_tex(6, 0.008))
	m.set_shader_parameter("color_gradient", _gradient_tex())
	return m


# Binbun grass.gdshader with the downloaded demo configuration
# (billboard quads, 2x2 shape atlas, dithered alpha) plus a gentle breeze
# (the demo ships wind_velocity (0,0); the shader's wind path is wired up
# and animated via TIME, so a light breeze shows the intended motion).
static func make_grass_material() -> ShaderMaterial:
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
	return m


# Template = one off-tree Node3D per model; placements duplicate() it, so
# meshes/materials stay shared. Prefers the imported .glb; falls back to
# parsing the kit's .gltf at runtime when import data is missing.
static func _load_template(model: String) -> Node3D:
	# Skip load() entirely when there is no import data: it would only log
	# a "No loader found" error before the fallback below handles it.
	if FileAccess.file_exists(KIT + model + ".glb.import"):
		var packed := load(KIT + model + ".glb") as PackedScene
		if packed != null and packed.can_instantiate():
			return packed.instantiate() as Node3D
	push_warning("OW: using runtime .gltf fallback for " + model + " (open the project in the editor once to import the .glb).")
	return _runtime_template(model)


static func _runtime_template(model: String) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(KIT_SRC + model + ".gltf", st)
	if err != OK:
		push_error("OW: cannot load megakit model " + model)
		return Node3D.new()
	var root := doc.generate_scene(st) as Node3D
	_slim_runtime_materials(root)
	return root


# Runtime-loaded ImageTextures stay uncompressed in RAM: cap albedo at
# 1024 px (with mipmaps) and drop normal maps (stylized look doesn't need
# them). Imported .glb assets already get engine texture compression, so
# this only applies to the fallback path.
static func _slim_runtime_materials(root: Node) -> void:
	var seen := {}
	var stack: Array = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			var mesh := mi.mesh
			if mesh != null:
				for s in mesh.get_surface_count():
					_slim_material(mesh.surface_get_material(s), seen)
		for c in cur.get_children():
			stack.append(c)


static func _slim_material(m: Material, seen: Dictionary) -> void:
	if not (m is StandardMaterial3D) or seen.has(m.get_instance_id()):
		return
	seen[m.get_instance_id()] = true
	var sm := m as StandardMaterial3D
	sm.normal_enabled = false
	var tex: Texture2D = sm.albedo_texture
	if tex != null:
		var img := tex.get_image()
		if img != null and not img.is_empty():
			if maxi(img.get_width(), img.get_height()) > 1024:
				var k := 1024.0 / float(maxi(img.get_width(), img.get_height()))
				img.resize(int(img.get_width() * k), int(img.get_height() * k))
			if not img.has_mipmaps():
				img.generate_mipmaps()
			sm.albedo_texture = ImageTexture.create_from_image(img)


static func build(world: Node3D) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var obstacles: Array = []
	var kit_cache := {}

	var get_scene := func(model):
		if not kit_cache.has(model):
			kit_cache[model] = _load_template(model)
		return kit_cache[model]

	# --- ground: Binbun-shaded meadow + darker horizon skirt ---
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var gp := PlaneMesh.new()
	gp.size = Vector2(96, 96)
	ground.mesh = gp
	ground.material_override = make_ground_material()
	world.add_child(ground)
	var skirt := MeshInstance3D.new()
	skirt.name = "Skirt"
	var sp := PlaneMesh.new()
	sp.size = Vector2(400, 400)
	skirt.mesh = sp
	skirt.position.y = -0.08
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.16, 0.32, 0.13)
	smat.roughness = 1.0
	skirt.material_override = smat
	world.add_child(skirt)

	# --- dirt paths (flat RockPath pieces, no collision) ---
	var path_rects: Array = [
		{"x0": -2.0, "x1": 2.0, "z0": -30.0, "z1": 30.0}, # N-S main
		{"x0": -30.0, "x1": 30.0, "z0": 1.0, "z1": 5.0}, # E-W branch
	]
	_lay_path(world, get_scene, rng, Vector2(0, -28), Vector2(0, 28), 2.0)
	_lay_path(world, get_scene, rng, Vector2(-28, 3), Vector2(28, 3), 2.0)

	# --- trees, rocks, decor (hand-placed clusters + seeded variants) ---
	_grove(world, get_scene, rng, obstacles, Vector2(-17, -13), 8.0,
		["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5"], 12, 1.0)
	_grove(world, get_scene, rng, obstacles, Vector2(17, -13), 8.0,
		["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"], 11, 1.0)
	_grove(world, get_scene, rng, obstacles, Vector2(16, 15), 6.0,
		["DeadTree_1", "DeadTree_2", "DeadTree_3", "DeadTree_4", "DeadTree_5"], 5, 0.9)
	# SW landmark: hero twisted tree + stones.
	_place(world, get_scene, rng, obstacles, "TwistedTree_1", Vector2(-16, 15), 1.7, true)
	_place(world, get_scene, rng, obstacles, "TwistedTree_3", Vector2(-19, 12), 1.1, true)
	_place(world, get_scene, rng, obstacles, "Rock_Medium_1", Vector2(-13, 17), 1.8, true)
	_place(world, get_scene, rng, obstacles, "Rock_Medium_3", Vector2(-18, 18), 1.3, true)
	# Boulder cluster mid-west + scattered loners.
	_place(world, get_scene, rng, obstacles, "Rock_Medium_2", Vector2(-9, -2), 2.0, true)
	_place(world, get_scene, rng, obstacles, "Rock_Medium_1", Vector2(-11, 0), 1.4, true)
	_place(world, get_scene, rng, obstacles, "Rock_Medium_3", Vector2(-7, 1), 1.1, true)
	_place(world, get_scene, rng, obstacles, "Rock_Medium_2", Vector2(8, -9), 1.6, true)
	_place(world, get_scene, rng, obstacles, "Rock_Medium_1", Vector2(-4, 11), 1.2, true)
	_place(world, get_scene, rng, obstacles, "CommonTree_3", Vector2(6, 12), 1.1, true)
	_place(world, get_scene, rng, obstacles, "Pine_2", Vector2(-6, -12), 1.2, true)
	# Bushes / flowers / pebbles / clover (decor only, never block).
	_scatter(world, get_scene, rng, ["Bush_Common", "Bush_Common_Flowers"], 22, 0.9, 1.4, obstacles, path_rects)
	_scatter(world, get_scene, rng, ["Pebble_Square_1", "Pebble_Square_3", "Pebble_Square_5"], 16, 0.8, 1.6, obstacles, path_rects)
	_scatter(world, get_scene, rng, ["Clover_1", "Clover_2", "Plant_1", "Plant_7"], 26, 0.8, 1.3, obstacles, path_rects)
	# Pine border wall (visual boundary, outside the playable clamp).
	for i in 36:
		var a := TAU * float(i) / 36.0 + rng.randf_range(-0.05, 0.05)
		var pos := Vector2(cos(a), sin(a)) * 34.0
		_place(world, get_scene, rng, obstacles, "Pine_%d" % rng.randi_range(1, 5), pos,
			rng.randf_range(1.2, 1.7), false)

	# --- Binbun grass field (one instanced draw, rejection-sampled) ---
	var grass_count := _plant_grass(world, rng, obstacles, path_rects)

	var camps := [
		{"pos": Vector3(9, 0, 4), "skins": PackedStringArray(["ninja", "ninja"])},
		{"pos": Vector3(-11, 0, 6), "skins": PackedStringArray(["cubeknight", "cubeknight", "cubecowboy"])},
		{"pos": Vector3(15, 0, 14), "skins": PackedStringArray(["cubecowboy", "cubeknight"])},
	]
	return {"obstacles": obstacles, "spawn": Vector3(0, 0, 20),
		"camps": camps, "grass_count": grass_count}


static func _in_rect(p: Vector2, r: Dictionary) -> bool:
	return p.x >= float(r["x0"]) and p.x <= float(r["x1"]) and p.y >= float(r["z0"]) and p.y <= float(r["z1"])


static func _blocked(p: Vector2, obstacles: Array, path_rects: Array, margin: float) -> bool:
	for o in obstacles:
		if p.distance_to(o["p"]) < float(o["r"]) + margin:
			return true
	for r in path_rects:
		if _in_rect(p, r):
			return true
	if p.distance_to(Vector2(0, 20)) < 4.0: # spawn clearing
		return true
	return false


static func _lay_path(world: Node3D, get_scene: Callable, rng: RandomNumberGenerator, a: Vector2, b: Vector2, half_w: float) -> void:
	# Flat stepping-stone trail between two points.
	var variants := ["RockPath_Round_Small_1", "RockPath_Round_Small_2", "RockPath_Round_Small_3",
		"RockPath_Square_Small_1", "RockPath_Square_Small_2", "RockPath_Square_Small_3"]
	var dist := a.distance_to(b)
	var n := int(dist / 2.1)
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(maxi(n, 1)))
		p += Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
		var inst := (get_scene.call(variants[rng.randi_range(0, variants.size() - 1)]) as Node3D).duplicate() as Node3D
		inst.position = Vector3(p.x, 0.03, p.y)
		inst.rotation.y = rng.randf() * TAU
		world.add_child(inst)


static func _place(world: Node3D, get_scene: Callable, rng: RandomNumberGenerator, obstacles: Array,
		model: String, pos: Vector2, scl: float, solid: bool) -> void:
	var inst := (get_scene.call(model) as Node3D).duplicate() as Node3D
	inst.position = Vector3(pos.x, 0, pos.y)
	inst.rotation.y = rng.randf() * TAU
	inst.scale = Vector3.ONE * scl
	world.add_child(inst)
	if not solid:
		return
	if model.begins_with("Rock"):
		var body := StaticBody3D.new()
		body.position = Vector3(pos.x, 0.8 * scl, pos.y)
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 1.5 * scl
		shape.shape = sphere
		body.add_child(shape)
		world.add_child(body)
		obstacles.append({"p": pos, "r": 1.6 * scl})
	else: # tree trunk: slim cylinder, leaves stay walk-through-free
		var body2 := StaticBody3D.new()
		body2.position = Vector3(pos.x, 1.5, pos.y)
		var shape2 := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.4 * scl
		cyl.height = 3.0
		shape2.shape = cyl
		body2.add_child(shape2)
		world.add_child(body2)
		obstacles.append({"p": pos, "r": 0.55 * scl})


static func _grove(world: Node3D, get_scene: Callable, rng: RandomNumberGenerator, obstacles: Array,
		center: Vector2, radius: float, models: Array, count: int, scl: float) -> void:
	# Ring-ish cluster with a walkable middle: trees on annulus + 1-2 inside.
	for i in count:
		var a := TAU * float(i) / float(count) + rng.randf_range(-0.2, 0.2)
		var rr := radius * rng.randf_range(0.55, 1.0)
		_place(world, get_scene, rng, obstacles, str(models[rng.randi_range(0, models.size() - 1)]),
			center + Vector2(cos(a), sin(a)) * rr, scl * rng.randf_range(0.9, 1.25), true)


static func _scatter(world: Node3D, get_scene: Callable, rng: RandomNumberGenerator, models: Array,
		count: int, s0: float, s1: float, obstacles: Array, path_rects: Array) -> void:
	if count <= 0:
		return
	var placed := 0
	var guard := 0
	while placed < count and guard < count * 40:
		guard += 1
		var p := Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
		if _blocked(p, obstacles, path_rects, 0.4):
			continue
		_place(world, get_scene, rng, obstacles, str(models[rng.randi_range(0, models.size() - 1)]),
			p, rng.randf_range(s0, s1), false)
		placed += 1


static func _plant_grass(world: Node3D, rng: RandomNumberGenerator, obstacles: Array, path_rects: Array) -> int:
	# One MultiMeshInstance3D (the Binbun demo's intended approach): billboard
	# quads, per-instance yaw/scale, no shadows, cheap static instancing.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	quad.subdivide_width = 2
	quad.subdivide_depth = 2
	quad.center_offset = Vector3(0, 0.2, 0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = GRASS_COUNT
	var placed := 0
	var guard := 0
	while placed < GRASS_COUNT and guard < GRASS_COUNT * 6:
		guard += 1
		var p := Vector2(rng.randf_range(-GRASS_R, GRASS_R), rng.randf_range(-GRASS_R, GRASS_R))
		if _blocked(p, obstacles, path_rects, 0.35):
			continue
		var s := rng.randf_range(0.8, 1.35)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		mm.set_instance_transform(placed, Transform3D(basis, Vector3(p.x, 0, p.y)))
		placed += 1
	mm.visible_instance_count = placed
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GrassField"
	mmi.multimesh = mm
	mmi.material_override = make_grass_material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mmi)
	return placed
