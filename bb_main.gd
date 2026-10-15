extends Node3D
## Block Brawl port (from html/block-brawl-quality.html): local 1v1 block
## fighter. Menu -> select (character skins from res://skins) -> countdown -> fight -> KO
## slow-mo -> winner screen. P1: WASD + J/K/L/O/P/Space. P2: arrows + ,/./Numpad1-5/Shift.

const FighterScript = preload("res://bb_fighter.gd")
const ArenaScript = preload("res://bb_arena.gd")
const VfxScript = preload("res://bb_vfx.gd")
const AudioScript = preload("res://bb_audio.gd")
const DebugScript = preload("res://bb_debug.gd")
const AIScript = preload("res://bb_ai.gd")

const SETTINGS_PATH := "user://cubebox_settings.cfg"
const DIFF_NAMES := ["Easy", "Normal", "Hard", "Expert"]
const SHADOW_NAMES := ["Low", "Medium", "High", "Ultra"]

var SKINS: Array = ["cubecowboy"]

var cfg := [{"skin": 0}, {"skin": 0, "cpu": true, "diff": 1}]
var shadow_quality := 1
var ai = null
var _loaded_vol := 0.6
var state := "menu"
var now := 0.0
var hs := 0.0
var shake := 0.0
var ts := 1.0
var shake_amt := 0.6
var quality := 2
var show_fps := true
var show_hitboxes := false

var fighters: Array = []
var vfx = null
var audio = null
var arena = null
var debug = null
var cam: Camera3D
var sun: DirectionalLight3D
var cp := Vector3(24, 24, 24)
var look := Vector3.ZERO
var orbit := 0.0
var zD := 27.0
var av := Vector3.ZERO
var cdT := 0.0
var lastN := 0
var koT := 0.0
var winner := 0
var prev := "play"
var from := "menu"
var fight_t := 0.0

var hud: Control
var hp_bars: Array = []
var cd_l: Array = []
var cd_r: Array = []
const CD_COLS := [Color(1.0, 0.85, 0.2), Color(1.0, 0.5, 0.15), Color(0.75, 0.4, 1.0)]
const CD_ORDER := ["S1", "S2", "S3"]
var cd: Label
var fps: Label
var screens := {}
var sel_panels := []
var win_label: Label
var bullets: Array = []
var clouds: Array = []
var _bullet_mesh: BoxMesh
const BULLET_R := 0.75
var _tracer_pool: Array = []
var _cloud_mesh: SphereMesh = null
var _cloud_mat: StandardMaterial3D = null
var _last_cd_l := [-1.0, -1.0, -1.0]
var _last_cd_r := [-1.0, -1.0, -1.0]


func _scan_skins() -> Array:
	var out: Array = []
	var d := DirAccess.open("res://skins")
	if d != null:
		for f in d.get_files():
			if f.ends_with(".glb") or f.ends_with(".gltf") or f.ends_with(".tscn"):
				out.append(f.get_basename())
	out.sort()
	if out.is_empty():
		out.append("cubecowboy")
	return out


func _skin_key(i: int) -> String:
	return str(SKINS[int(cfg[i]["skin"]) % SKINS.size()])


func _skin_pretty(sname: String) -> String:
	match sname:
		"cubecowboy":
			return "Cowboy"
		"cubeknight":
			return "Knight"
		_:
			return sname.capitalize().replace("_", " ")


func _skin_col(sname: String) -> Color:
	match sname:
		"cubecowboy":
			return Color(0.86, 0.22, 0.16)
		"cubeknight":
			return Color(0.55, 0.62, 0.72)
		"ninja":
			return Color(0.25, 0.25, 0.38)
		_:
			return Color(0.23, 0.51, 0.96)


func _ready() -> void:
	SKINS = _scan_skins()
	if int(cfg[1].get("skin", 0)) >= SKINS.size():
		cfg[1]["skin"] = 0
	_load_settings()
	_bullet_mesh = BoxMesh.new()
	_bullet_mesh.size = Vector3.ONE
	# Crash fix: never leave a mesh with a null base material (Intel GLES3
	# null deref). Bullets always set material_override, this is belt only.
	var _bm := StandardMaterial3D.new()
	_bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bullet_mesh.material = _bm
	_build_env()
	arena = ArenaScript.new()
	add_child(arena)
	vfx = VfxScript.new()
	add_child(vfx)
	audio = AudioScript.new()
	add_child(audio)
	audio.vol = _loaded_vol
	debug = DebugScript.new()
	add_child(debug)
	arena.build(vfx)
	_make_fighters()
	_build_ui()
	to_menu()
	# Heavy rendering changes (MSAA framebuffer realloc + shadow atlas
	# realloc) crash Intel UHD / old Windows drivers when done inside
	# _ready. Defer until after the first frame so the viewport exists.
	call_deferred("_apply_startup_rendering")


func _apply_startup_rendering() -> void:
	apply_quality()
	apply_shadows()


func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.95, 0.75, 0.58)
	psm.sky_horizon_color = Color(1.0, 0.91, 0.82)
	psm.ground_bottom_color = Color(0.29, 0.45, 0.22)
	psm.ground_horizon_color = Color(0.85, 0.76, 0.66)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.set("tone_mapper", 3) # ACES
	env.set("fog_enabled", true)
	env.set("fog_light_color", Color(0.95, 0.86, 0.75))
	env.set("fog_depth_begin", 50.0)
	env.set("fog_depth_end", 100.0)
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.rotation = Vector3(-0.9, 0.6, 0)
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.62, 0.82, 1.0)
	rim.light_energy = 0.45
	rim.shadow_enabled = false
	rim.rotation = Vector3(-0.4, -2.4, 0)
	add_child(rim)
	cam = Camera3D.new()
	cam.fov = 28.0
	add_child(cam)
	cam.current = true
	cam.position = cp


func _make_fighters() -> void:
	fighters.clear()
	for i in 2:
		var f = FighterScript.new()
		f.idx = i
		f.game = self
		add_child(f)
		fighters.append(f)
	fighters[0].foe = fighters[1]
	fighters[1].foe = fighters[0]
	# Ninja mapping: J = light attack (L slot / katana string),
	# K = heavy attack (H slot), L = kunai throw (S2), P = smoke bomb (S3).
	# S1 sits on O so every slot stays reachable with no duplicate keys.
	fighters[0].keys = {"up": [KEY_W], "down": [KEY_S], "left": [KEY_A], "right": [KEY_D],
		"L": [KEY_J], "H": [KEY_K], "D": [KEY_SPACE],
		"S1": [KEY_O], "S2": [KEY_L], "S3": [KEY_P]}
	fighters[1].keys = {"up": [KEY_UP], "down": [KEY_DOWN], "left": [KEY_LEFT], "right": [KEY_RIGHT],
		"L": [KEY_KP_1, KEY_COMMA], "H": [KEY_KP_2, KEY_PERIOD], "D": [KEY_SHIFT, KEY_SLASH],
		"S1": [KEY_KP_3], "S2": [KEY_KP_4], "S3": [KEY_KP_5]}
	if ai == null:
		ai = AIScript.new()
		add_child(ai)
		ai.setup(self, fighters[1], fighters[0], int(cfg[1].get("diff", 1)))
	_apply_cpu_flag()
	_pv()


func _pv() -> void:
	_setup_fighters()
	for f in fighters:
		f.v = Vector3.ZERO


