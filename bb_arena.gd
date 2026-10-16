extends Node3D
## Arena builder: 10x10 checkered grass platform on dirt, rocks/trees/flowers.
## Floor = ONE MultiMesh (1 draw). Props (rock/tree/flower parts) = TWO
## MultiMeshes (solid with shadows, deco without) instead of 3-4
## MeshInstance3D per prop. Destructible state stays data-only
## (hp/wobble/respawn/grow); visuals update by rewriting that prop's
## instance transforms — no per-prop nodes, no per-frame allocations.
## Typed GDScript; _physics_process owns timers, _process owns visuals.

const CBLayers = preload("res://core/cb_layers.gd")
const CBPerf = preload("res://core/cb_perf.gd")

var _box: BoxMesh
var _mats := {}
var vfx = null
var props: Array = []
var _tick := 0.0
var _phys_tick := 0.0
var _static: Array = []

# Batched prop visuals: each entry {prop: int, off: Vector3, size: Vector3}
var _solid_parts: Array = []
var _deco_parts: Array = []
var _solid_mmi: MultiMeshInstance3D = null
var _deco_mmi: MultiMeshInstance3D = null
var _lod_cam: Vector3 = Vector3.ZERO
var _lod_has_cam := false
var _lod_t := 0.0
var _map_half := 5.0


func build(p_vfx, p_size: int = 10) -> void:
	vfx = p_vfx
	var n := maxi(10, p_size)
	var half := float(n) * 0.5
	_map_half = half
	_box = BoxMesh.new()
	_box.size = Vector3.ONE
	var _fb := StandardMaterial3D.new()
	_fb.roughness = 0.85
	_box.material = _fb
	props.clear()
	_static.clear()
	_solid_parts.clear()
	_deco_parts.clear()
	for k in 4:
		_tile(Vector3(0, -1.3125 - k * 0.625, 0), Vector3(n, 0.625, n),
			Color.from_hsv(0.07, 0.4, 0.36 - k * 0.05))
	for x in n:
		for z in n:
			var e := maxf(absf(float(x) - (half - 0.5)), absf(float(z) - (half - 0.5)))
			var v := 0.44 + randf() * 0.05 + float((x + z) % 2) * 0.025
			var c := Color.from_hsv(0.29 + randf() * 0.02, 0.5, v)
			var rim := (half - 0.5) - e
			if rim < 1.3:
				c = c * (1.0 - (1.3 - rim) * 0.11)
			_tile(Vector3(float(x) - half + 0.5, -0.5, float(z) - half + 0.5), Vector3(0.985, 1, 0.985), c)
	var sc := float(n) / 10.0
	var rock_spots := [Vector3(-4.3, 0, 4.2), Vector3(4.4, 0, -3.9), Vector3(4.2, 0, 4.3)]
	var tree_spots := [Vector3(-4.3, 0, -4.3), Vector3(4.3, 0, 2.5)]
	var flower_spots := [Vector3(-2.9, 0, 4.3), Vector3(0, 0, 4.5), Vector3(3.2, 0, -4.5),
		Vector3(-4.5, 0, 0), Vector3(4.5, 0, 0.4), Vector3(-1.4, 0, -4.5), Vector3(1.3, 0, 4.5)]
	if n > 10:
		for s in rock_spots.duplicate():
			rock_spots[rock_spots.find(s)] = Vector3(s.x * sc, 0, s.z * sc)
		for s in tree_spots.duplicate():
			tree_spots[tree_spots.find(s)] = Vector3(s.x * sc, 0, s.z * sc)
		for s in flower_spots.duplicate():
			flower_spots[flower_spots.find(s)] = Vector3(s.x * sc, 0, s.z * sc)
		var extra := int(float(n * n - 100) / 28.0)
		# Quality LOD: Low graphics halves extras so 80x80 stays sane.
		var q := _read_quality()
		if q == 0:
			extra = extra / 2
		elif q == 1:
			extra = int(extra * 0.75)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234 + n
		for i in extra:
			var p := Vector3(rng.randf_range(-half + 2.0, half - 2.0), 0, rng.randf_range(-half + 2.0, half - 2.0))
			if Vector2(p.x, p.z).length() < 3.0:
				continue
			if i % 3 == 0:
				rock_spots.append(p)
			elif i % 3 == 1:
				tree_spots.append(p)
			else:
				flower_spots.append(p)
	for spot in rock_spots:
		_prop("rock", 30.0, spot, [
			[Vector3(0.1, 0.01, 0.1), Vector3(1.3, 0.02, 1.3), Color(0x1f4a24ff)],
			[Vector3(0, 0.25, 0), Vector3(0.5, 0.5, 0.5), Color(0x9aa3adff)],
			[Vector3(0.5, 0.15, 0.2), Vector3(0.3, 0.3, 0.3), Color(0x80898fff)]], false)
	for spot in tree_spots:
		_prop("tree", 25.0, spot, [
			[Vector3(0.3, 0.01, 0.3), Vector3(2.4, 0.02, 2.4), Color(0x1f4a24ff)],
			[Vector3(0, 0.6, 0), Vector3(0.4, 1.2, 0.4), Color(0x7a4b2aff)],
			[Vector3(0, 1.6, 0), Vector3(1.5, 1.1, 1.5), Color(0x2f9a3dff)],
			[Vector3(0, 2.4, 0), Vector3(0.9, 0.8, 0.9), Color(0x3fb04cff)]], false)
	var tops := [Color(0xff5d8fff), Color(0xffd23fff), Color(0xffffffff)]
	for i in flower_spots.size():
		var s: Vector3 = flower_spots[i]
		_prop("flower", 10.0, s, [
			[Vector3(0, 0.15, 0), Vector3(0.06, 0.3, 0.06), Color(0x2a7a35ff)],
			[Vector3(0, 0.38, 0), Vector3(0.2, 0.2, 0.2), tops[i % 3]]], true)
	_bake_statics()
	_bake_props()
	_build_prop_collisions()


