extends Node3D
## Blocky fighter ported from block-brawl-quality.html: floating head cube +
## fist cubes + hat, custom combat state machine (free/atk/dash/stun/ko),
## procedural animation, HTML attack table (light/heavy).

const ATK_L := {"w": 0.1, "a": 0.08, "r": 0.18, "dmg": 6.0, "kb": 4.5,
	"range": 2.0, "arc": 0.32, "lunge": 3.0, "sh": 0.08, "hs": 0.04, "vy": 0.0,
	"kind": "punch", "big": false, "radial": false}
const ATK_H := {"w": 0.38, "a": 0.1, "r": 0.42, "dmg": 15.0, "kb": 10.0,
	"range": 2.6, "arc": 0.12, "lunge": 5.5, "sh": 0.3, "hs": 0.09, "vy": 5.0,
	"kind": "punch", "big": true, "radial": false}
const ATK_S1 := {"w": 0.22, "a": 0.3, "r": 0.3, "dmg": 10.0, "kb": 7.0,
	"range": 2.4, "arc": 0.3, "lunge": 0.0, "sh": 0.2, "hs": 0.06, "vy": 0.0,
	"kind": "dash", "big": false, "radial": false, "cd": 4.0}
const ATK_S2 := {"w": 0.3, "a": 0.15, "r": 0.45, "dmg": 12.0, "kb": 6.0,
	"range": 2.2, "arc": 0.4, "lunge": 2.0, "sh": 0.25, "hs": 0.08, "vy": 9.0,
	"kind": "upper", "big": true, "radial": false, "cd": 6.0}
const ATK_S3 := {"w": 0.3, "a": 0.35, "r": 0.35, "dmg": 9.0, "kb": 8.0,
	"range": 2.6, "arc": 0.0, "lunge": 1.0, "sh": 0.2, "hs": 0.06, "vy": 2.0,
	"kind": "spin", "big": true, "radial": true, "cd": 8.0}
const CD_ORDER := ["S1", "S2", "S3"]

var idx := 0
var game = null
var foe = null
var keys := {"up": [], "down": [], "left": [], "right": [], "L": [], "H": [], "D": [],
	"S1": [], "S2": [], "S3": []}

var body_col := Color.BLUE
var hat_kind := 1
var visor := true

var v := Vector3.ZERO
var vy := 0.0
var ang := 0.0
var face := Vector3(0, 0, 1)
var hp := 100.0
var dmg := 0.0
var st := "free"
var t := 0.0
var atk = null
var hit_done := false
var dash_cd := 0.0
var inv := 0.0
var flash := 0.0
var rec := 0.0
var stun := 0.0
var ph := 0.0
var mass := 1.0
var buf := {"L": -9.0, "H": -9.0, "D": -9.0, "S1": -9.0, "S2": -9.0, "S3": -9.0}
var cd := {"S1": 0.0, "S2": 0.0, "S3": 0.0}
var cd_max := {"S1": 4.0, "S2": 6.0, "S3": 8.0}
var spin_a := 0.0
var _dd := Vector3.ZERO
var _tr := 0.0

var model: Node3D
var head_mi: MeshInstance3D
var arm_l: Node3D
var arm_r: Node3D
var hat_root: Node3D
var mats: Array = []
var _box: BoxMesh


func _ready() -> void:
	_box = BoxMesh.new()
	_box.size = Vector3.ONE
	model = Node3D.new()
	add_child(model)
	arm_l = Node3D.new()
	arm_r = Node3D.new()
	model.add_child(arm_l)
	model.add_child(arm_r)
	hat_root = Node3D.new()
	model.add_child(hat_root)
	rebuild()


func setup(p_col: Color, p_hat: int, p_visor: bool) -> void:
	body_col = p_col
	hat_kind = p_hat
	visor = p_visor
	rebuild()


func reset_match(pos: Vector3, p_ang: float) -> void:
	position = pos
	v = Vector3.ZERO
	vy = 0.0
	ang = p_ang
	face = Vector3(sin(ang), 0, cos(ang))
	hp = 100.0
	dmg = 0.0
	st = "free"
	t = 0.0
	atk = null
	dash_cd = 0.0
	inv = 0.0
	flash = 0.0
	rec = 0.0
	spin_a = 0.0
	for key in cd:
		cd[key] = 0.0
	visible = true
	rotation.y = ang