func _apply_cpu_flag() -> void:
	var cpu := bool(cfg[1].get("cpu", false))
	fighters[1].ai_enabled = cpu
	if ai != null:
		ai.set_difficulty(int(cfg[1].get("diff", 1)))
		ai.reset_ai()


func _setup_fighters() -> void:
	for i in 2:
		fighters[i].setup_skin(_skin_key(i))


func start_match() -> void:
	_setup_fighters()
	_apply_cpu_flag()
	fighters[0].reset_match(Vector3(-2.0, 0, 2.0), atan2(4.0, -4.0))
	fighters[1].reset_match(Vector3(2.0, 0, -2.0), atan2(-4.0, 4.0))
	vfx.clear_all()
	_clear_bullets()
	_clear_clouds()
	ts = 1.0
	hs = 0.0
	shake = 0.0
	state = "count"
	cdT = 3.2
	lastN = 0
	show_screen(null)


func damage_props(pos: Vector3, radius: float, dmg: float) -> int:
	if arena == null:
		return 0
	return arena.damage_props(pos, radius, dmg)


func ko(f) -> void:
	if String(f.st) == "ko":
		return
	f.st = "ko"
	f.hp = 0.0
	f.visible = false
	f.clear_stuck()
	var p: Vector3 = Vector3(f.position.x, maxf(0.6, f.position.y), f.position.z)
	vfx.burst(p, f.body_col, 34, 8.0, 0.2, 0.9)
	vfx.burst(p, Color.WHITE, 8, 5.0, 0.1, 0.5)
	vfx.flash(p, 1.4, f.body_col)
	audio.play("ko")
	shake = maxf(shake, 0.45 * shake_amt)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var e := event as InputEventKey
		if e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
			toggle_pause()
		if e.pressed and not e.echo and e.keycode == KEY_F1:
			show_hitboxes = not show_hitboxes
			_sync_hitbox_checkbox()
		if e.pressed and not e.echo and e.keycode == KEY_F11:
			toggle_fullscreen()


func toggle_pause() -> void:
	if state == "play" or state == "count":
		prev = state
		state = "pause"
		show_screen("pause")
	elif state == "pause":
		state = prev
		show_screen(null)


func _physics_process(dt: float) -> void:
	if state == "pause" or state == "settings":
		return
	now += dt
	var sd := dt
	if hs > 0.0:
		hs -= dt
		sd = dt * 0.05
	else:
		sd = dt * ts
	vfx.dt_scale = sd / maxf(dt, 0.00001)
	if state == "count" or state == "play" or state == "ko" or state == "over":
		if state == "count":
			cdT -= dt
			var n := int(ceil(cdT))
			if cdT > 0.0:
				cd.text = str(n)
				if n != lastN:
					lastN = n
					audio.play("beep_lo")
			elif cdT > -0.6:
				cd.text = "FIGHT!"
			if cdT <= 0.0 and state == "count":
				state = "play"
				audio.play("beep_hi")
		else:
			cdT -= dt
			if cdT < -0.6:
				cd.text = ""
		var a = fighters[0]
		var b = fighters[1]
		if ai != null:
			ai.update(sd, state == "play")
		a.upd(sd, state == "play")
		b.upd(sd, state == "play")
		_upd_bullets(sd)
		_upd_clouds(sd)
		_upd_stuck(sd, state == "play")
		# Cached state strings: String(st) allocates, and the old code did
		# it 4x per tick just for the push-apart check.
		var ast: String = a.st
		var bst: String = b.st
		if ast != "dash" and bst != "dash" and ast != "ko" and bst != "ko":
			var dx: float = b.position.x - a.position.x
			var dz: float = b.position.z - a.position.z
			var d: float = Vector2(dx, dz).length()
			if d < 0.9 and d > 0.001:
				var pu := (0.9 - d) * 0.5
				a.position.x -= dx / d * pu
				a.position.z -= dz / d * pu
				b.position.x += dx / d * pu
				b.position.z += dz / d * pu
		if state == "play" and (float(a.hp) <= 0.0 or float(b.hp) <= 0.0):
			if float(a.hp) <= 0.0:
				ko(a)
			if float(b.hp) <= 0.0:
				ko(b)
			state = "ko"
			koT = 0.0
			ts = 0.3
			if float(a.hp) <= 0.0 and float(b.hp) <= 0.0:
				winner = 0 if float(a.dmg) < float(b.dmg) else 1
			else:
				winner = 1 if float(a.hp) <= 0.0 else 0
		if state == "ko":
			koT += dt
			if koT > 1.1:
				state = "over"
				ts = 1.0
				win_label.text = _skin_pretty(_skin_key(winner)) + " wins!"
				win_label.add_theme_color_override("font_color", _skin_col(_skin_key(winner)))
				audio.play("win")
				show_screen("over")
		a.anim(sd, now)
		b.anim(sd, now)
	else:
		for f in fighters:
			f.t += dt
			f.anim(dt, now)


func _process(dt: float) -> void:
	_cam_upd(dt)
	_upd_hp_bars()
	_upd_debug()
	if fighters.size() == 2:
		var a = fighters[0]
		var b = fighters[1]
		for j in 3:
			var n: String = CD_ORDER[j]
			var fl: float = 1.0 - clampf(float(a.cd[n]) / float(a.cd_max[n]), 0.0, 1.0)
			if absf(fl - _last_cd_l[j]) > 0.002:
				_last_cd_l[j] = fl
				(cd_l[j] as ColorRect).anchor_right = fl
			var fr: float = 1.0 - clampf(float(b.cd[n]) / float(b.cd_max[n]), 0.0, 1.0)
			if absf(fr - _last_cd_r[j]) > 0.002:
				_last_cd_r[j] = fr
				(cd_r[j] as ColorRect).anchor_left = 1.0 - fr
	if show_fps:
		fight_t += dt
		if fight_t >= 0.5:
			fight_t = 0.0
			fps.text = str(Engine.get_frames_per_second()) + " FPS"


func _cam_upd(dt: float) -> void:
	var in_fight := state == "play" or state == "count" or state == "ko" or state == "pause" or state == "over"
	var tg := Vector3(0, 0.5, 0)
	var D := 30.0
	var dir := Vector3.ZERO
	if in_fight and fighters.size() == 2:
		var p0: Vector3 = fighters[0].position
		var p1: Vector3 = fighters[1].position
		var v0: Vector3 = fighters[0].v
		var v1: Vector3 = fighters[1].v
		var sep := Vector2(p0.x - p1.x, p0.z - p1.z).length()
		av = av.lerp((v0 + v1) * 0.5, 1.0 - exp(-3.0 * dt))
		tg = Vector3((p0.x + p1.x) * 0.5, 0.5, (p0.z + p1.z) * 0.5) + av * 0.35
		var vp := get_viewport().get_visible_rect().size
		D = minf(30.0, 20.0 + sep * 0.9) * maxf(1.0, 1.3 / maxf(vp.x / maxf(vp.y, 1.0), 0.1))
		dir = Vector3(1, 0.95, 1).normalized()
	else:
		orbit += dt * 0.12
		av = av.lerp(Vector3.ZERO, 1.0 - exp(-3.0 * dt))
		D = 24.0 if state == "select" else 30.0
		dir = Vector3(cos(orbit + 0.8), 0.9, sin(orbit + 0.8)).normalized()
	zD = lerpf(zD, D, 1.0 - exp(-3.0 * dt))
	var goal := tg + dir * zD
	cp = cp.lerp(goal, 1.0 - exp(-4.0 * dt))
	look = look.lerp(tg, 1.0 - exp(-5.0 * dt))
	cam.position = cp
	if shake > 0.0:
		cam.position.x += randf_range(-0.5, 0.5) * shake
		cam.position.y += randf_range(-0.5, 0.5) * shake
		shake = maxf(0.0, shake - dt * 1.2)
	cam.look_at(look)


