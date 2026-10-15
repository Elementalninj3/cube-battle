extends Node3D
## VFX pool ported from block-brawl-quality.html: ground rings, hit flashes,
## slash arcs, dash streaks + instanced box particles. Meshes are built in
## code; each active FX owns one pooled MeshInstance3D + material.

var cap := 100

var _ring_mesh: ArrayMesh
var _slash_l_mesh: ArrayMesh
var _slash_h_mesh: ArrayMesh
var _slash_n_mesh: ArrayMesh
var _flash_mesh: SphereMesh
var _streak_mesh: BoxMesh
var _cube_mesh: BoxMesh

var _pool := {"ring": [], "slashL": [], "slashH": [], "slashN": [], "flash": [], "streak": [], "ghost": [], "puff": []}
var _fx: Array = []

var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _pp: Array = []
var _pi := 0
const NP := 100
var dt_scale := 1.0
var _any_live := false


func _ready() -> void:
	_ring_mesh = _annulus(0.85, 1.0, 40, TAU)
	_slash_l_mesh = _sector(1.0, 1.6, 1.8)
	_slash_h_mesh = _sector(1.1, 2.3, 2.6)
	# HTML slash trail: RingGeometry(0.9, 2.35, 8, 1) arc segments, life 0.22.
	_slash_n_mesh = _sector(0.9, 2.35, 2.2)
	_cube_mesh = BoxMesh.new()
	_cube_mesh.size = Vector3(1, 1, 1)
	_cube_mesh.material = _fallback_mat()
	_flash_mesh = SphereMesh.new()
	_flash_mesh.radius = 1.0
	_flash_mesh.height = 2.0
	_flash_mesh.material = _fallback_mat()
	_streak_mesh = BoxMesh.new()
	_streak_mesh.size = Vector3(1, 1, 1)
	_streak_mesh.material = _fallback_mat()
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var pm := BoxMesh.new()
	pm.size = Vector3(1, 1, 1)
	pm.material = _fallback_mat()
	_mm.mesh = pm
	_mm.instance_count = NP
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pmat := StandardMaterial3D.new()
	pmat.vertex_color_use_as_albedo = true
	pmat.roughness = 0.9
	_mmi.material_override = pmat
	add_child(_mmi)
	var zero := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	for i in NP:
		_pp.append({"p": Vector3.ZERO, "v": Vector3.ZERO, "life": 0.0, "max": 1.0, "s": 0.1, "gr": 10.0})
		_mm.set_instance_transform(i, zero)
		_mm.set_instance_color(i, Color.WHITE)


func _fallback_mat() -> StandardMaterial3D:
	# Crash fix: no procedural mesh may carry a null base material. GLES3
	# queries the mesh material even when material_override is set, and a
	# null deref there access-violates old Intel Windows drivers.
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	return m


func set_cap(n: int) -> void:
	cap = n


func ring(pos: Vector3, col: Color, r0: float, r1: float, dur: float, alpha: float = 0.85, linear: bool = false) -> void:
	var m := _grab("ring", _ring_mesh, col, false)
	m.position = Vector3(pos.x, 0.06, pos.z)
	_fx.append({"kind": "ring", "m": m, "t": 0.0, "dur": dur, "r0": r0, "r1": r1, "a0": alpha, "lin": linear})