func _mat(col: Color, rough: float = 0.55, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	m.emission_enabled = true
	m.emission = Color(0.05, 0.05, 0.05)
	mats.append(m)
	return m


func _bx(w: float, h: float, d: float, mat: Material, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box
	mi.scale = Vector3(w, h, d)
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


func rebuild() -> void:
	if model == null:
		return
	for c in model.get_children():
		if c != arm_l and c != arm_r and c != hat_root:
			c.queue_free()
	for c in hat_root.get_children():
		c.queue_free()
	for a in [arm_l, arm_r]:
		for c in a.get_children():
			c.queue_free()
	mats.clear()
	var body := _mat(body_col)
	var dk := _mat(Color(body_col.r * 0.6, body_col.g * 0.6, body_col.b * 0.6))
	var blk := _mat(Color(0.08, 0.08, 0.08), 0.4)
	var shirt := _mat(Color(0.93, 0.93, 0.93), 0.8)
	# arms attached at head sides (fists overlap head edge)
	arm_l.position = Vector3(-0.62, 0.55, 0)
	arm_r.position = Vector3(0.62, 0.55, 0)
	_bx(0.36, 0.36, 0.36, body, Vector3.ZERO, arm_l)
	_bx(0.36, 0.36, 0.36, body, Vector3.ZERO, arm_r)
	# simple floating block
	head_mi = _bx(1.0, 1.0, 1.0, body, Vector3(0, 0.55, 0), model)
	# block attire: white shirt band + dark tie
	_bx(1.08, 0.32, 1.08, shirt, Vector3(0, 0.22, 0), model)
	_bx(0.18, 0.34, 0.05, dk, Vector3(0, 0.24, 0.55), model)
	if visor:
		_bx(0.6, 0.16, 0.06, _mat(Color(0.1, 0.16, 0.33), 0.2, 0.5), Vector3(0, 0.6, 0.51), model)
	else:
		_bx(0.12, 0.14, 0.05, blk, Vector3(-0.15, 0.6, 0.51), model)
		_bx(0.12, 0.14, 0.05, blk, Vector3(0.15, 0.6, 0.51), model)
	_build_hat(body)


func _build_hat(body: Material) -> void:
	if hat_kind == 1: # cowboy
		var b := _mat(Color(0.54, 0.35, 0.17), 0.7)
		_bx(1.05, 0.06, 1.05, b, Vector3(0, 1.08, 0), hat_root)
		_bx(0.5, 0.3, 0.5, b, Vector3(0, 1.25, 0), hat_root)
	elif hat_kind == 2: # crown
		var y := _mat(Color(1.0, 0.79, 0.24), 0.3, 0.7)
		_bx(0.68, 0.16, 0.68, y, Vector3(0, 1.12, 0), hat_root)
		for sx in [-0.27, 0.27]:
			for sz in [-0.27, 0.27]:
				_bx(0.14, 0.16, 0.14, y, Vector3(sx, 1.26, sz), hat_root)
	elif hat_kind == 3: # beanie
		_bx(0.72, 0.24, 0.72, _mat(Color(0.95, 0.95, 0.95)), Vector3(0, 1.16, 0), hat_root)
		_bx(0.72, 0.1, 0.72, body, Vector3(0, 1.07, 0), hat_root)
		_bx(0.16, 0.16, 0.16, body, Vector3(0, 1.36, 0), hat_root)
	elif hat_kind == 4: # helmet
		var s := _mat(Color(0.6, 0.64, 0.7), 0.35, 0.6)
		_bx(0.76, 0.3, 0.76, s, Vector3(0, 1.16, 0), hat_root)
		_bx(0.12, 0.3, 0.8, body, Vector3(0, 1.2, 0), hat_root)


func _input(event: InputEvent) -> void:
	if game == null:
		return
	if not (event is InputEventKey):
		return
	var e := event as InputEventKey
	if not e.pressed or e.echo:
		return
	if not (String(game.state) == "play" or String(game.state) == "count"):
		return
	var k := e.physical_keycode
	var kc := e.keycode
	if k in (keys["L"] as Array) or kc in (keys["L"] as Array):
		buf["L"] = game.now
	elif k in (keys["H"] as Array) or kc in (keys["H"] as Array):
		buf["H"] = game.now
	elif k in (keys["D"] as Array) or kc in (keys["D"] as Array):
		buf["D"] = game.now
	elif k in (keys["S1"] as Array) or kc in (keys["S1"] as Array):
		buf["S1"] = game.now
	elif k in (keys["S2"] as Array) or kc in (keys["S2"] as Array):
		buf["S2"] = game.now
	elif k in (keys["S3"] as Array) or kc in (keys["S3"] as Array):
		buf["S3"] = game.now


func _has(n: String) -> bool:
	return game.now - float(buf[n]) < 0.2


func _eat(n: String) -> void:
	buf[n] = -9.0


func _key_down(codes: Array) -> bool:
	for c in codes:
		if Input.is_physical_key_pressed(c):
			return true
	return false


func upd(dt: float, play: bool) -> void:
	t += dt
	dash_cd = maxf(0.0, dash_cd - dt)
	inv = maxf(0.0, inv - dt)
	flash = maxf(0.0, flash - dt)
	rec = maxf(0.0, rec - dt)
	for key in cd:
		cd[key] = maxf(0.0, float(cd[key]) - dt)
	if st == "ko":
		return
	position.x = clampf(position.x, -4.7, 4.7)
	position.z = clampf(position.z, -4.7, 4.7)
	var ix := 0.0
	var iy := 0.0
	if play:
		ix = (1.0 if _key_down(keys["right"]) else 0.0) - (1.0 if _key_down(keys["left"]) else 0.0)
		iy = (1.0 if _key_down(keys["up"]) else 0.0) - (1.0 if _key_down(keys["down"]) else 0.0)
	var wx := ix - iy
	var wz := -ix - iy
	var wl := Vector2(wx, wz).length()
	if wl > 0.01:
		wx /= wl
		wz /= wl
	else:
		wx = 0.0
		wz = 0.0
	var ta = null
	if st == "free":
		if play and rec <= 0.0:
			if _has("D") and dash_cd <= 0.0:
				_eat("D")
				start_dash(Vector3(wx, 0, wz) if wl > 0.01 else face)
			elif _has("H"):
				_eat("H")
				start_atk("H")
			elif _has("L"):
				_eat("L")
				start_atk("L")
			elif _has("S1") and float(cd["S1"]) <= 0.0:
				_eat("S1")
				start_atk("S1")
			elif _has("S2") and float(cd["S2"]) <= 0.0:
				_eat("S2")
				start_atk("S2")
			elif _has("S3") and float(cd["S3"]) <= 0.0:
				_eat("S3")
				start_atk("S3")
		if st == "free":
			var e := 1.0 - exp(-(16.0 if wl > 0.01 else 11.0) * dt)
			v.x += (wx * 6.4 - v.x) * e
			v.z += (wz * 6.4 - v.z) * e
			if wl > 0.01:
				ta = atan2(wx, wz)
			elif foe != null and String(foe.st) != "ko":
				ta = atan2(foe.position.x - position.x, foe.position.z - position.z)
	elif st == "atk":
		var e2 := exp(-7.0 * dt)
		v.x *= e2
		v.z *= e2
		if atk != null and String(atk["kind"]) == "dash" and foe != null and String(foe.st) != "ko":
			var ddx: float = foe.position.x - position.x
			var ddz: float = foe.position.z - position.z
			var dl := Vector2(ddx, ddz).length()
			if dl > 0.05:
				v.x = ddx / dl * 14.0
				v.z = ddz / dl * 14.0
				ang = atan2(ddx, ddz)
				face = Vector3(sin(ang), 0, cos(ang))
		if atk != null and String(atk["kind"]) == "spin":
			spin_a += dt * 18.0
		else:
			spin_a = 0.0
		if not hit_done and t >= float(atk["w"]):
			hit_done = true
			strike()
		if t > float(atk["w"]) + float(atk["a"]) and play and _has("D") and dash_cd <= 0.0:
			_eat("D")
			start_dash(Vector3(wx, 0, wz) if wl > 0.01 else face)
		elif t >= float(atk["w"]) + float(atk["a"]) + float(atk["r"]):
			st = "free"
			atk = null
	elif st == "dash":
		v = _dd * 18.0
		_tr -= dt
		if _tr <= 0.0:
			_tr = 0.04
			game.vfx.streak(position, atan2(_dd.x, _dd.z), body_col)
			game.vfx.emit(position + Vector3(0, 0.1, 0),
				Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1)),
				Color(0.91, 0.89, 0.78), 0.1, 0.3, 6.0)
		if t > 0.17:
			st = "free"
			rec = 0.08
			v *= 0.3
	elif st == "stun":
		var e3 := exp(-3.0 * dt)
		v.x *= e3
		v.z *= e3
		if t >= stun:
			st = "free"
	if ta != null:
		var da := float(ta) - ang
		da = atan2(sin(da), cos(da))
		ang += da * minf(1.0, 18.0 * dt)
		face = Vector3(sin(ang), 0, cos(ang))
	position.x += v.x * dt
	position.z += v.z * dt
	if position.y <= 0.0 and vy <= 0.0:
		position.y = 0.0
		vy = 0.0
	else:
		vy -= 30.0 * dt
		position.y += vy * dt
	if position.y < -6.0 or hp <= 0.0:
		game.ko(self)