# ---------- PROJECTILES ----------
# Real travelling bullets: spawned at the muzzle with a fixed velocity,
# integrated every physics frame, damaged only on physical intersection.

# Two shared bullet materials (small/big use fixed colors) instead of one
# new material per shot: avoids shader recompiles and per-frame allocations
# during fan-fire (6 shots per S1).
var _bullet_mats := {}


func _bullet_mat(big: bool, bc: Color) -> StandardMaterial3D:
	var key := ("big" if big else "small") + bc.to_html()
	if not _bullet_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = bc
		m.emission_enabled = true
		m.emission = bc
		_bullet_mats[key] = m
	return _bullet_mats[key]


func _obtain_tracer() -> MeshInstance3D:
	if _tracer_pool.is_empty():
		var bx := MeshInstance3D.new()
		bx.mesh = _bullet_mesh
		bx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bx)
		return bx
	var bx2 := _tracer_pool.pop_back() as MeshInstance3D
	bx2.visible = true
	return bx2


func _release_tracer(mi: MeshInstance3D) -> void:
	mi.visible = false
	mi.position = Vector3.ZERO
	if _tracer_pool.size() < 32:
		_tracer_pool.append(mi)
	else:
		mi.queue_free()


func fire_bullet(owner: Node3D, mpos: Vector3, dir: Vector3, cfg: Dictionary) -> void:
	# Ninja kunai are full procedural kunai scenes (same design as the held
	# props): tip at origin along +Z, aimed along the velocity at spawn and
	# held straight (tip first, no spin) for the whole flight, then
	# reparented whole into the victim on impact. Other bullets are pooled
	# box tracers (shared mesh, cached materials, reused nodes).
	var mi: Node3D = null
	var sp: float = float(cfg.get("speed", 22.0))
	var bc: Color = cfg.get("col", Color(1.0, 0.8, 0.35))
	var is_kunai := bool(cfg.get("kunai", false))
	if is_kunai:
		mi = FighterScript.make_kunai_node()
		mi.scale = Vector3.ONE * FighterScript.NINJA_KUNAI_THROWN_SCALE
		mi.rotation.y = atan2(dir.x, dir.z)
		for ch in (mi as Node).get_children():
			if ch is GeometryInstance3D:
				(ch as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	else:
		var bx := _obtain_tracer()
		bx.mesh = _bullet_mesh
		bx.scale = Vector3(0.09, 0.09, 0.28 + sp * 0.012)
		bx.rotation.y = atan2(dir.x, dir.z)
		bx.material_override = _bullet_mat(bool(cfg.get("big", false)), bc)
		mi = bx
	mi.position = mpos
	bullets.append({"node": mi, "p": mpos, "v": dir.normalized() * sp,
		"life": float(cfg.get("life", 0.45)), "dmg": float(cfg.get("dmg", 4.0)),
		"kb": float(cfg.get("kb", 2.5)), "vy": float(cfg.get("vy", 2.0)),
		"stun": float(cfg.get("stun", 0.18)), "big": bool(cfg.get("big", false)),
		"kunai": is_kunai,
		"owner": owner, "col": bc, "trail": 0.0})


func _seg_point(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom < 0.000001:
		return a.distance_to(p)
	var u := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return (a + ab * u).distance_to(p)


func _upd_bullets(dt: float) -> void:
	if bullets.is_empty():
		return
	for i in range(bullets.size() - 1, -1, -1):
		var b: Dictionary = bullets[i]
		b["life"] = float(b["life"]) - dt
		var p: Vector3 = b["p"]
		var v: Vector3 = b["v"]
		var np := p + v * dt
		if float(b["life"]) <= 0.0 or absf(np.x) > 6.5 or absf(np.z) > 6.5 or np.y < -0.5 or np.y > 8.0:
			_kill_bullet(i, false)
			continue
		var hit := false
		for f in fighters:
			if f == b["owner"] or String(f.st) == "ko" or not (f as Node3D).visible:
				continue
			var chest: Vector3 = (f as Node3D).position + Vector3(0, 0.9, 0)
			if _seg_point(p, np, chest) < BULLET_R:
				_bullet_hit(i, b, f)
				hit = true
				break
		if hit:
			continue
		b["p"] = np
		(b["node"] as Node3D).position = np
		# Kunai keep their spawn aim (rotation.y points +Z along the flight
		# direction) with no roll, so they fly perfectly straight, tip first.
		b["trail"] = float(b["trail"]) - dt
		if float(b["trail"]) <= 0.0:
			# HTML kunai speed trail: 0xbfe3ff spark, life 0.18, every frame.
			b["trail"] = 0.02 if bool(b.get("kunai", false)) else 0.07
			if bool(b.get("kunai", false)):
				vfx.emit(np, Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)), Color(0.75, 0.89, 1.0), 0.05, 0.18, 0.0)
			else:
				vfx.burst(np, b["col"], 1, 0.3, 0.05, 0.2)


func _bullet_hit(i: int, b: Dictionary, f) -> void:
	var big := bool(b["big"])
	var own = b["owner"]
	if f.counter_open():
		f._do_counter(own)
		_kill_bullet(i, false)
		return
	if float(f.inv) > 0.0:
		_kill_bullet(i, false)
		vfx.burst((f as Node3D).position + Vector3(0, 0.9, 0), Color.WHITE, 4, 3.0, 0.07, 0.3)
		return
	# Ninja kunai sticks into the victim and detonates after a fuse
	# (html/ninjasetup.html) instead of dealing damage on impact.
	if bool(b.get("kunai", false)):
		_stick_kunai(i, f)
		return
	var dmg: float = float(b["dmg"])
	f.hp = maxf(0.0, float(f.hp) - dmg)
	f.dmg += dmg
	var kk := float(b["kb"]) * 0.55 / float(f.mass)
	var flat: Vector3 = b["v"]
	flat.y = 0.0
	flat = flat.normalized() if flat.length() > 0.01 else Vector3(0, 0, 1)
	f.v = Vector3(flat.x * kk, 0, flat.z * kk)
	f.vy = float(b["vy"])
	f.st = "stun"
	f.t = 0.0
	f.stun = float(b["stun"])
	f.flash = 0.14
	f.atk = null
	var hp_pos: Vector3 = (f as Node3D).position + Vector3(0, 0.9, 0)
	vfx.damage_number((f as Node3D).position + Vector3(0, 2.0, 0), str(int(dmg)),
		Color.WHITE if big else Color(0.85, 0.75, 1.0), big)
	vfx.flash(hp_pos, 0.9 if big else 0.55, Color.WHITE)
	vfx.burst(hp_pos, own.body_col, 16 if big else 7, 7.0 if big else 4.5, 0.1, 0.45)
	hs = maxf(hs, 0.1 if big else 0.03)
	shake = maxf(shake, (0.35 if big else 0.12) * shake_amt)
	audio.play("hitH" if big else "hitL")
	_kill_bullet(i, true)


