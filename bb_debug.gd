extends Node3D
## Hitbox / hurtbox debug overlay for Block Brawl.
## Drawn with a single ImmediateMesh (lines, no depth test) rebuilt each frame.
## Enabled via bb_main.show_hitboxes (Settings checkbox or F1).

var _mesh: ImmediateMesh
var _mi: MeshInstance3D

const HURT := Color(0.2, 1.0, 0.35, 1.0)
const RANGE_IDLE := Color(1.0, 1.0, 1.0, 0.35)
const RANGE_WINDUP := Color(1.0, 0.9, 0.2, 0.9)
const RANGE_ACTIVE := Color(1.0, 0.15, 0.15, 1.0)
const RANGE_RECOVER := Color(1.0, 0.55, 0.15, 0.9)
const TIP_COL := Color(0.3, 0.9, 1.0, 1.0)
const BULLET_COL := Color(1.0, 0.85, 0.2, 1.0)
const FACE_COL := Color(1.0, 1.0, 1.0, 0.9)
const COUNTER_COL := Color(0.3, 0.8, 1.0, 1.0)


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_mi = MeshInstance3D.new()
	_mi.mesh = _mesh
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	_mi.material_override = mat
	add_child(_mi)


func _line(a: Vector3, b: Vector3, col: Color) -> void:
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(b)


func _circle_y(c: Vector3, r: float, col: Color, segs: int = 32) -> void:
	var prev := c + Vector3(r, 0, 0)
	for i in range(1, segs + 1):
		var a: float = TAU * float(i) / float(segs)
		var p := c + Vector3(cos(a) * r, 0, sin(a) * r)
		_line(prev, p, col)
		prev = p


func _sphere_wire(c: Vector3, r: float, col: Color) -> void:
	_circle_y(c, r, col, 24)
	# XY ring
	var prev := c + Vector3(r, 0, 0)
	for i in range(1, 17):
		var a: float = TAU * float(i) / 16.0
		var p := c + Vector3(cos(a) * r, sin(a) * r, 0)
		_line(prev, p, col)
		prev = p
	# ZY ring
	prev = c + Vector3(0, 0, r)
	for i in range(1, 17):
		var a2: float = TAU * float(i) / 16.0
		var p := c + Vector3(0, sin(a2) * r, cos(a2) * r)
		_line(prev, p, col)
		prev = p


func _arc_cone(origin: Vector3, yaw: float, atk_range: float, arc_dot: float, radial: bool, col: Color) -> void:
	if radial:
		_circle_y(origin, atk_range + 0.45, col, 40)
		return
	var half := acos(clampf(arc_dot, -1.0, 1.0))
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	for s in [-1.0, 1.0]:
		var a: float = half * float(s)
		var dir := Vector3(
			fwd.x * cos(a) + fwd.z * sin(a), 0,
			-fwd.x * sin(a) + fwd.z * cos(a))
		_line(origin, origin + dir * (atk_range + 0.45), col)
	# arc edge
	var segs := 20
	var prev := Vector3.ZERO
	for i in range(segs + 1):
		var a2: float = -half + 2.0 * half * float(i) / float(segs)
		var dir2 := Vector3(
			fwd.x * cos(a2) + fwd.z * sin(a2), 0,
			-fwd.x * sin(a2) + fwd.z * cos(a2))
		var p := origin + dir2 * (atk_range + 0.45)
		if i > 0:
			_line(prev, p, col)
		prev = p


func draw_frame(fighters: Array, bullets: Array, bullet_r: float) -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for f in fighters:
		if f == null or not (f is Node3D):
			continue
		var fp: Vector3 = (f as Node3D).position
		if String(f.st) == "ko" or not (f as Node3D).visible:
			continue
		var chest := fp + Vector3(0, 0.9, 0)
		# hurtbox: matches bullet check (dist to chest < BULLET_R)
		_sphere_wire(chest, bullet_r, HURT)
		# body push radius
		_circle_y(Vector3(fp.x, 0.08, fp.z), 0.45, HURT, 20)
		# face arrow
		var face: Vector3 = f.face
		_line(chest, chest + face * 1.2, FACE_COL)
		_line(chest + face * 1.2, chest + face * 0.9 + Vector3(face.z, 0, -face.x) * 0.15, FACE_COL)
		_line(chest + face * 1.2, chest + face * 0.9 - Vector3(face.z, 0, -face.x) * 0.15, FACE_COL)
		# attack range / arc
		if String(f.st) == "atk" and f.atk != null:
			var atk: Dictionary = f.atk
			var col := RANGE_ACTIVE
			if f.t < float(atk.get("w", 0.0)):
				col = RANGE_WINDUP
			elif f.t > float(atk.get("w", 0.0)) + float(atk.get("a", 0.0)):
				col = RANGE_RECOVER
			var kind := String(atk.get("kind", ""))
			if kind == "bash":
				var tip: Vector3 = f._shield_tip()
				_sphere_wire(Vector3(tip.x, 0.9, tip.z), 1.4, col)
				_line(chest, Vector3(tip.x, 0.9, tip.z), col)
				_sphere_wire(tip, 0.2, TIP_COL)
			elif kind == "sweep":
				var tip2: Vector3 = f._sword_tip()
				_sphere_wire(Vector3(tip2.x, 0.9, tip2.z), 1.3, col)
				_line(chest, Vector3(tip2.x, 0.9, tip2.z), col)
				_sphere_wire(tip2, 0.2, TIP_COL)
				_arc_cone(Vector3(fp.x, 0.1, fp.z), f.ang, 2.6, -0.3, false, col)
			elif atk.has("range"):
				_arc_cone(Vector3(fp.x, 0.1, fp.z), f.ang,
					float(atk["range"]), float(atk.get("arc", 0.0)),
					bool(atk.get("radial", false)), col)
			if kind == "counter" and f.counter_open():
				_circle_y(Vector3(fp.x, 0.12, fp.z), 1.6, COUNTER_COL, 32)
				_sphere_wire(chest, bullet_r + 0.3, COUNTER_COL)
		else:
			# idle: faint default punch range hint
			_circle_y(Vector3(fp.x, 0.07, fp.z), 2.0 + 0.45, RANGE_IDLE, 28)
		# sword / shield tips when present
		if f.sword_node != null:
			var st: Vector3 = f._sword_tip()
			_sphere_wire(st, 0.15, TIP_COL)
		if f.shield_node != null:
			var sht: Vector3 = f._shield_tip()
			_sphere_wire(sht, 0.15, TIP_COL)
	for b in bullets:
		var p: Vector3 = b["p"]
		var v: Vector3 = b["v"]
		_sphere_wire(p, bullet_r, BULLET_COL)
		_line(p, p - v.normalized() * 0.6, BULLET_COL)
	_mesh.surface_end()


func clear() -> void:
	if _mesh != null and _mesh.get_surface_count() > 0:
		_mesh.clear_surfaces()
