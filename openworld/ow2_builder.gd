extends RefCounted
## Open World 2 (Nature World) builder: a larger Grass Render-style world.
##
## Same visual setup as Grass Render (Binbun shaders, palette, wind,
## white/color environment, neutral sun, 2-split shadows), expanded to a
## 64x64 meadow with Stylized Nature Megakit trees, rocks and bushes.
##
## Performance approach: one ground plane, grass in 4 chunk MultiMeshes
## (no shadows), one template instance per Megakit model
## loaded once and duplicated per placement (meshes/materials shared),
## movement blocking via push-out circles (fighters never query physics,
## so nature needs no StaticBodies), one ground collision box.
##
## Returned dict: {obstacles, spawn, camps, grass_count}

const KIT := "res://openworld/models/"
const KIT_SRC := "res://free assets/Stylized Nature MegaKit[Standard]/glTF/"
const GRASS_DIR := "res://free assets/grassshader/assets/BinbunGrass/src/"

const HALF := 32.0 # playable half-extent (fighters clamp to 30)
const SEED := 77
# 4 x 3500 = 14000 blades (was 18000). Demo 0.4m blades kept; density trim
# comes from count only so the Binbun look is unchanged, overdraw ~22% lower.
const CHUNK_N := 3500
const CLEAR_C := Vector2(0, 4)
const CLEAR_R := 11.0

# Palette copied 1:1 from BinbunGrass palette_01.tres (standard Binbun
# look, same as Grass Render).
const PALETTE := [Color(0.658824, 0.792157, 0.345098),
	Color(0.458824, 0.654902, 0.262745),
	Color(0.27451, 0.509804, 0.196078)]


# Cached procedural textures shared by ground + all grass chunks. Each
# 1024px wind NoiseTexture costs real load time; without caching one build
# created 5+ duplicates.
static var _noise_cached: NoiseTexture2D = null
static var _grad_cached: GradientTexture2D = null
static var _wind_cached: NoiseTexture2D = null


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


static func make_ground_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(GRASS_DIR + "shader/ground.gdshader")
	m.set_shader_parameter("noise_texture", _noise_tex(6, 0.008))
	m.set_shader_parameter("color_gradient", _gradient_tex())
	return m


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


# One cached template Node3D per model; placements duplicate() it so all
# meshes/materials stay shared. Prefers imported .glb with a valid import,
# else parses the kit .gltf at runtime (the openworld/models/*.glb copies
# currently fail the importer: valid=false).
static func _load_template(model: String) -> Node3D:
	var cfg := ConfigFile.new()
	if cfg.load(KIT + model + ".glb.import") == OK \
	and cfg.get_value("remap", "valid", true) != false \
	and str(cfg.get_value("remap", "path", "")) != "":
		var packed := load(KIT + model + ".glb") as PackedScene
		if packed != null and packed.can_instantiate():
			return packed.instantiate() as Node3D
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(KIT_SRC + model + ".gltf", st) != OK:
		push_error("OW2: cannot load megakit model " + model)
		return Node3D.new()
	var root := doc.generate_scene(st) as Node3D
	_slim_runtime_materials(root)
	return root


static func _slim_runtime_materials(root: Node) -> void:
	var seen := {}
	var stack: Array = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mesh := (cur as MeshInstance3D).mesh
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
		if img != null and not img.is_empty() and not img.is_compressed():
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
	# Layer A: single Binbun ground plane + one collision box.
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var gp := PlaneMesh.new()
	gp.size = Vector2(HALF * 2.0 + 4.0, HALF * 2.0 + 4.0)
	ground.mesh = gp
	ground.material_override = make_ground_material()
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(ground)
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(HALF * 2.0, 1.0, HALF * 2.0)
	shape.shape = box
	body.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	world.add_child(body)
	# Layer B: intentional nature layout, clearings kept open.
	_grove(world, get_scene, rng, obstacles, Vector2(-19, -13), 8.0,
		["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5"], 8, 1.0)
	_grove(world, get_scene, rng, obstacles, Vector2(19, -11), 8.0,
		["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"], 7, 1.0)
	_grove(world, get_scene, rng, obstacles, Vector2(17, 17), 6.0,
		["DeadTree_1", "DeadTree_2", "DeadTree_3", "DeadTree_4", "DeadTree_5"], 4, 0.9)
	# Landmark twisted tree + boulders south-west.
	_place(world, get_scene, rng, obstacles, "TwistedTree_1", Vector2(-15, 16), 1.7, 0.9, true)
	_place(world, get_scene, rng, obstacles, "Rock_Medium_1", Vector2(-12, 18), 1.8, 2.6, true)
	_place(world, get_scene, rng, obstacles, "Rock_Medium_3", Vector2(-17, 19), 1.3, 2.0, true)
	# Lone boulders (cover, never in the clearing).
	_place(world, get_scene, rng, obstacles, "Rock_Medium_2", Vector2(-9, -4), 2.0, 2.8, true)
	_place(world, get_scene, rng, obstacles, "Rock_Medium_2", Vector2(9, -10), 1.6, 2.4, true)
	_place(world, get_scene, rng, obstacles, "Rock_Medium_1", Vector2(-5, 12), 1.2, 1.8, true)
	# Bushes/flowers/pebbles: decoration only, no collision, no shadows.
	_scatter(world, get_scene, rng, ["Bush_Common", "Bush_Common_Flowers"], 12, 0.9, 1.4, obstacles)
	_scatter(world, get_scene, rng, ["Pebble_Square_1", "Pebble_Square_3", "Pebble_Square_5"], 10, 0.8, 1.6, obstacles)
	_scatter(world, get_scene, rng, ["Clover_1", "Clover_2", "Plant_1", "Plant_7"], 14, 0.8, 1.3, obstacles)
	# Pine border wall outside the playable clamp (visual boundary).
	# No shadows out here: 28 large casters outside gameplay would only
	# inflate the shadow pass for pixels rarely on screen.
	for i in 28:
		var a := TAU * float(i) / 28.0 + rng.randf_range(-0.05, 0.05)
		_place(world, get_scene, rng, obstacles,
			"Pine_%d" % rng.randi_range(1, 5),
			Vector2(cos(a), sin(a)) * (HALF + 3.0),
			rng.randf_range(1.2, 1.7), 0.0, false)
	# One shared grass material for all 4 chunks (was 4 duplicates).
	var shared_grass := make_grass_material()
	var grass_count := 0
	for cx in 2:
		for cz in 2:
			grass_count += _plant_chunk(world, rng, obstacles, cx, cz, shared_grass)
	return {"obstacles": obstacles, "spawn": Vector3(0, 0, 24),
		"camps": [], "grass_count": grass_count}