func _stick_kunai(i: int, f) -> void:
	# HTML kunai hit: the live projectile stops flying and embeds in the
	# target (kept as a child so it rides movement until detonation frees
	# it), 10 sparks (white/gold), shake 0.15, fuse 0.9 (chain 0.5).
	var b: Dictionary = bullets[i]
	var node := b["node"] as Node3D
	var at: Vector3 = b["p"]
	bullets.remove_at(i)
	f.attach_stuck(node)
	vfx.burst(at, b["col"], 4, 3.0, 0.07, 0.3)
	var chest: Vector3 = (f as Node3D).position + Vector3(0, 0.9, 0)
	for s in 10:
		var sc := Color.WHITE if s % 2 == 0 else Color(1.0, 0.83, 0.48)
		vfx.emit(chest, Vector3(randf_range(-2.5, 2.5), randf_range(1.0, 5.0), randf_range(-2.5, 2.5)), sc, 0.06, randf_range(0.3, 0.5), 10.0)
	audio.play("hitL")
	shake = maxf(shake, 0.15 * shake_amt)


# Sticky-kunai fuses: accelerating red blink, then detonation. Nearby
# stuck bombs chain with a short fuse, like the reference.
func _upd_stuck(dt: float, play: bool) -> void:
	if not play:
		return
	if fighters.size() == 2 and (fighters[0] as Node).get("stuck").is_empty() and (fighters[1] as Node).get("stuck").is_empty():
		return
	for f in fighters:
		if String(f.st) == "ko" or not (f as Node3D).visible:
			f.clear_stuck()
			continue
		for i in range(f.stuck.size() - 1, -1, -1):
			var s: Dictionary = f.stuck[i]
			s["t"] = float(s["t"]) + dt
			var fuse := maxf(float(s["fuse"]), 0.01)
			f.flash = maxf(float(f.flash), 0.05)
			if float(s["t"]) >= fuse:
				# The expired kunai's own embedded mesh goes with the blast
				# too (it is already out of `stuck` when _detonate frees
				# the rest), so no visible kunai survives the detonation.
				f.stuck.remove_at(i)
				var expired: Node3D = s.get("node", null)
				if expired != null and is_instance_valid(expired):
					expired.queue_free()
				_detonate(f)


func _detonate(victim) -> void:
	# HTML explode(): hot flash (3.4, 0.35) + white core (1.8, 0.16),
	# orange ring, light pop (energy 3, range 12), 16 debris, 30 sparks,
	# scorch (r 1.5, life 3), shake 0.5. Smoke thinned for readability
	# (7 billowing puffs instead of 14, 5 dust instead of 10); damage,
	# radius, flashes, ring, debris, sparks and scorch are unchanged.
	# Every kunai stuck in anyone caught by the blast is consumed by it,
	# so no embedded kunai survive the detonation visibly.
	var at: Vector3 = (victim as Node3D).position
	var bp := Vector3(at.x, maxf(at.y, 0.0) + 0.6, at.z)
	# 1:1 port of HTML explode(): flash sphere (size 3.4, 0.35 s, hot
	# 0xfff2b0 -> cool 0xff4a12) + white-hot core (1.8, 0.16 s), orange
	# shockwave ring (0.45 s), light pop (0xff9a4d, 3, range 12, 0.25 s),
	# 16 debris, 30 sparks, scorch disc (r 1.5, 3 s), shake 0.5.
	# Smoke only is thinned (~50% fewer puffs, lower opacity); damage,
	# radius and all signature effects are unchanged.
	# (MultiMesh particles can't spin like the HTML debris; sizes, speeds,
	# gravity and lifetimes match.)
	vfx.blast_flash(bp, 3.4, Color(1.0, 0.95, 0.69), Color(1.0, 0.29, 0.07), 0.35, false)
	vfx.blast_flash(bp, 1.8, Color.WHITE, Color.WHITE, 0.16, true)
	vfx.light_pop(bp, Color(1.0, 0.6, 0.3), 3.0, 0.25)
	vfx.ring(Vector3(at.x, 0.05, at.z), Color(1.0, 0.54, 0.24), 0.5, 5.5, 0.45, 0.8, true)
	for j in 16:
		var da := randf() * TAU
		var dsp := 3.0 + randf() * 5.0
		vfx.emit(bp, Vector3(cos(da) * dsp, 3.0 + randf() * 5.0, sin(da) * dsp),
			Color(1.0, 0.54, 0.24) if randf() < 0.5 else Color(1.0, 0.82, 0.48),
			0.1 + randf() * 0.15, 0.7, 20.0)
	for k in 7:
		var sa := randf() * TAU
		var ssp := 0.8 + randf() * 2.2
		vfx.puff(bp + Vector3(randf_range(-0.25, 0.25), randf() * 0.4, randf_range(-0.25, 0.25)),
			Color(0.42, 0.23, 0.11), 0.5 + randf() * 0.4, 1.2 + randf() * 0.7, 0.0,
			2.2, 0.6, Color(0.17, 0.17, 0.2),
			Vector3(cos(sa) * ssp, 1.5 + randf() * 2.5, sin(sa) * ssp))
	for n in 5:
		var na := (float(n) / 5.0) * TAU + randf() * 0.4
		var nsp := 4.0 + randf() * 3.0
		vfx.puff(Vector3(at.x, 0.15, at.z), Color(0.72, 0.65, 0.54),
			0.3 + randf() * 0.25, 0.7 + randf() * 0.3, 0.0,
			2.5, 0.5, Color(0.43, 0.42, 0.46),
			Vector3(cos(na) * nsp, 0.3, sin(na) * nsp))
	for q in 30:
		var qa := randf() * TAU
		var qsp := 6.0 + randf() * 6.0
		vfx.emit(bp, Vector3(cos(qa) * qsp, 2.0 + randf() * 7.0, sin(qa) * qsp),
			Color(1.0, 0.76, 0.3) if randf() < 0.5 else Color(1.0, 0.48, 0.16),
			0.06 + randf() * 0.07, 0.4 + randf() * 0.5, 10.0)
	vfx.scorch(Vector3(at.x, 0.0, at.z), 3.0, 1.5)
	audio.play("boom")
	shake = maxf(shake, 0.5 * shake_amt)
	hs = maxf(hs, 0.09)
	for s in victim.stuck:
		var sn: Node3D = s.get("node", null)
		if sn != null and is_instance_valid(sn):
			sn.queue_free()
	victim.stuck.clear()
	for f in fighters:
		if String(f.st) == "ko" or not (f as Node3D).visible:
			continue
		var dx: float = (f as Node3D).position.x - at.x
		var dz: float = (f as Node3D).position.z - at.z
		var d := Vector2(dx, dz).length()
		if d > FighterScript.BLAST_R:
			continue
		if f != victim and float(f.inv) > 0.0:
			vfx.burst((f as Node3D).position + Vector3(0, 0.9, 0), Color.WHITE, 4, 3.0, 0.07, 0.3)
			continue
		f.hp = maxf(0.0, float(f.hp) - FighterScript.BLAST_DMG)
		f.dmg += FighterScript.BLAST_DMG
		vfx.damage_number((f as Node3D).position + Vector3(0, 2.0, 0), str(int(FighterScript.BLAST_DMG)), Color.WHITE, true)
		var kk := 10.0 * 0.55 / float(f.mass)
		var dir := Vector3(dx / maxf(d, 0.01), 0, dz / maxf(d, 0.01))
		f.v = Vector3(dir.x * kk, 0, dir.z * kk)
		f.vy = 6.0
		f.st = "stun"
		f.t = 0.0
		f.stun = 0.4
		f.flash = 0.14
		f.atk = null
		vfx.flash((f as Node3D).position + Vector3(0, 0.9, 0), 0.9, Color.WHITE)
		# The blast consumes every kunai stuck in anyone it catches, so no
		# embedded kunai stay visible after the detonation. Stickers outside
		# the blast keep their own fuses and still go off in their own spot.
		for s in f.stuck:
			var sn2: Node3D = s.get("node", null)
			if sn2 != null and is_instance_valid(sn2):
				sn2.queue_free()
		f.stuck.clear()


