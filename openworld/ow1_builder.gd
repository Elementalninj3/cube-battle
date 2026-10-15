extends RefCounted
## Open World 1 (Storybook Meadow) builder: the reference-map layout.
##
## Zones (x right, +z south; spawn (0,24) south-center):
##   CENTRAL FIELD  clearing ellipse (0,4) r~11 — open combat ground.
##   TREE GROVE     SW (-19,13): ring of CommonTrees.
##   TRAINING AREA  NW (-19,-13): dirt patch, 3 target dummies, crates,
##                  U-fence (open south, walk-in).
##   ENEMY CAMP     NE (19,-13): dirt yard, 2 tents, campfire, watchtower
##                  with banner, crates, fence ring with south gate,
##                  2 cubeknight guards.
##   POND           E (26,5): blocking water ellipse, rock rim, plank bridge
##                  (vista), lily pads.
##   ROCKY EDGE     S rim: boulder + block cluster.
##   ENCOUNTER      SE (17,17): 3 ninja patrol.
## Dirt paths link camp -> clearing -> pond bridge, clearing -> encounter ->
## spawn, clearing -> training, clearing -> grove.
## Coins (14) sit along paths and at points of interest.
##
## Performance approach (same as OW2): one Binbun ground plane, 4
## grass chunks sharing one material, ALL static
## voxel/prop boxes merged into ONE vertex-colored MultiMesh (1 draw call,
## shadows on for grounding), kit trees/rocks instanced from shared
## templates, movement blocking via push-out circles (fighters never query
## physics — only one ground StaticBody), coins as 14 cheap shared-material
## nodes. Zero per-frame cost from the environment itself.
##
## Returned dict: {obstacles, spawn, camps, coins, grass_count}

const KIT := "res://openworld/models/"
const KIT_SRC := "res://free assets/Stylized Nature MegaKit[Standard]/glTF/"
const GRASS_DIR := "res://free assets/grassshader/assets/BinbunGrass/src/"

const HALF := 32.0 # same footprint as Open World 2 (fighters clamp to 30)
const SEED := 11
# 4 quadrant chunks x 3000 = 12000 total. Smaller 0.4x0.55 blades cut alpha
# overdraw ~35% while the jittered-grid layout keeps even coverage;
# quadrants stay independent draw calls.
const CHUNK_N := 3000

const CLEAR_C := Vector2(0, 4)
const CLEAR_R := 11.0
const CAMP_C := Vector2(19, -13)
const TRAIN_C := Vector2(-19, -13)
const POND_C := Vector2(26, 5)
const POND_R := Vector2(3.5, 5.5)

# Green-only stops (dark -> mid -> light green). Same three-stop layout
# as Binbun palette_01, restricted to the green range.
const GREEN_PALETTE := [Color(0.38, 0.68, 0.2),
	Color(0.25, 0.58, 0.18),
	Color(0.15, 0.44, 0.14)]

const DIRT_COL := Color(0.78, 0.68, 0.50)
const WOOD := Color(0.45, 0.30, 0.17)
const WOOD_DARK := Color(0.34, 0.22, 0.12)
const CANVAS := Color(0.87, 0.82, 0.70)
const CANVAS_SHADE := Color(0.74, 0.68, 0.56)
const STONE := Color(0.55, 0.57, 0.60)
const ROCK_DARK := Color(0.42, 0.43, 0.47)
const TARGET_RED := Color(0.80, 0.15, 0.12)
const TARGET_WHITE := Color(0.92, 0.90, 0.86)
const BANNER_BLUE := Color(0.20, 0.35, 0.75)


# Cached procedural textures: NoiseTexture2D generation (especially the
# 1024px wind map) costs milliseconds each; all chunks/materials share one
# set per builder instead of rebuilding them per material.
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


static func _green_gradient_tex() -> GradientTexture2D:
	if _grad_cached != null:
		return _grad_cached
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.166667, 0.5, 0.833333])
	g.colors = PackedColorArray(GREEN_PALETTE)
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
	m.set_shader_parameter("color_gradient", _green_gradient_tex())
	return m