func _read_quality() -> int:
	var c := ConfigFile.new()
	if c.load("user://cubebox_settings.cfg") != OK:
		return 2
	return clampi(int(c.get_value("game", "quality", 2)), 0, 2)


func _bake_statics() -> void:
	if _static.is_empty():
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
	mm.instance_count = _static.size()
	for i in _static.size():
		var sd: Dictionary = _static[i]
		var sp: Vector3 = sd["pos"]
		var ss: Vector3 = sd["size"]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(ss), sp))
		mm.set_instance_color(i, sd["col"])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Static: tell the lightmapper + culler this never moves.
	mmi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	CBPerf.apply_mmi_culling(mmi, _map_half + 2.0)
	add_child(mmi)
	_static.clear()


func _make_prop_mmi(parts: Array, shadows: bool) -> MultiMeshInstance3D:
	if parts.is_empty():
		return null
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
	mm.instance_count = parts.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	CBPerf.apply_mmi_culling(mmi, _map_half + 4.0)
	add_child(mmi)
	return mmi


func _bake_props() -> void:
	_solid_mmi = _make_prop_mmi(_solid_parts, true)
	_deco_mmi = _make_prop_mmi(_deco_parts, false)
	_refresh_all_prop_instances()


func _prop_base_scale(pi: int) -> float:
	# Respawned/destroyed props collapse to zero; far props culled by LOD.
	var p: Dictionary = props[pi]
	if float(p["respawn"]) > 0.0:
		return 0.0
	if _lod_has_cam:
		var pp: Vector3 = p["pos"]
		var dx: float = pp.x - _lod_cam.x
		var dz: float = pp.z - _lod_cam.z
		if dx * dx + dz * dz > 55.0 * 55.0:
			return 0.0
		if String(p["kind"]) == "flower":
			# Flowers are deco: drop them past 30 m (grass covers the look).
			if dx * dx + dz * dz > 30.0 * 30.0:
				return 0.0
	var grow: float = float(p["grow"])
	var wob: float = float(p["wob"])
	return maxf(grow * (1.0 + 0.18 * wob * sin(_tick * 30.0)), 0.01)


func _refresh_all_prop_instances() -> void:
	for pi in props.size():
		_refresh_prop(pi)


func _refresh_prop(pi: int) -> void:
	var p: Dictionary = props[pi]
	var s: float = _prop_base_scale(pi)
	var base: Vector3 = p["pos"]
	var s_from: int = int(p["s_from"])
	var s_to: int = int(p["s_to"])
	var d_from: int = int(p["d_from"])
	var d_to: int = int(p["d_to"])
	if _solid_mmi != null and s_to > s_from:
		var mm: MultiMesh = _solid_mmi.multimesh
		for k in range(s_from, s_to):
			var part: Dictionary = _solid_parts[k]
			var off: Vector3 = part["off"]
			var sz: Vector3 = part["size"]
			var wp := Vector3(base.x + off.x * s, off.y * s, base.z + off.z * s)
			if s <= 0.0:
				mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3.ZERO), wp))
			else:
				mm.set_instance_transform(k, Transform3D(Basis.from_scale(sz * s), wp))
			mm.set_instance_color(k, part["col"])
	if _deco_mmi != null and d_to > d_from:
		var mm2: MultiMesh = _deco_mmi.multimesh
		var di := 0
		for k in range(d_from, d_to):
			var part2: Dictionary = _deco_parts[k]
			var off2: Vector3 = part2["off"]
			var sz2: Vector3 = part2["size"]
			var wp2 := Vector3(base.x + off2.x * s, off2.y * s, base.z + off2.z * s)
			if s <= 0.0:
				mm2.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3.ZERO), wp2))
			else:
				mm2.set_instance_transform(k, Transform3D(Basis.from_scale(sz2 * s), wp2))
			mm2.set_instance_color(k, part2["col"])
			di += 1