func _kill_bullet(i: int, impacted: bool) -> void:
	var b: Dictionary = bullets[i]
	if impacted:
		vfx.burst(b["p"], b["col"], 6, 3.0, 0.07, 0.3)
	var nd := b["node"] as Node3D
	if bool(b.get("kunai", false)):
		nd.queue_free()
	else:
		_release_tracer(nd as MeshInstance3D)
	bullets.remove_at(i)


func _clear_bullets() -> void:
	for b in bullets:
		var nd := (b as Dictionary)["node"] as Node3D
		if bool((b as Dictionary).get("kunai", false)):
			nd.queue_free()
		else:
			_release_tracer(nd as MeshInstance3D)
	bullets.clear()


# ---------- SMOKE CLOUDS (ninja S3) ----------
# Lingering tick-damage zones from html/ninjasetup.html: they chip HP of
# anyone but the owner standing inside, with no stun-lock.

func deploy_cloud(owner: Node3D, pos: Vector3, radius: float, life: float,
		tick: float, dmg: float, col: Color) -> void:
	# HTML releaseBomb/burst: bomb arcs hand->landing over 0.55 s with peak
	# 6*u*(1-u), spinning, trailing gray puffs + sparks; bursts early if it
	# touches a foe, else on landing.
	var from := (owner as Node3D).position + Vector3(0, 0.8, 0)
	clouds.append({"owner": owner, "from": from, "p": pos, "r": radius,
		"life": life, "delay": 0.55, "landed": false, "bomb": null,
		"tick": tick, "tick_t": 0.3, "ticks": 0, "puff_t": 0.0, "dmg": dmg, "col": col})


func _cloud_bomb() -> MeshInstance3D:
	# Procedural flying bomb: dark sphere like the held prop. Mesh +
	# material shared across all throws (was rebuilt per bomb).
	if _cloud_mesh == null:
		_cloud_mesh = SphereMesh.new()
		_cloud_mesh.radius = 0.17
		_cloud_mesh.height = 0.34
	if _cloud_mat == null:
		_cloud_mat = StandardMaterial3D.new()
		_cloud_mat.albedo_color = Color(0.10, 0.06, 0.19)
		_cloud_mat.roughness = 0.5
		_cloud_mat.emission_enabled = true
		_cloud_mat.emission = Color(0.33, 0.33, 0.38)
		_cloud_mat.emission_energy_multiplier = 0.6
	var bm := MeshInstance3D.new()
	bm.mesh = _cloud_mesh
	bm.material_override = _cloud_mat
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return bm


func _upd_clouds(dt: float) -> void:
	if clouds.is_empty():
		return
	for i in range(clouds.size() - 1, -1, -1):
		var c: Dictionary = clouds[i]
		var p: Vector3 = c["p"]
		var r: float = c["r"]
		if not bool(c["landed"]):
			c["delay"] = float(c["delay"]) - dt
			var u := clampf(1.0 - float(c["delay"]) / 0.55, 0.0, 1.0)
			var bp: Vector3 = (c["from"] as Vector3).lerp(p, u) + Vector3(0, 6.0 * u * (1.0 - u), 0)
			# Visible spinning bomb mesh along the arc (freed at burst).
			if c["bomb"] == null or not is_instance_valid(c["bomb"]):
				c["bomb"] = _cloud_bomb()
				add_child(c["bomb"])
			(c["bomb"] as Node3D).position = bp
			(c["bomb"] as Node3D).rotation.x += 14.0 * dt
			(c["bomb"] as Node3D).rotation.z += 9.0 * dt
			vfx.puff(bp, Color(0.71, 0.71, 0.74), 0.14, 0.5, 0.3)
			if randf() < 0.6:
				vfx.emit(bp, Vector3(0, 0.5, 0), Color(0.78, 0.78, 0.82), 0.05, 0.25, 0.0)
			# Reference: the flying bomb bursts early if it touches a foe.
			var early := false
			for f in fighters:
				if f == c["owner"] or String(f.st) == "ko" or not (f as Node3D).visible:
					continue
				var fdx: float = (f as Node3D).position.x - bp.x
				var fdz: float = (f as Node3D).position.z - bp.z
				if Vector2(fdx, fdz).length() < 1.2 and bp.y < 2.0:
					c["p"] = Vector3((f as Node3D).position.x, 0, (f as Node3D).position.z)
					p = c["p"]
					early = true
					break
			if float(c["delay"]) <= 0.0 or early:
				c["landed"] = true
				if c["bomb"] != null and is_instance_valid(c["bomb"]):
					(c["bomb"] as Node).queue_free()
				c["bomb"] = null
			# HTML burst(): white flash (size 2.6), gray ring to 9,
			# 22 puffs, 20 sparks, shake 0.3, then disc/edge/dome cloud.
			# Visual-density reduction (smoke only): the initial burst uses
			# ~45% fewer smoke puffs (16 instead of 30) with slightly
			# smaller, more transparent puffs. Flash, ground ring, sparks,
			# damage radius, ticks, lifetime and cooldown are unchanged.
			vfx.flash(p + Vector3(0, 0.5, 0), 1.3, Color.WHITE)
			# Subtle landing ring only (no stacked grey discs).
			vfx.ring(Vector3(p.x, 0.05, p.z), Color(0.78, 0.78, 0.82), 0.3, 9.0, 0.55, 0.2)
			for j in 16:
				var a := randf() * TAU
				var sp := randf_range(2.0, 5.0)
				vfx.puff(p + Vector3(0, 0.3, 0), Color(0.71, 0.71, 0.74), randf_range(0.45, 0.7), randf_range(1.0, 1.6), 1.0, 0.0, 0.55)
				vfx.emit(p + Vector3(0, 0.3, 0), Vector3(cos(a) * sp, randf_range(0.5, 1.5), sin(a) * sp), Color(0.71, 0.71, 0.74), 0.1, 0.8, 2.0)
			for k in 26:
				var a2 := randf() * TAU
				var sp2 := randf_range(4.0, 8.0)
				vfx.emit(p + Vector3(0, 0.5, 0), Vector3(cos(a2) * sp2, randf_range(2.0, 7.0), sin(a2) * sp2), Color(0.83, 0.83, 0.85), 0.07, 0.5, 10.0)
				audio.play("hitH")
				shake = maxf(shake, 0.3 * shake_amt)
			continue
		c["life"] = float(c["life"]) - dt
		if float(c["life"]) <= 0.0:
			clouds.remove_at(i)
			continue
		c["puff_t"] = float(c["puff_t"]) - dt
		if float(c["puff_t"]) <= 0.0:
			# Throttled ~45% vs the old 0.07 s cadence so the lingering
			# cloud stays readable: fewer, slightly smaller and more
			# transparent puffs. Lifetime, radius, tick damage and
			# cooldown are unchanged.
			c["puff_t"] = 0.13
			var a := randf() * TAU
			var rr := sqrt(randf()) * r * 0.95
			var fade := clampf(float(c["life"]) / 0.8, 0.0, 1.0)
			if fade <= 0.0:
				fade = 1.0
			vfx.puff(p + Vector3(cos(a) * rr, randf_range(0.1, 0.6), sin(a) * rr),
				Color(0.71, 0.71, 0.74), randf_range(0.6, 1.05), randf_range(1.6, 2.6), randf_range(0.35, 0.85), 0.0, 0.45)
			if randf() < 0.35 * fade:
				vfx.emit(p + Vector3(cos(a) * rr, 0.2, sin(a) * rr), Vector3(0, randf_range(0.8, 1.4), 0), Color(0.61, 1.0, 0.69), 0.05, 1.2, 0.0)
		c["tick_t"] = float(c["tick_t"]) - dt
		if float(c["tick_t"]) > 0.0:
			continue
		c["tick_t"] = float(c["tick"])
		c["ticks"] = int(c["ticks"]) + 1
		# Subtle tick pulse: ring only every second tick, low alpha.
		if int(c["ticks"]) % 2 == 0:
			vfx.ring(Vector3(p.x, 0.06, p.z), c["col"], 0.3, r, 0.4, 0.3)
		vfx.burst(p + Vector3(0, 0.5, 0), Color(0.61, 1.0, 0.69), 4, 2.0, 0.06, 0.4)
		for f in fighters:
			if f == c["owner"] or String(f.st) == "ko" or not (f as Node3D).visible:
				continue
			if float(f.inv) > 0.0:
				continue
			var dx: float = (f as Node3D).position.x - p.x
			var dz: float = (f as Node3D).position.z - p.z
			if Vector2(dx, dz).length() > r:
				continue
			var dmg: float = float(c["dmg"])
			f.hp = maxf(0.0, float(f.hp) - dmg)
			f.dmg += dmg
			f.flash = 0.1
			vfx.damage_number((f as Node3D).position + Vector3(0, 2.0, 0), str(int(dmg)), Color(0.61, 1.0, 0.69), false)
			vfx.burst((f as Node3D).position + Vector3(0, 0.9, 0), c["col"], 4, 2.5, 0.08, 0.3)