static func make_grass_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(GRASS_DIR + "shader/grass.gdshader")
	m.set_shader_parameter("billboard", true)
	m.set_shader_parameter("shape_texture", load(GRASS_DIR + "texture/basic/grass_basic_02.png"))
	m.set_shader_parameter("shape_atlas", load(GRASS_DIR + "texture/basic/grass_basic_atlas.png"))
	m.set_shader_parameter("use_atlas", true)
	m.set_shader_parameter("noise_texture", _noise_tex(6, 0.008))
	m.set_shader_parameter("color_gradient", _green_gradient_tex())
	m.set_shader_parameter("random_variation", 0.0)
	m.set_shader_parameter("wind_texture", _wind_tex())
	m.set_shader_parameter("wind_velocity", Vector2(0.5, 0.25))
	m.set_shader_parameter("alpha_cut_start", 0.4)
	m.set_shader_parameter("alpha_cut_end", 0.6)
	m.set_shader_parameter("alpha_mode", 1)
	return m


# One cached template Node3D per kit model; placements duplicate() it so
# all meshes/materials stay shared (same approach as OW2).
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
		push_error("OW1: cannot load megakit model " + model)
		return Node3D.new()
	var root := doc.generate_scene(st) as Node3D
	return root


static func build(world: Node3D) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var obstacles: Array = []
	var boxes: Array = [] # merged voxel layer {pos, size, col}
	var path_pts: Array = [] # Vector2 dirt samples (grass rejection)
	var kit_cache := {}
	var get_scene := func(model):
		if not kit_cache.has(model):
			kit_cache[model] = _load_template(model)
		return kit_cache[model]
	# Layer A: single Binbun ground plane + one collision box.
	_build_ground(world)
	# Layer B: zones, paths, structures (all merged boxes + kit placements).
	_build_paths(boxes, path_pts)
	_build_training(boxes, obstacles, path_pts)
	_build_camp(boxes, obstacles)
	_build_pond(world, boxes, obstacles)
	_build_rocky_edge(world, get_scene, rng, obstacles, boxes)
	_build_grove(world, get_scene, rng, obstacles)
	_build_lone_nature(world, get_scene, rng, obstacles, boxes)
	_build_border(world, get_scene, rng, obstacles)
	_bake_voxels(world, boxes)
	var coins := _coin_spots()
	var grass_count := _plant_grass(world, rng, obstacles, path_pts)
	var camps := [
		{"pos": Vector3(19, 0, -10.5), "skins": ["cubeknight", "cubeknight"]},
		{"pos": Vector3(17, 0, 17), "skins": ["ninja", "ninja", "ninja"]},
	]
	return {"obstacles": obstacles, "spawn": Vector3(0, 0, 24),
		"camps": camps, "coins": coins, "grass_count": grass_count}


static func _build_ground(world: Node3D) -> void:
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


static func _box(boxes: Array, pos: Vector3, size: Vector3, col: Color) -> void:
	boxes.append({"pos": pos, "size": size, "col": col})


static func _dirt_patch(boxes: Array, rng: RandomNumberGenerator,
		c: Vector2, w: float, d: float) -> void:
	# Sandy tile bed with slight per-tile variance (voxel look).
	var x0 := c.x - w * 0.5
	var z0 := c.y - d * 0.5
	var ix := 0
	while ix < int(w):
		var iz := 0
		while iz < int(d):
			var v := rng.randf_range(-0.03, 0.03)
			var col := Color(DIRT_COL.r + v, DIRT_COL.g + v, DIRT_COL.b + v * 0.5)
			_box(boxes, Vector3(x0 + ix + 0.5, 0.03, z0 + iz + 0.5),
				Vector3(0.98, 0.08, 0.98), col)
			iz += 1
		ix += 1


static func _path_run(boxes: Array, path_pts: Array, pts: Array) -> void:
	# Dirt-tile polyline: a tile every ~1.0m (1.3m squares overlap slightly
	# so the trail reads continuous). Every sample feeds grass rejection.
	for si in range(pts.size() - 1):
		var a: Vector2 = pts[si]
		var b: Vector2 = pts[si + 1]
		var dist := a.distance_to(b)
		var steps := maxi(1, int(dist / 1.0))
		for i in steps + 1:
			var p := a.lerp(b, float(i) / float(steps))
			_box(boxes, Vector3(p.x, 0.025, p.y), Vector3(1.3, 0.07, 1.3), DIRT_COL)
			path_pts.append(p)