func damage_props(pos: Vector3, radius: float, dmg: float) -> int:
	var hits := 0
	for pi in props.size():
		var p: Dictionary = props[pi]
		if float(p["respawn"]) > 0.0:
			continue
		var pp: Vector3 = p["pos"]
		var dx: float = pp.x - pos.x
		var dz: float = pp.z - pos.z
		# Squared check: no Vector2 alloc, no sqrt in the hot loop.
		if dx * dx + dz * dz <= (radius + 1.0) * (radius + 1.0):
			hits += 1
			p["hp"] = float(p["hp"]) - dmg
			p["wob"] = 1.0
			if vfx != null:
				vfx.burst(pp + Vector3(0, 0.6, 0), Color(0.7, 0.7, 0.72), 6, 3.0, 0.08, 0.4)
			if float(p["hp"]) <= 0.0:
				p["respawn"] = 10.0
				_refresh_prop(pi)
				if vfx != null:
					vfx.burst(pp + Vector3(0, 0.8, 0), Color(0.9, 0.9, 0.9), 16, 5.0, 0.12, 0.7)
					vfx.ring(pp, Color(0.8, 0.8, 0.8), 0.3, 2.5, 0.4)
			else:
				_refresh_prop(pi)
	return hits


# Timers live in physics (fixed step, no render-rate dependence).
func _physics_process(dt: float) -> void:
	_phys_tick += dt
	var any_timer := false
	for pi in props.size():
		var p: Dictionary = props[pi]
		var r: float = float(p["respawn"])
		if r > 0.0:
			r -= dt
			p["respawn"] = r
			if r <= 0.0:
				p["hp"] = float(p["max_hp"])
				p["grow"] = 0.0
				p["respawn"] = 0.0
				_refresh_prop(pi)
			any_timer = true
		elif float(p["grow"]) < 1.0:
			p["grow"] = minf(1.0, float(p["grow"]) + dt * 3.0)
			_refresh_prop(pi)
			any_timer = true
	if any_timer:
		pass


# Visuals only: wobble decay. No dictionaries allocated here.
func _process(dt: float) -> void:
	_tick += dt
	var wobbling := false
	for pi in props.size():
		var p: Dictionary = props[pi]
		if float(p["wob"]) > 0.0:
			p["wob"] = maxf(0.0, float(p["wob"]) - dt * 4.0)
			_refresh_prop(pi)
			wobbling = true
	# Distance LOD at ~4 Hz so 80x80 maps don't rewrite 1000 instances/frame.
	_lod_t += dt
	if _lod_t >= 0.25 and _lod_has_cam:
		_lod_t = 0.0
		_refresh_all_prop_instances()
	elif not wobbling:
		pass


func update_lod(cam_pos: Vector3) -> void:
	_lod_cam = cam_pos
	_lod_has_cam = true


func _prop(kind: String, hp: float, base: Vector3, parts: Array, deco: bool) -> void:
	var s_from := _solid_parts.size()
	var d_from := _deco_parts.size()
	for part in parts:
		var pa: Array = part
		var rec := {"prop": props.size(), "off": pa[0], "size": pa[1], "col": pa[2]}
		if deco:
			_deco_parts.append(rec)
		else:
			_solid_parts.append(rec)
	props.append({"root": null, "pos": base, "hp": hp, "max_hp": hp,
		"kind": kind, "wob": 0.0, "respawn": 0.0, "grow": 1.0,
		"s_from": s_from, "s_to": _solid_parts.size() if not deco else s_from,
		"d_from": d_from, "d_to": _deco_parts.size() if deco else d_from})


func _build_prop_collisions() -> void:
	# One StaticBody, one BoxShape per solid prop (rock/tree). Flowers are
	# walk-through. Single body + layer WORLD / mask 0 = minimal pairs.
	var body := StaticBody3D.new()
	body.name = "PropColliders"
	CBLayers.apply_static(body)
	var count := 0
	for p in props:
		var kind := String(p["kind"])
		if kind != "rock" and kind != "tree":
			continue
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.1, 1.6 if kind == "tree" else 0.9, 1.1)
		cs.shape = bs
		var bp: Vector3 = p["pos"]
		cs.position = bp + Vector3(0, 0.6 if kind == "tree" else 0.3, 0)
		body.add_child(cs)
		count += 1
	if count > 0:
		add_child(body)


func _tile(pos: Vector3, size: Vector3, col: Color) -> void:
	_static.append({"pos": pos, "size": size, "col": col})


func _tile_parent(_parent: Node3D, _pos: Vector3, _size: Vector3, _col: Color) -> void:
	# Legacy per-node path removed: props are MultiMesh-batched now.
	pass


func _mat(col: Color) -> StandardMaterial3D:
	var key := col.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.85
		_mats[key] = m
	return _mats[key]