func _clear_clouds() -> void:
	clouds.clear()


# ---------- UI ----------

func _style(bg: Color, radius: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


func _btn(parent: Control, text: String, action: String, green: bool = false, i: int = -1, v: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 20)
	var sb := _style(Color(0.25, 0.68, 0.3) if green else Color(1.0, 0.54, 0.24))
	b.add_theme_stylebox_override("normal", sb)
	b.set_meta("action", action)
	b.set_meta("i", i)
	b.set_meta("v", v)
	b.pressed.connect(_on_action.bind(b))
	parent.add_child(b)
	return b


func _panel() -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	return vb


func _screen(sname: String) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.visible = false
	add_child(c)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(cc)
	var pc := PanelContainer.new()
	var sb := _style(Color(1.0, 0.98, 0.93, 0.93), 18)
	sb.shadow_size = 8
	pc.add_theme_stylebox_override("panel", sb)
	cc.add_child(pc)
	var vb := _panel()
	pc.add_child(vb)
	screens[sname] = {"root": c, "box": vb}
	return c


@warning_ignore("integer_division")
func _title_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0.16, 0.48, 0.21))
	l.add_theme_constant_override("outline_size", maxi(2, size / 12))
	return l


func _build_ui() -> void:
	# HUD
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	_build_hp_bars()
	_cd_pips(false)
	_cd_pips(true)
	cd = Label.new()
	cd.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd.add_theme_font_size_override("font_size", 120)
	cd.add_theme_color_override("font_color", Color.WHITE)
	cd.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	cd.add_theme_constant_override("outline_size", 10)
	cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(cd)
	fps = Label.new()
	fps.text = "-- FPS"
	fps.add_theme_font_size_override("font_size", 15)
	fps.add_theme_color_override("font_color", Color.WHITE)
	var fbg := _style(Color(0, 0, 0, 0.4), 8)
	fps.add_theme_stylebox_override("normal", fbg)
	fps.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	fps.position = Vector2(-110, -40)
	hud.add_child(fps)
	# menu
	_screen("menu")
	var mb: VBoxContainer = screens["menu"]["box"]
	mb.add_child(_title_label("BLOCK BRAWL", 96))
	_btn(mb, "Play local 1v1", "play", true)
	_btn(mb, "Open World 1 — Performance Field", "ow1")
	_btn(mb, "Open World 2 — Nature World", "ow2")
	_btn(mb, "Grass Render", "grassrender")
	_btn(mb, "Settings", "set")
	# select
	_screen("select")
	var sb2: VBoxContainer = screens["select"]["box"]
	sb2.add_child(_title_label("SELECT", 48))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	sb2.add_child(row)
	sel_panels.clear()
	for i in 2:
		var vb := _panel()
		row.add_child(vb)
		sel_panels.append(vb)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 12)
	sb2.add_child(row2)
	_btn(row2, "Start match", "start", true)
	_btn(row2, "Back", "menu")
	var hint := Label.new()
	hint.text = "P1: WASD move, J light, K heavy, L kunai/special-2, O special-1, P smoke/special-3, Space dash. P2: arrows, ,/. attacks, Numpad3/4/5 specials, Shift or / dash. Esc pauses. Cooldowns: yellow=O, orange=L, purple=P. Ninja kit: J katana string, K heavy, L kunai throw, P smoke bomb. Cowboy kit: O fan-fire (6 shots), L rifle (heavy), P horse ride. Knight kit: O shield counter, L shield bash, P sword sweep."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(560, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	sb2.add_child(hint)
	# pause
	_screen("pause")
	var pb: VBoxContainer = screens["pause"]["box"]
	pb.add_child(_title_label("Paused", 40))
	_btn(pb, "Resume", "resume", true)
	_btn(pb, "Restart", "restart")
	_btn(pb, "Settings", "set")
	_btn(pb, "Main menu", "menu")
	# over
	_screen("over")
	var ob: VBoxContainer = screens["over"]["box"]
	win_label = _title_label("", 44)
	ob.add_child(win_label)
	_btn(ob, "Rematch", "restart", true)
	_btn(ob, "Main menu", "menu")
	# settings
	_screen("settings")
	var stb: VBoxContainer = screens["settings"]["box"]
	stb.add_child(_title_label("Settings", 40))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	stb.add_child(grid)
	var sv := _slider(grid, "Sound volume", int(_loaded_vol * 100.0))
	sv.value_changed.connect(func(_v: float) -> void: audio.vol = sv.value / 100.0; _save_settings())
	var ss := _slider(grid, "Screen shake", int(shake_amt * 100.0))
	ss.value_changed.connect(func(_v: float) -> void: shake_amt = ss.value / 100.0; _save_settings())
	_opt(grid)
	_shadow_opt(grid)
	var sf := CheckBox.new()
	sf.text = "Show FPS"
	sf.button_pressed = show_fps
	var sl := Label.new()
	sl.text = "Show FPS"
	grid.add_child(sl)
	grid.add_child(sf)
	fps.visible = show_fps
	sf.toggled.connect(func(on: bool) -> void: show_fps = on; fps.visible = on; _save_settings())
	var hb_lab := Label.new()
	hb_lab.text = "Show Hitboxes (F1)"
	grid.add_child(hb_lab)
	_hitbox_box = CheckBox.new()
	_hitbox_box.text = "Show Hitboxes"
	_hitbox_box.button_pressed = show_hitboxes
	grid.add_child(_hitbox_box)
	_hitbox_box.toggled.connect(func(on: bool) -> void: show_hitboxes = on)
	var fs_lab := Label.new()
	fs_lab.text = "Fullscreen (F11)"
	grid.add_child(fs_lab)
	_fs_box = CheckBox.new()
	_fs_box.text = "Fullscreen"
	grid.add_child(_fs_box)
	_fs_box.toggled.connect(func(on: bool) -> void: _set_fullscreen(on))
	_btn(stb, "Back", "back", true)


func _hp_bar_color(frac: float) -> Color:
	if frac > 0.66:
		return Color(0.3, 0.8, 0.3)
	elif frac > 0.4:
		return Color(0.95, 0.85, 0.25)
	elif frac > 0.2:
		return Color(0.95, 0.55, 0.2)
	return Color(0.9, 0.25, 0.25)


func _build_hp_bars() -> void:
	for i in fighters.size():
		var root := Control.new()
		root.custom_minimum_size = Vector2(124, 30)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(root)
		var bg := ColorRect.new()
		bg.color = Color(0.05, 0.05, 0.08, 0.9)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bg)
		var fill := ColorRect.new()
		fill.color = Color(0.3, 0.8, 0.3)
		fill.position = Vector2(3, 3)
		fill.size = Vector2(118, 24)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(fill)
		var lab := Label.new()
		lab.set_anchors_preset(Control.PRESET_FULL_RECT)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.add_theme_font_size_override("font_size", 15)
		lab.add_theme_color_override("font_color", Color.WHITE)
		lab.add_theme_color_override("font_outline_color", Color.BLACK)
		lab.add_theme_constant_override("outline_size", 4)
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(lab)
		hp_bars.append({"root": root, "fill": fill, "lab": lab, "last_hp": -1.0, "last_frac": -1.0})