static func _build_paths(boxes: Array, path_pts: Array) -> void:
	# Camp gate -> clearing -> pond bridge.
	_path_run(boxes, path_pts, [Vector2(19, -8.5), Vector2(14, -4),
		Vector2(8, 0), Vector2(4, 3)])
	_path_run(boxes, path_pts, [Vector2(4, 3), Vector2(10, 4),
		Vector2(16, 5), Vector2(20.5, 5)])
	# Clearing -> encounter -> spawn.
	_path_run(boxes, path_pts, [Vector2(4, 3), Vector2(2, 10),
		Vector2(8, 15), Vector2(14, 16)])
	_path_run(boxes, path_pts, [Vector2(17, 17), Vector2(12, 22), Vector2(4, 24)])
	# Clearing -> training gate.
	_path_run(boxes, path_pts, [Vector2(4, 3), Vector2(-6, -2),
		Vector2(-14, -8), Vector2(-17, -10)])
	# Clearing -> grove edge.
	_path_run(boxes, path_pts, [Vector2(2, 10), Vector2(-8, 12), Vector2(-14, 13)])


static func _fence(boxes: Array, x0: float, z0: float, x1: float, z1: float) -> void:
	# Axis-aligned post-and-rail fence (merged boxes, no collision).
	var a := Vector2(x0, z0)
	var b := Vector2(x1, z1)
	var length := a.distance_to(b)
	var n := maxi(1, int(length / 1.5) + 1)
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		_box(boxes, Vector3(p.x, 0.45, p.y), Vector3(0.16, 0.9, 0.16), WOOD_DARK)
	var mid := (a + b) * 0.5
	var horiz := absf(x1 - x0) >= absf(z1 - z0)
	for y in [0.55, 0.82]:
		if horiz:
			_box(boxes, Vector3(mid.x, y, mid.y),
				Vector3(length, 0.1, 0.08), WOOD)
		else:
			_box(boxes, Vector3(mid.x, y, mid.y),
				Vector3(0.08, 0.1, length), WOOD)


static func _crate(boxes: Array, obstacles: Array, x: float, z: float, s: float = 0.8) -> void:
	_box(boxes, Vector3(x, s * 0.5, z), Vector3(s, s, s), WOOD)
	_box(boxes, Vector3(x, s + 0.03, z), Vector3(s + 0.08, 0.08, s + 0.08), WOOD_DARK)
	obstacles.append({"p": Vector2(x, z), "r": s * 0.75})


static func _target(boxes: Array, x: float, z: float, yaw_deg: float) -> void:
	# Training dummy: post + straw board + red/white roundel (axis boxes).
	_box(boxes, Vector3(x, 0.7, z), Vector3(0.18, 1.4, 0.18), WOOD_DARK)
	var fx := sin(deg_to_rad(yaw_deg))
	var fz := cos(deg_to_rad(yaw_deg))
	var bx := x + fx * 0.25
	var bz := z + fz * 0.25
	_box(boxes, Vector3(bx, 1.15, bz), Vector3(0.95, 0.95, 0.14), Color(0.72, 0.58, 0.36))
	_box(boxes, Vector3(bx + fx * 0.08, 1.15, bz + fz * 0.08),
		Vector3(0.62, 0.62, 0.06), TARGET_WHITE)
	_box(boxes, Vector3(bx + fx * 0.13, 1.15, bz + fz * 0.13),
		Vector3(0.34, 0.34, 0.06), TARGET_RED)


static func _tent(boxes: Array, obstacles: Array, x: float, z: float) -> void:
	# Stepped-canvas tent (axis boxes, merged): floor, back + side walls,
	# two roof steps, ridge + poles.
	_box(boxes, Vector3(x, 0.06, z), Vector3(2.6, 0.12, 2.2), CANVAS_SHADE)
	_box(boxes, Vector3(x, 0.75, z - 1.0), Vector3(2.6, 1.4, 0.16), CANVAS)
	_box(boxes, Vector3(x - 1.2, 0.65, z), Vector3(0.16, 1.2, 2.0), CANVAS)
	_box(boxes, Vector3(x + 1.2, 0.65, z), Vector3(0.16, 1.2, 2.0), CANVAS)
	_box(boxes, Vector3(x, 1.5, z - 0.2), Vector3(2.7, 0.16, 1.9), CANVAS)
	_box(boxes, Vector3(x, 1.72, z - 0.2), Vector3(2.8, 0.14, 1.1), CANVAS_SHADE)
	_box(boxes, Vector3(x, 0.9, z + 1.05), Vector3(0.14, 1.8, 0.14), WOOD_DARK)
	_box(boxes, Vector3(x, 1.85, z + 1.05), Vector3(0.5, 0.14, 0.14), WOOD_DARK)
	obstacles.append({"p": Vector2(x, z), "r": 1.9})


