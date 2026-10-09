extends Node3D
## VFX pool ported from block-brawl-quality.html: ground rings, hit flashes,
## slash arcs, dash streaks + instanced box particles. Meshes are built in
## code; each active FX owns one pooled MeshInstance3D + material.

var cap := 100

var _ring_mesh: ArrayMesh
var _slash_l_mesh: ArrayMesh
var _slash_h_mesh: ArrayMesh
var _flash_mesh: SphereMesh
var _streak_mesh: BoxMesh

var _pool := {"ring": [], "slashL": [], "slashH": [], "flash": [], "streak": []}
var _fx: Array = []

var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _pp: Array = []
var _pi := 0
const NP := 100
var dt_scale := 1.0


func _ready() -> void:
	_ring_mesh = _annulus(0.85, 1.0, 40, TAU)
	_slash_l_mesh = _sector(1.0, 1.6, 1.8)
	_slash_h_mesh = _sector(1.1, 2.3, 2.6)
	_flash_mesh = SphereMesh.new()
	_flash_mesh.radius = 1.0
	_flash_mesh.height = 2.0
	_streak_mesh = BoxMesh.new()
	_streak_mesh.size = Vector3(1, 1, 1)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var pm := BoxMesh.new()
	pm.size = Vector3(1, 1, 1)
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


func set_cap(n: int) -> void:
	cap = n


func ring(pos: Vector3, col: Color, r0: float, r1: float, dur: float) -> void:
	var m := _grab("ring", _ring_mesh, col, false)
	m.position = Vector3(pos.x, 0.06, pos.z)
	_fx.append({"kind": "ring", "m": m, "t": 0.0, "dur": dur, "r0": r0, "r1": r1})


func flash(pos: Vector3, sz: float, col: Color) -> void:
	var m := _grab("flash", _flash_mesh, col, true)
	m.position = pos
	_fx.append({"kind": "flash", "m": m, "t": 0.0, "dur": 0.14, "sz": sz})


func slash(pos: Vector3, yaw: float, heavy: bool, col: Color) -> void:
	var m := _grab("slashH" if heavy else "slashL", _slash_h_mesh if heavy else _slash_l_mesh, col.lerp(Color.WHITE, 0.5), false)
	m.position = Vector3(pos.x, 0.75, pos.z)
	_fx.append({"kind": "slash", "m": m, "t": 0.0, "dur": 0.3 if heavy else 0.18,
		"yaw": yaw, "heavy": heavy})


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


func burst(pos: Vector3, col: Color, n: int, sp: float, s: float, life: float, up: float = 1.0) -> void:
	for i in n:
		var a := randf() * TAU
		var e := randf() * sp
		emit(pos, Vector3(cos(a) * e, randf() * sp * 0.8 * up + 1.0, sin(a) * e),
			col, s, life * randf_range(0.6, 1.2))


func clear_all() -> void:
	for x in _fx:
		_rel(x)
	_fx.clear()
	for i in NP:
		(_pp[i] as Dictionary)["life"] = 0.0
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))


func _process(dt: float) -> void:
	var sd := dt * dt_scale
	for i in range(_fx.size() - 1, -1, -1):
		var x: Dictionary = _fx[i]
		x["t"] = float(x["t"]) + sd
		var u := clampf(float(x["t"]) / float(x["dur"]), 0.0, 1.0)
		var m: MeshInstance3D = x["m"]
		match String(x["kind"]):
			"ring":
				var s := float(x["r0"]) + (float(x["r1"]) - float(x["r0"])) * (1.0 - (1.0 - u) * (1.0 - u))
				m.scale = Vector3(s, 1, s)
				_op(m, 0.85 * (1.0 - u))
			"flash":
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
	if any:
		pass # transforms write straight into the multimesh


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
		"streak":
			key = "streak"
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
	for i in verts.size():
		st.set_normal(normals[i])
		st.add_vertex(verts[i])
	for i in idx:
		st.add_index(i)
	return st.commit()