func start_atk(kind: String) -> void:
	if kind == "L":
		atk = ATK_L.duplicate()
	elif kind == "H":
		atk = ATK_H.duplicate()
	elif kind == "S1":
		atk = ATK_S1.duplicate()
	elif kind == "S2":
		atk = ATK_S2.duplicate()
	else:
		atk = ATK_S3.duplicate()
		kind = "S3"
	if atk.has("cd"):
		cd[kind] = float(atk["cd"])
	st = "atk"
	t = 0.0
	hit_done = false
	if foe != null and String(foe.st) != "ko":
		var dx: float = foe.position.x - position.x
		var dz: float = foe.position.z - position.z
		if Vector2(dx, dz).length() < 5.0:
			ang = atan2(dx, dz)
	face = Vector3(sin(ang), 0, cos(ang))
	if kind == "S1":
		game.audio.play("dash")
	elif kind == "L":
		game.audio.play("light")
	else:
		game.audio.play("heavy")


func start_dash(d: Vector3) -> void:
	st = "dash"
	t = 0.0
	_dd = Vector3(d.x, 0, d.z)
	if _dd.length() < 0.01:
		_dd = face
	_dd = _dd.normalized()
	inv = 0.22
	dash_cd = 0.75
	_tr = 0.0
	game.audio.play("dash")
	game.vfx.burst(position + Vector3(0, 0.1, 0), Color(0.91, 0.89, 0.78), 6, 2.0, 0.1, 0.35, 0.3)