static func _tower(boxes: Array, obstacles: Array, x: float, z: float) -> void:
	# Watchtower: 4 legs, platform, rails, canopy roof, blue banner.
	for sx in [-0.9, 0.9]:
		for sz in [-0.9, 0.9]:
			_box(boxes, Vector3(x + sx, 1.6, z + sz),
				Vector3(0.26, 3.2, 0.26), WOOD_DARK)
	_box(boxes, Vector3(x, 3.25, z), Vector3(2.5, 0.25, 2.5), WOOD)
	_box(boxes, Vector3(x, 3.85, z - 1.15), Vector3(2.5, 0.55, 0.12), WOOD)
	_box(boxes, Vector3(x, 3.85, z + 1.15), Vector3(2.5, 0.55, 0.12), WOOD)
	_box(boxes, Vector3(x - 1.15, 3.85, z), Vector3(0.12, 0.55, 2.5), WOOD)
	_box(boxes, Vector3(x + 1.15, 3.85, z), Vector3(0.12, 0.55, 2.5), WOOD)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(boxes, Vector3(x + sx, 4.5, z + sz),
				Vector3(0.16, 1.6, 0.16), WOOD_DARK)
	_box(boxes, Vector3(x, 5.35, z), Vector3(3.0, 0.22, 3.0), CANVAS)
	_box(boxes, Vector3(x, 5.55, z), Vector3(1.6, 0.18, 1.6), CANVAS_SHADE)
	_box(boxes, Vector3(x + 0.8, 6.1, z), Vector3(0.12, 1.4, 0.12), WOOD_DARK)
	_box(boxes, Vector3(x + 1.25, 6.4, z), Vector3(0.8, 0.55, 0.08), BANNER_BLUE)
	obstacles.append({"p": Vector2(x, z), "r": 1.5})


static func _campfire(boxes: Array, obstacles: Array, x: float, z: float) -> void:
	# Stone ring + crossed logs (merged); the flame itself is one small
	# emissive node added by _build_camp (1 extra draw, no light).
	for i in 6:
		var a := TAU * float(i) / 6.0
		_box(boxes, Vector3(x + cos(a) * 0.65, 0.13, z + sin(a) * 0.65),
			Vector3(0.28, 0.26, 0.28), STONE)
	_box(boxes, Vector3(x, 0.12, z), Vector3(1.0, 0.18, 0.2), WOOD_DARK)
	_box(boxes, Vector3(x, 0.12, z), Vector3(0.2, 0.18, 1.0), WOOD_DARK)
	_box(boxes, Vector3(x, 0.28, z), Vector3(0.7, 0.16, 0.18), WOOD)
	obstacles.append({"p": Vector2(x, z), "r": 1.0})


static func _build_training(boxes: Array, obstacles: Array, path_pts: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 101
	_dirt_patch(boxes, rng, TRAIN_C, 9.0, 7.0)
	_target(boxes, -21.0, -14.0, 35.0)
	_target(boxes, -19.0, -15.0, 0.0)
	_target(boxes, -17.0, -14.0, -35.0)
	_crate(boxes, obstacles, -16.0, -11.0, 0.8)
	_crate(boxes, obstacles, -22.0, -11.0, 0.7)
	# U-fence, open to the south (walk-in). Visual only — free movement.
	_fence(boxes, -23.5, -16.5, -14.5, -16.5)
	_fence(boxes, -23.5, -16.5, -23.5, -10.5)
	_fence(boxes, -14.5, -16.5, -14.5, -10.5)


static func _build_camp(boxes: Array, obstacles: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 202
	_dirt_patch(boxes, rng, CAMP_C, 11.0, 9.0)
	_tent(boxes, obstacles, 16.5, -15.0)
	_tent(boxes, obstacles, 21.5, -15.0)
	_campfire(boxes, obstacles, 19.0, -12.0)
	_tower(boxes, obstacles, 23.0, -16.0)
	_crate(boxes, obstacles, 15.0, -10.5, 0.8)
	_crate(boxes, obstacles, 22.5, -10.0, 0.9)
	_crate(boxes, obstacles, 20.5, -15.5, 0.65)
	# Fence ring with a south gate (gate faces the path at z=-8.5).
	_fence(boxes, 13.5, -17.5, 24.5, -17.5)
	_fence(boxes, 13.5, -17.5, 13.5, -8.5)
	_fence(boxes, 24.5, -17.5, 24.5, -8.5)
	_fence(boxes, 13.5, -8.5, 17.0, -8.5)
	_fence(boxes, 21.0, -8.5, 24.5, -8.5)
	for fp in [Vector2(13.5, -17.5), Vector2(24.5, -17.5), Vector2(13.5, -8.5),
			Vector2(24.5, -8.5), Vector2(13.5, -13), Vector2(24.5, -13)]:
		obstacles.append({"p": fp, "r": 0.5})


static func _flame_node() -> MeshInstance3D:
	# Single emissive flame wedge over the campfire (no OmniLight: one
	# dynamic light per camp would re-shade the whole yard every frame).
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.28
	cm.height = 0.8
	cm.radial_segments = 6
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.55, 0.15)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.45, 0.1)
	m.emission_energy_multiplier = 2.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _water_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.55, 0.85, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.15
	m.metallic = 0.3
	return m


