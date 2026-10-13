extends Node3D
## Block Brawl port (from html/block-brawl-quality.html): local 1v1 block
## fighter. Menu -> select (character skins from res://skins) -> countdown -> fight -> KO
## slow-mo -> winner screen. P1: WASD + J/K/L/O/P/Space. P2: arrows + ,/./Numpad1-5/Shift.

const FighterScript = preload("res://bb_fighter.gd")
const ArenaScript = preload("res://bb_arena.gd")
const VfxScript = preload("res://bb_vfx.gd")
const AudioScript = preload("res://bb_audio.gd")
const DebugScript = preload("res://bb_debug.gd")
const AnimEditorScript = preload("res://bb_anim_editor.gd")

var SKINS: Array = ["cubecowboy"]

var cfg := [{"skin": 0}, {"skin": 0}]
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
var _bullet_mesh: BoxMesh
const BULLET_R := 0.75


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
		_:
			return Color(0.23, 0.51, 0.96)


func _ready() -> void:
	SKINS = _scan_skins()
	if int(cfg[1]["skin"]) >= SKINS.size():
		cfg[1]["skin"] = 0
	_bullet_mesh = BoxMesh.new()
	_bullet_mesh.size = Vector3.ONE
	_build_env()
	arena = ArenaScript.new()
	add_child(arena)
	vfx = VfxScript.new()
	add_child(vfx)
	audio = AudioScript.new()
	add_child(audio)
	debug = DebugScript.new()
	add_child(debug)
	arena.build(vfx)
	_make_fighters()
	_build_ui()
	apply_quality()
	to_menu()


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
	fighters[0].keys = {"up": [KEY_W], "down": [KEY_S], "left": [KEY_A], "right": [KEY_D],
		"L": [KEY_J], "H": [KEY_K], "D": [KEY_SPACE],
		"S1": [KEY_L], "S2": [KEY_O], "S3": [KEY_P]}
	fighters[1].keys = {"up": [KEY_UP], "down": [KEY_DOWN], "left": [KEY_LEFT], "right": [KEY_RIGHT],
		"L": [KEY_KP_1, KEY_COMMA], "H": [KEY_KP_2, KEY_PERIOD], "D": [KEY_SHIFT, KEY_SLASH],
		"S1": [KEY_KP_3], "S2": [KEY_KP_4], "S3": [KEY_KP_5]}
	_pv()


func _pv() -> void:
	_setup_fighters()
	for f in fighters:
		f.v = Vector3.ZERO


func _setup_fighters() -> void:
	for i in 2:
		fighters[i].setup_skin(_skin_key(i))


func start_match() -> void:
	_setup_fighters()
	fighters[0].reset_match(Vector3(-2.0, 0, 2.0), atan2(4.0, -4.0))
	fighters[1].reset_match(Vector3(2.0, 0, -2.0), atan2(-4.0, 4.0))
	vfx.clear_all()
	_clear_bullets()
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
		a.upd(sd, state == "play")
		b.upd(sd, state == "play")
		_upd_bullets(sd)
		if String(a.st) != "dash" and String(b.st) != "dash" and String(a.st) != "ko" and String(b.st) != "ko":
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
			(cd_l[j] as ColorRect).anchor_right = fl
			var fr: float = 1.0 - clampf(float(b.cd[n]) / float(b.cd_max[n]), 0.0, 1.0)
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