# Floating damage number (HTML .dmg popup): rises ~1.2 u over 0.85 s with
# an early scale pop, then fades. Visual only; freed on expiry.
func damage_number(pos: Vector3, text: String, col: Color, big: bool = false) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96 if big else 64
	l.pixel_size = 0.012 if big else 0.009
	l.modulate = col
	l.outline_size = 12
	l.outline_modulate = Color(0.05, 0.02, 0.1, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos + Vector3(randf_range(-0.15, 0.15), 0, 0)
	add_child(l)
	_fx.append({"kind": "popup", "m": l, "t": 0.0, "dur": 0.85})


func flash(pos: Vector3, sz: float, col: Color) -> void:
	var m := _grab("flash", _flash_mesh, col, true)
	m.position = pos
	_fx.append({"kind": "flash", "m": m, "t": 0.0, "dur": 0.14, "sz": sz})


# HTML-exact explosion flash: sphere grows 0.3 -> 0.3+size over dur, hot
# color lerps to cool (white-hot core stays constant), opacity fades.
func blast_flash(pos: Vector3, size: float, col_hot: Color, col_cool: Color, dur: float, core: bool = false) -> void:
	var m := _grab("flash", _flash_mesh, col_hot, true)
	m.position = pos
	_fx.append({"kind": "flash", "m": m, "t": 0.0, "dur": dur, "sz": size,
		"hx": true, "core": core, "cc": col_hot, "ct": col_cool})


func slash(pos: Vector3, yaw: float, heavy: bool, col: Color) -> void:
	var m := _grab("slashH" if heavy else "slashL", _slash_h_mesh if heavy else _slash_l_mesh, col.lerp(Color.WHITE, 0.5), false)
	m.position = Vector3(pos.x, 0.75, pos.z)
	_fx.append({"kind": "slash", "m": m, "t": 0.0, "dur": 0.3 if heavy else 0.18,
		"yaw": yaw, "heavy": heavy})


# Faithful HTML katana trail: annular sector 0.9-2.35 at y~0.55, green
# additive, opacity 0.55, life 0.22. Follows the real swing yaw.
func slash_ninja(pos: Vector3, yaw: float, col: Color) -> void:
	var m := _grab("slashN", _slash_n_mesh, col, true)
	m.position = Vector3(pos.x, 0.55, pos.z)
	_fx.append({"kind": "slashN", "m": m, "t": 0.0, "dur": 0.22,
		"yaw": yaw})


# Faithful HTML shadow-dash ghost: dark box (0x1a0a2e, opacity 0.55,
# depth-write off) capturing position/yaw/scale, life 0.35, shrinks away.
func ghost(pos: Vector3, yaw: float, scl: Vector3) -> void:
	var m := _grab("ghost", _cube_mesh, Color(0.10, 0.04, 0.18), false)
	m.position = pos
	m.rotation = Vector3(0, yaw, 0)
	m.scale = scl
	_fx.append({"kind": "ghost", "m": m, "t": 0.0, "dur": 0.35})


# Faithful HTML smoke puff: small box (dark purple 0x2a1250 for dash,
# gray for bombs/clouds), rises with vy, spins, fades. Unshaded alpha.
# Extended params (all backwards compatible) reproduce the explosion smoke
# exactly: grow (scale 1 -> 1+grow), op (peak opacity, sqrt fade when
# growing), col_to (color lerp target, HTML prog*1.6), vel (damped drift).
func puff(pos: Vector3, col: Color, size: float, life: float, vy: float = 1.5,
		grow: float = 0.0, op: float = 0.7, col_to: Color = Color(0, 0, 0, -1),
		vel: Vector3 = Vector3.ZERO) -> void:
	var m := _grab("puff", _cube_mesh, col, false)
	m.position = pos
	m.rotation = Vector3(randf() * 3.0, randf() * 3.0, randf() * 3.0)
	m.scale = Vector3.ONE * size
	_fx.append({"kind": "puff", "m": m, "t": 0.0, "dur": life, "vy": vy,
		"spin": randf_range(-4.0, 4.0), "s0": size, "grow": grow, "op": op,
		"c0": col, "ct": col_to, "vel": vel})


# Lingering scorch disc (HTML CircleGeometry r=1.5, opacity 0.55, life 3).
func scorch(pos: Vector3, dur: float = 3.0, r: float = 1.0) -> void:
	var m := _grab("ring", _ring_mesh, Color(0.03, 0.03, 0.05, 0.55), false)
	m.position = Vector3(pos.x, 0.03, pos.z)
	_fx.append({"kind": "scorch", "m": m, "t": 0.0, "dur": dur, "r0": r})


# Temporary point light pop (HTML PointLight 0xff9a4d energy 3 range 12,
# life 0.25). Compatibility renderer supports a few omni lights fine.
# Capped at 2 concurrent pops: each extra omni re-renders every lit pixel,
# and detonations already read well from flash + ring + sparks alone.
var _active_lights := 0


func light_pop(pos: Vector3, col: Color, energy: float, dur: float = 0.25) -> void:
	if _active_lights >= 2:
		return
	_active_lights += 1
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = 12.0
	l.position = pos
	add_child(l)
	_fx.append({"kind": "light", "m": l, "t": 0.0, "dur": dur, "e0": energy})


func streak(pos: Vector3, yaw: float, col: Color) -> void:
	var m := _grab("streak", _streak_mesh, col, false)
	m.position = Vector3(pos.x, 0.6, pos.z)
	m.rotation.y = yaw
	m.scale = Vector3(0.5, 0.8, 1.6)
	_fx.append({"kind": "streak", "m": m, "t": 0.0, "dur": 0.22})


func emit(pos: Vector3, vel: Vector3, col: Color, s: float, life: float, gr: float = 10.0) -> void:
	var i := _pi % mini(cap, NP)
	_pi += 1
	var q: Dictionary = _pp[i]
	q["p"] = pos
	q["v"] = vel
	q["s"] = s
	q["life"] = life
	q["max"] = life
	q["gr"] = gr
	_mm.set_instance_color(i, col)
	_any_live = true


func burst(pos: Vector3, col: Color, n: int, sp: float, s: float, life: float, up: float = 1.0, gr: float = 10.0) -> void:
	for i in n:
		var a := randf() * TAU
		var e := randf() * sp
		emit(pos, Vector3(cos(a) * e, randf() * sp * 0.8 * up + 1.0, sin(a) * e),
			col, s, life * randf_range(0.6, 1.2), gr)


func clear_all() -> void:
	for x in _fx:
		_rel(x)
	_fx.clear()
	_active_lights = 0
	_any_live = false
	for i in NP:
		(_pp[i] as Dictionary)["life"] = 0.0
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))


