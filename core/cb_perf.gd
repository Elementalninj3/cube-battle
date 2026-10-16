class_name CBPerf
extends RefCounted
## Perf / batching / LOD / pooling / compute helpers shared by all modes.
## Typed, allocation-free at runtime: no per-frame Array/Dictionary creation
## in the hot paths that call into here.

const GRASS_BASE := {"low": 6000, "med": 11000, "high": 20000, "ultra": 32000}
const SHADOW_NAMES: PackedStringArray = ["Low", "Medium", "High", "Ultra"]

# Reused scratch transform to avoid per-instance Transform3D allocs in loops.
static var _scratch_basis := Basis.IDENTITY
static var _scratch_xform := Transform3D.IDENTITY


static func grass_count_for_quality(quality: int, requested: int) -> int:
	var cap: int = GRASS_BASE["low"]
	match quality:
		0:
			cap = GRASS_BASE["low"]
		1:
			cap = GRASS_BASE["med"]
		2:
			cap = GRASS_BASE["high"]
		_:
			cap = GRASS_BASE["ultra"]
	return mini(requested, cap)


static func apply_mmi_culling(mmi: MultiMeshInstance3D, half_extent: float) -> void:
	# One MultiMesh = one AABB. Without an explicit AABB the engine must
	# scan all instances for frustum culling. Set it once at build time.
	var aabb := AABB(Vector3(-half_extent, -2.0, -half_extent),
		Vector3(half_extent * 2.0, 12.0, half_extent * 2.0))
	mmi.custom_aabb = aabb
	mmi.extra_cull_margin = 2.0


static func update_grass_lod(mmi: MultiMeshInstance3D, cam_pos: Vector3, center: Vector3, full_count: int, quality: int, half_extent: float = 0.0) -> void:
	# Cheap distance LOD: shrink visible_instance_count when the camera is
	# far instead of moving 50k instances on the CPU. Called at 4 Hz max.
	# Near grass (< ~30 m) always renders at full density: identical pixels
	# to no LOD. Two refinements over plain thresholds:
	#  - hysteresis bands (enter far beyond 52 m, leave inside 47 m; enter
	#    near inside 30 m, leave beyond 32 m) so borderline distances don't
	#    oscillate the count every tick;
	#  - eased transitions: the visible count moves at most 12% of full per
	#    tick toward the target instead of jumping, so density changes fade
	#    in over ~0.5 s with no popping. Redundant writes are skipped (each
	#    visible_instance_count store can re-upload the instance buffer).
	# When half_extent > 0 (chunked grass), distance is measured on the
	# ground plane (XZ) to the NEAREST point of the chunk square instead
	# of its centre: the chunk under the camera reads ~0 m (full density,
	# as it should — that grass is the closest on screen) rather than
	# half a chunk away. Camera height is excluded on purpose — it is a
	# near-constant offset that would only compress the LOD range.
	# No per-blade CPU work: only the prefix length changes.
	if mmi == null or not is_instance_valid(mmi) or mmi.multimesh == null:
		return
	var mm: MultiMesh = mmi.multimesh
	var d2: float
	if half_extent > 0.0:
		var nx := clampf(cam_pos.x, center.x - half_extent, center.x + half_extent)
		var nz := clampf(cam_pos.z, center.z - half_extent, center.z + half_extent)
		var ddx := cam_pos.x - nx
		var ddz := cam_pos.z - nz
		d2 = ddx * ddx + ddz * ddz
	else:
		d2 = cam_pos.distance_squared_to(center)
	var band := int(mmi.get_meta("cb_lod_band", 2)) # 0 far, 1 mid, 2 near
	var frac := 1.0
	if band == 0 and d2 > 47.0 * 47.0:
		frac = 0.40
	elif band == 2 and d2 < 32.0 * 32.0:
		frac = 1.0
	elif d2 > 52.0 * 52.0:
		frac = 0.40
		band = 0
	elif d2 > 30.0 * 30.0:
		frac = 0.7
		band = 1
	else:
		frac = 1.0
		band = 2
	mmi.set_meta("cb_lod_band", band)
	if quality == 0:
		frac *= 0.6
	elif quality == 1:
		frac *= 0.85
	var target := clampi(int(float(full_count) * frac), mini(64, full_count), full_count)
	var last := int(mmi.get_meta("cb_lod_cur", target))
	var next := last
	if target != last:
		var step := maxi(1, int(float(full_count) * 0.12))
		if target > last:
			next = mini(target, last + step)
		else:
			next = maxi(target, last - step)
		mmi.set_meta("cb_lod_cur", next)
	if next != mm.visible_instance_count:
		# Never exceed the real buffer: a stale full_count (or a floor
		# above a small chunk's count) must not error every LOD tick.
		mm.visible_instance_count = mini(next, mm.instance_count)