static func _build_pond(world: Node3D, boxes: Array, obstacles: Array) -> void:
	# Blocking water ellipse + rock rim + plank bridge (vista) + lilies.
	var water := MeshInstance3D.new()
	water.name = "Pond"
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.12
	disc.radial_segments = 24
	water.mesh = disc
	water.material_override = _water_mat()
	water.scale = Vector3(POND_R.x, 1.0, POND_R.y)
	water.position = Vector3(POND_C.x, 0.05, POND_C.y)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(water)
	# Lily pads.
	var lily_mat := StandardMaterial3D.new()
	lily_mat.albedo_color = Color(0.35, 0.65, 0.3)
	lily_mat.roughness = 0.7
	for lp in [Vector2(25, 4), Vector2(27, 6), Vector2(26, 7.5)]:
		var lily := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.35
		lm.bottom_radius = 0.35
		lm.height = 0.04
		lm.radial_segments = 10
		lily.mesh = lm
		lily.material_override = lily_mat
		lily.position = Vector3(lp.x, 0.13, lp.y)
		lily.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(lily)
	# Rock rim (merged) + kit boulders at the tips.
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 303
	for i in 10:
		var a := TAU * float(i) / 10.0
		var rx := POND_C.x + cos(a) * (POND_R.x + 0.4)
		var rz := POND_C.y + sin(a) * (POND_R.y + 0.4)
		var s := rng.randf_range(0.4, 0.8)
		_box(boxes, Vector3(rx, s * 0.25, rz), Vector3(s, s * 0.6, s), STONE)
	# Plank bridge over the west tip (deck + rails, merged).
	for i in 5:
		var v := rng.randf_range(-0.02, 0.02)
		_box(boxes, Vector3(21.0 + float(i) * 0.85, 0.35, 5.0),
			Vector3(0.8, 0.12, 1.8),
			Color(WOOD.r + v, WOOD.g + v, WOOD.b + v))
	_box(boxes, Vector3(22.7, 0.75, 4.15), Vector3(4.6, 0.1, 0.1), WOOD_DARK)
	_box(boxes, Vector3(22.7, 0.75, 5.85), Vector3(4.6, 0.1, 0.1), WOOD_DARK)
	for px in [20.8, 24.6]:
		for pz in [4.15, 5.85]:
			_box(boxes, Vector3(px, 0.45, pz), Vector3(0.14, 0.7, 0.14), WOOD_DARK)
	# Water blocks movement: 3 circles (bridge tip stays walkable vista).
	obstacles.append({"p": Vector2(26, 1.5), "r": 2.6})
	obstacles.append({"p": Vector2(27, 5), "r": 2.7})
	obstacles.append({"p": Vector2(26, 8.5), "r": 2.6})