func _process(dt: float) -> void:
	# Idle fast path: no active mesh FX and no live particles. Skips the
	# 100-slot particle scan every frame when nothing is playing.
	if _fx.is_empty() and not _any_live:
		return
	var sd := dt * dt_scale
	for i in range(_fx.size() - 1, -1, -1):
		var x: Dictionary = _fx[i]
		x["t"] = float(x["t"]) + sd
		var u := clampf(float(x["t"]) / float(x["dur"]), 0.0, 1.0)
		if String(x["kind"]) == "light":
			(x["m"] as OmniLight3D).light_energy = float(x["e0"]) * (1.0 - u)
			if u >= 1.0:
				_rel(x)
				_fx.remove_at(i)
			continue
		if String(x["kind"]) == "popup":
			var lb := x["m"] as Label3D
			lb.position.y += sd * 1.4
			var pop := 1.0 + 0.35 * (1.0 - minf(1.0, float(x["t"]) / 0.15))
			lb.scale = Vector3.ONE * pop
			var lc := lb.modulate
			lc.a = 1.0 - u * u
			lb.modulate = lc
			if u >= 1.0:
				_rel(x)
				_fx.remove_at(i)
			continue
		var m: MeshInstance3D = x["m"]
		match String(x["kind"]):
			"ring":
				var s := float(x["r0"]) + (float(x["r1"]) - float(x["r0"])) * u if bool(x.get("lin", false)) else float(x["r0"]) + (float(x["r1"]) - float(x["r0"])) * (1.0 - (1.0 - u) * (1.0 - u))
				m.scale = Vector3(s, 1, s)
				_op(m, float(x.get("a0", 0.85)) * (1.0 - u))
			"flash":
				if bool(x.get("hx", false)):
					# HTML blast flash: 0.3 + prog*size, hot->cool lerp
					# (core stays white), opacity (1 or 0.9) * (1-prog).
					m.scale = Vector3.ONE * (0.3 + u * float(x["sz"]))
					var fmat: StandardMaterial3D = m.material_override
					if bool(x.get("core", false)):
						fmat.albedo_color = x["cc"]
					else:
						fmat.albedo_color = (x["cc"] as Color).lerp(x["ct"] as Color, u)
					_op(m, (1.0 if bool(x.get("core", false)) else 0.9) * (1.0 - u))
				else:
					m.scale = Vector3.ONE * (float(x["sz"]) * (0.4 + u))
					_op(m, 0.9 * (1.0 - u))
			"slash":
				var hv: bool = x["heavy"]
				var th: float = x["yaw"]
				m.rotation.y = th + (0.8 - 1.6 * u) * (1.0 if hv else 0.7)
				var ss := 0.85 + 0.3 * u
				m.scale = Vector3(ss, 1, ss)
				_op(m, 0.95 * (1.0 - u * u))
			"streak":
				_op(m, 0.5 * (1.0 - u))
				m.scale.x = 0.5 * (1.0 - u)
			"slashN":
				m.rotation.y = float(x["yaw"]) + (0.8 - 1.6 * u) * 0.7
				_op(m, 0.55 * (1.0 - u))
			"ghost":
				_op(m, 0.5 * (1.0 - u))
				m.scale = m.scale * (1.0 - sd * 1.2)
			"puff":
				var vv: Vector3 = x["vel"]
				vv *= maxf(0.0, 1.0 - sd * 1.5)
				x["vel"] = vv
				m.position += vv * sd
				m.position.y += float(x["vy"]) * sd
				m.rotation.x += float(x["spin"]) * sd
				m.rotation.y += float(x["spin"]) * sd
				var grow: float = float(x.get("grow", 0.0))
				var ct: Color = x.get("ct", Color(0, 0, 0, -1))
				if ct.a >= 0.0:
					var pmat: StandardMaterial3D = m.material_override
					pmat.albedo_color = (x["c0"] as Color).lerp(ct, minf(1.0, u * 1.6))
				if grow != 0.0:
					m.scale = Vector3.ONE * (float(x["s0"]) * (1.0 + u * grow))
					_op(m, float(x.get("op", 0.7)) * sqrt(maxf(0.0, 1.0 - u)))
				else:
					_op(m, float(x.get("op", 0.7)) * (1.0 - u))
					var ps := float(x["s0"]) * (0.4 + (1.0 - u) * 0.6)
					m.scale = Vector3.ONE * ps
			"scorch":
				var ss2 := float(x.get("r0", 1.0)) * minf(1.0, 0.5 + u * 8.0)
				m.scale = Vector3(ss2, 1, ss2)
				_op(m, 0.55 * minf(1.0, (1.0 - u) * 3.0))
		if u >= 1.0:
			_rel(x)
			_fx.remove_at(i)
	var any := false
	for i in NP:
		var q: Dictionary = _pp[i]
		if float(q["life"]) <= 0.0:
			continue
		any = true
		q["life"] = float(q["life"]) - sd
		if float(q["life"]) <= 0.0:
			_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		else:
			var v: Vector3 = q["v"]
			v.y -= float(q["gr"]) * sd
			var p: Vector3 = q["p"] + v * sd
			if p.y < 0.05:
				p.y = 0.05
				v *= 0.6
			q["v"] = v
			q["p"] = p
			var s2: float = float(q["s"]) * float(q["life"]) / float(q["max"])
			_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s2), p))
	_any_live = any or not _fx.is_empty()


