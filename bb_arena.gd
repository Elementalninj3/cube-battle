extends Node3D
## Arena builder ported from block-brawl-quality.html: 10x10 checkered grass
## platform on a dirt base, with rocks, trees and flowers. Floor tiles are
## static; rocks/trees/flowers are destructible props (HP + wobble + destroy
## + respawn). All boxes share one BoxMesh; materials are cached per color.

var _box: BoxMesh
var _mats := {}
var vfx = null
var props: Array = []
var _tick := 0.0
# Static floor tiles are baked into ONE MultiMesh (1 draw call instead of
# 104, in both the color and shadow passes). Destructible props stay as
# individual nodes (wobble/respawn needs per-prop transforms).
var _static: Array = []


func build(p_vfx) -> void:
	vfx = p_vfx
	_box = BoxMesh.new()
	_box.size = Vector3.ONE
	_box.material = null
	props.clear()
	# dirt base, 4 layers
	for k in 4:
		_tile(Vector3(0, -1.3125 - k * 0.625, 0), Vector3(10, 0.625, 10),
			Color.from_hsv(0.07, 0.4, 0.36 - k * 0.05))
	# grass platform
	for x in 10:
		for z in 10:
			var e := maxf(absf(x - 4.5), absf(z - 4.5))
			var v := 0.44 + randf() * 0.05 + float((x + z) % 2) * 0.025
			var c := Color.from_hsv(0.29 + randf() * 0.02, 0.5, v)
			if e > 3.2:
				c = c * (1.0 - (e - 3.2) * 0.11)
			_tile(Vector3(x - 4.5, -0.5, z - 4.5), Vector3(0.985, 1, 0.985), c)
	# rocks (destructible)
	for spot in [Vector3(-4.3, 0, 4.2), Vector3(4.4, 0, -3.9), Vector3(4.2, 0, 4.3)]:
		_prop("rock", 30.0, spot, [
			[Vector3(0.1, 0.01, 0.1), Vector3(1.3, 0.02, 1.3), Color(0x1f4a24ff)],
			[Vector3(0, 0.25, 0), Vector3(0.5, 0.5, 0.5), Color(0x9aa3adff)],
			[Vector3(0.5, 0.15, 0.2), Vector3(0.3, 0.3, 0.3), Color(0x80898fff)]])
	# trees (destructible)
	for spot in [Vector3(-4.3, 0, -4.3), Vector3(4.3, 0, 2.5)]:
		_prop("tree", 25.0, spot, [
			[Vector3(0.3, 0.01, 0.3), Vector3(2.4, 0.02, 2.4), Color(0x1f4a24ff)],
			[Vector3(0, 0.6, 0), Vector3(0.4, 1.2, 0.4), Color(0x7a4b2aff)],
			[Vector3(0, 1.6, 0), Vector3(1.5, 1.1, 1.5), Color(0x2f9a3dff)],
			[Vector3(0, 2.4, 0), Vector3(0.9, 0.8, 0.9), Color(0x3fb04cff)]])
	# flowers (destructible)
	var tops := [Color(0xff5d8fff), Color(0xffd23fff), Color(0xffffffff)]
	var spots := [Vector3(-2.9, 0, 4.3), Vector3(0, 0, 4.5), Vector3(3.2, 0, -4.5),
		Vector3(-4.5, 0, 0), Vector3(4.5, 0, 0.4), Vector3(-1.4, 0, -4.5), Vector3(1.3, 0, 4.5)]
	for i in spots.size():
		var s: Vector3 = spots[i]
		_prop("flower", 10.0, s, [
			[Vector3(0, 0.15, 0), Vector3(0.06, 0.3, 0.06), Color(0x2a7a35ff)],
			[Vector3(0, 0.38, 0), Vector3(0.2, 0.2, 0.2), tops[i % 3]]])
	_bake_statics()


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
	add_child(mmi)
	_static.clear()


func damage_props(pos: Vector3, radius: float, dmg: float) -> int:
	var hits := 0
	for p in props:
		if float(p["respawn"]) > 0.0:
			continue
		var pp: Vector3 = p["pos"]
		var dx: float = pp.x - pos.x
		var dz: float = pp.z - pos.z
		if Vector2(dx, dz).length() <= radius + 1.0:
			hits += 1
			p["hp"] = float(p["hp"]) - dmg
			p["wob"] = 1.0
			if vfx != null:
				vfx.burst(pp + Vector3(0, 0.6, 0), Color(0.7, 0.7, 0.72), 6, 3.0, 0.08, 0.4)
			if float(p["hp"]) <= 0.0:
				(p["root"] as Node3D).visible = false
				p["respawn"] = 10.0
				if vfx != null:
					vfx.burst(pp + Vector3(0, 0.8, 0), Color(0.9, 0.9, 0.9), 16, 5.0, 0.12, 0.7)
					vfx.ring(pp, Color(0.8, 0.8, 0.8), 0.3, 2.5, 0.4)
	return hits


func _process(dt: float) -> void:
	_tick += dt
	var dirty := false
	for p in props:
		if float(p["respawn"]) > 0.0:
			p["respawn"] = float(p["respawn"]) - dt
			if float(p["respawn"]) <= 0.0:
				p["hp"] = float(p["max_hp"])
				p["grow"] = 0.0
				(p["root"] as Node3D).visible = true
				p["respawn"] = 0.0
				dirty = true
		else:
			if float(p["wob"]) > 0.0:
				p["wob"] = maxf(0.0, float(p["wob"]) - dt * 4.0)
				dirty = true
			if float(p["grow"]) < 1.0:
				p["grow"] = minf(1.0, float(p["grow"]) + dt * 3.0)
				dirty = true
		if dirty:
			var s: float = float(p["grow"]) * (1.0 + 0.18 * float(p["wob"]) * sin(_tick * 30.0))
			(p["root"] as Node3D).scale = Vector3.ONE * maxf(s, 0.01)
			dirty = false


func _prop(kind: String, hp: float, base: Vector3, parts: Array) -> void:
	var root := Node3D.new()
	root.position = base
	add_child(root)
	for part in parts:
		var pa: Array = part
		_tile_parent(root, pa[0], pa[1], pa[2])
	props.append({"root": root, "pos": base, "hp": hp, "max_hp": hp,
		"kind": kind, "wob": 0.0, "respawn": 0.0, "grow": 1.0})


func _tile(pos: Vector3, size: Vector3, col: Color) -> void:
	_static.append({"pos": pos, "size": size, "col": col})


func _tile_parent(parent: Node3D, pos: Vector3, size: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _box
	mi.position = pos
	mi.scale = size
	mi.material_override = _mat(col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)


func _mat(col: Color) -> StandardMaterial3D:
	var key := col.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.85
		_mats[key] = m
	return _mats[key]