static func _build_rocky_edge(world: Node3D, get_scene: Callable,
		rng: RandomNumberGenerator, obstacles: Array, boxes: Array) -> void:
	# South rim boulder cluster: kit rocks + gray voxel blocks.
	_place(world, get_scene, rng, obstacles, "Rock_Medium_1",
		Vector2(-10, 28), 1.8, 2.4, true)
	_place(world, get_scene, rng, obstacles, "Rock_Medium_2",
		Vector2(0, 29), 2.0, 2.6, true)
	_place(world, get_scene, rng, obstacles, "Rock_Medium_3",
		Vector2(10, 28), 1.6, 2.2, true)
	_place(world, get_scene, rng, obstacles, "Rock_Medium_2",
		Vector2(20, 27), 1.4, 2.0, true)
	_place(world, get_scene, rng, obstacles, "Rock_Medium_1",
		Vector2(-20, 27), 1.4, 2.0, true)
	for i in 8:
		var x := -14.0 + float(i) * 4.0 + rng.randf_range(-1.0, 1.0)
		var s := rng.randf_range(0.7, 1.3)
		_box(boxes, Vector3(x, s * 0.3, 29.5 + rng.randf_range(-1.0, 1.0)),
			Vector3(s, s * 0.7, s), ROCK_DARK if i % 2 == 0 else STONE)


static func _build_grove(world: Node3D, get_scene: Callable,
		rng: RandomNumberGenerator, obstacles: Array) -> void:
	# Tree grove: ring of CommonTrees around (-19,13).
	for i in 8:
		var a := TAU * float(i) / 8.0 + rng.randf_range(-0.15, 0.15)
		var rr := 8.0 * rng.randf_range(0.6, 1.0)
		var pos := Vector2(-19, 13) + Vector2(cos(a), sin(a)) * rr
		_place(world, get_scene, rng, obstacles,
			"CommonTree_%d" % rng.randi_range(1, 5), pos,
			rng.randf_range(0.95, 1.3), 0.8, true)
	# Heart of the grove stays walkable (clearing for coins).
	_place(world, get_scene, rng, obstacles, "Bush_Common",
		Vector2(-23, 16), 1.2, 0.0, false)


static func _build_lone_nature(world: Node3D, get_scene: Callable,
		rng: RandomNumberGenerator, obstacles: Array, boxes: Array) -> void:
	# Cover boulders (never in the clearing or on paths).
	_place(world, get_scene, rng, obstacles, "Rock_Medium_2",
		Vector2(-9, -2), 1.6, 2.2, true)
	_place(world, get_scene, rng, obstacles, "Rock_Medium_1",
		Vector2(9, 10), 1.3, 1.9, true)
	_place(world, get_scene, rng, obstacles, "Rock_Medium_3",
		Vector2(12, 20), 1.2, 1.7, true)
	# Landmark twisted tree south-west of the clearing.
	_place(world, get_scene, rng, obstacles, "TwistedTree_1",
		Vector2(-12, 20), 1.5, 1.1, true)
	# Small scatter: decoration only, no collision, no shadows.
	_scatter(world, get_scene, rng,
		["Bush_Common", "Bush_Common_Flowers"], 8, 0.9, 1.4, obstacles)
	_scatter(world, get_scene, rng,
		["Pebble_Square_1", "Pebble_Square_3", "Pebble_Square_5"],
		8, 0.8, 1.6, obstacles)
	_scatter(world, get_scene, rng,
		["Clover_1", "Clover_2", "Plant_1", "Plant_7"],
		10, 0.8, 1.3, obstacles)


static func _build_border(world: Node3D, get_scene: Callable,
		rng: RandomNumberGenerator, obstacles: Array) -> void:
	# Pine border wall outside the playable clamp (visual boundary, no
	# shadows: 24 large casters out here would only inflate the shadow pass).
	for i in 24:
		var a := TAU * float(i) / 24.0 + rng.randf_range(-0.05, 0.05)
		_place(world, get_scene, rng, obstacles,
			"Pine_%d" % rng.randi_range(1, 5),
			Vector2(cos(a), sin(a)) * (HALF + 3.0),
			rng.randf_range(1.2, 1.7), 0.0, false)


static func _coin_spots() -> Array:
	# 14 coins: path-side pickups + point-of-interest rewards.
	return [
		Vector2(16, -6.5), Vector2(11, -2), Vector2(12, 4.5),
		Vector2(18, 6.5), Vector2(6, 8), Vector2(5, 12),
		Vector2(11, 15.5), Vector2(17, 19), Vector2(-10, -5),
		Vector2(-15.5, -9), Vector2(-19, -11), Vector2(-16, 14),
		Vector2(6, 23), Vector2(21.5, 5.8),
	]


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