func _upd_hp_bars() -> void:
	# Position tracks the fighters every frame (cheap), but fill size/color
	# and label text only rewrite when hp actually changed (avoids per-frame
	# container relayout + string allocs at 60Hz).
	for i in fighters.size():
		var f = fighters[i]
		var hb: Dictionary = hp_bars[i]
		var root := hb["root"] as Control
		root.visible = hud.visible
		if not hud.visible:
			continue
		var wp: Vector3 = (f as Node3D).position + Vector3(0, f.top_y(), 0)
		if cam.is_position_behind(wp):
			root.visible = false
			continue
		root.position = cam.unproject_position(wp) + Vector2(-62, -34)
		var hp := clampf(float(f.hp), 0.0, 100.0)
		if absf(hp - float(hb["last_hp"])) < 0.05:
			continue
		hb["last_hp"] = hp
		var frac := hp / 100.0
		if absf(frac - float(hb["last_frac"])) > 0.001:
			hb["last_frac"] = frac
			var fill := hb["fill"] as ColorRect
			fill.size = Vector2(118.0 * frac, 24.0)
			fill.color = _hp_bar_color(frac)
		(hb["lab"] as Label).text = "%d/100" % int(ceil(hp))


var _hitbox_box: CheckBox = null
var _fs_box: CheckBox = null


func _upd_debug() -> void:
	if debug == null:
		return
	if show_hitboxes:
		debug.draw_frame(fighters, bullets, BULLET_R)
	else:
		debug.clear()


func _sync_hitbox_checkbox() -> void:
	if _hitbox_box != null and is_instance_valid(_hitbox_box):
		_hitbox_box.set_pressed_no_signal(show_hitboxes)


func toggle_fullscreen() -> void:
	_set_fullscreen(DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN)


func _set_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	if _fs_box != null and is_instance_valid(_fs_box):
		_fs_box.set_pressed_no_signal(on)


func _cd_pips(right: bool) -> void:
	for j in 3:
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.45)
		bg.custom_minimum_size = Vector2(120, 10)
		if right:
			bg.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			bg.position = Vector2(-398 + j * 128, 100)
		else:
			bg.position = Vector2(18 + j * 128, 100)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(bg)
		var fill := ColorRect.new()
		fill.color = CD_COLS[j]
		fill.set_anchors_preset(Control.PRESET_FULL_RECT)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(fill)
		if right:
			cd_r.append(fill)
		else:
			cd_l.append(fill)


func _slider(grid: GridContainer, text: String, val: int) -> HSlider:
	var l := Label.new()
	l.text = text
	grid.add_child(l)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.value = val
	s.custom_minimum_size = Vector2(160, 0)
	grid.add_child(s)
	return s


func _opt(grid: GridContainer) -> void:
	var l := Label.new()
	l.text = "Graphics"
	grid.add_child(l)
	var o := OptionButton.new()
	o.add_item("Low", 0)
	o.add_item("Medium", 1)
	o.add_item("High", 2)
	o.selected = clampi(quality, 0, 2)
	grid.add_child(o)
	o.item_selected.connect(func(idx: int) -> void: quality = idx; apply_quality(); _save_settings())


func _shadow_opt(grid: GridContainer) -> void:
	var l := Label.new()
	l.text = "Shadow Quality"
	grid.add_child(l)
	var o := OptionButton.new()
	for si in SHADOW_NAMES.size():
		o.add_item(SHADOW_NAMES[si], si)
	o.selected = clampi(shadow_quality, 0, SHADOW_NAMES.size() - 1)
	grid.add_child(o)
	o.item_selected.connect(_on_shadow_selected)


func apply_quality() -> void:
	vfx.set_cap([60, 100, 100][clampi(quality, 0, 2)])
	var sc: float = [0.85, 1.0, 1.0][clampi(quality, 0, 2)]
	get_viewport().set("scaling_3d_scale", sc)
	# MSAA is the biggest fix for jagged block edges in the Compatibility
	# renderer (it has no TAA/FSR). Capped at 2x everywhere: 4x crashes
	# some Windows drivers and most mobile GPUs when set at startup, and
	# 2x already removes nearly all edge shimmer on these blocky meshes.
	# NOTE (crash fix): assigning msaa_3d reallocates the framebuffers even
	# when the value is unchanged, which access-violates Intel UHD + old
	# Windows GL drivers. Only assign when the value actually differs.
	var want_msaa := Viewport.MSAA_DISABLED if clampi(quality, 0, 2) <= 0 else Viewport.MSAA_2X
	if get_viewport().msaa_3d != want_msaa:
		get_viewport().msaa_3d = want_msaa
	apply_shadows()