func fire_bullet(owner: Node3D, mpos: Vector3, dir: Vector3, cfg: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _bullet_mesh
	var sp: float = float(cfg.get("speed", 22.0))
	mi.scale = Vector3(0.09, 0.09, 0.28 + sp * 0.012)
	mi.rotation.y = atan2(dir.x, dir.z)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var bc: Color = cfg.get("col", Color(1.0, 0.8, 0.35))
	mat.albedo_color = bc
	mat.emission_enabled = true
	mat.emission = bc
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position = mpos
	bullets.append({"node": mi, "p": mpos, "v": dir.normalized() * sp,
		"life": float(cfg.get("life", 0.45)), "dmg": float(cfg.get("dmg", 4.0)),
		"kb": float(cfg.get("kb", 2.5)), "vy": float(cfg.get("vy", 2.0)),
		"stun": float(cfg.get("stun", 0.18)), "big": bool(cfg.get("big", false)),
		"owner": owner, "col": bc, "trail": 0.0})


func _seg_point(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom < 0.000001:
		return a.distance_to(p)
	var u := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return (a + ab * u).distance_to(p)


func _upd_bullets(dt: float) -> void:
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
		b["trail"] = float(b["trail"]) - dt
		if float(b["trail"]) <= 0.0:
			b["trail"] = 0.07
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
	vfx.flash(hp_pos, 0.9 if big else 0.55, Color.WHITE)
	vfx.burst(hp_pos, own.body_col, 16 if big else 7, 7.0 if big else 4.5, 0.1, 0.45)
	hs = maxf(hs, 0.1 if big else 0.03)
	shake = maxf(shake, (0.35 if big else 0.12) * shake_amt)
	audio.play("hitH" if big else "hitL")
	_kill_bullet(i, true)


func _kill_bullet(i: int, impacted: bool) -> void:
	var b: Dictionary = bullets[i]
	if impacted:
		vfx.burst(b["p"], b["col"], 6, 3.0, 0.07, 0.3)
	(b["node"] as Node3D).queue_free()
	bullets.remove_at(i)


func _clear_bullets() -> void:
	for b in bullets:
		(b["node"] as Node3D).queue_free()
	bullets.clear()


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
	_btn(mb, "Animation Editor", "anim_editor")
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
	hint.text = "P1: WASD move, J light, K heavy, L dash-atk, O uppercut, P spin, Space dash. P2: arrows, ,/. attacks, Numpad3/4/5 specials, Shift or / dash. Esc pauses. Cooldowns: yellow=L, orange=O, purple=P. Cowboy kit: L fan-fire (6 shots), O rifle (heavy), P horse ride. Knight kit: L shield counter, O shield bash, P sword sweep."
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
	var sv := _slider(grid, "Sound volume", 60)
	sv.value_changed.connect(func(_v: float) -> void: audio.vol = sv.value / 100.0)
	var ss := _slider(grid, "Screen shake", 60)
	ss.value_changed.connect(func(_v: float) -> void: shake_amt = ss.value / 100.0)
	_opt(grid)
	var sf := CheckBox.new()
	sf.text = "Show FPS"
	sf.button_pressed = true
	var sl := Label.new()
	sl.text = "Show FPS"
	grid.add_child(sl)
	grid.add_child(sf)
	sf.toggled.connect(func(on: bool) -> void: show_fps = on; fps.visible = on)
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
		hp_bars.append({"root": root, "fill": fill, "lab": lab})


func _upd_hp_bars() -> void:
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
		var frac := hp / 100.0
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
	o.selected = 2
	grid.add_child(o)
	o.item_selected.connect(func(idx: int) -> void: quality = idx; apply_quality())


func apply_quality() -> void:
	vfx.set_cap([60, 100, 100][clampi(quality, 0, 2)])
	sun.shadow_enabled = quality > 0
	var sc: float = [0.85, 1.0, 1.0][clampi(quality, 0, 2)]
	get_viewport().set("scaling_3d_scale", sc)


func show_screen(sname) -> void:
	for k in screens:
		(screens[k]["root"] as Control).visible = k == sname
	hud.visible = state == "play" or state == "count" or state == "ko" or state == "pause" or state == "over"


func to_menu() -> void:
	state = "menu"
	_clear_bullets()
	_pv()
	show_screen("menu")


func rs() -> void:
	for i in 2:
		var vb: VBoxContainer = sel_panels[i]
		for ch in vb.get_children():
			ch.queue_free()
		var t := Label.new()
		t.text = "Player " + str(i + 1)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.add_theme_font_size_override("font_size", 22)
		vb.add_child(t)
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
	elif a == "start" or a == "restart":
		start_match()
	elif a == "menu":
		to_menu()
	elif a == "anim_editor":
		get_tree().change_scene_to_file("res://animation_editor.tscn")
	elif a == "resume":
		toggle_pause()
	elif a == "set":
		from = "pause" if state == "pause" else "menu"
		show_screen("settings")
	elif a == "back":
		show_screen(from)