static func _scatter(world: Node3D, get_scene: Callable, rng: RandomNumberGenerator,
		models: Array, count: int, s0: float, s1: float,
		obstacles: Array) -> void:
	var placed := 0
	var guard := 0
	while placed < count and guard < count * 40:
		guard += 1
		var p := Vector2(rng.randf_range(-HALF, HALF), rng.randf_range(-HALF, HALF))
		if _kept_clear(p):
			continue
		if _blocked_by(p, obstacles, 0.4):
			continue
		_place(world, get_scene, rng, obstacles,
			str(models[rng.randi_range(0, models.size() - 1)]),
			p, rng.randf_range(s0, s1), 0.0, false)
		placed += 1


static func _kept_clear(p: Vector2) -> bool:
	# Gameplay surfaces stay clean: spawn, clearing, camp/training yards.
	if p.distance_to(Vector2(0, 24)) < 3.0:
		return true
	if p.distance_to(CLEAR_C) < CLEAR_R:
		return true
	if absf(p.x - CAMP_C.x) < 6.5 and absf(p.y - CAMP_C.y) < 5.5:
		return true
	if absf(p.x - TRAIN_C.x) < 5.5 and absf(p.y - TRAIN_C.y) < 4.5:
		return true
	if _in_pond(p):
		return true
	return false


static func _in_pond(p: Vector2) -> bool:
	var dx := (p.x - POND_C.x) / POND_R.x
	var dy := (p.y - POND_C.y) / POND_R.y
	return dx * dx + dy * dy < 1.25


static func _blocked_by(p: Vector2, obstacles: Array, pad: float) -> bool:
	for o in obstacles:
		var op: Vector2 = o["p"]
		var dx := p.x - op.x
		var dy := p.y - op.y
		var rr := float(o["r"]) + pad
		if dx * dx + dy * dy < rr * rr:
			return true
	return false


static func _bake_voxels(world: Node3D, boxes: Array) -> void:
	# Every static box (paths, patches, fences, tents, tower, rocks, rim)
	# in ONE MultiMesh: 1 draw call in color and shadow passes.
	if boxes.is_empty():
		return
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
	world.add_child(mmi)
	# Campfire flame (single emissive node, no light).
	var flame := _flame_node()
	flame.position = Vector3(19.0, 0.65, -12.0)
	world.add_child(flame)


static func _plant_grass(world: Node3D, rng: RandomNumberGenerator,
		obstacles: Array, path_pts: Array) -> int:
	# One shared Binbun material for all 4 chunks.
	var shared_mat := make_grass_material()
	var total := 0
	for cx in 2:
		for cz in 2:
			total += _plant_chunk(world, rng, shared_mat, obstacles, path_pts, cx, cz)
	return total


# One quadrant chunk: jittered-grid scatter inside the quadrant keeps even
# coverage without clumps/gaps; own MultiMesh keeps the quadrants as separate
# draw calls. Zero per-frame cost.
static func _plant_chunk(world: Node3D, rng: RandomNumberGenerator,
		shared_mat: ShaderMaterial, obstacles: Array, path_pts: Array,
		cx: int, cz: int) -> int:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.55)
	quad.subdivide_width = 2
	quad.subdivide_depth = 2
	quad.center_offset = Vector3(0, 0.275, 0)
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
	# Jittered 2m cells inside this quadrant.
	var cells := int(HALF / 2.0)
	var quota := CHUNK_N / cells / cells
	var extra := CHUNK_N - quota * cells * cells
	var placed := 0
	for ix in cells:
		for iz in cells:
			var n := quota + (1 if extra > 0 else 0)
			extra -= 1
			for k in n:
				if placed >= CHUNK_N:
					break
				var p := Vector2(x0 + (ix + rng.randf()) * 2.0,
					z0 + (iz + rng.randf()) * 2.0)
				if p.distance_to(Vector2(0, 24)) < 2.5: # spawn clearing
					continue
				if _kept_clear(p):
					continue
				if _blocked_by(p, obstacles, 0.35):
					continue
				if _on_path(p, path_pts):
					continue
				var s := rng.randf_range(0.8, 1.3)
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


static func _on_path(p: Vector2, path_pts: Array) -> bool:
	# Squared-distance check against decimated path samples (see build:
	# every sample kept, blades rejected within ~0.85m so trails read clean).
	for q in path_pts:
		var qq: Vector2 = q
		var dx := p.x - qq.x
		var dy := p.y - qq.y
		if dx * dx + dy * dy < 0.72:
			return true
	return false