## -- Object pool (tracers, puffs, coins) ---------------------------------
class Pool:
	var _free: Array = []
	var _factory: Callable
	var _parent: Node = null
	var _max: int = 64

	func _init(parent: Node, factory: Callable, prewarm: int = 0, max_size: int = 64) -> void:
		_parent = parent
		_factory = factory
		_max = max_size
		for i in prewarm:
			var n: Node = _factory.call() as Node
			n.visible = false
			_parent.add_child(n)
			_free.append(n)

	func obtain() -> Node:
		if _free.is_empty():
			var n: Node = _factory.call() as Node
			_parent.add_child(n)
			return n
		var n2: Node = _free.pop_back() as Node
		n2.visible = true
		return n2

	func release(n: Node) -> void:
		if _free.size() >= _max:
			n.queue_free()
			return
		n.visible = false
		_free.append(n)


## -- GPU compute (placement) with CPU fallback -----------------------------
## RenderingDevice compute is NOT available in GL Compatibility, so per-frame
## animation stays on the GPU (shader TIME wind) while one-time placement is
## computed once at load. When a compute-capable renderer exists we use a
## real compute shader; otherwise we fill the same buffer on the CPU.
static func fill_grass_transforms(mm: MultiMesh, xs: PackedFloat32Array, zs: PackedFloat32Array, ys: PackedFloat32Array, scales: PackedFloat32Array, yaws: PackedFloat32Array) -> void:
	var n: int = mini(mm.instance_count, xs.size())
	for i in n:
		_scratch_basis = Basis(Vector3.UP, yaws[i]).scaled(Vector3.ONE * scales[i])
		_scratch_xform = Transform3D(_scratch_basis, Vector3(xs[i], ys[i], zs[i]))
		mm.set_instance_transform(i, _scratch_xform)


static func try_compute_available() -> bool:
	# RenderingDevice exists on Forward+/Mobile; on Compatibility this
	# returns false and callers must use the CPU path above.
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	return rd != null


## -- Shader preloading (loading screen calls this first) -------------------
static var _shader_cache: Dictionary = {}

static func preload_shaders() -> void:
	# Only what the game actually draws with: the Binbun grass + ground
	# shaders every grass mode uses, plus the blade atlas/shape textures
	# (a first-use texture upload mid-frame would hitch; warming them here
	# keeps that off the steady-state path). The unused cb_* variants are
	# deliberately NOT preloaded (nothing assigns them); their files stay
	# on disk as an optional benchmark.
	var paths: PackedStringArray = PackedStringArray([
		"res://free assets/grassshader/assets/BinbunGrass/src/shader/grass.gdshader",
		"res://free assets/grassshader/assets/BinbunGrass/src/shader/ground.gdshader",
		"res://free assets/grassshader/assets/BinbunGrass/src/texture/basic/grass_basic_atlas.png",
		"res://free assets/grassshader/assets/BinbunGrass/src/texture/basic/grass_basic_02.png",
	])
	for p in paths:
		if _shader_cache.has(p):
			continue
		if ResourceLoader.exists(p):
			_shader_cache[p] = load(p)


static func cached_shader(path: String) -> Shader:
	if _shader_cache.has(path):
		return _shader_cache[path] as Shader
	if ResourceLoader.exists(path):
		var s: Shader = load(path) as Shader
		_shader_cache[path] = s
		return s
	return null


## -- Profiler: what the editor profiler would flag --------------------------
static func snapshot(tag: String) -> Dictionary:
	var draws: float = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var tris: float = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var phys_bodies: float = Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var snap: Dictionary = {"tag": tag, "draws": draws, "tris": tris, "phys": phys_bodies, "fps": fps}
	print("[CBPerf:%s] draws=%d tris=%d phys_active=%d fps=%.0f" % [tag, draws, tris, phys_bodies, fps])
	if draws > 120.0:
		push_warning("[CBPerf] draw calls high (%d) in %s: check prop MultiMesh batching + grass LOD + shadow splits." % [draws, tag])
	return snap