func strike() -> void:
	var heavy := bool(atk["big"])
	game.vfx.slash(position, ang, heavy, body_col)
	v += face * float(atk["lunge"])
	game.damage_props(position, float(atk["range"]) + 0.6, float(atk["dmg"]))
	if foe == null:
		return
	var dx: float = foe.position.x - position.x
	var dz: float = foe.position.z - position.z
	var d: float = Vector2(dx, dz).length()
	if String(foe.st) == "ko" or d > float(atk["range"]) + 0.45:
		return
	if not bool(atk["radial"]) and d > 0.01 and (dx * face.x + dz * face.z) / d < float(atk["arc"]):
		return
	if float(foe.inv) > 0.0:
		game.vfx.burst(foe.position + Vector3(0, 0.8, 0), Color.WHITE, 4, 3.0, 0.07, 0.3)
		return
	foe.hp = maxf(0.0, float(foe.hp) - float(atk["dmg"]))
	foe.dmg += float(atk["dmg"])
	var k := float(atk["kb"]) * 0.55 / float(foe.mass)
	foe.v = Vector3(dx / maxf(d, 0.01) * k, 0, dz / maxf(d, 0.01) * k)
	foe.vy = float(atk["vy"])
	foe.st = "stun"
	foe.t = 0.0
	foe.stun = minf(0.45, 0.12 + k * 0.02)
	foe.flash = 0.14
	foe.atk = null
	var hp_pos: Vector3 = foe.position + Vector3(0, 0.9 + foe.position.y, 0)
	game.vfx.flash(hp_pos, 0.9 if heavy else 0.55, Color.WHITE)
	game.vfx.burst(hp_pos, body_col, 16 if heavy else 7, 7.0 if heavy else 4.5, 0.1, 0.45)
	if heavy:
		game.vfx.ring(foe.position, body_col, 0.3, 3.4, 0.35)
		if int(game.quality) > 0:
			game.vfx.burst(hp_pos, Color.WHITE, 5, 5.0, 0.07, 0.3)
	game.hs = maxf(game.hs, float(atk["hs"]))
	game.shake = maxf(game.shake, float(atk["sh"]) * game.shake_amt)
	if heavy:
		game.audio.play("hitH")
	else:
		game.audio.play("hitL")