# Shadow Quality (Low/Medium/High/Ultra, Medium default). Tuned for soft,
# clean shadows on the blocky art: tight PSS range over the 10x10 arena
# (denser texels = less shimmer), blended splits, blur for soft edges,
# bias/normal-bias balanced against acne vs. detached shadows, and full
# opacity so characters stay visually grounded. Graphics Low forces shadows
# off entirely (existing performance guarantee).
# NOTE: the Compatibility renderer has no SSAO/SSIL/SDFGI/glow, so softness
# comes from blur + MSAA + tight range rather than those effects.
func apply_shadows() -> void:
	if sun == null:
		return
	if quality <= 0:
		sun.shadow_enabled = false
		return
	sun.shadow_enabled = true
	var q := clampi(shadow_quality, 0, 3)
	# NOTE (crash fix): 4096 risks VRAM exhaustion / driver OOM and an
	# access-violation inside the GL driver on Intel UHD + Android iGPUs
	# for zero visible gain on a 10x10 stylized arena. Cap at 2048; Ultra
	# instead maxes filtering and tightens range, where sharpness comes from.
	var atlas: int = [1024, 2048, 2048, 2048][q]
	# NOTE (crash fix): atlas_set_size reallocates the shadow atlas even
	# when unchanged. Only call when the size actually differs.
	if int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", atlas)) != atlas:
		RenderingServer.directional_shadow_atlas_set_size(atlas, false)
		ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/size", atlas)
	# ShadowQuality enum: 0 HARD, 1 SOFT_VERY_LOW, 2 SOFT_LOW,
	# 3 SOFT_MEDIUM, 4 SOFT_HIGH, 5 SOFT_ULTRA (5 skipped: too costly).
	RenderingServer.directional_soft_shadow_filter_set_quality(q + 1)
	# DirectionalShadowMode: 0 ORTHOGONAL, 1 PARALLEL_2_SPLITS, 2 PARALLEL_4_SPLITS.
	sun.directional_shadow_mode = 1 if q == 0 else 2
	sun.directional_shadow_max_distance = [45.0, 40.0, 35.0, 30.0][q]
	sun.directional_shadow_blend_splits = q >= 1
	sun.directional_shadow_pancake_size = [20.0, 16.0, 14.0, 12.0][q]
	sun.shadow_blur = [1.0, 1.5, 2.0, 2.5][q]
	sun.shadow_bias = [0.05, 0.04, 0.03, 0.03][q]
	sun.shadow_normal_bias = [1.5, 1.0, 0.8, 0.6][q]
	# Full opacity: soft edges, but characters never look like they float.
	sun.shadow_opacity = 1.0


func _on_shadow_selected(idx: int) -> void:
	shadow_quality = clampi(idx, 0, SHADOW_NAMES.size() - 1)
	apply_shadows()
	_save_settings()


func _save_settings() -> void:
	var c := ConfigFile.new()
	c.set_value("game", "quality", quality)
	c.set_value("game", "shadow_quality", shadow_quality)
	c.set_value("game", "volume", audio.vol if audio != null else _loaded_vol)
	c.set_value("game", "shake", shake_amt)
	c.set_value("game", "show_fps", show_fps)
	c.set_value("game", "p2_cpu", bool(cfg[1].get("cpu", false)))
	c.set_value("game", "p2_diff", int(cfg[1].get("diff", 1)))
	c.save(SETTINGS_PATH)


func _load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(SETTINGS_PATH) != OK:
		return
	quality = clampi(int(c.get_value("game", "quality", quality)), 0, 2)
	shadow_quality = clampi(int(c.get_value("game", "shadow_quality", 1)), 0, 3)
	_loaded_vol = clampf(float(c.get_value("game", "volume", 0.6)), 0.0, 1.0)
	shake_amt = clampf(float(c.get_value("game", "shake", 0.6)), 0.0, 1.0)
	show_fps = bool(c.get_value("game", "show_fps", true))
	cfg[1]["cpu"] = bool(c.get_value("game", "p2_cpu", true))
	cfg[1]["diff"] = clampi(int(c.get_value("game", "p2_diff", 1)), 0, DIFF_NAMES.size() - 1)


func show_screen(sname) -> void:
	for k in screens:
		(screens[k]["root"] as Control).visible = k == sname
	hud.visible = state == "play" or state == "count" or state == "ko" or state == "pause" or state == "over"


func to_menu() -> void:
	state = "menu"
	_clear_bullets()
	_clear_clouds()
	_pv()
	if ai != null:
		ai.reset_ai()
	show_screen("menu")


func rs() -> void:
	for i in 2:
		var vb: VBoxContainer = sel_panels[i]
		for ch in vb.get_children():
			ch.queue_free()
		var t := Label.new()
		if i == 1 and bool(cfg[1].get("cpu", false)):
			t.text = "Player 2 (CPU)"
		else:
			t.text = "Player " + str(i + 1)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.add_theme_font_size_override("font_size", 22)
		vb.add_child(t)
		if i == 1:
			var mrow := HBoxContainer.new()
			mrow.alignment = BoxContainer.ALIGNMENT_CENTER
			mrow.add_theme_constant_override("separation", 8)
			vb.add_child(mrow)
			var cpu := bool(cfg[1].get("cpu", false))
			var mb := Button.new()
			mb.text = "CPU: ON" if cpu else "CPU: OFF"
			mb.custom_minimum_size = Vector2(110, 36)
			mb.set_meta("action", "p2cpu")
			mb.set_meta("i", 1)
			mb.set_meta("v", "")
			mb.pressed.connect(_on_action.bind(mb))
			mrow.add_child(mb)
			var dob := OptionButton.new()
			for di in DIFF_NAMES.size():
				dob.add_item(DIFF_NAMES[di], di)
			dob.selected = clampi(int(cfg[1].get("diff", 1)), 0, DIFF_NAMES.size() - 1)
			dob.disabled = not cpu
			dob.tooltip_text = "CPU difficulty"
			dob.item_selected.connect(_on_diff_selected)
			mrow.add_child(dob)
		for j in SKINS.size():
			var sname := str(SKINS[j])
			var b := Button.new()
			b.text = _skin_pretty(sname)
			b.custom_minimum_size = Vector2(180, 40)
			var sb := _style(_skin_col(sname), 8)
			if int(cfg[i]["skin"]) == j:
				sb.border_width_left = 3
				sb.border_width_right = 3
				sb.border_width_top = 3
				sb.border_width_bottom = 3
				sb.border_color = Color.WHITE
			b.add_theme_stylebox_override("normal", sb)
			b.set_meta("action", "skin")
			b.set_meta("i", i)
			b.set_meta("v", str(j))
			b.pressed.connect(_on_action.bind(b))
			vb.add_child(b)


func _on_action(b: Button) -> void:
	var a := String(b.get_meta("action"))
	var i := int(b.get_meta("i"))
	if a == "play":
		state = "select"
		rs()
		_pv()
		show_screen("select")
	elif a == "skin":
		cfg[i]["skin"] = int(b.get_meta("v")) % SKINS.size()
		if SKINS.size() > 1:
			while int(cfg[1 - i]["skin"]) == int(cfg[i]["skin"]):
				cfg[1 - i]["skin"] = (int(cfg[1 - i]["skin"]) + 1) % SKINS.size()
		rs()
		_pv()
	elif a == "p2cpu":
		cfg[1]["cpu"] = not bool(cfg[1].get("cpu", false))
		_apply_cpu_flag()
		_save_settings()
		rs()
	elif a == "start" or a == "restart":
		start_match()
	elif a == "openworld":
		get_tree().change_scene_to_file("res://openworld/ow_world.tscn")
	elif a == "ow1":
		get_tree().change_scene_to_file("res://openworld/ow1_world.tscn")
	elif a == "ow2":
		get_tree().change_scene_to_file("res://openworld/ow2_world.tscn")
	elif a == "grassrender":
		get_tree().change_scene_to_file("res://grass_render.tscn")
	elif a == "menu":
		to_menu()
	elif a == "resume":
		toggle_pause()
	elif a == "set":
		from = "pause" if state == "pause" else "menu"
		show_screen("settings")
	elif a == "back":
		show_screen(from)


func _on_diff_selected(idx: int) -> void:
	cfg[1]["diff"] = clampi(idx, 0, DIFF_NAMES.size() - 1)
	_apply_cpu_flag()
	_save_settings()
	rs()