func _grab(key: String, mesh: Mesh, col: Color, additive: bool) -> MeshInstance3D:
	var m: MeshInstance3D
	if (_pool[key] as Array).is_empty():
		m = MeshInstance3D.new()
		m.mesh = mesh
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if additive:
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.material_override = mat
		add_child(m)
	else:
		m = (_pool[key] as Array).pop_back()
	m.visible = true
	m.rotation = Vector3.ZERO
	m.scale = Vector3.ONE
	var mat2: StandardMaterial3D = m.material_override
	mat2.albedo_color = col
	mat2.albedo_color.a = 1.0
	return m


func _rel(x: Dictionary) -> void:
	if String(x["kind"]) == "light":
		(x["m"] as Node).queue_free()
		_active_lights = maxi(0, _active_lights - 1)
		return
	if String(x["kind"]) == "popup":
		(x["m"] as Node).queue_free()
		return
	var m: MeshInstance3D = x["m"]
	m.visible = false
	var key := "ring"
	match String(x["kind"]):
		"ring":
			key = "ring"
		"flash":
			key = "flash"
		"slash":
			key = "slashH" if bool(x["heavy"]) else "slashL"
		"slashN":
			key = "slashN"
		"streak":
			key = "streak"
		"ghost":
			key = "ghost"
		"puff":
			key = "puff"
		"scorch":
			key = "ring"
	(_pool[key] as Array).append(m)


func _op(m: MeshInstance3D, a: float) -> void:
	var mat: StandardMaterial3D = m.material_override
	var c := mat.albedo_color
	c.a = clampf(a, 0.0, 1.0)
	mat.albedo_color = c


# flat annulus in XZ, full circle
func _annulus(r0: float, r1: float, segs: int, arc: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in segs + 1:
		var a := arc * float(i) / float(segs)
		var ca := cos(a)
		var sa := sin(a)
		verts.append(Vector3(ca * r0, 0, sa * r0))
		verts.append(Vector3(ca * r1, 0, sa * r1))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
	for i in segs:
		var b := i * 2
		idx.append_array([b, b + 1, b + 3, b, b + 3, b + 2])
	return _mesh(verts, normals, idx)


# annular sector centered on +Z (fighter forward)
func _sector(r0: float, r1: float, arc: float) -> ArrayMesh:
	var segs := 24
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in segs + 1:
		var a := -arc * 0.5 + arc * float(i) / float(segs)
		verts.append(Vector3(sin(a) * r0, 0, cos(a) * r0))
		verts.append(Vector3(sin(a) * r1, 0, cos(a) * r1))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
	for i in segs:
		var b := i * 2
		idx.append_array([b, b + 1, b + 3, b, b + 3, b + 2])
	return _mesh(verts, normals, idx)


func _mesh(verts: PackedVector3Array, normals: PackedVector3Array, idx: PackedInt32Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Crash fix: ArrayMesh surfaces must not carry null material (Intel GLES3).
	st.set_material(_fallback_mat())
	for i in verts.size():
		st.set_normal(normals[i])
		st.add_vertex(verts[i])
	for i in idx:
		st.add_index(i)
	return st.commit()