static func _clear(p: Vector2) -> bool:
	if p.distance_to(CLEAR_C) < CLEAR_R:
		return true
	if p.distance_to(Vector2(0, 24)) < 3.0: # spawn clearing
		return true
	return false


static func _place(world: Node3D, get_scene: Callable, rng: RandomNumberGenerator,
		obstacles: Array, model: String, pos: Vector2, scl: float,
		collide_r: float, shadow_on: bool) -> void:
	var inst := (get_scene.call(model) as Node3D).duplicate() as Node3D
	inst.position = Vector3(pos.x, 0, pos.y)
	inst.rotation.y = rng.randf() * TAU
	inst.scale = Vector3.ONE * scl
	if not shadow_on:
		_set_shadow_off(inst)
	world.add_child(inst)
	if collide_r > 0.0:
		obstacles.append({"p": pos, "r": collide_r * scl})


static func _set_shadow_off(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_set_shadow_off(c)


static func _grove(world: Node3D, get_scene: Callable, rng: RandomNumberGenerator,
		obstacles: Array, center: Vector2, radius: float, models: Array,
		count: int, scl: float) -> void:
	for i in count:
		var a := TAU * float(i) / float(count) + rng.randf_range(-0.2, 0.2)
		var rr := radius * rng.randf_range(0.55, 1.0)
		var pos := center + Vector2(cos(a), sin(a)) * rr
		if _clear(pos):
			continue
		_place(world, get_scene, rng, obstacles,
			str(models[rng.randi_range(0, models.size() - 1)]), pos,
			scl * rng.randf_range(0.9, 1.25), 0.7, true)


static func _scatter(world: Node3D, get_scene: Callable, rng: RandomNumberGenerator,
		models: Array, count: int, s0: float, s1: float,
		obstacles: Array) -> void:
	var placed := 0
	var guard := 0
	while placed < count and guard < count * 40:
		guard += 1
		var p := Vector2(rng.randf_range(-HALF, HALF), rng.randf_range(-HALF, HALF))
		if _clear(p):
			continue
		var blocked := false
		for o in obstacles:
			if p.distance_to(o["p"]) < float(o["r"]) + 0.4:
				blocked = true
				break
		if blocked:
			continue
		_place(world, get_scene, rng, obstacles,
			str(models[rng.randi_range(0, models.size() - 1)]),
			p, rng.randf_range(s0, s1), 0.0, false)
		placed += 1


# One grass chunk per quadrant: same demo blades, own MultiMesh so the
# quadrants stay independent draw calls. Skips the clearing, spawn and the
# inside of solid footprints.
static func _plant_chunk(world: Node3D, rng: RandomNumberGenerator,
		obstacles: Array, cx: int, cz: int, shared_mat: ShaderMaterial) -> int:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	quad.subdivide_width = 2
	quad.subdivide_depth = 2
	quad.center_offset = Vector3(0, 0.2, 0)
	var qm := StandardMaterial3D.new()
	qm.vertex_color_use_as_albedo = true
	qm.roughness = 0.9
	quad.material = qm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = CHUNK_N
	var x0 := -HALF + cx * HALF
	var z0 := -HALF + cz * HALF
	var placed := 0
	var guard := 0
	while placed < CHUNK_N and guard < CHUNK_N * 6:
		guard += 1
		var p := Vector2(rng.randf_range(x0, x0 + HALF),
			rng.randf_range(z0, z0 + HALF))
		if _clear(p):
			continue
		var blocked := false
		for o in obstacles:
			if p.distance_to(o["p"]) < float(o["r"]) + 0.35:
				blocked = true
				break
		if blocked:
			continue
		var s := rng.randf_range(0.8, 1.35)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		mm.set_instance_transform(placed, Transform3D(basis, Vector3(p.x, 0, p.y)))
		placed += 1
	mm.visible_instance_count = placed
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GrassChunk%d%d" % [cx, cz]
	mmi.multimesh = mm
	mmi.material_override = shared_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mmi)
	return placed