func anim(dt: float, tnow: float) -> void:
	var sp := Vector2(v.x, v.z).length()
	ph += dt * sp * 2.4
	var w := minf(1.0, sp / 4.5)
	var la := sin(ph) * 0.9 * w
	var lean := 0.0
	var sq := 1.0
	var tw := sin(ph) * 0.08 * w
	if st == "free" and sp < 0.5:
		sq = 1.0 + sin(tnow * 3.0 + float(idx)) * 0.015
	var E := [0.0, 0.0]
	var U := [0.0, 0.0]
	if st == "atk" and atk != null:
		var kind := String(atk["kind"])
		var W: float = float(atk["w"])
		var A: float = float(atk["a"])
		var R: float = float(atk["r"])
		var u := t
		if kind == "dash":
			lean = 0.8
			sq = 1.08
			E[0] = 1.2
			E[1] = 1.2
			U[0] = 0.0
			U[1] = 0.0
		elif kind == "upper":
			if u < W:
				var e := u / maxf(W, 0.001)
				lean = -0.35 * e
				sq = 1.0 - 0.18 * e
				E[0] = -0.4 * e
				E[1] = -0.4 * e
			elif u < W + A:
				lean = -0.55
				sq = 1.12
				E[0] = 0.5
				E[1] = 0.5
				U[0] = 1.2
				U[1] = 1.2
			else:
				var e4u := (u - W - A) / maxf(R, 0.001)
				lean = 0.2 * (1.0 - e4u)
				sq = 1.0
				E[0] = 0.6 * (1.0 - e4u)
				E[1] = 0.6 * (1.0 - e4u)
				U[0] = 0.4 * (1.0 - e4u)
				U[1] = 0.4 * (1.0 - e4u)
		elif kind == "spin":
			lean = 0.15
			sq = 1.0
			E[0] = 1.0
			E[1] = 1.0
			U[0] = 0.1
			U[1] = 0.1
		else:
			var hv: bool = bool(atk["big"])
			var rc := 1.7 if hv else 1.4
			var hu := 0.9 if hv else 0.25
			var ex := 0.0
			var uy := 0.0
			if u < W:
				var e := u / W
				ex = -0.5 * e
				uy = hu * e
				lean = -0.25 * e
			elif u < W + A:
				var e2 := (u - W) / A
				ex = -0.5 + (rc + 0.5) * e2
				uy = hu * (1.0 - e2)
				lean = 0.45
			else:
				var e3 := (u - W - A) / maxf(R, 0.001)
				ex = rc * (1.0 - e3 * 0.9)
				uy = 0.0
				lean = 0.3
			E[1] = ex
			U[1] = uy
			if hv:
				E[0] = ex
				U[0] = uy
			else:
				E[0] = -0.25
	elif st == "stun":
		lean = -0.5
		tw = sin(tnow * 40.0) * 0.06
		sq = 0.95
		E[0] = -0.3
		E[1] = -0.3
		U[0] = 0.35
		U[1] = 0.35
	elif st == "dash":
		lean = 0.7
		sq = 0.9
		E[0] = -0.5
		E[1] = -0.5
	for k in 2:
		var s := 1.0 if k == 1 else -1.0
		var arm: Node3D = arm_r if k == 1 else arm_l
		var x := clampf(float(E[k]), 0.0, 1.0)
		var sw := (la if k == 1 else -la) * 0.35
		var hv2 := atk != null and bool(atk["big"])
		arm.position = Vector3(s * (0.62 - 0.3 * x),
			0.55 + float(U[k]) + (0.2 * x if st == "atk" else 0.0),
			float(E[k]) + sw)
		arm.scale = Vector3.ONE * (1.0 + 0.45 * x * (1.0 if hv2 else 0.4))
	model.rotation.x = lean
	model.rotation.z = tw
	if st == "atk" and atk != null and String(atk["kind"]) == "spin":
		model.rotation.y = spin_a
	else:
		model.rotation.y = 0.0
	model.scale = Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq))
	model.position.y = absf(sin(ph)) * 0.06 * w
	rotation.y = ang
	var e4 := 0.8 if flash > 0.0 else 0.05
	for m in mats:
		(m as StandardMaterial3D).emission = Color(e4, e4, e4)
