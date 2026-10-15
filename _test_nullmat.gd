extends SceneTree

var _imm: ImmediateMesh
var _imm_mi: MeshInstance3D


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.2, 0.2)
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-PI / 4.0, 0, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 4, 14)
	cam.look_at(Vector3.ZERO)
	world.add_child(cam)

	var mat := StandardMaterial3D.new()

	# A: plain box, mesh surface has no material, no override, casts shadow
	var a := MeshInstance3D.new()
	var ab := BoxMesh.new()
	a.mesh = ab
	a.position = Vector3(-12, 0, 0)
	world.add_child(a)

	# B: box, surface material set on the mesh, no override
	var b := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.material = mat
	b.mesh = bb
	b.position = Vector3(-8, 0, 0)
	world.add_child(b)

	# C: box + material_override, surface has no material
	var c := MeshInstance3D.new()
	c.mesh = BoxMesh.new()
	c.material_override = mat
	c.position = Vector3(-4, 0, 0)
	world.add_child(c)

	# D: ImmediateMesh with ZERO surfaces + material_override
	_imm = ImmediateMesh.new()
	_imm_mi = MeshInstance3D.new()
	_imm_mi.mesh = _imm
	_imm_mi.material_override = mat
	_imm_mi.position = Vector3(0, 0, 0)
	world.add_child(_imm_mi)

	# E: MultiMesh, box surface material on mesh
	var f := MultiMeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = fm
	mm.instance_count = 4
	for i in 4:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(4 + i, 0, 0)))
	f.multimesh = mm
	world.add_child(f)

	# G: ArrayMesh from SurfaceTool with no material
	var g := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in 3:
		st.add_vertex(Vector3(8 + i, 0, -1))
		st.add_vertex(Vector3(8 + i, 0, 1))
		st.add_vertex(Vector3(8 + i, 2, 0))
	var am := st.commit()
	g.mesh = am
	g.position = Vector3(0, 0, 0)
	world.add_child(g)

	print("MARKER_BEFORE_DRAW")
	for i in 4:
		await process_frame
	# now rebuild the ImmediateMesh every frame, like bb_debug.gd does
	for fno in 10:
		_imm.clear_surfaces()
		_imm.surface_begin(Mesh.PRIMITIVE_LINES)
		_imm.surface_add_vertex(Vector3(-1, 0, 0))
		_imm.surface_add_vertex(Vector3(1, 0, 0))
		_imm.surface_end()
		await process_frame
	print("MARKER_DONE")
	quit()
